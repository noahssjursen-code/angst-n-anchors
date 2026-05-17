shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2DArray displacement_map : filter_linear, repeat_enable;
uniform sampler2DArray slope_map : filter_linear, repeat_enable;
uniform vec4 length_scales = vec4(256.0, 64.0, 16.0, 4.0);

uniform float wave_time;
uniform float water_level = -1.5;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;

uniform vec3 shallow_albedo : source_color = vec3(0.028, 0.074, 0.118);
uniform vec3 deep_albedo    : source_color = vec3(0.006, 0.018, 0.036);
uniform vec3 horizon_tint   : source_color = vec3(0.068, 0.118, 0.172);
uniform float roughness     : hint_range(0.0, 1.0) = 0.20;
uniform float metallic      : hint_range(0.0, 1.0) = 0.0;
uniform float specular      : hint_range(0.0, 1.0) = 0.40;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.1;
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.48;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;

// Wind chop — per-pixel normal perturbation strength (independent of geometry waves).
uniform float chop_strength : hint_range(0.0, 1.0) = 0.12;

uniform float foam_strength    : hint_range(0.0, 2.0) = 0.55;
uniform float foam_steep_start : hint_range(0.0, 1.0) = 0.60;
uniform float foam_steep_end   : hint_range(0.0, 1.0) = 0.92;

uniform vec4 boat_coupling = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 boat_coupling_axes = vec2(1.0, 1.0);
uniform vec2 boat_velocity = vec2(0.0, 0.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_wave_steep;
varying float v_boat_wake;
varying float v_foam;

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

	vec3 displacement = vec3(0.0);
	vec2 slopes = vec2(0.0);
	float fft_foam = 0.0;

	for(int i = 0; i < 4; i++) {
		float lScale = length_scales[i];
		vec2 uv = wp.xz / lScale;
		
		vec4 disp_sample = textureLod(displacement_map, vec3(uv, float(i)), 0.0);
		vec4 slope_sample = textureLod(slope_map, vec3(uv, float(i)), 0.0);
		
		displacement += disp_sample.xyz;
		slopes += slope_sample.xy;
		fft_foam += clamp(disp_sample.w, 0.0, 1.0);
	}

	fft_foam = clamp(fft_foam * 0.22, 0.0, 1.0);

	// Increase the FFT base amplitude slightly so shapes have mass.
	float amp_scale = wave_intensity * wave_energy_multiplier * 0.42;
	displacement *= amp_scale;
	slopes *= amp_scale;

	// Full summed slopes define geometry / lighting.
	vec3 displaced_world = vec3(wp.x + displacement.x, water_level + displacement.y, wp.z + displacement.z);

	float boat_dip = 0.0;
	float ddip_dx = 0.0;
	float ddip_dz = 0.0;
	float wake = 0.0;
	if (boat_coupling.z > 0.0001) {
		float bx = boat_coupling.x;
		float bz = boat_coupling.y;
		float amp = boat_coupling.z;
		float sx = max(boat_coupling_axes.x, 0.01);
		float sz = max(boat_coupling_axes.y, 0.01);
		float dx = displaced_world.x - bx;
		float dz = displaced_world.z - bz;
		float u = dx / sx;
		float v = dz / sz;
		float g = -0.5 * (u * u + v * v);
		if (g > -8.0) {
			boat_dip = amp * exp(g);
			ddip_dx = -boat_dip * u / sx;
			ddip_dz = -boat_dip * v / sz;
		}

		// Trailing wake
		float v_len = length(boat_velocity);
		if (v_len > 0.5) {
			vec2 v_dir = boat_velocity / v_len;
			float along = dx * v_dir.x + dz * v_dir.y;
			float across = dx * -v_dir.y + dz * v_dir.x;
			
			// Behind the boat
			if (along < 0.0 && along > -v_len * 3.0) {
				float trail_width = mix(sz * 1.2, sz * 3.0, -along / (v_len * 3.0));
				float t_u = across / trail_width;
				float t_v = along / (v_len * 3.0); 
				
				float t_g = -0.5 * (t_u * t_u);
				if (t_g > -5.0) {
					// Mask for foam wake
					wake = exp(t_g) * (1.0 + t_v) * clamp(v_len * 0.1, 0.0, 1.0);
				}
			}
		}
	}
	displaced_world.y -= boat_dip;
	slopes.x += ddip_dx;
	slopes.y += ddip_dz;

	vec3 world_n_geom = normalize(vec3(-slopes.x, 1.0, -slopes.y));
	vec3 world_n_foam_metric = normalize(vec3(-slopes.x * 0.25, 1.0, -slopes.y * 0.25));

	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced_world, 1.0)).xyz;
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_n_geom, 0.0)).xyz);

	v_world_pos   = displaced_world;
	v_world_normal = world_n_geom;
	float foam_steep_raw = 1.0 - clamp(world_n_foam_metric.y, 0.0, 1.0);
	// Tighter power curve here reduces the area of wave peaks classified as "steep"
	v_wave_steep = pow(foam_steep_raw, 2.75);
	v_boat_wake = wake;
	v_foam = fft_foam;
}

