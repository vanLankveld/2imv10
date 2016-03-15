module _2imv10.text;

import std.stdio;

import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import derelict.freetype.ft;

FT_Library ft;
FT_Face face;

GLuint program;
GLint attribute_coord;
GLint uniform_tex;
GLint uniform_color;

GLint vbo;

void initTextRendering() {
/*    DerelictFT.load();
    FT_Init_FreeType(&ft);

    FT_New_Face(ft, "OpenSans-Regular.ttf", 0, &face);
    FT_Set_Pixel_Sizes(face, 0, 32);

    program = create_program("text.v.glsl", "text.f.glsl");

    attribute_coord = get_attrib(program, "coord");
    uniform_tex = get_uniform(program, "tex");
    uniform_color = get_uniform(program, "color");

    glGenBuffers(1, &vbo);*/
}