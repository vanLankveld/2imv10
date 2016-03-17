import std.conv;
import std.file;
import std.math;
import std.stdio;
import std.range;
import std.string;
import std.random;
import std.datetime;

import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import gl3n.linalg;
import _2imv10.sphere;

import mfellner.exception;
import mfellner.math;

bool fullscreen = false;

GLuint vertexLoc, colorLoc, normalLoc;
GLuint projMatrixLoc, offsetLoc, viewMatrixLoc, lightIntensitiesLoc, lightPositionLoc, lightAmbientLoc;

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

GLfloat g = 0.3; // Gravity force
GLfloat h = 1.5; // Kernel size
GLfloat rho = 0.0008; // Rest density
GLfloat eps = 0.02; // Relaxation parameter

GLfloat binsize = 1.0; // Size of bins for spatial partitioning, should be at least 4*h

GLfloat absDQ = 0.2; // Fixed distance scaled in smoothing kernel for tensile instability stuff
GLfloat nPow = 4; // Power for that stuff
GLfloat kScale = 0.1; // Scalar for that stuff

GLfloat cScale = 0.01; // Scalar for viscocity

int solveIter = 3; // Number of corrective calculation cycles
int numUpdates = 5; // Number of updates per frame

int fps = 15; //Number of frames per second

ulong sphereVertexCount;

//Bounds
GLfloat[VECTOR_SIZE] boundsU = [3.5,3.5,3.5];
GLfloat[VECTOR_SIZE] boundsL = [-1.5,-3.5,-1.5];

//Camera position
GLfloat lookatX = 0;
GLfloat lookatY = 0;
GLfloat lookatZ = -1;

GLfloat cameraX = 4;
GLfloat cameraY = 1;
GLfloat cameraZ = 4;

GLfloat walkStepSize = 0.05;


// Data for drawing Axis
GLfloat[] verticesAxis = [
-20.0,  0.0,  0.0f, 1.0,
 20.0,  0.0,  0.0f, 1.0,
  0.0,-20.0,  0.0f, 1.0,
  0.0, 20.0,  0.0f, 1.0,
  0.0,  0.0,-20.0f, 1.0,
  0.0,  0.0, 20.0f, 1.0];

GLfloat[] colorAxis = [
  1.0, 0.0, 0.0, 1.0,
  1.0, 0.0, 0.0, 1.0,
  0.0, 1.0, 0.0, 1.0,
  0.0, 1.0, 0.0, 1.0,
  0.0, 0.0, 1.0, 1.0,
  0.0, 0.0, 1.0, 1.0];

bool wIsDown = false;
bool aIsDown = false;
bool sIsDown = false;
bool dIsDown = false;

bool checkExecutionTime = false;

void printProgramInfoLog(GLuint program) {
  GLint infologLength = 0;
  GLint charsWritten  = 0;

  glGetProgramiv(program, GL_INFO_LOG_LENGTH, &infologLength);

  if (infologLength > 0) {
    char[] infoLog;
    //glGetProgramInfoLog(program, infologLength, &charsWritten, infoLog.ptr);
    //Generates errors for Leo
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

  GLint status;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
  if (status != GL_TRUE) {
    throw new Exception("Failed to compile shader");
  }

  GLint infologLength;
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

  setTranslationMatrix(aux, -posX, -posY, -posZ);

  multMatrix(viewMatrix, aux);
}

void predictPositions(ref GLfloat[VECTOR_SIZE][] parAux, ref GLfloat dt){
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
            parVel[sphereIndex] = [parVel[sphereIndex][0], parVel[sphereIndex][1] - g*dt, parVel[sphereIndex][2]];
            for (int j = 0; j < VECTOR_SIZE; j++){
                parAux[sphereIndex][j] = parPos[sphereIndex][j] + parVel[sphereIndex][j]*dt;
            }
        }
}

