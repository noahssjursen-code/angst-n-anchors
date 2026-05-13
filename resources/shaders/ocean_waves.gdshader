shader_type spatial;
render_mode specular_schlick_ggx;

/* Must match scripts/systems/boat/wave_surface.gd — waves + optional hull dip uniforms. */
uniform float wave_time;
uniform float water_level = -1.5;
uniform float amplitude_1 = 0.30;
uniform float frequency_1 = 0.18;
uniform float speed_1 = 0.75;
uniform vec2 dir_1 = vec2(1.0, 0.6);
uniform float amplitude_2 = 0.12;
uniform float frequency_2 = 0.26;
uniform float speed_2 = 1.1;
uniform vec2 dir_2 = vec2(-0.5, 1.0);
uniform float wave_intensity = 1.0;

// Sunlit surface tint — subdued; bulk darkness comes from deep_albedo.
uniform vec3 shallow_albedo : source_color = vec3(0.04, 0.10, 0.14);
uniform float roughness = 0.38;
uniform float metallic = 0.06;
uniform float specular = 0.28;

uniform vec3 deep_albedo : source_color = vec3(0.006, 0.018, 0.032);
uniform float fresnel_power : hint_range(0.5, 10.0) = 4.2;
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.06;
uniform vec3 horizon_tint : source_color = vec3(0.14, 0.18, 0.22);
uniform float foam_strength : hint_range(0.0, 1.5) = 0.65;
uniform float foam_steep_start : hint_range(0.0, 1.0) = 0.12;
uniform float foam_steep_end : hint_range(0.0, 1.0) = 0.42;
uniform float micro_ripple : hint_range(0.0, 0.12) = 0.022;

uniform vec4 boat_coupling = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 boat_coupling_axes = vec2(1.0, 1.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_wave_steep;

void vertex() {
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wp = w4.xyz;

	vec2 d1n = normalize(dir_1);
	vec2 d2n = normalize(dir_2);
	float a1 = amplitude_1 * wave_intensity;
	float a2 = amplitude_2 * wave_intensity;
	float ph1 = (wp.x * d1n.x + wp.z * d1n.y) * frequency_1 + wave_time * speed_1;
	float ph2 = (wp.x * d2n.x + wp.z * d2n.y) * frequency_2 + wave_time * speed_2;
	float wv1 = sin(ph1) * a1;
	float wv2 = sin(ph2) * a2;

	float boat_dip = 0.0;
	float ddip_dx = 0.0;
	float ddip_dz = 0.0;
	if (boat_coupling.z > 0.0001) {
		float bx = boat_coupling.x;
		float bz = boat_coupling.y;
		float amp = boat_coupling.z;
		float sx = max(boat_coupling_axes.x, 0.01);
		float sz = max(boat_coupling_axes.y, 0.01);
		float u = (wp.x - bx) / sx;
		float v = (wp.z - bz) / sz;
		float g = -0.5 * (u * u + v * v);
		if (g > -8.0) {
			boat_dip = amp * exp(g);
			ddip_dx = -boat_dip * u / sx;
			ddip_dz = -boat_dip * v / sz;
		}
	}

	float displaced_y = water_level + wv1 + wv2 - boat_dip;

	float dw1dx = cos(ph1) * a1 * frequency_1 * d1n.x;
	float dw1dz = cos(ph1) * a1 * frequency_1 * d1n.y;
	float dw2dx = cos(ph2) * a2 * frequency_2 * d2n.x;
	float dw2dz = cos(ph2) * a2 * frequency_2 * d2n.y;
	float dwdx = dw1dx + dw2dx - ddip_dx;
	float dwdz = dw1dz + dw2dz - ddip_dz;
	vec3 world_n = normalize(vec3(-dwdx, 1.0, -dwdz));

	vec3 new_world = vec3(wp.x, displaced_y, wp.z);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world, 1.0)).xyz;
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_n, 0.0)).xyz);

	v_world_pos = new_world;
	v_world_normal = world_n;
	v_wave_steep = 1.0 - clamp(world_n.y, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float ndv = clamp(dot(n, view_dir), 0.001, 1.0);

	/* ndv high ≈ looking into the water (path through volume long) → stay near deep_albedo.
	   Grazing sees a little sunlit skin + weak fresnel toward muted horizon — not saturated blue. */
	float look_in = pow(ndv, 1.18);
	float look_graze = 1.0 - look_in;

	vec3 body = mix(deep_albedo, shallow_albedo, look_graze * 0.10);
	float fresnel = pow(look_graze, fresnel_power);
	vec3 col = mix(body, horizon_tint, fresnel * fresnel_sky_mix);

	// Crest foam from slope (synced with wave geometry).
	float foam = smoothstep(foam_steep_start, foam_steep_end, v_wave_steep) * foam_strength;
	col = mix(col, vec3(0.78, 0.82, 0.85), foam);

	// Subtle sparkle; keep centred near 1.0 so it does not lift overall brightness.
	vec2 xz = v_world_pos.xz;
	float rip = sin(xz.x * 14.0 + wave_time * 2.8) * sin(xz.y * 11.0 - wave_time * 2.1);
	col *= 1.0 + rip * micro_ripple;

	ALBEDO = col;
	ROUGHNESS = mix(roughness, 0.88, foam);
	METALLIC = mix(metallic, 0.02, foam);
	SPECULAR = mix(specular, 0.22, foam);
}
