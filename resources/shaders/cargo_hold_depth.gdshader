shader_type spatial;
render_mode diffuse_burley;

uniform vec3 hold_color : source_color = vec3(0.03, 0.03, 0.045);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.72;
uniform float pit_depth : hint_range(0.0, 1.0) = 0.88;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float rim = smoothstep(0.01, 0.14, edge);
	float pit = mix(pit_depth, 1.0, rim * rim_strength);
	float grain = hash(UV * 96.0) * 0.04;
	vec3 col = hold_color * (pit + grain);
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.82, rim);
	METALLIC = 0.02;
}
