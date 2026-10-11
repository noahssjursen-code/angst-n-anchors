shader_type spatial;
render_mode diffuse_burley;

// 0 = iron ore (hematite), 1 = coal
uniform int pile_kind : hint_range(0, 1) = 0;

uniform vec3 iron_base : source_color = vec3(0.58, 0.26, 0.14);
uniform vec3 iron_rust : source_color = vec3(0.74, 0.36, 0.17);
uniform vec3 iron_dark : source_color = vec3(0.30, 0.12, 0.07);

uniform vec3 coal_base : source_color = vec3(0.07, 0.07, 0.09);
uniform vec3 coal_fleck : source_color = vec3(0.20, 0.20, 0.22);
uniform vec3 coal_highlight : source_color = vec3(0.34, 0.35, 0.38);

uniform float grain_scale : hint_range(4.0, 80.0) = 32.0;
uniform float chunk_scale : hint_range(1.0, 24.0) = 8.0;

varying vec3 material_pos;
varying vec3 material_normal;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
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

float sample_grain(vec3 pos, float scale) {
	vec3 n = abs(normalize(material_normal));
	n = pow(max(n, vec3(0.0001)), vec3(2.0));
	n /= (n.x + n.y + n.z);
	float xz = value_noise(pos.xz * scale + pos.y * 0.41);
	float xy = value_noise(pos.xy * scale + pos.z * 0.37);
	float yz = value_noise(pos.yz * scale + pos.x * 0.29);
	float grain = xz * n.y + xy * n.z + yz * n.x;
	// Unresolved grains average out instead of sparkling at distant quays.
	float footprint = max(length(dFdx(pos)), length(dFdy(pos))) * scale;
	return mix(grain, .5, smoothstep(.4, 1.5, footprint));
}

void vertex() {
	// Metre-scaled object coordinates retain precision at ports kilometres away.
	// Absolute world coordinates quantized the old fine-grain hash into bands.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	material_pos = VERTEX * scale;
	material_normal = normalize(NORMAL / max(scale, vec3(.0001)));
}

void fragment() {
	float fine = sample_grain(material_pos, grain_scale);
	float chunk = sample_grain(material_pos + vec3(17.3, 4.1, 9.8), chunk_scale);
	float macro = sample_grain(material_pos + vec3(3.7, 22.0, 11.4), chunk_scale * 0.38);

	if (pile_kind == 0) {
		vec3 col = mix(iron_dark, iron_base, chunk * 0.85 + macro * 0.15);
		col = mix(col, iron_rust, fine * 0.62 + macro * 0.22);
		col *= 0.86 + fine * 0.28;
		float glint = smoothstep(0.90, 0.98, fine) * smoothstep(0.72, 0.92, chunk) * 0.18;
		col += vec3(glint * 0.10, glint * 0.05, glint * 0.02);
		ALBEDO = col;
		ROUGHNESS = clamp(0.94 - chunk * 0.14 + fine * 0.04, 0.78, 0.98);
		METALLIC = 0.04 + glint * 0.22;
	} else {
		vec3 col = mix(coal_base, coal_fleck, chunk * 0.70 + macro * 0.18);
		col = mix(col, coal_highlight, fine * 0.22);
		float flake = smoothstep(0.84, 0.96, fine + chunk * 0.25) * 0.32;
		col += vec3(flake * 0.14);
		ALBEDO = col;
		ROUGHNESS = mix(0.88, 0.98, fine * 0.65);
		METALLIC = flake * 0.42;
	}
}
