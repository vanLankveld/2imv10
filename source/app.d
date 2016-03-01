import std.conv;
import std.file;
import std.math;
import std.stdio;
import std.range;
import std.string;

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

GLuint[] sphereIndices;
ulong sphereVertexCount;

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
    window = glfwCreateWindow(640, 480, "Hello World", glfwGetPrimaryMonitor(), null);
  } else {
    window = glfwCreateWindow(640, 480, "Hello World", null, null);
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

    int spheresX = 5;
    int spheresY = 5;
    int spheresZ = 5;

    writeln("build vertices for spheres");

    for (int i = 0; i < spheresX; i++)
    {
      GLfloat cX = 0.2 * i;
      for (int j = 0; j < spheresY; j++)
      {
          GLfloat cY = 0.2 * j;
          for (int k = 0; k < spheresZ; k++)
          {
              GLfloat cZ = 0.2 * k;
              GLfloat[][] sphereData = generateVerticesAndNormals([cX, cY, cZ, 1.0], 0.08, 6 , 12);
              vertices = sphereData[0];
              normals = sphereData[1];
              colors = generateColorArray(vertices);
              prepareSphereBuffers(vertices, normals, colors, vao[vaoIndex], vbo, nbo, vertexLoc, vSize,
                                   stride,  colorLoc, cSize, cPointer, normalLoc);
              glCheckError();
              sphereIndices ~= [vaoIndex];
              sphereVertexCount = vertices.length;
              vaoIndex++;
          }
      }
    }

  writeln(sphereVertexCount * vaoIndex-1);

  int i = 0, k = 1;
  uint frame = 0;
  auto range = iota(-100, 100);

  GLfloat[VECTOR_SIZE] movementVector = [0,0,0];
  glUseProgram(shaderProgram);
  glUniform3fv(cast(uint)lightPositionLoc, 1, cast(const(float)*)[cameraX, cameraY, cameraZ]);
  glUniform3fv(cast(uint)lightIntensitiesLoc, 1, cast(const(float)*)[1f,1f,1f]);
  glUniform3fv(cast(uint)lightAmbientLoc, 1, cast(const(float)*)[0.1f,0.1f,0.1f]);

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
    // Draw the spheres

    for (int sphereIndex = 0; sphereIndex < sphereIndices.length; sphereIndex++)
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
