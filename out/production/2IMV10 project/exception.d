module mfellner.exception;

import core.stdc.stdio : fputs, fputc, stderr, printf;
import derelict.opengl3.gl3;

extern(C) nothrow void glfwPrintError(int error, const(char)* description) {
  fputs(description, stderr);
  fputc('\n', stderr);
}

void glCheckError() {
  GLuint errorCode = glGetError();
  if (errorCode != GL_NO_ERROR) {
     printf("OpenGL Error code %#08x\n", errorCode);
     throw new Exception("OpenGL encountered an error!");
  }
}
