import std.conv;
import std.file;
import std.math;
import std.stdio;
import std.range;
import std.string;
import std.random;

import std.parallelism;

import std.datetime;


import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import gl3n.linalg;
import _2imv10.sphere;
import _2imv10.particle;
import _2imv10.util;
import std.algorithm.sorting;

import mfellner.exception;
import mfellner.math;

bool fullscreen = false;

GLuint vertexLoc, colorLoc, normalLoc;
GLuint projMatrixLoc, offsetLoc, viewMatrixLoc, particleColorLoc, lightIntensitiesLoc, lightPositionLoc, lightAmbientLoc;

GLfloat[MATRIX_SIZE] projMatrix;
GLfloat[MATRIX_SIZE] viewMatrix;

GLuint[1000000] vao;
GLuint vaoSpheres;

GLuint[] sphereIndices; // Particle indices for vao
GLfloat[VECTOR_SIZE][] parPos; // Current particle positions
GLfloat[VECTOR_SIZE][] parVel; // Current particle velocities

GLfloat[][] sphereData;
GLfloat[] sphereVertexTemplates;
GLfloat[] sphereNormals;
GLfloat[] sphereColors;

GLuint CameraRight_worldspace_ID;
GLuint CameraUp_worldspace_ID;
GLuint TextureID;

GLuint squareVerticesLoc, xyzsLoc;

GLfloat g = 0.3; // Gravity force
GLfloat h = 1.5; // Kernel size
GLfloat rho = 0.0008; // Rest density
GLfloat eps = 0.4; // Relaxation parameter

GLfloat binsize = 1.0; // Size of bins for spatial partitioning, should be at least 4*h

GLfloat absDQ = 0.2; // Fixed distance scaled in smoothing kernel for tensile instability stuff
GLfloat nPow = 4; // Power for that stuff
GLfloat kScale = 0.1; // Scalar for that stuff

GLfloat cScale = 0.01; // Scalar for viscocity

int solveIter = 3; // Number of corrective calculation cycles
int numUpdates = 1; // Number of updates per frame

int fps = 15; //Number of frames per second

ulong sphereVertexCount;

//Bounds
GLfloat[VECTOR_SIZE] boundsU = [7.5,11.5,7.5];
GLfloat[VECTOR_SIZE] boundsL = [-7.5,-7.5,-7.5];
GLfloat secondBottom = -9.5;

//Faucets
GLfloat[VECTOR_SIZE][] faucets;

//Camera position
GLfloat lookatX = 0;
GLfloat lookatY = 0;
GLfloat lookatZ = -1;

GLfloat cameraX = 4;
GLfloat cameraY = 1;
GLfloat cameraZ = 4;

GLfloat rotateHorizontal = 0;
GLfloat rotateVertical = 0;
GLfloat zoom = 0;

const(GLfloat) walkStepSize = 0.05;
const(GLfloat) orbitStepSize = 0.05;
const(GLfloat) zoomStepSize = 0.2;

static const GLfloat[] g_vertex_buffer_data = [
 -0.5f, -0.5f, 0.0f,
 0.5f, -0.5f, 0.0f,
 -0.5f, 0.5f, 0.0f,
 0.5f, 0.5f, 0.0f
];

bool wIsDown = false;
bool aIsDown = false;
bool sIsDown = false;
bool dIsDown = false;

bool fIsDown = false;
bool gIsDown = false;
bool bIsDown = false;

bool upIsDown = false;
bool rightIsDown = false;
bool downIsDown = false;
bool leftIsDown = false;

bool checkExecutionTime = false;

void printProgramInfoLog(GLuint program) {
  GLint infologLength = 0;
  GLint charsWritten  = 0;

  glGetProgramiv(program, GL_INFO_LOG_LENGTH, &infologLength);

  if (infologLength > 0) {
    char[] infoLog;
    //glGetProgramInfoLog(program, infologLength, &charsWritten, infoLog.ptr);
    //Still causes exit with code -11
    writeln(infoLog);
  } else {
    writeln("no program info log");
  }
}

string loadShader(string filename) {
  if (exists(filename) != 0) {
    return readText(filename);
  } else {
    throw new Exception("Shader file not found");
  }
}

GLuint compileShader(string filename, GLuint type) {
  const(char)* sp = loadShader(filename).toStringz();

  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &sp, null);
  glCompileShader(shader);

  GLint infologLength;

  GLint status;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE) {
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infologLength);
        if (infologLength > 0) {
            char[] buffer = new char[infologLength];
            glGetShaderInfoLog(shader, infologLength, null, buffer.ptr);
            writeln(buffer);
        }
    throw new Exception("Failed to compile shader");
  }

  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infologLength);
  if (infologLength > 0) {
    char[] buffer = new char[infologLength];
    glGetShaderInfoLog(shader, infologLength, null, buffer.ptr);
    writeln(buffer);
  } else {
    writeln("no shader info log");
  }
  return shader;
}

