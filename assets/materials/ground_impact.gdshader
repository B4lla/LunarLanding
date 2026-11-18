shader_type spatial;
// Low planar interaction: glowing hot-spot on metal; moving ballistic streaks on regolith.
// An actual lunar surface has no atmospheric smoke cloud.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float is_deck : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

void fragment() {
    vec2 p = (UV - vec2(0.5)) * 2.0;
    float radial = length(p);
    float angle = atan(p.y, p.x);
    float outer_fade = 1.0 - smoothstep(0.76, 0.99, radial);
    float center_mask = 1.0 - smoothstep(0.06, 0.38, radial);
    float ripple = 0.49 + 0.12 * sin(TIME * 6.8 + seed);
    float rim = 1.0 - smoothstep(0.04, 0.22, abs(radial - ripple));
    float streaks = pow(max(sin(angle * 19.0 + radial * 18.0 - TIME * 3.4), 0.0), 4.0);
    float dust = outer_fade * (0.20 * center_mask + 0.22 * rim + 0.22 * streaks * rim);
    float heated_deck = outer_fade * (0.38 * center_mask + 0.15 * rim);
    vec3 dust_color = vec3(0.48, 0.47, 0.44);
    vec3 deck_color = vec3(1.0, 0.69, 0.31);
    ALBEDO = mix(dust_color, deck_color, is_deck);
    EMISSION = mix(vec3(0.0), deck_color * heated_deck * intensity * 1.4, is_deck);
    ALPHA = clamp(mix(dust, heated_deck, is_deck) * intensity, 0.0, 0.30);
}
