module _2imv10.shaderUtil;

import std.conv;
import std.file;
import std.math;
import std.stdio;
import std.range;
import std.string;

import derelict.opengl3.gl3;

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
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infologLength);
  if (status != GL_TRUE) {
    if (infologLength > 0) {
      char[] buffer = new char[infologLength];
      glGetShaderInfoLog(shader, infologLength, null, buffer.ptr);
      writeln(buffer);
    }
    throw new Exception("Failed to compile shader");
  }

  if (infologLength > 0) {
    char[] buffer = new char[infologLength];
    glGetShaderInfoLog(shader, infologLength, null, buffer.ptr);
    writeln(buffer);
  } else {
    writeln("no shader info log");
  }
  return shader;
}


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