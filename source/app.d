import std.conv;
import std.file;
import std.math;
import std.stdio;
import std.range;
import std.string;
import std.random;

import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import _2imv10.sphere;

import mfellner.exception;
import mfellner.math;

bool fullscreen = false;

GLuint vertexLoc, colorLoc, normalLoc;
GLuint projMatrixLoc, viewMatrixLoc, lightIntensitiesLoc, lightPositionLoc, lightAmbientLoc;

GLfloat[MATRIX_SIZE] projMatrix;
GLfloat[MATRIX_SIZE] viewMatrix;

GLuint[1000000] vao;

GLuint[] sphereIndices; // Particle indices for vao
GLfloat[3][] parPos; // Current particle positions
GLfloat[3][] parAux; // Auxiliary particle positions
GLfloat[3][] parDP; // Current particle delta p
GLfloat[3][] parVel; // Current particle velocities
GLfloat[] parLam; // Current particle lambda values

GLfloat g = 0.3; // Gravity force
GLfloat h = 0.075; // Kernel size
GLfloat rho = 0.008; // Rest density
GLfloat eps = 0.02; // Relaxation parameter

GLfloat absDQ = 0.2; // Fixed distance scaled in smoothing kernel for tensile instability stuff
GLfloat nPow = 4; // Power for that stuff
GLfloat kScale = 0.1; // Scalar for that stuff

int solveIter = 3; // Number of corrective calculation cycles
int numUpdates = 5; // Number of updates per frame

int fps = 30; //Number of frames per second

ulong sphereVertexCount;

//Bounds
GLfloat[VECTOR_SIZE] bounds = [0.5,1.5,0.5];

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

// Updates the state of particles for a time difference dt
void updateState(GLfloat dt){

    for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
    {
        parVel[sphereIndex] = [parVel[sphereIndex][0], parVel[sphereIndex][1] - g*dt, parVel[sphereIndex][2]];
        for (int j = 0; j < VECTOR_SIZE; j++){
            parAux[sphereIndex][j] = parPos[sphereIndex][j] + parVel[sphereIndex][j]*dt;
        }

    }

    for (int i = 0; i < solveIter; i++){

        for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
        {
            GLfloat rhoi = 0;
            for (int neighIndex = cast(int)sphereIndices.length - 1; neighIndex >= 0; neighIndex--)
            {
                if(sphereIndex != neighIndex){
                    rhoi += IKGaussFromDist(distance(subtract(parAux[sphereIndex], parAux[neighIndex])), h);
                }
            }

            GLfloat PkSum = 0;
            for (int neighIndex = cast(int)sphereIndices.length - 1; neighIndex >= 0; neighIndex--)
            {
                GLfloat summand = 0;
                if(sphereIndex != neighIndex){
                    GLfloat[VECTOR_SIZE] db = dbIKGauss(subtract(parAux[sphereIndex], parAux[neighIndex]), h);
                    summand = selfDotProduct(db);
                } else {
                    for (int neighIndex2 = cast(int)sphereIndices.length - 1; neighIndex2 >= 0; neighIndex2--)
                    {
                        if(sphereIndex != neighIndex2){
                            GLfloat[VECTOR_SIZE] da = daIKGauss(subtract(parAux[sphereIndex], parAux[neighIndex2]), h);
                            summand += selfDotProduct(da);
                        }
                    }
                }
                PkSum += summand;
            }
            PkSum /= (rho*rho);

            parLam[sphereIndex] = (rhoi/rho - 1)/(PkSum + eps);
        }

        for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
        {
            GLfloat[VECTOR_SIZE] dp = [0,0,0];
            for (int neighIndex = cast(int)sphereIndices.length - 1; neighIndex >= 0; neighIndex--)
            {
                if(sphereIndex != neighIndex){
                    GLfloat sCorr =  -kScale;
                    GLfloat frac = IKGaussFromDist(distance(subtract(parAux[sphereIndex], parAux[neighIndex])), h)/IKGaussFromDist(absDQ*h, h);
                    for (int n = 0; n < nPow; n++){
                        sCorr *= frac;
                    }
                    GLfloat scalar = parLam[sphereIndex] + parLam[neighIndex] + sCorr;
                    GLfloat[VECTOR_SIZE] da = daIKGauss(subtract(parAux[sphereIndex], parAux[neighIndex]), h);
                    dp = [dp[0] + da[0]*scalar, dp[1] + da[1]*scalar, dp[2] + da[2]*scalar];
                }
            }
            parDP[sphereIndex] = dp;
            //Collision detection with aquarium (faulty)
            for (int j = 0; j < 3; j++){
                if(parDP[sphereIndex][j] + parAux[sphereIndex][j] > bounds[j]){
                    parDP[sphereIndex][j] = bounds[j] - parAux[sphereIndex][j];
                } else if(parDP[sphereIndex][j] + parAux[sphereIndex][j] < -bounds[j]){
                    parDP[sphereIndex][j] = -bounds[j] - parAux[sphereIndex][j];
                }
            }
        }

        for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
        {
            for (int j = 0; j < VECTOR_SIZE; j++){
                parAux[sphereIndex][j] = parDP[sphereIndex][j] + parAux[sphereIndex][j];
            }
        }
    }

    for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
    {
        for (int j = 0; j < VECTOR_SIZE; j++){
            parVel[sphereIndex][j] = (parAux[sphereIndex][j] - parPos[sphereIndex][j])/dt;
        }
        parPos[sphereIndex] = parAux[sphereIndex];
    }

}

