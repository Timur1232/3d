#version 330 core
in vec3 v_norm;

uniform vec3 u_light_pos;

out vec4 FragColor;

void main() {
    float d = dot(v_norm, normalize(u_light_pos));
    d = clamp(d, 0.2, 1.0);
    FragColor = vec4(vec3(d), 1.0);
}
