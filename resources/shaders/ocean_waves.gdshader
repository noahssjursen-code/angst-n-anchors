shader_type spatial;
render_mode blend_mix,depth_prepass_alpha,specular_schlick_ggx;

/* Must match scripts/systems/boat/wave_surface.gd — waves + optional hull dip uniforms. */
uniform float wave_time;
uniform float water_level = -1.5;
uniform float amplitude_1 = 0.30;
uniform float frequency_1 = 0.18;
uniform float speed_1 = 0.75;
uniform vec2 dir_1 = vec2(1.0, 0.6);
uniform float steepness_1 = 0.45;
uniform float amplitude_2 = 0.12;
uniform float frequency_2 = 0.18;
uniform float speed_2 = 1.2;
uniform vec2 dir_2 = vec2(-0.5, 1.0);
uniform float steepness_2 = 0.35;
uniform float amplitude_3 = 0.22;
uniform float frequency_3 = 0.05;
uniform float speed_3 = 0.6;
uniform vec2 dir_3 = vec2(0.23, -0.97);
uniform float steepness_3 = 0.40;
uniform float amplitude_4 = 0.08;
uniform float frequency_4 = 0.32;
uniform float speed_4 = 1.5;
uniform vec2 dir_4 = vec2(-0.91, -0.2);
uniform float steepness_4 = 0.25;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;

uniform vec3 shallow_albedo : source_color = vec3(0.028, 0.074, 0.118);
uniform vec3 deep_albedo    : source_color = vec3(0.006, 0.018, 0.036);
uniform vec3 horizon_tint   : source_color = vec3(0.068, 0.118, 0.172);
uniform float roughness     : hint_range(0.0, 1.0) = 0.14;
uniform float metallic      : hint_range(0.0, 1.0) = 0.02;
uniform float specular      : hint_range(0.0, 1.0) = 0.56;
uniform float water_alpha   : hint_range(0.15, 1.0) = 0.94;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.8;
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.62;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;

// Wind chop — per-pixel normal perturbation strength (independent of geometry waves).
uniform float chop_strength : hint_range(0.0, 1.0) = 0.12;

uniform float foam_strength    : hint_range(0.0, 2.0) = 0.55;
uniform float foam_steep_start : hint_range(0.0, 1.0) = 0.60;
uniform float foam_steep_end   : hint_range(0.0, 1.0) = 0.92;

uniform vec4 boat_coupling = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 boat_coupling_axes = vec2(1.0, 1.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_wave_steep;

/* Smooth procedural noise — pure sine grids read as tiling under one sun/light. */

float wf_hash21(vec2 p) {
	vec2 hp = fract(p * vec2(123.344, 445.891));
	hp += dot(hp, hp + 341.743);
	return fract(hp.x * hp.y * 9571.834);
}


float wf_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = wf_hash21(i);
	float b = wf_hash21(i + vec2(1.0, 0.0));
	float c = wf_hash21(i + vec2(0.0, 1.0));
	float d = wf_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);


}

float wf_ocean_ripple_eta(vec2 xz, float wt) {


	mat2 ra = mat2(vec2(0.809174, -0.587582), vec2(0.587582, 0.809174));


	mat2 rb = mat2(vec2(0.422618, -0.906308), vec2(0.906308, 0.422618));


	vec2 a = ra * xz;


	vec2 b = rb * xz;


	float wt_e = wt * 1.38;


	// Suppress broad stationary bowl-like features: favor finer octaves + faster drift.
	float eta = wf_vnoise(a * 1.58 + wt_e * vec2(-0.63, 0.71)) * 0.36
			+ wf_vnoise(b * 2.74 + wt_e * vec2(0.88, -0.73)) * 0.31
			+ wf_vnoise(
				  a * 4.95
				  + vec2(b.x * (-0.24) + b.y * 0.17, b.x * 0.19 + b.y * 0.26)
				  + wt_e * vec2(-0.96, 0.91))
				* 0.11;

	eta += sin(dot(a, vec2(1.21, -0.93)) + wt_e * 1.37) * 0.046;
	eta += sin(dot(b * vec2(2.64, -2.21), vec2(0.92, 0.78)) + wt_e * (-1.61)) * 0.034;


	return eta;


}

