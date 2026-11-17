shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D source_ground : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 mist_color : source_color = vec4(0.32,0.39,0.34,1.0);
varying vec3 world_point;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float haze(vec2 p) {
    vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 edge=clamp(world_point.xz,vec2(-180.0,-140.0),vec2(180.0,140.0));
    vec2 uv=(edge+vec2(180.0,140.0))/vec2(360.0,280.0);
    vec3 ground=texture(source_ground,uv).rgb;
    float outside=length(world_point.xz-edge);
    // A short transition avoids stretching each border texel into a visible stripe.
    float wash=smoothstep(0.25,24.0,outside);
    vec3 mist=mist_color.rgb*(0.97+0.06*haze(world_point.xz/65.0));
    ALBEDO=mix(ground,mist,wash);
    ROUGHNESS=1.0;
}
