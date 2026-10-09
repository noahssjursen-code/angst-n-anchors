shader_type spatial;
render_mode cull_disabled, depth_draw_never, diffuse_burley;

// Analytic optical streak: soft edges, no repeated bitmap or opaque rod.
// Particle transform supplies camera-facing Z and velocity-aligned Y.
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float cross_section = exp(-pow((UV.x - 0.5) * 4.5, 2.0));
	float tail = smoothstep(0.0, 0.23, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));
	float distance_fade = smoothstep(0.7, 2.8, length(VERTEX)) * (1.0 - smoothstep(22.0, 32.0, length(VERTEX)));
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float intersection_fade = clamp((-behind.z / behind.w + VERTEX.z) / 0.25, 0.0, 1.0);
	ALBEDO = vec3(0.62, 0.68, 0.72);
	ROUGHNESS = 0.5;
	SPECULAR = 0.35;
	ALPHA = cross_section * tail * distance_fade * intersection_fade * 0.38;
}
