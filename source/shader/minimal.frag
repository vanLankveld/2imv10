#version 400

uniform mat4 projMatrix;

uniform vec3 lightPosition;
uniform vec3 lightIntensities;
uniform vec3 lightAmbient;

in vec3 fragVertex;
in vec3 fragNormal;
in vec3 fragColor;

out vec4 outColor;

void main()
{
    mat3 normalMatrix = transpose(inverse(mat3(projMatrix)));
    vec3 normal = normalize(normalMatrix * fragNormal);

    vec3 fragPosition = vec3(projMatrix * vec4(fragVertex, 1));
    vec3 surfaceToLight = lightPosition - fragPosition;

    float brightness = dot(normal, surfaceToLight) / (length(surfaceToLight) * length(normal));
    brightness = clamp(brightness, 0, 1);

    outColor = vec4(lightAmbient + (brightness * lightIntensities * fragColor), 1.0);
    //outColor = vec4(fragColor, 1.0);
}
