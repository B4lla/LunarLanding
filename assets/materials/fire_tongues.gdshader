shader_type spatial;
// F39 fiery engine throat: thin, broken combustion filaments moving into
// vacuum.  Crossed sheets are optical approximation, NOT an atmospheric fireball.
// GL Compatibility, no screen textures, no dynamic lighting requirement.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 near_color : source_color = vec3(1.0, 0.96, 0.77);
uniform vec3 far_color : source_color = vec3(1.0, 0.36, 0.08);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.66;
uniform float edge_breadth : hint_range(0.1, 1.2) = 0.85;
uniform float softness : hint_range(0.1, 6.0) = 2.0;
uniform float flow_speed : hint_range(0.1, 20.0) = 4.8;
uniform float layer_seed = 0.0;
uniform float gas_mode : hint_range(0.0, 1.0) = 0.0;
uniform float tip_spread : hint_range(0.0, 2.0) = 0.50;
uniform float diffuse_mix : hint_range(0.0, 1.0) = 0.20;
uniform float flare_strength : hint_range(0.0, 1.0) = 0.40;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),
        mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);
}

void fragment() {
    float v = clamp(UV.y, 0.0, 1.0);
    float axis = UV.x*2.0-1.0;
    float time = TIME*flow_speed;
    float macro = noise(vec2(axis*3.4 + layer_seed, v*9.0-time*0.77));
    float curls = noise(vec2(axis*11.8-layer_seed*0.24, v*23.0-time*1.85));
    float fibers = noise(vec2(axis*27.0+layer_seed*0.48, v*38.0-time*2.65));
    float density_noise = .45*macro + .34*curls + .21*fibers;
    float twist = (macro-.5)*(.14 + .19*v) + (curls-.5)*.045;
    float r = abs(axis + twist);
    // Turbulent tongues become narrower, more fractured, and less frequent
    // downstream. The edge and tip always fade to alpha zero.
    float tapered = (.33 + .22*v) * edge_breadth;
    float core = 1.0-smoothstep(tapered*.18, tapered, r);
    float broken = smoothstep(.34, .76, density_noise + .30*(1.0-v));
    float inner = pow(max(core, 0.0), softness*.80);
    float streak = smoothstep(.51,.83,fibers)*(.40+ .60*macro)*inner;
    float edge = 1.0-smoothstep(.82,.995,abs(axis));
    float start = smoothstep(0.0, .026, v);
    float tip = 1.0-smoothstep(.51 + .19*macro, .90, v);
    float mass = (inner*broken + streak*.44) * edge * start * tip;
    // White/yellow energy close to throat; thin orange streaks farther out.
    float heat = pow(1.0-v, 2.15) * (.82+.18*curls);
    vec3 col = mix(far_color, near_color, heat);
    float amber = (1.0-v)*inner*.24;
    col = mix(col, vec3(1.0,.66,.24), amber);
    ALBEDO = col;
    EMISSION = col * (1.10+1.35*mass)*strength;
    ALPHA = clamp(mass * opacity * strength, 0.0, 0.67);
}
