// Shared approved ocean shading helpers. Keep body colour, Fresnel, sky
// reflection, crest breakup, and glint identical across fixed-cost LOD tiers.

float ocean_hash21(vec2 p) {
	vec2 hp = fract(p * vec2(123.344, 445.891));
	hp += dot(hp, hp + 341.743);
	return fract(hp.x * hp.y * 9571.834);
}

float ocean_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = ocean_hash21(i);
	float b = ocean_hash21(i + vec2(1.0, 0.0));
	float c = ocean_hash21(i + vec2(0.0, 1.0));
	float d = ocean_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float ocean_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += a * ocean_vnoise(p);
		p = m * p * 2.07;
		a *= 0.5;
	}
	return v;
}

vec2 ocean_wake_uv(vec2 world_xz, vec2 wake_origin, float wake_extent) {
	return (world_xz - wake_origin) / max(wake_extent, 0.001);
}

float ocean_wake_coverage(vec2 uv) {
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return inside.x * inside.y;
}

float ocean_fresnel(vec3 normal_world, vec3 view_dir) {
	float ndv = clamp(dot(normal_world, view_dir), 0.001, 1.0);
	return 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
}

float ocean_crest(
	vec3 world_pos,
	vec3 normal_world,
	float water_level_value,
	float wave_time_value,
	float wave_intensity_value
) {
	float steep = clamp(1.0 - normal_world.y, 0.0, 1.0);
	float height_rel = clamp((world_pos.y - water_level_value) * 0.55, -0.5, 1.0);
	float noise = ocean_vnoise(world_pos.xz * 0.55 + wave_time_value * 0.12);
	float crest = smoothstep(0.22, 0.78, steep * 0.9 + max(height_rel, 0.0) * 0.2);
	crest *= mix(0.4, 1.0, noise);
	crest *= mix(1.0, 0.5, clamp((wave_intensity_value - 0.8) * 0.4, 0.0, 1.0));
	return clamp(crest, 0.0, 1.0);
}

vec3 ocean_body(
	vec3 deep_color,
	vec3 shallow_color,
	vec3 normal_world,
	vec3 view_dir,
	vec3 world_pos,
	float water_level_value,
	float near_lift,
	float crest,
	float noise
) {
	// Absorbed/scattered water colour. Angle-dependent sky colour belongs in
	// environment reflection, not this diffuse term. Avoid height-painted bands.
	return mix(deep_color, shallow_color, 0.08 + crest * 0.10);
}

// Independent high-precision hash: the legacy noise hash multiplies very large
// float values before fract(), which quantizes cell jitter into visible rows.
float ocean_foam_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float ocean_foam_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ocean_foam_hash(i), ocean_foam_hash(i + vec2(1,0)), u.x),
		mix(ocean_foam_hash(i + vec2(0,1)), ocean_foam_hash(i + vec2(1)), u.x), u.y);
}

// Coarse FFT compression decides where foam is possible, not its texture.
float ocean_foam_coverage(vec2 xz, float wt, float breaking, float steep) {
	vec2 drift = xz + wt * vec2(0.16, -0.11);
	float footprint = max(length(dFdx(xz)), length(dFdy(xz)));
	float rafts = mix(0.5, ocean_foam_noise(drift * 2.3), 1.0 - smoothstep(0.12, 0.6, footprint));
	float lace = mix(0.5, ocean_foam_noise(drift * 9.7 + vec2(rafts * 2.0)), 1.0 - smoothstep(0.03, 0.18, footprint));
	float density = breaking + steep * 0.10 - rafts * 0.65 - lace * 0.30;
	return smoothstep(0.24, 0.37, density);
}

float ocean_foam_bubbles(vec2 xz, float wt, float footprint) {
	vec2 drift = xz + wt * vec2(0.16, -0.11);
	vec2 p = drift * 14.0;
	p += vec2(ocean_foam_noise(drift * 3.1), ocean_foam_noise(drift * 3.1 + vec2(37.1))) * 2.0;
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 10.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 id = cell + offset;
			vec2 centre = vec2(ocean_foam_hash(id), ocean_foam_hash(id + vec2(37.2, 11.8)));
			float radius = mix(0.08, 0.40, ocean_foam_hash(id + vec2(9.3, 53.1)));
			nearest = min(nearest, length(offset + centre - local) - radius);
		}
	}
	float aa = clamp(footprint * 14.0, 0.025, 0.3);
	float holes = smoothstep(-aa, aa, nearest);
	float resolved = 1.0 - smoothstep(0.018, 0.06, footprint);
	return mix(0.78, mix(0.25, 1.0, holes), resolved);
}