// Creates a new particle from position p
void createParticle(GLfloat[VECTOR_SIZE] p, int vaoIndex){
    sphereIndices ~= vaoIndex;
    parPos ~= p;
    parAux ~= [0,0,0];
    parDP ~= [0,0,0];
    parVel ~= [0,0,0];
    parLam ~= [0,0,0];
}

// adapted from http://open.gl/drawing and
// http://www.lighthouse3d.com/cg-topics/code-samples/opengl-3-3-glsl-1-5-sample
void main() {
  DerelictGL3.load();
  DerelictGLFW3.load();

  glfwSetErrorCallback(&glfwPrintError);

  if(!glfwInit()) {
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

  if (fullscreen) {
    window = glfwCreateWindow(640, 480, "Hello Blueberries", glfwGetPrimaryMonitor(), null);
  } else {
    window = glfwCreateWindow(640, 480, "Hello Blueberries", null, null);
  }

  if (!window) {
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

  projMatrixLoc = glGetUniformLocation(shaderProgram, "projMatrix");
  viewMatrixLoc = glGetUniformLocation(shaderProgram, "viewMatrix");
  lightPositionLoc = glGetUniformLocation(shaderProgram, "lightPosition");
  lightIntensitiesLoc = glGetUniformLocation(shaderProgram, "lightIntensities");
  lightAmbientLoc = glGetUniformLocation(shaderProgram, "lightAmbient");
  glCheckError();

  GLuint[2] vbo;
  GLuint nbo;
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
              GLfloat[3] center = [cX, cY, cZ];
              createParticle(center, vaoIndex);
              /*GLfloat[][] sphereData = generateVerticesAndNormals([center[0], center[1], center[2], 1.0], 0.08, 6 , 12);
              vertices = sphereData[0];
              normals = sphereData[1];
              colors = generateColorArray(vertices);
              prepareSphereBuffers(vertices, normals, colors, vao[vaoIndex], vbo, nbo, vertexLoc, vSize,
                                   stride,  colorLoc, cSize, cPointer, normalLoc);
              glCheckError();*/
              vaoIndex++;
          }
      }
    }

    GLfloat[][] gVaA = generateVerticesAndNormals([0, 0, 0, 1.0], 0.08, 6 , 12);
    vertices = gVaA[0];
    sphereVertexCount = vertices.length;

    writeln(sphereVertexCount * vaoIndex-1);

  int i = 0, k = 1;
  uint frame = 0;
  auto range = iota(-100, 100);

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Tests
  writeln(daIKGauss([0,0,1],h));
  writeln("end tests");


  GLfloat[VECTOR_SIZE] movementVector = [0,0,0];
  glUseProgram(shaderProgram);
  glUniform3fv(cast(uint)lightPositionLoc, 1, cast(const(float)*)[cameraX, cameraY, cameraZ]);
  glUniform3fv(cast(uint)lightIntensitiesLoc, 1, cast(const(float)*)[1f,1f,1f]);
  glUniform3fv(cast(uint)lightAmbientLoc, 1, cast(const(float)*)[0.1f,0.1f,0.1f]);

  int iter = 0;

  while (!glfwWindowShouldClose(window)) {
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
    for (int u = 0; u < numUpdates; u++){
        updateState(1.0/cast(GLfloat) fps);

        if(iter%(4*fps) == 0){
              createParticle([uniform(-0.1, 0.1),0.5,uniform(-0.1, 0.1)], vaoIndex);
              vaoIndex++;
              writeln(vaoIndex);
        }

        iter++;
    }

    // Update spheres
    for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
    {
              GLfloat[][] sphereData = generateVerticesAndNormals([parPos[sphereIndex][0] ,parPos[sphereIndex][1] ,parPos[sphereIndex][2] ,1.0], 0.12, 6 , 12);
              vertices = sphereData[0];
              normals = sphereData[1];
              colors = generateColorArray(vertices);
              prepareSphereBuffers(vertices, normals, colors, vao[sphereIndices[sphereIndex]], vbo, nbo, vertexLoc, vSize,
                                   stride,  colorLoc, cSize, cPointer, normalLoc);
              glCheckError();
    }

    //////////////////////////////////////////////////////////////////////////////
    // Draw the spheres

    for (int sphereIndex = cast(int)sphereIndices.length - 1; sphereIndex >= 0; sphereIndex--)
    {
        GLuint vao = vao[sphereIndices[sphereIndex]];
        drawSphere(vao, sphereVertexCount);
    }

    //Draw axis
    glBindVertexArray(vao[0]);
    glDrawArrays(GL_LINES, 0, 6);

    glfwSwapBuffers(window);
    glfwPollEvents();


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
