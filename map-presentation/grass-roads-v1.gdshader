shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D widened_road_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 meadow_heal_color : source_color = vec3(0.263, 0.302, 0.180);

uniform sampler2D card_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D ground_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind : hint_range(0.0, 0.25) = 0.060;
uniform float fade_start = 42.0;
uniform float fade_end = 72.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float grain_strength : hint_range(0.0, 0.6) = 0.08;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float tip = 1.0 - UV.y;
	float w = tip * tip;
	float ph = wpos.x * 0.42 + wpos.z * 0.31;
	float sway = sin(TIME * 1.6 + ph) * 0.6 + sin(TIME * 2.7 + ph * 1.9) * 0.4;
	VERTEX.x += sway * wind * w;
	VERTEX.z += sway * wind * 0.55 * w;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float f = clamp((dist - fade_start) / max(fade_end - fade_start, 0.001), 0.0, 1.0);
	VERTEX.y -= f * 0.65;
}

vec3 display_color(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
	           c * 12.92, lessThanEqual(c, vec3(0.0031308)));
}

void fragment() {
	vec4 t = texture(card_tex, UV);
	if (t.a < alpha_cut) { discard; }
	float border_margin = min(180.0 - abs(wpos.x), 140.0 - abs(wpos.z));
	if (border_margin < 4.0) { discard; }
	vec2 ground_uv = clamp((wpos.xz + vec2(180.0, 140.0)) / vec2(360.0, 280.0), vec2(0.0), vec2(1.0));
	vec2 road_sample = texture(widened_road_tex, ground_uv).rg;
	if (road_sample.r > 0.35) { discard; }
	float g = texture(grain_tex, wpos.xz * 1.9).r - 0.5;
	vec3 vertex_tint = OUTPUT_IS_SRGB ? display_color(COLOR.rgb) : COLOR.rgb;
	vec3 ground = texture(ground_tex, ground_uv).rgb;
	ground = mix(ground, meadow_heal_color, road_sample.g * (1.0 - road_sample.r));
	vec3 blade = t.rgb * mix(0.96, 1.08, 1.0 - UV.y);
	vec3 c = mix(blade, ground * mix(0.96, 1.10, 1.0 - UV.y), 0.78);
	c *= vertex_tint * tint * (1.0 + g * grain_strength);
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = 0.94;
	SPECULAR = 0.10;
	BACKLIGHT = c * 0.12;
}