void boundPositions(ref GLfloat[VECTOR_SIZE][] parAux){

        for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
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
        for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
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
    for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
    {
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
        for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
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
        for (int sphereIndex = to!int(sphereIndices.length) - 1; sphereIndex >= 0; sphereIndex--)
        {
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
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

    GLFWwindow* window;

    if (fullscreen)
    {
        window = glfwCreateWindow(640, 480, "Hello Blueberries", glfwGetPrimaryMonitor(), null);
    }
    else
    {
        window = glfwCreateWindow(640, 480, "Hello Blueberries", null, null);
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

    //////////////////////////////////////////////////////////////////////////////
    // Prepare shader program
    GLuint vertexShader   = compileShader("source/shader/minimal.vert", GL_VERTEX_SHADER);
    GLuint fragmentShader = compileShader("source/shader/minimal.frag", GL_FRAGMENT_SHADER);

    GLuint shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertexShader);
    glAttachShader(shaderProgram, fragmentShader);
    glBindFragDataLocation(shaderProgram, 0, "outColor");
    glLinkProgram(shaderProgram);
    printProgramInfoLog(shaderProgram);

    vertexLoc = glGetAttribLocation(shaderProgram,"position");
    colorLoc = glGetAttribLocation(shaderProgram, "color");
    normalLoc = glGetAttribLocation(shaderProgram, "normal");
    offsetLoc = glGetAttribLocation(shaderProgram, "offset");

    projMatrixLoc = glGetUniformLocation(shaderProgram, "projMatrix");
    viewMatrixLoc = glGetUniformLocation(shaderProgram, "viewMatrix");
    lightPositionLoc = glGetUniformLocation(shaderProgram, "lightPosition");
    lightIntensitiesLoc = glGetUniformLocation(shaderProgram, "lightIntensities");
    lightAmbientLoc = glGetUniformLocation(shaderProgram, "lightAmbient");
    glCheckError();

    GLuint[2] vbo;
    GLuint nbo;
    GLuint obo;
    glGenVertexArrays(1000000, vao.ptr);
    GLint            vSize = 4, cSize = 3;
    GLsizei         stride = 4 * float.sizeof;
    const GLvoid* cPointer = null; //cast(void*)(? * GLfloat.sizeof);

    //////////////////////////////////////////////////////////////////////////////
    // VAO for the Axis
    glBindVertexArray(vao[0]);
    // Generate two slots for the vertex and color buffers
    glGenBuffers(2, vbo.ptr);
    // bind buffer for vertices and copy data into buffer
    glBindBuffer(GL_ARRAY_BUFFER, vbo[0]);
    glBufferData(GL_ARRAY_BUFFER, verticesAxis.length * GLfloat.sizeof, verticesAxis.ptr, GL_STATIC_DRAW);
    glEnableVertexAttribArray(vertexLoc);
    glVertexAttribPointer(vertexLoc, vSize, GL_FLOAT, GL_FALSE, stride, null);
    // bind buffer for colors and copy data into buffer
    glBindBuffer(GL_ARRAY_BUFFER, vbo[1]);
    glBufferData(GL_ARRAY_BUFFER, colorAxis.length * GLfloat.sizeof, colorAxis.ptr, GL_STATIC_DRAW);
    glEnableVertexAttribArray(colorLoc);
    glVertexAttribPointer(colorLoc, cSize, GL_FLOAT, GL_FALSE, stride, cPointer);
    glCheckError();

    int width, height;
    glfwGetWindowSize(window, &width, &height);
    reshape(window, width, height);

    sphereData = generateVerticesAndNormals([0,0,0 ,1.0], 0.12, 6 , 12);
    sphereVertexTemplates = sphereData[0];
    sphereNormals = sphereData[1];
    sphereColors = generateColorArray(sphereVertexTemplates);

    GLfloat[] vertices;
    GLfloat[] normals;
    GLfloat[] colors;
    GLuint vaoIndex = 1;

    int spheresX = 1;
    int spheresY = 1;
    int spheresZ = 1;

    writeln("build vertices for spheres");

    for (int i = 0; i < spheresX; i++)
    {
      GLfloat cX = 0.2 * i + uniform(0.0, 0.15);
      for (int j = 0; j < spheresY; j++)
      {
          GLfloat cY = 0.2 * j + uniform(0.0, 0.15);
          for (int k = 0; k < spheresZ; k++)
          {
              GLfloat cZ = 0.2 * k + uniform(0.0, 0.15);
              GLfloat[VECTOR_SIZE] center = [cX, cY, cZ];
              createParticle(center, vaoIndex);
              vaoIndex++;
          }
      }
    }

    GLfloat[][] gVaA = generateVerticesAndNormals([0, 0, 0, 1.0], 0.08, 6 , 12);
    vertices = gVaA[0];
    sphereVertexCount = vertices.length;

    //writeln(sphereVertexCount * vaoIndex-1);

  int i = 0, k = 1;
  uint frame = 0;
  auto range = iota(-100, 100);

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Tests
////////////

  GLfloat[VECTOR_SIZE] movementVector = [0,0,0];
  glUseProgram(shaderProgram);
  glUniform3fv(cast(uint)lightPositionLoc, 1, cast(const(float)*)[cameraX, cameraY, cameraZ]);
  glUniform3fv(cast(uint)lightIntensitiesLoc, 1, cast(const(float)*)[1f,1f,1f]);
  glUniform3fv(cast(uint)lightAmbientLoc, 1, cast(const(float)*)[0.1f,0.1f,0.1f]);

  int iter = 0;

  StopWatch sw;

  while (!glfwWindowShouldClose(window)) {
    TickDuration frameStart = sw.peek();
    sw.start();
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    movementVector = [0,0,0];

    if(wIsDown)
    {
        GLfloat[VECTOR_SIZE] dMovementVector = getMovementInXZPlane(lookatX, lookatZ, cameraX, cameraZ, 0, walkStepSize);
        add(movementVector, dMovementVector, movementVector);
    }
    if(sIsDown)
    {
        GLfloat[VECTOR_SIZE] dMovementVector = getMovementInXZPlane(lookatX, lookatZ, cameraX, cameraZ, 1, walkStepSize);
        add(movementVector, dMovementVector, movementVector);
    }
    if(aIsDown)
    {
        GLfloat[VECTOR_SIZE] dMovementVector = getMovementInXZPlane(lookatX, lookatZ, cameraX, cameraZ, 2, walkStepSize);
        add(movementVector, dMovementVector, movementVector);
    }
    if(dIsDown)
    {
        GLfloat[VECTOR_SIZE] dMovementVector = getMovementInXZPlane(lookatX, lookatZ, cameraX, cameraZ, 3, walkStepSize);
        add(movementVector, dMovementVector, movementVector);
    }

    lookatX += movementVector[0];
    lookatZ += movementVector[1];
    cameraX += movementVector[0];
    cameraZ += movementVector[1];

    setCamera(cameraX, cameraY, cameraZ, lookatX, lookatY, lookatZ);
    setUniforms();


    //////////////////////////////////////////////////////////////////////////////
    // Update the points
    TickDuration startUpdate = sw.peek();
    for (int u = 0; u < numUpdates; u++){
        updateState(1.0/cast(GLfloat) fps);

        if(iter%(4*fps) == 0){
              createParticle([uniform(-0.1, 0.1),boundsU[1],uniform(-0.1, 0.1)], vaoIndex);
              vaoIndex++;
        }

        iter++;
    }
    TickDuration endUpdate = sw.peek()-startUpdate;

    GLfloat[] offsets;
    TickDuration startRender = sw.peek();
    for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
    {
        offsets ~= [parPos[sphereIndex][0], parPos[sphereIndex][1], parPos[sphereIndex][2], 1.0];
    }

    prepareSphereBuffers(sphereVertexTemplates, sphereNormals, sphereColors, vao[1], vbo, nbo, vertexLoc, vSize,
                                           stride,  colorLoc, cSize, cPointer, normalLoc);

    glGenBuffers(1, &obo);
    glBindBuffer(GL_ARRAY_BUFFER, obo);
    glBufferData(GL_ARRAY_BUFFER, 4 * GLfloat.sizeof * sphereIndices.length, &offsets[0], GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(offsetLoc);
    glVertexAttribPointer(
        offsetLoc,
        4,
        GL_FLOAT,
        GL_FALSE,
        stride,
        null
    );
    glBindBuffer(GL_ARRAY_BUFFER, vertexLoc);
    glVertexAttribDivisor(offsetLoc, 1);

    glBindVertexArray(vao[1]);
    glDrawArraysInstanced(GL_TRIANGLES, 0, cast(int)sphereVertexTemplates.length, cast(int)sphereIndices.length);
    glCheckError();

    //prepareSphereBuffers(sphereVertexTemplates, sphereNormals, sphereColors, vaoSpheres, vbo, nbo, vertexLoc, vSize,
    //                                     stride,  colorLoc, cSize, cPointer, normalLoc);
    //glCheckError();
    //drawSphere(vaoSpheres, sphereVertexTemplates.length);

    //Draw axis
    glBindVertexArray(vao[0]);
    glDrawArrays(GL_LINES, 0, 6);

    TickDuration endRender = sw.peek()-startRender;

    glfwSwapBuffers(window);
    glfwPollEvents();
    sw.stop();
    TickDuration frameEnd = sw.peek()-frameStart;
    float frameRate = 1000f/frameEnd.msecs;

    if(checkExecutionTime)
        {
            checkExecutionTime = false;
            printf("%d,%d,%.4f\n", endUpdate.msecs, endRender.msecs, frameRate);
        }

    if (fullscreen && glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
      glfwSetWindowShouldClose(window, GL_TRUE);
  }

  glDeleteProgram(shaderProgram);
  glDeleteShader(fragmentShader);
  glDeleteShader(vertexShader);
  glDeleteBuffers(1, vbo.ptr);
  glDeleteVertexArrays(1, vao.ptr);

  glfwDestroyWindow(window);
  glfwTerminate();
}

extern(C) nothrow void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{

    if ((action != 1 && action != 0) || (key != GLFW_KEY_W && key != GLFW_KEY_A && key != GLFW_KEY_S && key != GLFW_KEY_D))
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
            default:
                break;
        }
    }
    catch (Exception e)
    {
        printf("Error while moving the camera.");
    }
}
