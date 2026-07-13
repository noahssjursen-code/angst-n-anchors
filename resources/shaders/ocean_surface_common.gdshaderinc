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

vec2 ocean_chop_gradient(vec2 xz, float wt) {
	vec2 d = vec2(0.0);
	float p1 = dot(xz, vec2(1.73, -1.19)) + wt * 2.15;
	float p2 = dot(xz, vec2(-2.41, 1.37)) + wt * 2.85;
	float p3 = dot(xz, vec2(0.91, 2.63)) + wt * (-3.35);
	d += vec2(1.73, -1.19) * cos(p1) * 0.55;
	d += vec2(-2.41, 1.37) * cos(p2) * 0.35;
	d += vec2(0.91, 2.63) * cos(p3) * 0.22;
	return d;
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
	float facing = pow(clamp(dot(normal_world, view_dir), 0.001, 1.0), 0.7);
	float height_rel = clamp((world_pos.y - water_level_value) * 0.55, -0.5, 1.0);
	vec3 body = mix(deep_color, shallow_color, (1.0 - facing) * (0.25 + near_lift * 0.4));
	body = mix(body, vec3(0.015, 0.11, 0.13), crest * 0.32);
	float trough = clamp(-height_rel, 0.0, 0.4) * mix(0.55, 1.0, noise);
	return body * (1.0 - trough * 0.28);
}

vec3 ocean_sky_reflection(
	vec3 body,
	vec3 horizon_color,
	vec3 top_color,
	vec3 normal_world,
	vec3 view_dir,
	float fresnel,
	float sky_mix
) {
	float facing = pow(clamp(dot(normal_world, view_dir), 0.001, 1.0), 0.7);
	vec3 ref_dir = reflect(-view_dir, normal_world);
	float sky_t = pow(clamp(ref_dir.y * 0.5 + 0.5, 0.0, 1.0), 0.85);
	vec3 sky_col = mix(horizon_color, top_color, sky_t);
	float sky_w = fresnel * sky_mix * mix(1.15, 0.35, facing);
	return mix(body, sky_col, clamp(sky_w, 0.0, 0.92));
}

float ocean_glint(vec3 normal_world, vec3 view_dir, vec3 sun_dir, float distance_to_camera) {
	float ndh = clamp(dot(normal_world, normalize(view_dir + sun_dir)), 0.0, 1.0);
	float glint = pow(ndh, 96.0) * 0.35 + pow(ndh, 420.0) * 0.55;
	glint *= 1.0 - smoothstep(50.0, 450.0, distance_to_camera) * 0.9;
	return min(glint, 0.85);
}