nothrow void buildProjectionMatrix(GLfloat fov, GLfloat ratio, GLfloat nearP, GLfloat farP) {
  GLfloat f = 1.0 / tan (fov * (PI / 360.0));

  setIdentityMatrix(projMatrix, 4);

  projMatrix[        0] = f / ratio;
  projMatrix[1 * 4 + 1] = f;
  projMatrix[2 * 4 + 2] = (farP + nearP) / (nearP - farP);
  projMatrix[3 * 4 + 2] = (2.0 * farP * nearP) / (nearP - farP);
  projMatrix[2 * 4 + 3] = -1.0;
  projMatrix[3 * 4 + 3] =  0.0;
}

extern(C) nothrow void reshape(GLFWwindow* window, int width, int height) {
  if(height == 0) height = 1;
  glViewport(0, 0, width, height);
  GLfloat ratio = cast(GLfloat)width / cast(GLfloat)height;
  buildProjectionMatrix(60.0, ratio, 1.0, 30.0);
}

void setUniforms() {
    glUniform3f(CameraRight_worldspace_ID, viewMatrix[0], viewMatrix[4], viewMatrix[8]);
    glUniform3f(CameraUp_worldspace_ID   , viewMatrix[1], viewMatrix[5], viewMatrix[9]);

    glUniformMatrix4fv(projMatrixLoc, 1, false, projMatrix.ptr);
    glUniformMatrix4fv(viewMatrixLoc, 1, false, viewMatrix.ptr);
}

void setCamera(GLfloat posX, GLfloat posY, GLfloat posZ, GLfloat lookAtX, GLfloat lookAtY, GLfloat lookAtZ) {
  GLfloat[VECTOR_SIZE]   dir;
  GLfloat[VECTOR_SIZE] right;
  GLfloat[VECTOR_SIZE]    up;

  up[0] = 0.0; up[1] = 1.0; up[2] = 0.0;

  dir[0] = (lookAtX - posX);
  dir[1] = (lookAtY - posY);
  dir[2] = (lookAtZ - posZ);
  normalize(dir);

  crossProduct(dir,up,right);
  normalize(right);

  crossProduct(right,dir,up);
  normalize(up);

  float[MATRIX_SIZE] aux;

  viewMatrix[0]  = right[0];
  viewMatrix[4]  = right[1];
  viewMatrix[8]  = right[2];
  viewMatrix[12] = 0.0;

  viewMatrix[1]  = up[0];
  viewMatrix[5]  = up[1];
  viewMatrix[9]  = up[2];
  viewMatrix[13] = 0.0;

  viewMatrix[2]  = -dir[0];
  viewMatrix[6]  = -dir[1];
  viewMatrix[10] = -dir[2];
  viewMatrix[14] =  0.0;

  viewMatrix[3]  = 0.0;
  viewMatrix[7]  = 0.0;
  viewMatrix[11] = 0.0;
  viewMatrix[15] = 1.0;

  mat4 viewMat = mat4(
    vec4(viewMatrix[0], viewMatrix[1], viewMatrix[2], viewMatrix[3]),
    vec4(viewMatrix[4], viewMatrix[5], viewMatrix[6], viewMatrix[7]),
    vec4(viewMatrix[8], viewMatrix[9], viewMatrix[10], viewMatrix[11]),
    vec4(viewMatrix[12], viewMatrix[13], viewMatrix[14], viewMatrix[15])
  );

    const(float)* pSource = cast(const(float)*)viewMat.value_ptr;
    for (int i = 0; i < 16; ++i)
    {
        viewMatrix[i] = pSource[i];
    }

  setTranslationMatrix(aux, -posX, -posY, -posZ);

  multMatrix(viewMatrix, aux);
}

void predictPositions(ref GLfloat[VECTOR_SIZE][] parAux, ref GLfloat dt){
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
            parVel[sphereIndex][1] -= g*dt;
            for (int j = 0; j < VECTOR_SIZE; j++){
                parAux[sphereIndex][j] = parPos[sphereIndex][j] + parVel[sphereIndex][j]*dt;
            }
        }
}

