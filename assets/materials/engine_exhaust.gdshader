shader_type spatial;
// F38 onboard-camera lunar rocket plume: hot nozzle core, rapid vacuum expansion,
// multi-frequency density structure and optical falloff. No terrestrial smoke.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 near_color : source_color = vec3(1.0, 0.97, 0.87);
uniform vec3 far_color : source_color = vec3(0.56, 0.75, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float edge_breadth : hint_range(0.1, 1.2) = 0.85;
uniform float softness : hint_range(0.1, 6.0) = 2.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float flow_speed : hint_range(0.1, 20.0) = 6.0;
uniform float layer_seed = 0.0;
uniform float gas_mode : hint_range(0.0, 1.0) = 0.0;
uniform float tip_spread : hint_range(0.0, 2.0) = 0.35;
uniform float diffuse_mix : hint_range(0.0, 1.0) = 0.30;
uniform float flare_strength : hint_range(0.0, 1.0) = 0.25;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    f = f*f*(3.0-2.0*f);
    float a = hash21(i);
    float b = hash21(i+vec2(1.0,0.0));
    float c = hash21(i+vec2(0.0,1.0));
    float d = hash21(i+vec2(1.0,1.0));
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

void fragment() {
    float v = clamp(UV.y, 0.0, 1.0);
    float axis = UV.x * 2.0 - 1.0;
    float travel = TIME * flow_speed;
    float noise_a = value_noise(vec2(axis*3.2+layer_seed, v*8.0-travel));
    float noise_b = value_noise(vec2(axis*8.0-layer_seed*0.53, v*21.0-travel*2.2));
    float streak = value_noise(vec2(axis*2.1+layer_seed*.14, v*34.0-travel*2.9));
    float turbulent = noise_a*.48 + noise_b*.36 + streak*.16;
    // Irregular lobes taper near the throat; broad but diffuse farther away.
    float warp = (turbulent-.5) * (0.08 + v*.21);
    float radial = abs(axis + warp);
    float width = (0.24 + v*.53) * edge_breadth;
    float core = 1.0 - smoothstep(width*.28, width, radial);
    float fine = pow(max(core,0.0), softness*.75);
    float halo = (1.0 - smoothstep(width*.57, min(.985,width+0.24), radial)) * diffuse_mix;
    float edge_guard = 1.0 - smoothstep(.83,.995,abs(axis));
    float launch = smoothstep(0.0, .038, v);
    float release = 1.0 - smoothstep(.46, .99, v);
    float swirl = mix(.46,1.15,turbulent);
    float length_density = (fine + halo*.65) * release * launch * edge_guard * swirl;
    // Chamber bright, expanded tail low density, no saturated orange cartoon cone.
    float near_mix = pow(1.0-v,1.5);
    vec3 col = mix(far_color, near_color, near_mix);
    float feather = smoothstep(.02,.25,v);
    float density = length_density * (1.0 - .21 * feather);
    ALBEDO = col;
    EMISSION = col * (0.45 + 1.15*density) * strength;
    ALPHA = clamp(density * opacity * strength,0.0,.85);
}
