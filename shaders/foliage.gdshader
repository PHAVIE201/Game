// Foliage / tree shader used by the vegetation MultiMeshes.
// - Vertex color alpha marks foliage (1) vs trunk/rock (0).
// - INSTANCE_CUSTOM.rgb = per-instance tint, .a = wind phase (0..1).
// Wind sway is done in the vertex shader: zero CPU cost per tree.
shader_type spatial;
render_mode cull_back;

uniform float wind_strength = 0.05;
uniform float wind_speed = 1.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	float foliage = COLOR.a;
	// Palette colors are authored in sRGB.
	COLOR.rgb = srgb_to_linear(COLOR.rgb) * mix(vec3(1.0), INSTANCE_CUSTOM.rgb, foliage);
	float phase = INSTANCE_CUSTOM.a * 6.2831853;
	float h = max(VERTEX.y - 1.0, 0.0);
	float sway = sin(TIME * wind_speed + phase) * wind_strength * foliage * h * 0.25;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6 * sin(TIME * wind_speed * 0.7 + phase);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