void boundPositions(ref GLfloat[VECTOR_SIZE][] parAux){
    foreach (sphereIndex; taskPool.parallel(iota(0,to!int(sphereIndices.length)))){
            //Collision detection with aquarium (faulty)
            for (int j = 0; j < 3; j++){
                if(parAux[sphereIndex][j] > boundsU[j]){
                    parAux[sphereIndex][j] = boundsU[j];
                } else if(parAux[sphereIndex][j] < boundsL[j]){
                    parAux[sphereIndex][j] = boundsL[j];
                }
            }
    }
}

void setBinDims(ref int[VECTOR_SIZE] binDims){
        for(int j = binDims.length -1; j >= 0; j--){
            binDims[j] = to!int(ceil((boundsU[j] - boundsL[j])/binsize));
        }
}

void assignBins(ref int[VECTOR_SIZE] binDims, ref int[][][][] bins, ref GLfloat[VECTOR_SIZE][] parAux, ref int[VECTOR_SIZE][] parBin){
        for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
            int[VECTOR_SIZE] curbin;
            for(int j = VECTOR_SIZE -1; j >= 0; j--){
                curbin[j] = to!int((parAux[sphereIndex][j] - boundsL[j])/binsize);
                if(curbin[j] == binDims[j] ) {
                    curbin[j]--;
                }
            }

            bins[curbin[0]][curbin[1]][curbin[2]] ~= sphereIndex;
            parBin[sphereIndex] = curbin;
        }
}

void assignNeighbours(ref int[VECTOR_SIZE] binDims, ref int[][][][] bins, ref GLfloat[VECTOR_SIZE][] parAux, ref int[VECTOR_SIZE][] parBin, ref int[][] neighbours){

    foreach (sphereIndex; taskPool.parallel(iota(0,to!int(sphereIndices.length)))){
            int[VECTOR_SIZE] curbin = parBin[sphereIndex];
            for (int dx = -1; dx <= 1; dx++){
                if(curbin[0] + dx >= 0 && curbin[0] + dx < binDims[0]){
                for (int dy = -1; dy <= 1; dy++){
                    if(curbin[1] + dy >= 0 && curbin[1] + dy < binDims[1]){
                    for (int dz = -1; dz <= 1; dz++){
                        if(curbin[2] + dz >= 0 && curbin[2] + dz < binDims[2]){
                            for(int binIndex = to!int(bins[curbin[0] + dx][curbin[1] + dy][curbin[2] + dz].length) - 1; binIndex >= 0; binIndex--){
				                int neighIndex = bins[curbin[0] + dx][curbin[1] + dy][curbin[2] + dz][binIndex];
				                if(distance(subtract(parAux[sphereIndex], parAux[neighIndex])) < binsize && sphereIndex != neighIndex){
				                    neighbours[sphereIndex] ~= neighIndex;
				                }
			                }
                        }
                    }}
                }}
            }
        }
}

void calculateLambdas(ref GLfloat[VECTOR_SIZE][] parAux, ref GLfloat[] parLam, ref int[][] neighbours){
    foreach (sphereIndex; taskPool.parallel(iota(0,to!int(sphereIndices.length)))){
        GLfloat rhoi = 0;
        for (int neighIndex = to!int(neighbours[sphereIndex].length) - 1; neighIndex >= 0; neighIndex--)
        {
            if(sphereIndex != neighbours[sphereIndex][neighIndex]){
                rhoi += IKGaussFromDist(distance(subtract(parAux[sphereIndex], parAux[neighbours[sphereIndex][neighIndex]])), h);
            }
        }

        GLfloat PkSum = 0;
        for (int neighIndex = to!int(neighbours[sphereIndex].length) - 1; neighIndex >= 0; neighIndex--)
        {
            GLfloat summand = 0;
            if(sphereIndex != neighbours[sphereIndex][neighIndex]){
                GLfloat[VECTOR_SIZE] db = dbIKGauss(subtract(parAux[sphereIndex], parAux[neighbours[sphereIndex][neighIndex]]), h);
                summand = selfDotProduct(db);
            } else {
                for (int neighIndex2 = to!int(neighbours[sphereIndex].length) - 1; neighIndex2 >= 0; neighIndex2--)
                {
                    if(sphereIndex != neighbours[sphereIndex][neighIndex2]){
                        GLfloat[VECTOR_SIZE] da = daIKGauss(subtract(parAux[sphereIndex], parAux[neighbours[sphereIndex][neighIndex2]]), h);
                        summand += selfDotProduct(da);
                    }
                }
            }
            PkSum += summand;
        }
        PkSum /= (rho*rho);

        parLam[sphereIndex] = (rhoi/rho - 1)/(PkSum + eps);
    }
}

