#version 330 core
layout (location = 0) in vec3 a_pos;

uniform float u_time;
uniform mat4 u_view;
uniform mat4 u_perspective;
uniform mat4 u_transform;

// #define PI 3.1415926538

void main() {
    gl_Position = u_perspective * u_view * u_transform * vec4(a_pos, 1.0);
}
