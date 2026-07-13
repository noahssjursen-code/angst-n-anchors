shader_type spatial;
// Water owns its specular — Godot GGX on a flat ocean reads as plastic wrap.
render_mode diffuse_burley, specular_disabled;


uniform sampler2DArray displacement_map : filter_linear, repeat_enable;
uniform sampler2DArray slope_map : filter_linear, repeat_enable;
uniform vec4 length_scales = vec4(256.0, 64.0, 16.0, 4.0);
uniform vec4 cascade_fade_end = vec4(5500.0, 1536.0, 384.0, 96.0);
uniform float geomorph_strength : hint_range(0.0, 1.0) = 1.0;

uniform float wave_time;
uniform float water_level = -1.5;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;

// Absorbing volume colors (linear RGB). Deep = looking straight down.
uniform vec3 shallow_albedo : source_color = vec3(0.02, 0.08, 0.12);
uniform vec3 deep_albedo    : source_color = vec3(0.004, 0.02, 0.04);
uniform vec3 sky_top_color     : source_color = vec3(0.07, 0.28, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.34, 0.54, 0.78);
uniform vec3 sun_direction     = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color         : source_color = vec3(1.0, 0.9, 0.8);

uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.52;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;
uniform float chop_strength : hint_range(0.0, 1.0) = 0.14;
uniform float glint_strength : hint_range(0.0, 4.0) = 0.55;

uniform float foam_strength    : hint_range(0.0, 2.0) = 0.7;
uniform float foam_steep_start : hint_range(0.0, 1.0) = 0.22;
uniform float foam_steep_end   : hint_range(0.0, 1.0) = 0.65;

uniform vec4 boat_coupling = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 boat_coupling_axes = vec2(1.0, 1.0);
uniform vec4 boat_basis = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 boat_velocity = vec2(0.0, 0.0);

