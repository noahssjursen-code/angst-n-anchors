shader_type spatial;
render_mode diffuse_burley;

uniform vec3 asphalt_color : source_color = vec3(0.285, 0.295, 0.315);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.91;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec2 p = UV * 48.0;
	float broad = value_noise(p * 0.22);
	float aggregate = value_noise(p * 2.8);
	float variation = (broad - 0.5) * 0.10 + (aggregate - 0.5) * 0.035;
	vec3 dry_color = asphalt_color * (1.0 + variation);
	ALBEDO = mix(dry_color, dry_color * 0.74, wetness);
	float dry_roughness = clamp(roughness_base + (aggregate - 0.5) * 0.07, 0.82, 0.98);
	ROUGHNESS = mix(dry_roughness, 0.34, wetness);
	METALLIC = 0.02;
}
