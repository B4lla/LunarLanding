shader_type spatial;
// F28: flare belongs to geometry; shader adds bounded turbulent density and
// guarantees full alpha falloff at every border. GL Compatibility compatible.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 near_color : source_color = vec3(1.0, 0.92, 0.67);
uniform vec3 far_color : source_color = vec3(0.38, 0.68, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float edge_breadth : hint_range(0.1, 1.2) = 0.88;
uniform float softness : hint_range(0.1, 6.0) = 2.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.65;
uniform float flow_speed : hint_range(0.1, 20.0) = 5.0;
uniform float layer_seed = 0.0;
uniform float gas_mode : hint_range(0.0, 1.0) = 0.0;
uniform float tip_spread : hint_range(0.0, 2.0) = 0.35;
uniform float diffuse_mix : hint_range(0.0, 1.0) = 0.30;
uniform float flare_strength : hint_range(0.0, 1.0) = 0.25;

float rand2(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 point) {
    vec2 cell = floor(point);
    vec2 fraction = fract(point);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    return mix(
        mix(rand2(cell), rand2(cell + vec2(1.0, 0.0)), fraction.x),
        mix(rand2(cell + vec2(0.0, 1.0)), rand2(cell + vec2(1.0, 1.0)), fraction.x),
        fraction.y);
}

void fragment() {
    float progress = clamp(UV.y, 0.0, 1.0);
    float side = abs(UV.x * 2.0 - 1.0);
    float noise_a = smooth_noise(vec2(UV.x * 4.7 + layer_seed, progress * 8.5 - TIME * flow_speed));
    float noise_b = smooth_noise(vec2(UV.x * 9.5 - layer_seed, progress * 16.0 - TIME * flow_speed * 1.65));
    float turbulence = mix(noise_a, noise_b, 0.38);
    float displacement = (turbulence - 0.5) * (0.09 + 0.12 * progress);
    float radial = clamp(side + displacement, 0.0, 1.2);

    // The shell must become fully transparent *before* the outer vertex edge.
    // F26 allowed width > 1, producing an abrupt rectangular cut-off.
    float core_width = mix(0.48, 0.74, progress) * mix(0.82, 1.0, edge_breadth);
    float core = 1.0 - smoothstep(core_width * 0.35, core_width, radial);
    core = pow(max(core, 0.0), softness);
    float haze_width = mix(0.72, 0.91, progress);
    float diffuse = (1.0 - smoothstep(core_width * 0.68, haze_width, radial)) * diffuse_mix;
    float rim_guard = 1.0 - smoothstep(0.76, 0.995, side);
    float start = smoothstep(0.0, 0.055, progress);
    float end = 1.0 - smoothstep(0.54 + 0.10 * gas_mode, 0.995, progress);
    float pulse = 0.94 + 0.06 * sin(TIME * 17.0 + layer_seed * 2.4 - progress * 13.0);
    float flutter = mix(0.68, 1.15, turbulence);
    float expansion_rim = flare_strength * progress * (1.0 - radial) * 0.22;
    float density = max(core + diffuse + expansion_rim, 0.0) * rim_guard * start * end * pulse * flutter;
    float heat = pow(1.0 - progress, 1.45) * (1.0 - gas_mode * 0.68);
    vec3 color = mix(far_color, near_color, heat);
    ALBEDO = color;
    EMISSION = color * (0.22 + 1.58 * density) * strength;
    ALPHA = clamp(density * opacity * strength, 0.0, 0.92);
}
