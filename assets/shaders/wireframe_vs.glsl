#version 330 core
layout (location = 0) in vec3 a_pos;
layout (location = 1) in vec3 a_norm;

uniform float u_time;
uniform mat4 u_perspective;
uniform mat4 u_view;
uniform mat4 u_model;

out vec3 v_norm;

void main() {
    gl_Position = u_perspective * u_view * u_model * vec4(a_pos + a_norm*0.001, 1.0);
    v_norm = normalize(mat3(u_model) * a_norm);
}
