module _2imv10.text;

import std.conv;
import std.file;
import std.math;
import std.stdio;
import std.range;
import std.string;
import std.random;

import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;
import derelict.freetype.ft;

import _2imv10.shaderUtil;

import mfellner.exception;
import mfellner.math;

FT_Library ft;
FT_Face face;

GLuint program;
GLint attribute_coord;
GLint uniform_tex;
GLint uniform_color;

int test;

GLuint textVbo;

void initTextLibs() {
    DerelictFT.load();
    FT_Init_FreeType(&ft);

    FT_New_Face(ft, "OpenSans-Regular.ttf", 0, &face);
}

GLuint initTextRendering() {
    GLuint textVertexShader   = compileShader("source/shader/text.vert", GL_VERTEX_SHADER);
    GLuint textFragmentShader = compileShader("source/shader/text.frag", GL_FRAGMENT_SHADER);

    GLuint textShaderProgram = glCreateProgram();
    glAttachShader(textShaderProgram, textVertexShader);
    glAttachShader(textShaderProgram, textFragmentShader);
    glLinkProgram(textShaderProgram);
    printProgramInfoLog(textShaderProgram);

    attribute_coord = glGetAttribLocation(textShaderProgram, "coord");
    uniform_tex = glGetUniformLocation(textShaderProgram, "tex");
    uniform_color = glGetUniformLocation(textShaderProgram, "color");

    glGenBuffers(1, &textVbo);

    glCheckError();

    return textShaderProgram;
}

void render_text(const char *text, float x, float y, float sx, float sy) {
	FT_Set_Pixel_Sizes(face, 0, 48);
	char* p;
	FT_GlyphSlot g = face.glyph;

	//Create a texture that will be used to hold one "glyph" 
	GLuint tex;
	glActiveTexture(GL_TEXTURE0);
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glUniform1i(uniform_tex, 0);
	glUniform4fv(uniform_color, 1, cast(const(float)*)[1f, 1f, 1f, 1f]);

	//We require 1 byte alignment when uploading texture data 
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

	//Clamping to edges is important to prevent artifacts when scaling 
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

	//Linear filtering usually looks best for text 
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	//Set up the VBO for our vertex data 
	glEnableVertexAttribArray(attribute_coord);
	glBindBuffer(GL_ARRAY_BUFFER, textVbo);
	glVertexAttribPointer(attribute_coord, 4, GL_FLOAT, GL_FALSE, 4 * float.sizeof, null);

	//Loop through all characters 
	for (p = cast(char*)text; *p; p++) {
		//Try to load and render the character
		if (FT_Load_Char(face, *p, FT_LOAD_RENDER))
			continue;

        //Upload the "bitmap", which contains an 8-bit grayscale image, as an alpha texture
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, g.bitmap.width, g.bitmap.rows, 0,
                        GL_RED, GL_UNSIGNED_BYTE, g.bitmap.buffer);

		//Calculate the vertex and texture coordinates
		GLfloat x2 = x + g.bitmap_left * sx;
		GLfloat y2 = -y - g.bitmap_top * sy;
		GLfloat w = g.bitmap.width * sx;
		GLfloat h = g.bitmap.rows * sy;

        GLfloat[] vertices = [
            x2, -y2, 0, 0,
            x2 + w, -y2, 1, 0,
            x2, -y2 - h, 0, 1,
            x2 + w, -y2 - h, 1, 1
        ];

		//Draw the character on the screen
		glBufferData(GL_ARRAY_BUFFER, vertices.length * GLfloat.sizeof, vertices.ptr, GL_DYNAMIC_DRAW);
		glDrawArrays(GL_TRIANGLES, 0, cast(int)vertices.length);

		// Advance the cursor to the start of the next character
		x += (g.advance.x >> 6) * sx;
		y += (g.advance.y >> 6) * sy;
	}

	glDisableVertexAttribArray(attribute_coord);
	glDeleteTextures(1, &tex);
}