module mfellner.math;

import std.math;
import derelict.opengl3.gl3;

const GLuint MATRIX_SIZE = 16;
const GLuint VECTOR_SIZE =  3;

// res = a cross b;
void crossProduct(ref GLfloat[VECTOR_SIZE] a, ref GLfloat[VECTOR_SIZE] b, ref GLfloat[VECTOR_SIZE] res) {
  res[0] = a[1] * b[2] - b[1] * a[2];
  res[1] = a[2] * b[0] - b[2] * a[0];
  res[2] = a[0] * b[1] - b[0] * a[1];
}

GLfloat[VECTOR_SIZE] add(GLfloat[VECTOR_SIZE] a, GLfloat[VECTOR_SIZE] b)
{
    GLfloat[VECTOR_SIZE] result =
    [
        a[0] + b[0],
        a[1] + b[1],
        a[2] + b[2]
    ];
    return result;
}
 
// normalize a vec3
void normalize(ref GLfloat[VECTOR_SIZE] a) {
  float mag = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  a[0] /= mag;
  a[1] /= mag;
  a[2] /= mag;
}

// sets the square matrix mat to the identity matrix,
// size refers to the number of rows (or columns)
nothrow void setIdentityMatrix(ref GLfloat[MATRIX_SIZE] mat, GLint size) {
    // fill matrix with 0
    for (int i = 0; i < size * size; i++)
      mat[i] = 0.0;
    // fill diagonal with 1
    for (int i = 0; i < size; i++)
        mat[i + i * size] = 1.0;
}

GLfloat[VECTOR_SIZE] getMovementInXZPlane(GLfloat lookatX, GLfloat lookatZ, GLfloat cameraX, GLfloat cameraZ, int direction, GLfloat stepSize)
{
    GLfloat dx = cameraX-lookatX;
    GLfloat dz = cameraZ-lookatZ;
    GLfloat[VECTOR_SIZE] lookatVector = [dx, dz, 0];
    GLfloat[VECTOR_SIZE] upVector = [0,0,1];
    GLfloat[VECTOR_SIZE] resultVector = [0,0,0];

    switch(direction)
    {
        case 1:
            resultVector = lookatVector;
            break;
        case 2:
            crossProduct(upVector, lookatVector, resultVector);
            break;
        case 3:
            crossProduct(lookatVector, upVector, resultVector);
            break;
        default:
            resultVector = lookatVector;
            resultVector[0] *= -1;
            resultVector[1] *= -1;
            break;
    }
    normalize(resultVector);
    resultVector[0] *= stepSize;
    resultVector[1] *= stepSize;
    resultVector[2] = 0;
    return resultVector;
}

// a = a * b;
void multMatrix(ref GLfloat[MATRIX_SIZE] a, ref GLfloat[MATRIX_SIZE] b) {
  GLfloat[MATRIX_SIZE] res;
  
  for (int i = 0; i < 4; i++) {
    for (int j = 0; j < 4; j++) {
      res[j * 4 + i] = 0.0;
      for (int k = 0; k < 4; k++) {
        res[j * 4 + i] += a[k * 4 + i] * b[j * 4 + k];
      }
    }
  }
  a[] = res[];
}
 
// defines a transformation matrix mat with a translation
void setTranslationMatrix(ref GLfloat[MATRIX_SIZE] mat, float x, float y, float z) {
  setIdentityMatrix(mat, 4);
  mat[12] = x;
  mat[13] = y;
  mat[14] = z;
}
