module mfellner.exception;

import core.stdc.stdio : fputs, fputc, stderr;
import derelict.opengl3.gl3;
import std.stdio;
import std.format;

extern(C) nothrow void glfwPrintError(int error, const(char)* description) {
  fputs(description, stderr);
  fputc('\n', stderr);
}

void glCheckError(string indicator) {
  GLenum err = glGetError();
  if (err != GL_NO_ERROR) {
    writeln(format("OpenGL error code: %x at '%s'", err, indicator));
     throw new Exception("OpenGL encountered an error!");
  }
}
