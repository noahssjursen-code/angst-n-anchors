shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform vec3 paint_color : source_color = vec3(0.18, 0.42, 0.72);
uniform vec3 paint_dark : source_color = vec3(0.10, 0.26, 0.48);
uniform vec3 paint_highlight : source_color = vec3(0.28, 0.54, 0.82);
uniform vec3 rust_color : source_color = vec3(0.42, 0.24, 0.12);
uniform vec3 door_color : source_color = vec3(0.08, 0.20, 0.38);

uniform float rib_freq : hint_range(1.0, 8.0) = 3.15;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.55;
uniform float seed : hint_range(0.0, 100.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
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

float triplanar_noise(vec3 pos, float scale) {
	vec3 n = abs(normalize(world_normal));
	n = pow(max(n, vec3(0.0001)), vec3(2.0));
	n /= (n.x + n.y + n.z);
	float xz = value_noise(pos.xz * scale + vec2(seed * 0.17, seed * 0.31));
	float xy = value_noise(pos.xy * scale + vec2(seed * 0.23, seed * 0.11));
	float yz = value_noise(pos.yz * scale + vec2(seed * 0.07, seed * 0.41));
	return xz * n.y + xy * n.z + yz * n.x;
}

float corrugation(vec3 pos, vec3 n) {
	vec3 an = abs(normalize(n));
	float along_z = sin((pos.x + seed * 0.04) * rib_freq * TAU);
	float along_x = sin((pos.z + seed * 0.06) * rib_freq * TAU);
	float side = mix(along_x, along_z, step(an.z, an.x));
	float side_mask = 1.0 - smoothstep(0.55, 0.92, an.y);
	return side * side_mask;
}

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 an = abs(n);

	float ribs = corrugation(world_pos, n);
	float rib_valley = smoothstep(-0.15, 0.55, ribs);
	float rib_crest = smoothstep(0.35, 0.95, ribs);

	float fine = triplanar_noise(world_pos, 18.0);
	float streak = triplanar_noise(world_pos + vec3(4.7, seed, 9.1), 2.4);

	vec3 col = mix(paint_dark, paint_color, 0.55 + streak * 0.22 + fine * 0.12);
	col = mix(col, paint_highlight, rib_crest * 0.28);
	col = mix(col, paint_dark * 0.92, (1.0 - rib_valley) * 0.42);

	float end_face = smoothstep(0.72, 0.94, an.z);
	col = mix(col, door_color, end_face * 0.62);

	float corner = smoothstep(0.42, 0.82, an.x) * smoothstep(0.42, 0.82, an.z);
	float top_edge = smoothstep(0.70, 0.95, an.y);
	float bottom_edge = smoothstep(0.70, 0.95, an.y) * step(local_pos.y, 0.12);
	float wear_mask = max(corner, max(top_edge, bottom_edge));
	wear_mask += smoothstep(0.78, 0.98, fine) * 0.18;
	col = mix(col, rust_color, wear_mask * wear_strength * (0.35 + streak * 0.45));

	float dirt = triplanar_noise(world_pos + vec3(0.0, seed * 0.2, 0.0), 6.0);
	col *= 0.94 + dirt * 0.10;

	ALBEDO = col;
	ROUGHNESS = clamp(
		0.72 - rib_crest * 0.12 + (1.0 - rib_valley) * 0.08 + wear_mask * 0.14 + fine * 0.05,
		0.38,
		0.94
	);
	METALLIC = clamp(0.22 + rib_crest * 0.18 - wear_mask * 0.08, 0.08, 0.42);
}
