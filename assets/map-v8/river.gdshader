shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D depth_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
varying vec3 wpos;

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

float value_noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec4 q = vec4(dot(i, vec2(127.1, 311.7)), dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7)),
                  dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7)), dot(i + vec2(1.0), vec2(127.1, 311.7)));
    q = fract(sin(q) * 43758.5453);
    return mix(mix(q.x, q.y, f.x), mix(q.z, q.w, f.x), f.y);
}

void fragment() {
    vec2 uv = (wpos.xz + vec2(180.0, 140.0)) / vec2(360.0, 280.0);
    float depth = texture(depth_tex, uv).r;
    float warp = value_noise(wpos.xz * 0.34 + vec2(TIME * 0.025, 0.0)) * 8.0;
    float current = sin(wpos.x * 1.4 + wpos.z * 5.2 + warp - TIME * 1.1);
    float crossed = sin(wpos.x * 5.0 - wpos.z * 3.1 + TIME * 0.6);
    float grain = texture(grain_tex, wpos.xz * 0.24 + vec2(TIME * 0.009, 0.0)).r;
    vec3 water = mix(vec3(0.17, 0.18, 0.13), vec3(0.075, 0.105, 0.115), smoothstep(0.02, 0.72, depth));
    water *= 0.97 + 0.05 * current + 0.04 * crossed + 0.13 * grain;
    vec3 to_camera = normalize(CAMERA_POSITION_WORLD - wpos);
    float fresnel = pow(1.0 - max(dot(to_camera, vec3(0.0, 1.0, 0.0)), 0.0), 4.0);
    water = mix(water, vec3(0.24, 0.27, 0.28), fresnel * 0.42);
    float shore = 1.0 - smoothstep(0.025, 0.14, depth);
    float broken_foam = smoothstep(0.52, 0.74, grain + current * 0.15);
    water = mix(water, vec3(0.37, 0.39, 0.35), shore * broken_foam * 0.65);
    ALBEDO = water;
    ROUGHNESS = 0.88;
    NORMAL_MAP = vec3(0.5 + current * 0.035, 0.5 + crossed * 0.02, 1.0);
    NORMAL_MAP_DEPTH = 0.26;
}
