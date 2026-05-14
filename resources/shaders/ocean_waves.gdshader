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

uniform vec3 shallow_albedo : source_color = vec3(0.04, 0.14, 0.28);
uniform vec3 deep_albedo    : source_color = vec3(0.008, 0.025, 0.055);
uniform vec3 horizon_tint   : source_color = vec3(0.10, 0.20, 0.38);
uniform float roughness     : hint_range(0.0, 1.0) = 0.07;
uniform float metallic      : hint_range(0.0, 1.0) = 0.1;
uniform float specular      : hint_range(0.0, 1.0) = 0.92;
uniform float water_alpha   : hint_range(0.15, 1.0) = 0.94;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.8;
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.72;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.20;

// Wind chop — per-pixel normal perturbation strength (independent of geometry waves).
uniform float chop_strength : hint_range(0.0, 1.0) = 0.08;

uniform float foam_strength    : hint_range(0.0, 2.0) = 0.55;
uniform float foam_steep_start : hint_range(0.0, 1.0) = 0.60;
uniform float foam_steep_end   : hint_range(0.0, 1.0) = 0.92;

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
	vec2 xz = v_world_pos.xz;

	// Per-pixel wind chop: 4 layers of scrolling directional normals.
	// Vertex Gerstner gives macro swells; this gives the micro-ripple churn
	// that makes water look alive at every distance.
	vec2 p1 = xz * 0.11;
	vec2 p2 = xz * 0.27;
	vec2 p3 = xz * 0.61;
	vec2 p4 = xz * 1.40;
	float nx = sin(p1.x + p1.y * 0.7  - wave_time * 0.55) * 0.40
	         + sin(p2.x * 0.8 - p2.y  + wave_time * 0.95) * 0.28
	         + sin(p3.y * 1.1 + p3.x  - wave_time * 1.80) * 0.18
	         + sin(p4.x - p4.y * 1.3  + wave_time * 3.10) * 0.14;
	float nz = cos(p1.y + p1.x * 0.6  + wave_time * 0.48) * 0.40
	         + cos(p2.y * 0.9 + p2.x  - wave_time * 0.82) * 0.28
	         + cos(p3.x * 1.2 - p3.y  + wave_time * 1.60) * 0.18
	         + cos(p4.y + p4.x * 1.4  - wave_time * 2.70) * 0.14;

	vec3 base_n  = normalize(v_world_normal);
	vec3 world_n = normalize(base_n + vec3(nx, 0.0, nz) * chop_strength);

	// Write perturbed normal in view space so Godot's PBR lighting uses it.
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float ndv        = clamp(dot(world_n, view_dir), 0.001, 1.0);
	float look_graze = 1.0 - pow(ndv, 1.18);

	vec3 body  = mix(deep_albedo, shallow_albedo, look_graze * (0.22 + near_color_lift * 0.25));
	float fres = pow(look_graze, fresnel_power);
	vec3 col   = mix(body, horizon_tint, fres * fresnel_sky_mix);

	// Foam: noisy break-up so it looks like spray, not paint.
	float foam_noise = fract(sin(dot(xz, vec2(12.9898, 78.233))) * 43758.5453);
	float foam = smoothstep(foam_steep_start, foam_steep_end, v_wave_steep) * foam_strength;
	foam *= mix(0.35, 1.0, foam_noise);
	col = mix(col, vec3(0.86, 0.90, 0.93), foam);

	ALBEDO    = col;
	ROUGHNESS = mix(roughness, 0.88, foam);
	METALLIC  = mix(metallic, 0.02, foam);
	SPECULAR  = mix(specular, 0.22, foam);
	ALPHA     = water_alpha;
}
