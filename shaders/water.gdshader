// Stylized cartoon water: depth-based color, animated ripples and shore foam.
// Uses the depth buffer (Forward+), no textures.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.28, 0.78, 0.82, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.33, 0.62, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float depth_fade = 7.0;
uniform float foam_width = 0.9;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	view.xyz /= view.w;
	float thickness = max(-view.z + VERTEX.z, 0.0);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float t = clamp(thickness / depth_fade, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);

	// Cartoon ripple highlights.
	vec2 uv = world_pos.xz;
	float n = vnoise(uv * 0.18 + vec2(TIME * 0.06, TIME * 0.04)) + vnoise(uv * 0.41 - vec2(TIME * 0.05, -TIME * 0.08));
	float ripple = smoothstep(1.35, 1.5, n);
	col = mix(col, foam_color.rgb, ripple * 0.35);

	// Foam line where the water meets the ground.
	float foam = 1.0 - smoothstep(0.0, foam_width, thickness);
	foam *= 0.65 + 0.35 * sin(TIME * 2.2 + world_pos.x * 0.35 + world_pos.z * 0.25);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));

	// Small normal wobble for sun glints.
	float nx = vnoise(uv * 0.6 + TIME * 0.3) - 0.5;
	float nz = vnoise(uv * 0.6 - TIME * 0.27 + 17.0) - 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(nx, 0.0, nz, 0.0)).xyz * 0.25);

	ALBEDO = col;
	ALPHA = clamp(mix(0.55, 0.93, t) + foam, 0.0, 1.0);
	ROUGHNESS = 0.06;
	SPECULAR = 0.55;
}