uniform sampler2D land_shelter_map  : filter_linear, repeat_disable;
uniform vec2      land_shelter_origin = vec2(0.0);
uniform float     land_shelter_size   = 0.0;
// Mid-ring clipmap: discard the near patch so only the outer ring draws.
// 0 = disabled (near patch).
uniform float     discard_half = 0.0; // Legacy fallback only.
uniform vec4      debug_tint : source_color = vec4(0.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_local_pos;
varying float v_wave_steep;
varying float v_foam;
varying float v_fresnel; // for light() soft reflections

#include "res://resources/shaders/ocean_surface_common.gdshaderinc"

void vertex() {
	VERTEX.xz = mix(VERTEX.xz, UV2, geomorph_strength);
	v_local_pos = VERTEX;
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wp = w4.xyz;
	float dist_to_cam = length(wp.xz - CAMERA_POSITION_WORLD.xz);

	vec3 displacement = vec3(0.0);
	vec2 slopes = vec2(0.0);
	float fft_foam = 0.0;

	for (int i = 0; i < 4; i++) {
		float lScale = length_scales[i];
		float cascade_weight = 1.0 - smoothstep(
			cascade_fade_end[i] * 0.75,
			cascade_fade_end[i],
			dist_to_cam
		);
		vec2 uv = wp.xz / lScale;
		vec4 disp_sample = textureLod(displacement_map, vec3(uv, float(i)), 0.0);
		vec4 slope_sample = textureLod(slope_map, vec3(uv, float(i)), 0.0);
		displacement += disp_sample.xyz * cascade_weight;
		slopes += slope_sample.xy * cascade_weight;
		fft_foam += clamp(disp_sample.w, 0.0, 1.0) * cascade_weight;
	}
	fft_foam = clamp(fft_foam, 0.0, 1.0);

	float shelter = 1.0;
	if (land_shelter_size > 0.0) {
		vec2 shelter_uv = (wp.xz - land_shelter_origin) / land_shelter_size;
		if (shelter_uv.x >= 0.0 && shelter_uv.x <= 1.0
				&& shelter_uv.y >= 0.0 && shelter_uv.y <= 1.0) {
			shelter = textureLod(land_shelter_map, shelter_uv, 0.0).r;
		}
	}

	float amp_scale = wave_intensity * wave_energy_multiplier * 0.42 * shelter;
	displacement *= amp_scale;
	slopes *= amp_scale;

	vec3 displaced_world = vec3(wp.x + displacement.x, water_level + displacement.y, wp.z + displacement.z);

	float boat_dip = 0.0;
	float ddip_dx = 0.0;
	float ddip_dz = 0.0;
	if (boat_coupling.z > 0.0001) {
		float bx = boat_coupling.x;
		float bz = boat_coupling.y;
		float amp = boat_coupling.z;
		float sx = max(boat_coupling_axes.x, 0.01);
		float sz = max(boat_coupling_axes.y, 0.01);
		float dx = displaced_world.x - bx;
		float dz = displaced_world.z - bz;
		float right_x = boat_basis.x;
		float right_z = boat_basis.y;
		float fwd_x = boat_basis.z;
		float fwd_z = boat_basis.w;
		float local_x = dx * right_x + dz * right_z;
		float local_z = dx * fwd_x + dz * fwd_z;
		float u = local_x / sx;
		float v = local_z / sz;
		float D = u * u + v * v;
		if (D < 4.0) {
			float a = 1.8;
			float b = 0.8;
			float c = 0.5;
			float exp_a = exp(-a * D);
			float exp_b = exp(-b * D);
			boat_dip = amp * (exp_a - c * D * exp_b);
			float d_dip_dD = amp * (-a * exp_a - c * exp_b * (1.0 - b * D));
			// Depression only — negative lobe would raise a berm around the hull.
			if (boat_dip < 0.0) {
				boat_dip = 0.0;
				d_dip_dD = 0.0;
			}
			float ddip_dlocal_x = d_dip_dD * 2.0 * u / sx;
			float ddip_dlocal_z = d_dip_dD * 2.0 * v / sz;
			ddip_dx = ddip_dlocal_x * right_x + ddip_dlocal_z * fwd_x;
			ddip_dz = ddip_dlocal_x * right_z + ddip_dlocal_z * fwd_z;
		}
	}
	displaced_world.y -= boat_dip;
	slopes.x += ddip_dx;
	slopes.y += ddip_dz;

	vec3 world_n_geom = normalize(vec3(-slopes.x, 1.0, -slopes.y));
	vec3 world_n_foam_metric = normalize(vec3(-slopes.x * 0.25, 1.0, -slopes.y * 0.25));

	mat4 inv_model = inverse(MODEL_MATRIX);
	VERTEX = (inv_model * vec4(displaced_world, 1.0)).xyz;
	NORMAL = normalize((inv_model * vec4(world_n_geom, 0.0)).xyz);

	v_world_pos = displaced_world;
	v_world_normal = world_n_geom;
	v_wave_steep = pow(1.0 - clamp(world_n_geom.y, 0.0, 1.0), 1.15);
	v_foam = fft_foam;
}

void fragment() {
	if (discard_half > 0.0 && abs(v_local_pos.x) < discard_half && abs(v_local_pos.z) < discard_half) {
		discard;
	}
	vec3 nm = normalize(v_world_normal);
	vec2 xz = v_world_pos.xz;
	float wt = wave_time;
	float dist_to_cam = length(CAMERA_POSITION_WORLD - v_world_pos);

	// Capillary chop — analytic sines near camera (FFT slopes carry the rest).
	float near_w = 1.0 - smoothstep(35.0, 280.0, dist_to_cam);
	vec3 world_n = nm;
	if (near_w > 0.01 && chop_strength > 0.001) {
		vec2 g_eta = ocean_chop_gradient(xz + wt * vec2(0.22, -0.18), wt);
		float ripple_gain = chop_strength * 1.85 * near_w;
		vec3 lateral = vec3(-g_eta.x, 0.0, -g_eta.y) * ripple_gain;
		world_n = normalize(nm + lateral - nm * dot(nm, lateral));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 sun_n = normalize(sun_direction);
	float sun_up = clamp(sun_n.y, 0.0, 1.0);

	// Fresnel from macro normal so sky follows swell, not chop noise.
	float ndv_macro = clamp(dot(nm, view_dir), 0.001, 1.0);
	float fres = ocean_fresnel(nm, view_dir);
	v_fresnel = fres;

	float facing = pow(ndv_macro, 0.7);
	float steep = clamp(v_wave_steep, 0.0, 1.0);
	float height_rel = clamp((v_world_pos.y - water_level) * 0.55, -0.5, 1.0);

	// Crest teal must NOT follow absolute height — FFT wind seas make long
	// parallel ridges, and height→color paints straight green stripes (max waves).
	// Prefer local steepness + noise breakup; keep height as a weak hint only.
	float crest_noise = ocean_vnoise(xz * 0.55 + wt * 0.12);
	float crest = ocean_crest(v_world_pos, nm, water_level, wt, wave_intensity);
	vec3 body = ocean_body(
		deep_albedo, shallow_albedo, nm, view_dir, v_world_pos,
		water_level, near_color_lift, crest, crest_noise
	);
	vec3 col = ocean_sky_reflection(
		body, sky_horizon_color, sky_top_color, nm, view_dir,
		fres, fresnel_sky_mix
	);

	// Soft glitter (refs), not silver sheets. Clamp for tonemap.
	float glint = ocean_glint(world_n, view_dir, sun_n, dist_to_cam);
	col += sun_color * glint * glint_strength * sun_up * (0.2 + fres * 0.5);

	float toward_sun = clamp(dot(-view_dir, sun_n), 0.0, 1.0);
	float sss = pow(toward_sun, 4.0) * crest * (0.4 + 0.6 * (1.0 - smoothstep(0.15, 0.8, sun_up)));
	col += vec3(0.04, 0.22, 0.20) * sun_color * sss * 0.55 * clamp(wave_intensity, 0.25, 1.6);

	// White slosh — FFT Jacobian foam sampled PER PIXEL from the two large
	// cascades only. Per-vertex sampling showed triangle blotches, and the
	// small cascades (16 m / 4 m) contribute per-texel speckle, not foam.
	float jac_foam = textureLod(displacement_map, vec3(xz / length_scales.x, 0.0), 0.0).w * 0.75
			+ textureLod(displacement_map, vec3(xz / length_scales.y, 1.0), 0.0).w * 0.45;
	jac_foam = clamp(jac_foam, 0.0, 1.0);

	mat2 ROT_A = mat2(vec2(0.809174, -0.587582), vec2(0.587582, 0.809174));
	mat2 ROT_B = mat2(vec2(0.422618, -0.906308), vec2(0.906308, 0.422618));
	vec2 xz_a = ROT_A * xz;
	vec2 xz_b = ROT_B * xz;
	// Soft edge erosion — one FBM is enough (was two).
	float erode = ocean_fbm(xz_a * 1.2 + xz_b * 0.35 + wt * vec2(0.4, -0.32));
	float foam_shape = smoothstep(0.15 + erode * 0.45, 0.85, jac_foam + steep * 0.3);

	float foam = foam_shape * foam_strength;
	foam = clamp(foam, 0.0, 1.0);
	foam *= 1.0 - smoothstep(300.0, 1600.0, dist_to_cam) * 0.55;

	float foam_mask = foam;
	vec3 foam_col = mix(vec3(0.75, 0.84, 0.88), vec3(0.97, 0.98, 1.0), foam_mask);
	col = mix(col, foam_col, foam_mask * 0.9);
	col = mix(col, debug_tint.rgb, debug_tint.a);

	ALBEDO = col;
	ROUGHNESS = mix(0.58, 0.95, foam_mask);
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

// Local lights only. Directional sun is in fragment — lighting it here again
// painted soft plastic white across every swell face.
void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float ndl = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ndl * 0.10;
		vec3 h = normalize(VIEW + LIGHT);
		float ndh = max(dot(NORMAL, h), 0.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(ndh, 80.0) * v_fresnel * 0.35;
	}
}