void calculateDeltaP(ref GLfloat[VECTOR_SIZE][] parAux, ref GLfloat[] parLam, ref GLfloat[VECTOR_SIZE][] parDP, ref int[][] neighbours){
    foreach (sphereIndex; taskPool.parallel(iota(0,to!int(sphereIndices.length)))){
            GLfloat[VECTOR_SIZE] dp = [0,0,0];
            for (int neighIndex = to!int(neighbours[sphereIndex].length) - 1; neighIndex >= 0; neighIndex--)
            {
                if(sphereIndex != neighbours[sphereIndex][neighIndex]){
                    GLfloat sCorr =  -kScale;
                    GLfloat frac = IKGaussFromDist(distance(subtract(parAux[sphereIndex], parAux[neighbours[sphereIndex][neighIndex]])), h)/IKGaussFromDist(absDQ*h, h);
                    for (int n = 0; n < nPow; n++){
                        sCorr *= frac;
                    }
                    GLfloat scalar = parLam[sphereIndex] + parLam[neighbours[sphereIndex][neighIndex]] + sCorr;
                    GLfloat[VECTOR_SIZE] da = daIKGauss(subtract(parAux[sphereIndex], parAux[neighbours[sphereIndex][neighIndex]]), h);
                    dp = [dp[0] + da[0]*scalar, dp[1] + da[1]*scalar, dp[2] + da[2]*scalar];
                }
            }
            parDP[sphereIndex] = dp;
        }
}

void applyDP(ref GLfloat[VECTOR_SIZE][] parAux, ref GLfloat[VECTOR_SIZE][] parDP){
    foreach (sphereIndex; taskPool.parallel(iota(0,to!int(sphereIndices.length)))){
            for (int j = 0; j < VECTOR_SIZE; j++){
                parAux[sphereIndex][j] = parDP[sphereIndex][j] + parAux[sphereIndex][j];
            }
        }
}

void applyPosChanges(ref GLfloat[VECTOR_SIZE][] parAux, ref GLfloat dt){
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
    {
        for (int j = 0; j < VECTOR_SIZE; j++){
            parVel[sphereIndex][j] = (parAux[sphereIndex][j] - parPos[sphereIndex][j])/dt;
        }

        parPos[sphereIndex] = parAux[sphereIndex];
    }
}

void calculateVorticity(ref GLfloat[VECTOR_SIZE][] parVelAux, ref int[][] neighbours, ref GLfloat dt){
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
    {
        //Apply vorticity
        GLfloat[VECTOR_SIZE] fVor;
        GLfloat[VECTOR_SIZE] omega = [0, 0, 0];
        GLfloat[VECTOR_SIZE] bigN = [0, 0, 0];
        GLfloat[VECTOR_SIZE][VECTOR_SIZE] crossDerivs = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
        for (int neighIndex = to!int(neighbours[sphereIndex].length) - 1; neighIndex >= 0; neighIndex--)
        {
            GLfloat[VECTOR_SIZE] velDiff = subtract(parVel[sphereIndex], parVel[neighbours[sphereIndex][neighIndex]]);
            GLfloat[VECTOR_SIZE] summand = crossProduct(velDiff,
                dbIKGauss(subtract(parPos[sphereIndex], parPos[neighbours[sphereIndex][neighIndex]]), h));
            omega = add(omega, summand);

            GLfloat[VECTOR_SIZE][VECTOR_SIZE] derivs = dadbIKGauss(subtract(parPos[sphereIndex], parPos[neighbours[sphereIndex][neighIndex]]), h);

            for (int j = 0; j < VECTOR_SIZE; j++){
                for (int k = 0; k < VECTOR_SIZE; k++){
                    crossDerivs[j][k] += velDiff[(k+1)%VECTOR_SIZE] * derivs[j][(k+2)%VECTOR_SIZE] - velDiff[(k+2)%VECTOR_SIZE] * derivs[j][(k+1)%VECTOR_SIZE];
                }
            }
        }

        // Njk based on index j in p with index k in omega
        for (int j = 0; j < VECTOR_SIZE; j++){
            for (int k = 0; k < VECTOR_SIZE; k++){
                bigN[j] += omega[k] * crossDerivs[j][k];
            }
        }

        // We skip dividing bigN by the distance of omega, since we normalize anyway
        if(distance(bigN) != 0){
            normalize(bigN);
        }
        crossProduct(bigN, omega, fVor);

        for (int j = 0; j < VECTOR_SIZE; j++){
            fVor[j] *= eps;
        }

        // Apply velocity adjustment
        for (int j = 0; j < VECTOR_SIZE; j++){
            parVelAux[sphereIndex][j] += fVor[j]*dt;
        }
    }
}

