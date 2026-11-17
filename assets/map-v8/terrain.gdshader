shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// Authored v6 terrain material. Screenshot pixels are never sampled.
// Depth comes from three things the v1 proof was missing: a real normal map,
// a roughness map instead of one flat value, and distance desaturation that
// mimics the aerial perspective measured from real ROTK14 screenshots.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
// v4: the albedo alpha channel carries the grass weight, and this multiplier
// adds blade-scale variation where grass actually grows.
uniform sampler2D grass_detail_tex : repeat_enable, filter_linear_mipmap;
uniform float grass_detail_strength : hint_range(0.0, 1.0) = 0.85;

uniform float grain_strength : hint_range(0.0, 1.0) = 0.34;
uniform float grain_scale_a = 0.085;
uniform float grain_scale_b = 0.34;
uniform float grain_scale_c = 2.60;
uniform float grain_scale_d = 7.40;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// Aerial perspective: measured near [114,105,91] -> far [131,121,131].
uniform float depth_desat : hint_range(0.0, 0.6) = 0.16;
uniform float depth_start = 30.0;
uniform float depth_rate = 0.0022;
uniform vec3 depth_tint : source_color = vec3(1.0, 1.0, 1.0);

uniform float grade_sat : hint_range(0.0, 1.5) = 1.0;
uniform vec3 grade_tint : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	vec3 alb = base.rgb;
	float grass_w = base.a;
	vec3 nrm = texture(normal_tex, UV).rgb;
	float rgh = texture(rough_tex, UV).r;

	// Each scalar channel describes one material, not a colored multiplier.
	// Grass blades, earth grains and rock pores stay distinct without pushing
	// the green channel brighter than the authored olive palette.
	float gm = smoothstep(0.05, 0.62, grass_w);
	float rock_w = 1.0 - smoothstep(0.55, 0.88, abs(wnormal.y));
	vec3 detail_a = texture(grass_detail_tex, wpos.xz * 0.42).rgb - vec3(0.5);
	vec3 detail_b = texture(grass_detail_tex, wpos.xz * 1.30).rgb - vec3(0.5);
	vec3 detail = detail_a * 0.64 + detail_b * 0.24;
	float surface = mix(mix(detail.g, detail.b, rock_w), detail.r, gm);
	float close_detail = 1.0 - smoothstep(65.0, 150.0, length(wpos - CAMERA_POSITION_WORLD));
	alb *= 1.0 + surface * grass_detail_strength * (0.38 + close_detail * 0.42);

	// Large-scale color drift keeps the plain from reading as one pale layer.
	// It uses the neutral grain data as a mask and preserves authored hue.
	float macro_a = texture(grain_tex, wpos.xz * 0.018 + vec2(0.31, 0.17)).r - 0.5;
	float macro_b = texture(grain_tex, wpos.xz * 0.047 - vec2(0.12, 0.27)).r - 0.5;
	float macro = macro_a * 0.68 + macro_b * 0.32;
	vec3 cool_sward = vec3(0.78, 0.88, 0.70);
	vec3 warm_wear = vec3(1.02, 0.93, 0.80);
	float cool_mask = gm * smoothstep(0.05, 0.34, macro);
	float wear_mask = (1.0 - gm) * smoothstep(0.04, 0.30, -macro);
	alb = mix(alb, alb * cool_sward, cool_mask * 0.20);
	alb = mix(alb, alb * warm_wear, wear_mask * 0.12);

	// Two world-space grain scales: the tiled octaves keep the surface from
	// going smooth when the camera pulls back, the painted octaves carry the
	// material character up close.
	float ga = texture(grain_tex, wpos.xz * grain_scale_a).r - 0.5;
	float gb = texture(grain_tex, wpos.xz * grain_scale_b).r - 0.5;
	float gc = texture(grain_tex, wpos.xz * grain_scale_c + wpos.y * 0.4).r - 0.5;
	float gd = texture(grain_tex, wpos.xz * grain_scale_d - wpos.y * 0.9).r - 0.5;
	float gsum = ga * grain_strength * 0.82
	           + gb * grain_strength * 0.85
	           + gc * grain_strength * 0.52
	           + gd * grain_strength * 0.34;
	alb *= 1.0 + gsum * mix(1.0, 0.72, 1.0 - grass_w);

	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength * mix(1.10, 0.60, grass_w);
	ROUGHNESS = clamp(rgh * 0.97 + gb * 0.07 + grass_w * 0.02, 0.50, 1.0);
	SPECULAR = 0.30;

	// Aerial perspective: far ground loses saturation and picks up the measured
	// violet-grey haze tint, which is what gives the original its sense of depth.
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float d = clamp(1.0 - exp(-max(dist - depth_start, 0.0) * depth_rate), 0.0, 1.0);
	float luma = dot(alb, vec3(0.2126, 0.7152, 0.0722));
	alb = mix(alb, vec3(luma), d * depth_desat);
	alb *= mix(vec3(1.0), depth_tint, d);

	alb = mix(vec3(luma), alb, grade_sat) * grade_tint;
	ALBEDO = clamp(alb, 0.0, 1.0);
}