vec2 wf_ocean_eta_gradient(vec2 xz, float wt, float e) {


	float e2 = max(e, 1e-4);


	float hx_m_z_m = wf_ocean_ripple_eta(xz + vec2(-e2, -e2), wt);


	float hx_0_z_m = wf_ocean_ripple_eta(xz + vec2(0.0, -e2), wt);


	float hx_p_z_m = wf_ocean_ripple_eta(xz + vec2(e2, -e2), wt);


	float hx_m_0 = wf_ocean_ripple_eta(xz + vec2(-e2, 0.0), wt);


	float hx_p_0 = wf_ocean_ripple_eta(xz + vec2(e2, 0.0), wt);


	float hx_m_z_p = wf_ocean_ripple_eta(xz + vec2(-e2, e2), wt);


	float hx_0_z_p = wf_ocean_ripple_eta(xz + vec2(0.0, e2), wt);


	float hx_p_z_p = wf_ocean_ripple_eta(xz + vec2(e2, e2), wt);


	float gx = hx_p_z_m + 2.0 * hx_p_0 + hx_p_z_p - hx_m_z_m - 2.0 * hx_m_0 - hx_m_z_p;


	float gz = hx_m_z_p + 2.0 * hx_0_z_p + hx_p_z_p - hx_m_z_m - 2.0 * hx_0_z_m - hx_p_z_m;


	float inv = 1.0 / max(8.0 * e2, 1e-4);


	return vec2(gx * inv, gz * inv);


}



void vertex() {
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wp = w4.xyz;

	vec2 d1n = normalize(dir_1);
	vec2 d2n = normalize(dir_2);
	vec2 d3n = normalize(dir_3);
	vec2 d4n = normalize(dir_4);
	float amp_scale = wave_intensity * wave_energy_multiplier;
	float a1 = amplitude_1 * amp_scale;
	float a2 = amplitude_2 * amp_scale;
	float a3 = amplitude_3 * amp_scale;
	float a4 = amplitude_4 * amp_scale;
	float q1 = clamp(steepness_1, 0.0, 0.98);
	float q2 = clamp(steepness_2, 0.0, 0.98);
	float q3 = clamp(steepness_3, 0.0, 0.98);
	float q4 = clamp(steepness_4, 0.0, 0.98);
	float ph1 = (wp.x * d1n.x + wp.z * d1n.y) * frequency_1 + wave_time * speed_1;
	float ph2 = (wp.x * d2n.x + wp.z * d2n.y) * frequency_2 + wave_time * speed_2;
	float ph3 = (wp.x * d3n.x + wp.z * d3n.y) * frequency_3 + wave_time * speed_3;
	float ph4 = (wp.x * d4n.x + wp.z * d4n.y) * frequency_4 + wave_time * speed_4;
	float s1 = sin(ph1); float c1 = cos(ph1);
	float s2 = sin(ph2); float c2 = cos(ph2);
	float s3 = sin(ph3); float c3 = cos(ph3);
	float s4 = sin(ph4); float c4 = cos(ph4);

	vec2 disp_xz = vec2(0.0);
	disp_xz += d1n * (q1 * a1 * c1);
	disp_xz += d2n * (q2 * a2 * c2);
	disp_xz += d3n * (q3 * a3 * c3);
	disp_xz += d4n * (q4 * a4 * c4);
	float disp_y = a1 * s1 + a2 * s2 + a3 * s3 + a4 * s4;

	vec3 displaced_world = vec3(wp.x + disp_xz.x, water_level + disp_y, wp.z + disp_xz.y);

	float boat_dip = 0.0;
	float ddip_dx = 0.0;
	float ddip_dz = 0.0;
	if (boat_coupling.z > 0.0001) {
		float bx = boat_coupling.x;
		float bz = boat_coupling.y;
		float amp = boat_coupling.z;
		float sx = max(boat_coupling_axes.x, 0.01);
		float sz = max(boat_coupling_axes.y, 0.01);
		float u = (displaced_world.x - bx) / sx;
		float v = (displaced_world.z - bz) / sz;
		float g = -0.5 * (u * u + v * v);
		if (g > -8.0) {
			boat_dip = amp * exp(g);
			ddip_dx = -boat_dip * u / sx;
			ddip_dz = -boat_dip * v / sz;
		}
	}
	displaced_world.y -= boat_dip;

	float dxdx = 1.0
		- q1 * a1 * frequency_1 * d1n.x * d1n.x * s1
		- q2 * a2 * frequency_2 * d2n.x * d2n.x * s2
		- q3 * a3 * frequency_3 * d3n.x * d3n.x * s3
		- q4 * a4 * frequency_4 * d4n.x * d4n.x * s4;
	float dzdz = 1.0
		- q1 * a1 * frequency_1 * d1n.y * d1n.y * s1
		- q2 * a2 * frequency_2 * d2n.y * d2n.y * s2
		- q3 * a3 * frequency_3 * d3n.y * d3n.y * s3
		- q4 * a4 * frequency_4 * d4n.y * d4n.y * s4;
	float dxdz = -q1 * a1 * frequency_1 * d1n.x * d1n.y * s1
		- q2 * a2 * frequency_2 * d2n.x * d2n.y * s2
		- q3 * a3 * frequency_3 * d3n.x * d3n.y * s3
		- q4 * a4 * frequency_4 * d4n.x * d4n.y * s4;
	float dydx = (
		a1 * frequency_1 * d1n.x * c1 + a2 * frequency_2 * d2n.x * c2
		+ a3 * frequency_3 * d3n.x * c3 + a4 * frequency_4 * d4n.x * c4
		- ddip_dx
	);
	float dydz = (
		a1 * frequency_1 * d1n.y * c1 + a2 * frequency_2 * d2n.y * c2
		+ a3 * frequency_3 * d3n.y * c3 + a4 * frequency_4 * d4n.y * c4
		- ddip_dz
	);

	vec3 tx = vec3(dxdx, dydx, dxdz);
	vec3 tz = vec3(dxdz, dydz, dzdz);
	vec3 world_n = normalize(cross(tz, tx));

	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced_world, 1.0)).xyz;
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_n, 0.0)).xyz);

	v_world_pos   = displaced_world;
	v_world_normal = world_n;
	v_wave_steep  = 1.0 - clamp(world_n.y, 0.0, 1.0);
}

