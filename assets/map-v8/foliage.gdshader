shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wind = 0.045;
varying vec3 wpos;

vec3 display_color(vec3 c) {
    return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
               c * 12.92, lessThanEqual(c, vec3(0.0031308)));
}

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float phase = wpos.x * 0.37 + wpos.z * 0.29;
    VERTEX.x += sin(TIME * 1.5 + phase) * wind * (1.0 - UV.y);
    VERTEX.z += cos(TIME * 1.1 + phase) * wind * 0.6;
}

void fragment() {
    vec4 leaf = texture(leaf_tex, UV);
    if (leaf.a < 0.38) { discard; }
    // glTF stores linear vertex colors. Compatibility lighting uses sRGB.
    vec3 tint = OUTPUT_IS_SRGB ? display_color(COLOR.rgb) : COLOR.rgb;
    ALBEDO = leaf.rgb * tint;
    ROUGHNESS = 0.97;
    BACKLIGHT = ALBEDO * 0.38;
}
