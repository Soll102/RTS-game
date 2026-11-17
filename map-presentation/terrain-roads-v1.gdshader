shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// Authored v6 terrain material with unified full-width road presentation,
// redundant-road scar healing, and 6-texture-sample 60 FPS fragment path.

uniform sampler2D widened_road_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 widened_road_color : source_color = vec3(0.440, 0.398, 0.314);
uniform vec3 meadow_heal_color : source_color = vec3(0.263, 0.302, 0.180);

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_detail_tex : repeat_enable, filter_linear_mipmap;
uniform float grass_detail_strength : hint_range(0.0, 1.0) = 0.85;

uniform float grain_strength : hint_range(0.0, 1.0) = 0.34;
uniform float grain_scale_a = 0.085;
uniform float grain_scale_b = 0.34;
uniform float grain_scale_c = 2.60;
uniform float grain_scale_d = 7.40;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

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
	vec2 road_sample = texture(widened_road_tex, UV).rg;
	float road_mask = road_sample.r;
	float heal_mask = road_sample.g * (1.0 - road_mask);
	float gb = texture(grain_tex, wpos.xz * grain_scale_b).r - 0.5;
	float gc = texture(grain_tex, wpos.xz * grain_scale_c + wpos.y * 0.4).r - 0.5;

	// Heal redundant dead-end dirt scars back into natural green meadow.
	vec3 meadow_target = meadow_heal_color * (1.0 + gb * 0.22 + gc * 0.08);
	alb = mix(alb, meadow_target, heal_mask);

	// Full-width compacted earth road blend: unifies the center dirt and widened
	// shoulders so roads never split into a dark center trench with bright side stripes.
	vec3 road_target = widened_road_color * (1.0 + gc * 0.08 + gb * 0.04);
	float center_blend = mix(1.0, 0.82, 1.0 - smoothstep(0.0, 0.30, base.a));
	alb = mix(alb, road_target, road_mask * center_blend);

	float grass_w = max(base.a, heal_mask * 0.96) * (1.0 - road_mask);
	vec3 nrm = texture(normal_tex, UV).rgb;
	float rgh = texture(rough_tex, UV).r;

	float gm = smoothstep(0.05, 0.62, grass_w);
	float rock_w = 1.0 - smoothstep(0.55, 0.88, abs(wnormal.y));
	vec3 detail = (texture(grass_detail_tex, wpos.xz * 0.55).rgb - vec3(0.5)) * 0.82;
	float surface = mix(mix(detail.g, detail.b, rock_w), detail.r, gm);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float close_detail = 1.0 - smoothstep(65.0, 150.0, dist);
	float detail_atten = mix(1.0, 0.30, road_mask);
	alb *= 1.0 + surface * grass_detail_strength * (0.38 + close_detail * 0.42) * detail_atten;

	vec3 cool_sward = vec3(0.78, 0.88, 0.70);
	vec3 warm_wear = vec3(1.02, 0.93, 0.80);
	float cool_mask = gm * smoothstep(0.05, 0.34, gb);
	float wear_mask = (1.0 - gm) * smoothstep(0.04, 0.30, -gb);
	alb = mix(alb, alb * cool_sward, cool_mask * 0.20);
	alb = mix(alb, alb * warm_wear, wear_mask * 0.12);

	float gsum = (gb * 1.45 + gc * 0.75) * grain_strength;
	alb *= 1.0 + gsum * mix(1.0, 0.65, max(1.0 - grass_w, road_mask));

	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength * mix(mix(1.10, 0.60, grass_w), 0.50, road_mask);
	ROUGHNESS = clamp(rgh * 0.97 + gb * 0.07 + grass_w * 0.02, 0.50, 1.0);
	SPECULAR = 0.30;

	float d = clamp(1.0 - exp(-max(dist - depth_start, 0.0) * depth_rate), 0.0, 1.0);
	float luma = dot(alb, vec3(0.2126, 0.7152, 0.0722));
	alb = mix(alb, vec3(luma), d * depth_desat);
	alb *= mix(vec3(1.0), depth_tint, d);

	alb = mix(vec3(luma), alb, grade_sat) * grade_tint;

	// Soft border fog: seamlessly hides the map perimeter into atmospheric mist
	float border_margin = min(180.0 - abs(wpos.x), 140.0 - abs(wpos.z));
	float border_fog = 1.0 - smoothstep(0.0, 32.0, max(0.0, border_margin));
	vec3 border_mist = vec3(0.55, 0.63, 0.65) * (0.95 + gb * 0.10);
	alb = mix(alb, border_mist, border_fog * 0.96);

	ALBEDO = clamp(alb, 0.0, 1.0);
}
