#pragma language glsl3

uniform mat4 camera_from_world;
uniform mat4 world_from_model;
uniform samplerCube tex;
in vec3 VertexNormal;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 normal = mat3(world_from_model) * VertexNormal;
    float light = dot(normal, vec3(sqrt(3)/2, 0, -0.5));
    VaryingColor = vec4(light, light, light, 1) * texture(tex, vec3(VertexTexCoord) * vec3(-1,1,1));
    return camera_from_world * world_from_model * vertex_position;
}