void calculateViscocity(ref GLfloat[VECTOR_SIZE][] parVelAux, ref int[][] neighbours){
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
    {

        //Apply viscocity
        GLfloat[VECTOR_SIZE] resVis = [0, 0, 0];
        for (int neighIndex = to!int(neighbours[sphereIndex].length) - 1; neighIndex >= 0; neighIndex--)
        {
            GLfloat kernelScale = IKGaussFromDist(distance(subtract(parVel[sphereIndex], parVel[neighbours[sphereIndex][neighIndex]])), h);
            for (int j = 0; j < VECTOR_SIZE; j++){
                resVis[j] += kernelScale * (parVel[neighbours[sphereIndex][neighIndex]][j] - parVel[sphereIndex][j]);
            }
        }

        // Apply velocity adjustment
        for (int j = 0; j < VECTOR_SIZE; j++){
            parVelAux[sphereIndex][j] += cScale*resVis[j];
        }
    }
}

void applyVelChanges(ref GLfloat[VECTOR_SIZE][] parVelAux){
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
    {
        // Apply velocity adjustment
        for (int j = 0; j < VECTOR_SIZE; j++){
            parVel[sphereIndex][j] = parVelAux[sphereIndex][j];
        }
    }
}

// Updates the state of particles for a time difference dt
void updateState(GLfloat dt){
    GLfloat[VECTOR_SIZE][] parAux = new GLfloat[VECTOR_SIZE][](to!int(sphereIndices.length)); // Auxiliary particle positions
    GLfloat[VECTOR_SIZE][] parDP =  new GLfloat[VECTOR_SIZE][](to!int(sphereIndices.length)); // Current particle delta p
    GLfloat[] parLam =  new GLfloat[](to!int(sphereIndices.length)); // Current particle lambda values

    predictPositions(parAux, dt);

    boundPositions(parAux);

    for (int i = 0; i < solveIter; i++){

        int[][] neighbours = new int[][](to!int(sphereIndices.length)); // Current particle neighbours
        int[VECTOR_SIZE] binDims;
        setBinDims(binDims);
        int[][][][] bins = new int[][][][](binDims[0], binDims[1], binDims[2]);
        int[VECTOR_SIZE][] parBin = new int[VECTOR_SIZE][](to!int(sphereIndices.length)); // Current particle bin
        assignBins(binDims, bins, parAux, parBin);// Assign bins
        assignNeighbours(binDims, bins, parAux, parBin, neighbours);// Assign neighbours

        // Calculate lambdas
        calculateLambdas(parAux, parLam, neighbours);

        // Calculate delta p + collision detection
        calculateDeltaP(parAux, parLam, parDP, neighbours);

        //Collision detection with aquarium (faulty)
        /*for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {

            for (int j = 0; j < 3; j++){
                if(parDP[sphereIndex][j] + parAux[sphereIndex][j] > boundsU[j]){
                    parDP[sphereIndex][j] = boundsU[j] - parAux[sphereIndex][j];
                } else if(parDP[sphereIndex][j] + parAux[sphereIndex][j] < boundsL[j]){
                    parDP[sphereIndex][j] = boundsL[j] - parAux[sphereIndex][j];
                }
            }
        }*/

        // Apply changes
        applyDP(parAux, parDP);

        boundPositions(parAux);
    }

    applyPosChanges(parAux, dt);

    int[][] neighbours = new int[][](to!int(sphereIndices.length)); // Current particle neighbours
    int[VECTOR_SIZE] binDims;
    setBinDims(binDims);
    int[][][][] bins = new int[][][][](binDims[0], binDims[1], binDims[2]);
    int[VECTOR_SIZE][] parBin = new int[VECTOR_SIZE][](to!int(sphereIndices.length)); // Current particle bin
    assignBins(binDims, bins, parAux, parBin);// Assign bins
    assignNeighbours(binDims, bins, parAux, parBin, neighbours);// Assign neighbours

    GLfloat[VECTOR_SIZE][] parVelAux = new GLfloat[VECTOR_SIZE][](to!int(sphereIndices.length)); // Auxiliary particle velocities

    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
    {
        for (int j = 0; j < VECTOR_SIZE; j++){
            parVelAux[sphereIndex][j] = parVel[sphereIndex][j];
        }
    }

    calculateVorticity(parVelAux, neighbours, dt);

    calculateViscocity(parVelAux, neighbours);

    applyVelChanges(parVelAux);
}

// Creates a new particle from position p
void createParticle(GLfloat[VECTOR_SIZE] p, int vaoIndex){
    sphereIndices ~= vaoIndex;
    parPos ~= p;
    parVel ~= [0,0,0];
    checkExecutionTime = true;
    sphereColors ~= [0,0,1.0];
}

