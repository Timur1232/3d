#version 330 core
uniform vec3 u_wire_color;

out vec4 FragColor;

void main() {
    FragColor = vec4(u_wire_color, 1.0);
}
