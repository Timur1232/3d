#version 330 core

in vec3 v_norm;

uniform vec3 u_light;

out vec4 FragColor;

vec3 color_value(vec3 normal, vec3 light) {
    float d = dot(normal, light);
    d = clamp(d, 0.1, 1.0);
    return vec3(d);
}

void main() {
    FragColor = vec4(color_value(v_norm, u_light), 1.0);
}
