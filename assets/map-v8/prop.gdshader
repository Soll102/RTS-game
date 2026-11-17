shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.28;
uniform float rough = 0.92;
uniform int material_kind = 0; // 1: masonry, 2: roof tile, 3: wood, 4: plaster
varying vec3 wpos;
varying vec3 wnormal;

vec3 display_color(vec3 c) {
    return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
               c * 12.92, lessThanEqual(c, vec3(0.0031308)));
}

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    wnormal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    vec3 c = OUTPUT_IS_SRGB ? display_color(COLOR.rgb) : COLOR.rgb;
    float g1 = texture(grain_tex, wpos.xz * 0.55 + wpos.y * 0.21).r - 0.5;
    float g2 = texture(grain_tex, wpos.xz * 2.0 - wpos.y * 0.55).r - 0.5;
    c *= 1.0 + g1 * grain_strength + g2 * grain_strength * 0.6;
    if (material_kind == 1) { c *= 0.88; }
    if (material_kind == 2) { c *= 0.92; }
    if (material_kind == 1 && wnormal.y > 0.5 && wpos.y < 1.70
        && abs(wpos.x - 26.0) < 7.2 && abs(wpos.z - 26.0) < 6.2) {
        float wear = texture(grain_tex, wpos.xz * 0.07).r;
        c = mix(vec3(0.23, 0.25, 0.17), vec3(0.37, 0.34, 0.28), wear);
    }
    if (material_kind == 1 && abs(wnormal.y) < 0.5) {
        float u = abs(wnormal.x) > abs(wnormal.z) ? wpos.z : wpos.x;
        float row = floor(wpos.y / 0.17);
        vec2 brick = vec2(u / 0.42 + mod(row, 2.0) * 0.5, wpos.y / 0.17);
        vec2 f = fract(brick);
        float mortar = 1.0 - smoothstep(0.02, 0.06, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
        float tone = fract(sin(dot(floor(brick), vec2(17.71, 31.17))) * 4375.53);
        c *= 0.91 + tone * 0.16;
        c *= 1.0 - mortar * 0.28;
    } else if (material_kind == 2) {
        // The tile silhouettes and joints are mesh geometry in v6.
        c *= 0.98 + g2 * 0.055;
    } else if (material_kind == 3) {
        float fibres = texture(grain_tex, vec2(wpos.y * 0.35, (wpos.x+wpos.z) * 14.0)).r - 0.5;
        c *= 1.0 + fibres * 0.15;
    } else if (material_kind == 4) {
        float damp = (1.0-smoothstep(1.4, 1.95, wpos.y)) * (0.5 + g1);
        c *= 1.0 - damp * 0.23;
    }
    ALBEDO = clamp(c, 0.0, 1.0);
    ROUGHNESS = clamp(rough + g2 * 0.06, 0.80, 1.0);
}
