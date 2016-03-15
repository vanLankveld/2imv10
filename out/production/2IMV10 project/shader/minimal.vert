#version 400

uniform mat4 viewMatrix, projMatrix;

in vec4 position;
in vec4 offset;
in vec3 color;
in vec4 normal;

out vec3 fragVertex;
out vec3 fragNormal;
out vec3 fragColor;

void main()
{
    fragColor = color;
    fragVertex = position.xyz;
    fragNormal = normal.xyz;
    gl_Position = projMatrix * viewMatrix * (position + offset);
}
