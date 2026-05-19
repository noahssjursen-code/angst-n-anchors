shader_type spatial;
render_mode unshaded, cull_back;

// Grass texture overlay using two-octave value noise on world XZ.
// No imported textures — noise is generated entirely in the fragment shader.
uniform float grass_scale    : hint_range(0.5, 8.0)  = 2.8;  // tile frequency of fine detail
uniform float grass_strength : hint_range(0.0, 0.5)  = 0.18; // how much the overlay shifts the base colour

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float _hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 74.27);
	return fract(p.x * p.y);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(_hash(i),              _hash(i + vec2(1.0, 0.0)), f.x),
		mix(_hash(i + vec2(0.0, 1.0)), _hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec3 base = COLOR.rgb;

	// Two octaves: coarse clumps + fine blade-scale detail
	vec2 uv   = world_pos.xz * grass_scale;
	float n   = _vnoise(uv) * 0.65 + _vnoise(uv * 2.7 + vec2(5.3, 1.7)) * 0.35;

	// Multiplicative overlay so dark areas (rock, pad) stay dark;
	// the effect is strongest where the base colour has some green.
	float shift = (n - 0.5) * grass_strength;
	ALBEDO = clamp(base + base * shift, 0.0, 1.0);
}
