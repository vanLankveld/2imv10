module _2imv10.particle;

import std.stdio;
import std.math;
import mfellner.math;
import mfellner.exception;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;

struct ParticleContainer{
    GLfloat[4] position;
    GLubyte[4] color;
	GLfloat cameraDistance;
	bool isSolid = false;
};

void createParticleBuffers(const(GLfloat[]) g_vertex_buffer_data, ref GLuint billboard_vertex_buffer, ref GLuint particles_position_buffer,
                            ref GLuint particles_color_buffer, const(int) ParticlesCount)
{
    glGenBuffers(1, &billboard_vertex_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, billboard_vertex_buffer);
    glBufferData(GL_ARRAY_BUFFER, g_vertex_buffer_data.length * GLfloat.sizeof, g_vertex_buffer_data.ptr, GL_STATIC_DRAW);

    // The VBO containing the positions and sizes of the particles
    glGenBuffers(1, &particles_position_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, particles_position_buffer);
    glBufferData(GL_ARRAY_BUFFER, ParticlesCount * 4 * GLfloat.sizeof, null, GL_STREAM_DRAW);

    glGenBuffers(1, &particles_color_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, particles_color_buffer);
    glBufferData(GL_ARRAY_BUFFER, ParticlesCount * 4 * GLubyte.sizeof, null, GL_STREAM_DRAW);
}

void updateParticleBuffers(ref GLuint particles_position_buffer, ref GLuint particles_color_buffer, GLuint ParticlesCount,
                           GLfloat[] g_particule_position_size_data, GLubyte[] g_particule_color_data)
{
    glBindBuffer(GL_ARRAY_BUFFER, particles_position_buffer);
    glBufferData(GL_ARRAY_BUFFER, ParticlesCount * 4 * GLfloat.sizeof, null, GL_STREAM_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, ParticlesCount * GLfloat.sizeof * 4, cast(const(void)*)g_particule_position_size_data);

    glBindBuffer(GL_ARRAY_BUFFER, particles_color_buffer);
    glBufferData(GL_ARRAY_BUFFER, ParticlesCount * 4 * GLubyte.sizeof, null, GL_STREAM_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, ParticlesCount * GLubyte.sizeof * 4, cast(const(void)*)g_particule_color_data);
}

void drawParticles(ref GLuint vao, ref GLuint billboard_vertex_buffer, ref GLuint particles_position_buffer, ref GLuint particles_color_buffer,
                    ref GLuint squareVerticesLoc, ref GLuint xyzsLoc, ref GLuint colorLoc, int ParticlesCount)
{

    glEnableVertexAttribArray(squareVerticesLoc);
    glBindBuffer(GL_ARRAY_BUFFER, billboard_vertex_buffer);
    glVertexAttribPointer(
         squareVerticesLoc,
         3, // size
         GL_FLOAT, // type
         GL_FALSE, // normalized?
         0, // stride
         cast(void*)0 // array buffer offset
    );

    // 2nd attribute buffer : positions of particles' centers
    glEnableVertexAttribArray(xyzsLoc);
    glBindBuffer(GL_ARRAY_BUFFER, particles_position_buffer);
    glVertexAttribPointer(
        xyzsLoc,
        4, // size : x + y + z + size => 4
        GL_FLOAT, // type
        GL_FALSE, // normalized?
        0, // stride
        cast(void*)0 // array buffer offset
    );
    glCheckError("1");

    // 3rd attribute buffer : particles' colors
    glEnableVertexAttribArray(colorLoc);
    glBindBuffer(GL_ARRAY_BUFFER, particles_color_buffer);
    glVertexAttribPointer(
        colorLoc,
        4, // size : r + g + b + a => 4
        GL_UNSIGNED_BYTE, // type
        GL_TRUE, // normalized? *** YES, this means that the unsigned char[4] will be accessible with a vec4 (floats) in the shader ***
        0, // stride
        cast(void*)0 // array buffer offset
    );

    glVertexAttribDivisor(squareVerticesLoc, 0); // particles vertices : always reuse the same 4 vertices -> 0
    glVertexAttribDivisor(xyzsLoc, 1); // positions : one per quad (its center) -> 1
    glVertexAttribDivisor(colorLoc, 1); // color : one per quad -> 1

    glBindVertexArray(vao);
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, ParticlesCount);
}