#version 330 core
in vec3 v_world_pos;

uniform vec3 u_light_pos;

out vec4 FragColor;

void main() {
    vec3 normal = normalize(cross(dFdx(v_world_pos), dFdy(v_world_pos)));
    float d = dot(normal, normalize(u_light_pos));
    d = clamp(d, 0.2, 1.0);
    FragColor = vec4(vec3(d), 1.0);
}
