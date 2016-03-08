module _2imv10.sphere;

import mfellner.math;
import std.stdio;
import std.math;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;


void prepareSphereBuffers(GLfloat[] vertices, GLfloat[] normals, GLfloat[] colors, GLuint vao, GLuint[] vbo, GLuint nbo, GLuint vertexLoc, GLint vSize,
                GLsizei stride, GLuint colorLoc, GLint cSize, const GLvoid* cPointer, GLuint normalLoc, GLuint offsetLoc, GLuint obo, GLfloat[] offsets)
{
    // VAO for the sphere
    glBindVertexArray(vao);
    // Generate two slots for the vertex and color buffers
    glGenBuffers(2, vbo.ptr);
    // bind buffer for vertices and copy data into buffer
    glBindBuffer(GL_ARRAY_BUFFER, vbo[0]);
    glBufferData(GL_ARRAY_BUFFER, vertices.length * GLfloat.sizeof, vertices.ptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(vertexLoc);
    glVertexAttribPointer(vertexLoc, vSize, GL_FLOAT, GL_FALSE, stride, null);
    // bind buffer for colors and copy data into buffer
    glBindBuffer(GL_ARRAY_BUFFER, vbo[1]);
    glBufferData(GL_ARRAY_BUFFER, colors.length * GLfloat.sizeof, colors.ptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(colorLoc);
    glVertexAttribPointer(colorLoc, cSize, GL_FLOAT, GL_FALSE, stride, cPointer);

    glGenBuffers(1, &obo);
    glBindBuffer(GL_ARRAY_BUFFER, obo);
    glBufferData(GL_ARRAY_BUFFER, offsets.length * GLfloat.sizeof, offsets.ptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(offsetLoc);
    glBindBuffer(GL_ARRAY_BUFFER, obo);
    glVertexAttribPointer(
        offsetLoc,
        4,
        GL_FLOAT,
        GL_FALSE,
        stride,
        null
    );

    glGenBuffers(1, &nbo);
    glBindBuffer(GL_ARRAY_BUFFER, nbo);
    glBufferData(GL_ARRAY_BUFFER, normals.length * GLfloat.sizeof, normals.ptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(normalLoc);
    glBindBuffer(GL_ARRAY_BUFFER, nbo);
    glVertexAttribPointer
    (
        normalLoc,                         // attribute
        4,                                // size
        GL_FLOAT,                         // type
        GL_FALSE,                         // normalized?
        stride,                           // stride
        null                     // array buffer offset
    );
}

void drawSphere(GLuint vao, long vertexCount)
{
    glBindVertexArray(vao);
    glDrawArrays(GL_TRIANGLES, 0, cast(uint)vertexCount);
}

GLfloat[][] generateVerticesAndNormals(GLfloat[4] center, GLfloat radius, int rings , int sectors)
{
    GLfloat thetaStep = PI / rings;
    GLfloat phiStep = (2*PI) / sectors;

    GLfloat theta = 0;
    GLfloat phi = 0;

    GLfloat[4] topVertex;
    GLfloat[4] bottomVertex;
    GLfloat[][][] otherVertices  = new GLfloat[][][](rings, sectors, 4);

    topVertex = getCoordinate(theta, phi, center, radius);

    for (int ring = 0; ring < rings; ring++)
    {
        theta += thetaStep;
        phi = 0;
        for (int sector = 0; sector < sectors; sector++)
        {
            phi += phiStep;
            GLfloat[4] coordinates = getCoordinate(theta, phi, center, radius);
            otherVertices[ring][sector][0] = coordinates[0];
            otherVertices[ring][sector][1] = coordinates[1];
            otherVertices[ring][sector][2] = coordinates[2];
            otherVertices[ring][sector][3] = coordinates[3];
        }
    }

    bottomVertex = getCoordinate(-PI/2, 0, center, radius);

    GLfloat[] vertexArray;
    GLfloat[] normalArray;

    for (int sector = 0; sector < sectors; sector++)
    {
        vertexArray ~= topVertex;
        normalArray ~= getNormal(topVertex, center);

        vertexArray ~= otherVertices[0][sector];
        normalArray ~= getNormal(otherVertices[0][sector][0..4], center);

        vertexArray ~= otherVertices[0][(sector+1) % sectors];
        normalArray ~= getNormal(otherVertices[0][(sector+1) % sectors][0..4], center);
    }

    if (rings > 1)
    {
        for (int ring = 0; ring < rings-1; ring++)
        {
            for(int sector = 0; sector < sectors; sector++)
            {
                //1st triangle of sector
                vertexArray ~= otherVertices[ring][sector];
                normalArray ~= getNormal(otherVertices[ring][sector][0..4], center);

                vertexArray ~= otherVertices[ring][(sector+1)%sectors];
                normalArray ~= getNormal(otherVertices[ring][(sector+1)%sectors][0..4], center);

                vertexArray ~= otherVertices[ring+1][sector];
                normalArray ~= getNormal(otherVertices[ring+1][sector][0..4], center);

                //2nd triangle of sector
                vertexArray ~= otherVertices[ring][(sector+1)%sectors];
                normalArray ~= getNormal(otherVertices[ring][(sector+1)%sectors][0..4], center);

                vertexArray ~= otherVertices[ring+1][(sector+1)%sectors];
                normalArray ~= getNormal(otherVertices[ring+1][(sector+1)%sectors][0..4], center);

                vertexArray ~= otherVertices[ring+1][sector];
                normalArray ~= getNormal(otherVertices[ring+1][sector][0..4], center);

            }
        }
    }

    //bottom ring
    for (int sector = 0; sector < sectors; sector++)
    {
        vertexArray ~= bottomVertex;
        normalArray ~= getNormal(bottomVertex, center);

        vertexArray ~= otherVertices[rings-1][sector];
        normalArray ~= getNormal(otherVertices[rings-1][sector][0..4], center);

        vertexArray ~= otherVertices[rings-1][(sector+1) % sectors];
        normalArray ~= getNormal(otherVertices[rings-1][(sector+1) % sectors][0..4], center);
    }
    return [vertexArray, normalArray];
}

GLfloat[4] getCoordinate(GLfloat theta, GLfloat phi, GLfloat[4] center, GLfloat radius)
{
    GLfloat[4] result =
    [
        radius * sin(theta) * cos(phi) + center[0],
        radius * sin(theta) * sin(phi) + center[1],
        radius * cos(theta) + center[2],
        1.0
    ];

    return result;
}

GLfloat[4] getNormal(GLfloat[4] vertex, GLfloat[4] center)
{
    GLfloat[3] result = [0,0,0];
    subtract(vertex[0..3], center[0..3], result);
    normalize(result);
    return [result[0], result[1], result[2], 1.0];
}

GLfloat[] generateColorArray(GLfloat[] vertexArray)
{
    GLfloat[] colorArray;

    colorArray = new GLfloat[](vertexArray.length);
    for(int i = 0; i < colorArray.length; i++)
    {
        if (i % 4 == 0 || i % 4 == 1)
        {
            colorArray[i] = 0.0;
            continue;
        }
        colorArray[i] = 1.0;
    }

    return colorArray;
}