shader_type spatial;
// Stylised vacuum-plume shading for the descent engine and cold-gas RCS jets.
// Emphasises a brighter energetic core near the source, radial falloff, subtle
// temporal breakup and smoother fading toward the tip. No atmospheric fireball.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 0.27);
uniform float radiance : hint_range(0.0, 4.0) = 1.0;
uniform float core_bias : hint_range(0.0, 1.0) = 0.55;
uniform float edge_softness : hint_range(0.5, 6.0) = 2.2;
uniform float tip_fade_start : hint_range(0.2, 0.95) = 0.66;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.14;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.12;
uniform vec3 hot_color : source_color = vec3(1.0, 0.82, 0.62);
uniform vec3 cold_color : source_color = vec3(0.65, 0.82, 1.0);

void fragment() {
    float v = clamp(UV.y, 0.0, 1.0);
    float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
    edge = pow(clamp(edge, 0.0, 1.0), edge_softness);
    float source = smoothstep(0.0, 0.16, v);
    float tip = 1.0 - smoothstep(tip_fade_start, 1.0, v);
    float breakup = 1.0 + noise_strength * (
        0.55 * sin(v * 24.0 - TIME * 18.0)
        + 0.45 * sin(UV.x * 37.0 + v * 11.0 + TIME * 12.5));
    float pulse = 1.0 + pulse_strength * sin(TIME * 26.0 + v * 22.0);
    float profile = clamp(source * tip * edge * breakup * pulse, 0.0, 1.0);
    float heat_mix = clamp((1.0 - v) * (0.55 + core_bias) + edge * 0.35 * core_bias, 0.0, 1.0);
    vec3 plume_color = mix(cold_color, hot_color, heat_mix);
    vec3 final_color = mix(tint.rgb, plume_color, 0.72);
    ALBEDO = final_color;
    EMISSION = final_color * radiance * (0.55 + 0.9 * profile + 0.35 * core_bias);
    ALPHA = tint.a * profile;
}
