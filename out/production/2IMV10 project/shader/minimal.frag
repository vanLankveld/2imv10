#version 400

uniform mat4 projMatrix;

uniform struct Light {
   vec3 position;
   vec3 intensities;
} light;

in vec3 fragVertex;
in vec3 fragNormal;
in vec3 fragColor;

out vec4 outColor;

void main()
{
    mat3 normalMatrix = transpose(inverse(mat3(projMatrix)));
    vec3 normal = normalize(normalMatrix * fragNormal);

    vec3 fragPosition = vec3(projMatrix * vec4(fragVertex, 1));
    vec3 surfaceToLight = light.position - fragPosition;

    float brightness = dot(normal, surfaceToLight) / (length(surfaceToLight) * length(normal));
    brightness = clamp(brightness, 0, 1);

    outColor = vec4(brightness * fragColor, 1.0);
    //outColor = vec4(fragColor, 1.0);
}
