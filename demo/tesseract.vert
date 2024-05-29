#pragma glsl3

uniform mat4 WORLD_FROM_MODEL;
uniform float HYPER_DISTANCE;
uniform mat4 VIEW_FROM_WORLD;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vertex_position = WORLD_FROM_MODEL * vertex_position;
    vertex_position.w += HYPER_DISTANCE;
    vertex_position /= vertex_position.w;
    vertex_position = VIEW_FROM_WORLD * vertex_position;
    return vertex_position;
}