// Creates a new faucet from position p
void createFaucet(GLfloat[VECTOR_SIZE] p){
    faucets ~= p;
}

// adapted from http://open.gl/drawing and
// http://www.lighthouse3d.com/cg-topics/code-samples/opengl-3-3-glsl-1-5-sample
void main() {
    DerelictGL3.load();
    DerelictGLFW3.load();

    glfwSetErrorCallback(&glfwPrintError);

    if(!glfwInit())
    {
        glfwTerminate();
        throw new Exception("Failed to create glcontext");
    }

    glfwWindowHint(GLFW_SAMPLES, 4);
    glfwWindowHint(GLFW_RESIZABLE, GL_TRUE);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

    GLFWwindow* window;

    if (fullscreen)
    {
        window = glfwCreateWindow(640, 480, "Position Based Fluids", glfwGetPrimaryMonitor(), null);
    }
    else
    {
        window = glfwCreateWindow(640, 480, "Position Based Fluids", null, null);
    }

    if (!window)
    {
        glfwTerminate();
        throw new Exception("Failed to create window");
    }

    glfwSetFramebufferSizeCallback(window, &reshape);
    glfwMakeContextCurrent(window);

    glfwSetKeyCallback(window, &key_callback);

    DerelictGL3.reload();

    writefln("Vendor:   %s",   to!string(glGetString(GL_VENDOR)));
    writefln("Renderer: %s",   to!string(glGetString(GL_RENDERER)));
    writefln("Version:  %s",   to!string(glGetString(GL_VERSION)));
    writefln("GLSL:     %s\n", to!string(glGetString(GL_SHADING_LANGUAGE_VERSION)));

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glClearColor(0.7f, 0.7f, 0.7f, 1.0f);

    //////////////////////////////////////////////////////////////////////////////
    // Prepare shader program
    GLuint vertexShader   = compileShader("source/shader/particles.vert", GL_VERTEX_SHADER);
    GLuint fragmentShader = compileShader("source/shader/particles.frag", GL_FRAGMENT_SHADER);

    GLuint shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertexShader);
    glAttachShader(shaderProgram, fragmentShader);
    glBindFragDataLocation(shaderProgram, 0, "color");
    glLinkProgram(shaderProgram);
    printProgramInfoLog(shaderProgram);

    projMatrixLoc = glGetUniformLocation(shaderProgram, "projMatrix");
    viewMatrixLoc = glGetUniformLocation(shaderProgram, "viewMatrix");
    CameraRight_worldspace_ID  = glGetUniformLocation(shaderProgram, "CameraRight_worldspace");
    CameraUp_worldspace_ID  = glGetUniformLocation(shaderProgram, "CameraUp_worldspace");
    TextureID  = glGetUniformLocation(shaderProgram, "textureSampler");

    squareVerticesLoc = glGetAttribLocation(shaderProgram, "squareVertices");
    xyzsLoc = glGetAttribLocation(shaderProgram, "xyzs");
    colorLoc = glGetAttribLocation(shaderProgram, "color");

    GLuint Texture = loadDDS("particle.DDS");

    glCheckError("Initializing shaders");

    GLuint[2] vbo;
    GLuint billboard_vertex_buffer;
    GLuint particles_position_buffer;
    GLuint particles_color_buffer;
    const int MaxParticles = 100000;

    GLuint nbo;
    GLuint obo;
    GLuint particleVao;
    glGenVertexArrays(1, &particleVao);
    glBindVertexArray(particleVao);
    GLint            vSize = 4, cSize = 3;
    GLsizei         stride = 4 * float.sizeof;
    const GLvoid* cPointer = null; //cast(void*)(? * GLfloat.sizeof);

    int width, height;
    glfwGetWindowSize(window, &width, &height);
    reshape(window, width, height);

    sphereData = generateVerticesAndNormals([0,0,0 ,1.0], 0.3, 6 , 12);
    sphereVertexTemplates = sphereData[0];
    sphereNormals = sphereData[1];
    sphereColors = [];

    GLfloat[] vertices;
    GLfloat[] normals;
    GLfloat[] colors;
    GLuint vaoIndex = 1;

    int spheresX = 1;
    int spheresY = 1;
    int spheresZ = 1;

  int i = 0, k = 1;
  uint frame = 0;
  auto range = iota(-100, 100);

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Tests
////////////


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Initialize rain
  for (float v = to!int(ceil(boundsL[0]))+1; v <= to!int(floor(boundsU[0]))-1; v+=1.5*h){
    for (float w = to!int(ceil(boundsL[2]))+1; w <= to!int(floor(boundsU[2]))-1; w +=1.5*h){
        createFaucet([v,6,w]);
    }
  }

  GLfloat[VECTOR_SIZE] movementVector = [0,0,0];
  glUseProgram(shaderProgram);
  /*glUniform3fv(cast(uint)lightPositionLoc, 1, cast(const(float)*)[cameraX, cameraY, cameraZ]);
  glUniform3fv(cast(uint)lightIntensitiesLoc, 1, cast(const(float)*)[1f,1f,1f]);
  glUniform3fv(cast(uint)lightAmbientLoc, 1, cast(const(float)*)[0.1f,0.1f,0.1f]);*/

  int iter = 0;

  int faucetCounter = 0;

  StopWatch sw;

  long totalUpdateTime = 0;
  long totalRenderTime = 0;
  long frames = 0;

  TickDuration framesStart = sw.peek();
  sw.start();

  while (!glfwWindowShouldClose(window)) {
    frames++;
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glCheckError("Clearing the window");

    movementVector = [0,0,0];

    rotateHorizontal = 0;
    rotateVertical = 0;
    zoom = 0;

    if(wIsDown)
    {
        zoom -= zoomStepSize;
    }
    if(sIsDown)
    {
        zoom += zoomStepSize;
    }
    if(fIsDown)
    {
        faucetCounter++;
    }
    if(gIsDown)
    {
        faucetCounter--;
    }
    if(bIsDown)
    {
        for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
            if(parPos[sphereIndex][0] < 1.5 && parPos[sphereIndex][0] > -1.5 && parPos[sphereIndex][2] < 1.5 && parPos[sphereIndex][2] > -1.5){
              parPos[sphereIndex][1] = parPos[sphereIndex][1] + 15;
            }
        }
    }
    if (upIsDown)
    {
        rotateVertical += orbitStepSize;
    }
    if (rightIsDown)
    {
        rotateHorizontal += orbitStepSize;
    }
    if (downIsDown)
    {
        rotateVertical -= orbitStepSize;
    }
    if (leftIsDown)
    {
        rotateHorizontal -= orbitStepSize;
    }

    //printf("rH=%f, rV=%f\n", rotateHorizontal, rotateVertical);

    //Translate to origin
      cameraX -= lookatX;
      cameraY -= lookatY;
      cameraZ -= lookatZ;

      //Rotate camera
      GLfloat[3] cameraSpherical = cartToSpherical([cameraX,cameraZ,cameraY,1.0]);
      cameraSpherical[0] += rotateVertical;
      cameraSpherical[1] += rotateHorizontal;
      cameraSpherical[2] += zoom;
      GLfloat[4] cameraCartesian = sphericalToCart(cameraSpherical[0],cameraSpherical[1],cameraSpherical[2]);

      cameraX = cameraCartesian[0];
      cameraZ = cameraCartesian[1];
      cameraY = cameraCartesian[2];

      //Translate back
      cameraX -= lookatX;
      cameraY += lookatY;
      cameraZ += lookatZ;

    lookatX += movementVector[0];
    lookatZ += movementVector[1];
    cameraX += movementVector[0];
    cameraZ += movementVector[1];


    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(shaderProgram);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, Texture);
    // Set our "myTextureSampler" sampler to user Texture Unit 0
    glUniform1i(TextureID, 0);

    setCamera(cameraX, cameraY, cameraZ, lookatX, lookatY, lookatZ);
    setUniforms();
    glCheckError("Setting the uniforms");

    //////////////////////////////////////////////////////////////////////////////
    // Update the points
    TickDuration startUpdate = sw.peek();
    for (int u = 0; u < numUpdates; u++){
        updateState(1.0/cast(GLfloat) fps);

        for (int w = 0; w < faucets.length && w < faucetCounter; w++){

            if((iter+w*4)%(4*fps) == 0){
              createParticle([uniform(-h/10, h/10) + faucets[w][0],uniform(-h/10, h/10) + faucets[w][1],uniform(-h/10, h/10) + faucets[w][2]], vaoIndex);
              vaoIndex++;
            }
        }

        iter++;
    }
    TickDuration endUpdate = sw.peek()-startUpdate;
    totalUpdateTime += endUpdate.msecs;

    TickDuration startRender = sw.peek();
    int ParticlesCount = cast(int)sphereIndices.length;
    GLfloat[] g_particule_position_size_data;
    GLubyte[] g_particule_color_data;
    ParticleContainer[] particles;
    for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
    {
        ParticleContainer p;
        p.position = [parPos[sphereIndex][0],parPos[sphereIndex][1],parPos[sphereIndex][2], 1.5f];
        p.color = [100,100,255,100];
        GLfloat[3] distanceVector;
        GLfloat[3] particlePos = [p.position[0],p.position[1],p.position[2]];
        GLfloat[3] cameraPos = [cameraX,cameraY,cameraZ];
        subtract(cameraPos, particlePos, distanceVector);
        p.cameraDistance = distance(distanceVector);
        particles ~= [p];
    }

    sort!("a.cameraDistance > b.cameraDistance", SwapStrategy.stable)(particles);

    for (int particleIndex = 0; particleIndex < cast(int)particles.length; particleIndex++)
    {
        ParticleContainer p = particles[particleIndex];
        //offsets ~= [parPos[sphereIndex][0], parPos[sphereIndex][1], parPos[sphereIndex][2], 1.0];
        g_particule_position_size_data ~= p.position;
        g_particule_color_data ~= p.color;
    }

    createParticleBuffers(g_vertex_buffer_data, billboard_vertex_buffer, particles_position_buffer, particles_color_buffer, ParticlesCount);
    glCheckError("Creating buffers");
    updateParticleBuffers(particles_position_buffer, particles_color_buffer, ParticlesCount,
                            g_particule_position_size_data, g_particule_color_data);
    glCheckError("Updating buffers");

    drawParticles(particleVao, billboard_vertex_buffer, particles_position_buffer, particles_color_buffer, squareVerticesLoc, xyzsLoc, colorLoc, ParticlesCount);
    glCheckError("Drawing the points");

    TickDuration endRender = sw.peek()-startRender;
    totalRenderTime = endRender.usecs;

    glfwSwapBuffers(window);
    glfwPollEvents();

    if(checkExecutionTime)
    {
        TickDuration frameEnd = sw.peek()-framesStart;
        checkExecutionTime = false;
        float avgUpdateTime = cast(float)totalUpdateTime/cast(float)frames;
        float avgRenderTime = cast(float)totalRenderTime/cast(float)frames;
        float avgFrameRate = cast(float)frames/(cast(float)frameEnd.msecs/1000);

        printf("%i,%f,%f,%f\n", vaoIndex, avgUpdateTime, avgRenderTime, avgFrameRate);
        frames = 0;
        framesStart = sw.peek();

        const(char)* title = cast(const(char)*)("Position Based Fluids. #particles=" ~ to!string(vaoIndex));

        glfwSetWindowTitle	(window, title);
    }

    if (fullscreen && glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
      glfwSetWindowShouldClose(window, GL_TRUE);
  }

  writeln(faucetCounter);
  writeln(vaoIndex);
  sw.stop();

  glDeleteProgram(shaderProgram);
  glDeleteShader(fragmentShader);
  glDeleteShader(vertexShader);
  glDeleteBuffers(1, vbo.ptr);
  glDeleteVertexArrays(1, vao.ptr);

  glfwDestroyWindow(window);
  glfwTerminate();
}

