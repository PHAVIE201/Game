shader_type spatial;
// Edge of the safe zone: a huge open cylinder, translucent blue with moving
// diagonal stripes, fading out toward the top. Seen from inside and outside.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.12, 0.38, 1.0, 0.5);
uniform float stripe_scale = 60.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float stripes = 0.5 + 0.5 * sin((world_pos.x + world_pos.z + world_pos.y * 1.5) / stripe_scale * 6.2831 - TIME * 1.5);
	// Solid near the ground, fading out high in the sky.
	float fade = 1.0 - smoothstep(60.0, 420.0, world_pos.y);
	// Stronger near the camera so the wall is readable up close.
	float near = 1.0 - smoothstep(30.0, 500.0, length(world_pos - CAMERA_POSITION_WORLD));
	ALBEDO = color.rgb * (1.0 + 0.5 * stripes);
	ALPHA = clamp(color.a * fade * (0.6 + 0.4 * stripes) * (0.55 + 0.45 * near), 0.0, 1.0);
}
