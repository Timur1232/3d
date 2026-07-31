#version 330 core
layout (location = 0) in vec3 a_pos;
layout (location = 2) in vec3 a_color;

uniform mat4 u_transform;

out vec3 v_color;

void main() {
    gl_Position = u_transform * vec4(a_pos, 1.0);
    v_color = a_color;
}