void fragment() {
	vec3 nm = normalize(v_world_normal);
	vec2 xz = v_world_pos.xz;
	float wt = wave_time;

	/* Stable finite-difference width (avoid distance-based ε — that caused strobing topo lines). */


	float epsilon = mix(0.74, 0.98, chop_strength);


	vec2 xz_eff = xz + wt * vec2(0.42, -0.35) + vec2(sin(wt * 0.21), cos(wt * 0.17)) * 0.75;



	vec2 g_eta = wf_ocean_eta_gradient(xz_eff, wt, epsilon);


	float dh_dx = g_eta.x;


	float dh_dz = g_eta.y;


	float grad_mag = length(g_eta);
	float grad_damp = 1.0 / (1.0 + grad_mag * 1.7);
	float ripple_gain = chop_strength * mix(8.6, 6.2, chop_strength) * mix(1.0, 0.78, clamp(v_wave_steep, 0.0, 1.0));
	ripple_gain *= mix(1.0, grad_damp, 0.38);
	vec3 lateral = vec3(-dh_dx, 0.0, -dh_dz) * ripple_gain;


	vec3 ripple = lateral - nm * dot(nm, lateral);


	vec3 world_n = normalize(nm + ripple);


	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float ndv = clamp(dot(world_n, view_dir), 0.001, 1.0);


	float look_graze = 1.0 - pow(ndv, 1.18);

	vec3 body = mix(deep_albedo, shallow_albedo, look_graze * (0.22 + near_color_lift * 0.25));


	float fres = pow(look_graze, fresnel_power);


	vec3 col = mix(body, horizon_tint, fres * fresnel_sky_mix);

	mat2 ROT_A = mat2(vec2(0.809174, -0.587582), vec2(0.587582, 0.809174));


	mat2 ROT_B = mat2(vec2(0.422618, -0.906308), vec2(0.906308, 0.422618));


	vec2 xz_a = ROT_A * xz;


	vec2 xz_b = ROT_B * xz;


	vec2 foam_uv = xz_a + xz_b * vec2(-0.27, 0.41);


	float foam_noise = wf_vnoise(
		foam_uv * 5.974 + xz_b.xx * vec2(-0.31, -0.22) + wt * vec2(1.47, -1.21));

	float foam = smoothstep(foam_steep_start, foam_steep_end, v_wave_steep) * foam_strength;


	foam *= mix(0.35, 1.0, foam_noise);


	col = mix(col, vec3(0.86, 0.90, 0.93), foam);

	vec2 jitter_c = xz_a * 21.974 + xz_b.yy * vec2(-9.834, 7.917) + wt * vec2(8.93, -6.71);


	vec2 jitter_d = xz_b.yx * vec2(17.401, -14.917) + wt * vec2(-7.61, 8.734);



	float sp = wf_vnoise(jitter_c) * 0.68 + wf_vnoise(jitter_d * 6.417 + vec2(83.917, -41.734)) * 0.32;


	ALBEDO = col;



	float r_body = clamp(
		roughness + 0.046 * (sp - 0.5) + v_wave_steep * 0.045, 0.034, 0.93);


	float spec_body = specular * mix(0.78, 0.96, sp);


	ROUGHNESS = mix(r_body, 0.88, foam);


	METALLIC = mix(metallic, 0.02, foam);


	SPECULAR = mix(spec_body, 0.22, foam);


	ALPHA = water_alpha;


}
