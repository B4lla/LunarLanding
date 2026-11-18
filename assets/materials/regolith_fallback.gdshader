shader_type spatial;
// Deterministic render-only fallback while licensed CC0 PBR files are absent.
// Does not displace geometry or feed any collision/physics query.
render_mode diffuse_burley, specular_schlick_ggx;

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
    vec2 ip = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(ip), hash2(ip + vec2(1.0, 0.0)), f.x),
        mix(hash2(ip + vec2(0.0, 1.0)), hash2(ip + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
    vec2 st = UV * 115.0;
    float broad = noise2(st * 0.42);
    float grains = noise2(st * 7.5);
    float value = clamp(0.35 + broad * 0.23 + grains * 0.11, 0.0, 1.0);
    ALBEDO = vec3(value * 0.73, value * 0.76, value * 0.79);
    ROUGHNESS = 0.97;
    METALLIC = 0.0;
    SPECULAR = 0.16;
}