extern(C) nothrow void mouse_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{

}

extern(C) nothrow void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{

    if ((action != 1 && action != 0) || (key != GLFW_KEY_W && key != GLFW_KEY_A && key != GLFW_KEY_S && key != GLFW_KEY_D
            && key != GLFW_KEY_F && key != GLFW_KEY_G && key != GLFW_KEY_B && key != GLFW_KEY_UP && key != GLFW_KEY_RIGHT
            && key != GLFW_KEY_DOWN && key != GLFW_KEY_LEFT))
    {
        return;
    }

    GLfloat[VECTOR_SIZE] movementVector = [0,0,0];

    try
    {
        switch (key)
        {
            case GLFW_KEY_W:
                wIsDown = action == 1;
                break;
            case GLFW_KEY_S:
                sIsDown = action == 1;
                break;
            case GLFW_KEY_A:
                aIsDown = action == 1;
                break;
            case GLFW_KEY_D:
                dIsDown = action == 1;
                break;
            case GLFW_KEY_F:
                fIsDown = action == 1;
                break;
            case GLFW_KEY_G:
                gIsDown = action == 1;
                break;
            case GLFW_KEY_B:
                bIsDown = action == 1;
                break;
            case GLFW_KEY_UP:
                upIsDown = action == 1;
                break;
            case GLFW_KEY_RIGHT:
                rightIsDown = action == 1;
                break;
            case GLFW_KEY_DOWN:
                downIsDown = action == 1;
                break;
            case GLFW_KEY_LEFT:
                leftIsDown = action == 1;
                break;
            default:
                break;
        }
    }
    catch (Exception e)
    {
        printf("Error while moving the camera.");
    }
}