void fragment() {
	vec3 nm = normalize(v_world_normal);
	vec2 xz = v_world_pos.xz;
	float wt = wave_time;

	/* Stable finite-difference width */
	float epsilon = mix(0.74, 0.98, chop_strength);

	vec2 xz_eff = xz + wt * vec2(0.42, -0.35) + vec2(sin(wt * 0.21), cos(wt * 0.17)) * 0.75;
	vec2 g_eta = wf_ocean_eta_gradient(xz_eff, wt, epsilon);

	float dh_dx = g_eta.x;
	float dh_dz = g_eta.y;

	float grad_mag = length(g_eta);
	float grad_damp = 1.0 / (1.0 + grad_mag * 1.7);
	float ripple_gain = chop_strength * mix(7.8, 5.9, chop_strength) * mix(1.0, 0.74, clamp(v_wave_steep, 0.0, 1.0));
	ripple_gain *= mix(1.0, grad_damp, 0.38);
	vec3 lateral = vec3(-dh_dx, 0.0, -dh_dz) * ripple_gain;

	vec3 ripple = lateral - nm * dot(nm, lateral);
	vec3 world_n = normalize(nm + ripple);

	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	float flat_ndv = clamp(dot(nm, view_dir), 0.001, 1.0);
	float look_graze = 1.0 - pow(flat_ndv, 1.18);
	vec3 body = mix(deep_albedo, shallow_albedo, look_graze * (0.22 + near_color_lift * 0.25));
	
	float fres = pow(look_graze, fresnel_power * 1.2);
	vec3 col = mix(body, horizon_tint, fres * fresnel_sky_mix);

	mat2 ROT_A = mat2(vec2(0.809174, -0.587582), vec2(0.587582, 0.809174));
	mat2 ROT_B = mat2(vec2(0.422618, -0.906308), vec2(0.906308, 0.422618));

	vec2 xz_a = ROT_A * xz;
	vec2 xz_b = ROT_B * xz;
	vec2 foam_uv = xz_a + xz_b * vec2(-0.27, 0.41);

	float foam_noise = wf_vnoise(
		foam_uv * 5.974 + xz_b.xx * vec2(-0.31, -0.22) + wt * vec2(1.47, -1.21));

	// Combine steepness-driven foam + FFT Jacobian foam (squash cascade stacking).
	float steep_foam = smoothstep(foam_steep_start, foam_steep_end, v_wave_steep) * foam_strength;
	float fft_foam_w = clamp(v_foam, 0.0, 1.0) * foam_strength * 0.16;
	float foam = steep_foam + fft_foam_w; 
	
	foam *= mix(0.15, 1.0, foam_noise);
	// Lower the floor for foam, make it slightly translucent, and mix based on final foam scalar.
	// This helps foam look like a surface layer rather than a solid opaque mesh.
	float foam_mask = clamp(foam, 0.0, 1.0);
	col = mix(col, vec3(0.86, 0.90, 0.93), foam_mask * 0.85);

	vec2 jitter_c = xz_a * 21.974 + xz_b.yy * vec2(-9.834, 7.917) + wt * vec2(8.93, -6.71);
	vec2 jitter_d = xz_b.yx * vec2(17.401, -14.917) + wt * vec2(-7.61, 8.734);

	float sp = wf_vnoise(jitter_c) * 0.68 + wf_vnoise(jitter_d * 6.417 + vec2(83.917, -41.734)) * 0.32;

	ALBEDO = col;

	/* FFT macro-normals are already directional; killing roughness (*0.45) reads as lacquered glass. */
	float chop_rough_boost = chop_strength * 0.12;
	float r_base = max(roughness * 1.18 + chop_rough_boost, 0.16);
	float r_micro = clamp(
		r_base + 0.042 * (sp - 0.5) + v_wave_steep * 0.035, 0.12, 0.93);

	ROUGHNESS = mix(r_micro, mix(0.78, 0.92, foam_noise * 0.35), foam_mask);

	METALLIC = metallic * 0.65;
	SPECULAR = mix(specular * 0.72, 0.17, foam_mask);
}
