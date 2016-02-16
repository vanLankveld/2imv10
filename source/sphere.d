module _2imv10.sphere;

import std.stdio;
import std.math;
import derelict.opengl3.gl3;
import derelict.glfw3.glfw3;

class Sphere
{
    private GLfloat[3] topVertex;
    private GLfloat[3] bottomVertex;
    private GLfloat[][][] otherVertices;

    private GLfloat[3] center;
    private GLfloat radius;
    private int rings;
    private int sectors;

    this(GLfloat centerX, GLfloat centerY, GLfloat centerZ, GLfloat radiusArg, int ringsArg , int sectorsArg)
    {
        this.center[0] = centerX;
        this.center[1] = centerY;
        this.center[2] = centerZ;
        this.radius = radiusArg;
        this.rings = ringsArg;
        this.sectors = sectorsArg;

        this.otherVertices = new GLfloat[][][](rings, sectors, 3);

        writeln(this.otherVertices);

        this.generateVertices();
    }

    private void generateVertices()
    {
        GLfloat thetaStep = PI / this.rings;
        GLfloat phiStep = (2*PI) / this.sectors;

        GLfloat theta = 0;
        GLfloat phi = 0;

        this.topVertex = this.getCoordinate(theta, phi);

        for (int ring = 0; ring < this.rings; ring++)
        {
            theta += thetaStep;
            phi = 0;
            for (int sector = 0; sector < this.sectors; sector++)
            {
                phi += phiStep;
                GLfloat[3] coordinates = this.getCoordinate(theta, phi);
                writeln(coordinates);
                this.otherVertices[ring][sector][0] = coordinates[0];
                this.otherVertices[ring][sector][1] = coordinates[1];
                this.otherVertices[ring][sector][2] = coordinates[2];
            }
        }

        this.bottomVertex = this.getCoordinate(-PI/2, 0);
    }

    private GLfloat[3] getCoordinate(GLfloat theta, GLfloat phi)
    {
        GLfloat[3] result =
        [
            this.radius * sin(theta) * cos(phi),
            this.radius * sin(theta) * sin(phi),
            this.radius * cos(theta)
        ];

        return result;
    }

    public void drawSphere()
    {

    }
}