shader_type spatial;
render_mode specular_schlick_ggx;

// ── Wave field (FFT cascade 0 only) ───────────────────────────────────────
// The horizon mesh is too coarse (~210 m verts at 20 km / 96 subdivs) to
// sample the smaller cascades without aliasing. Cascade 0 has the longest
// wavelength (~256 m) and carries the storm swell that the user actually
// reads at distance, so we sample it alone.
uniform sampler2DArray displacement_map : filter_linear, repeat_enable;
uniform sampler2DArray slope_map        : filter_linear, repeat_enable;
uniform float length_scale_0 = 256.0;

uniform float wave_time = 0.0;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;

// Distance from camera at which horizon waves start fading to flat. The
// inner ocean mesh extends to `discard_half` so amplitude should still be
// near-full at that boundary — the seam is invisible because the inner mesh
// is already discarding the horizon mesh's pixels there.
uniform float wave_fade_near : hint_range(200.0, 5000.0) = 900.0;
uniform float wave_fade_far  : hint_range(1000.0, 12000.0) = 5500.0;

// Half-extent of the inner ocean mesh — we discard fragments inside that
// square so the inner mesh is the only thing visible in the foreground.
// Set by world_renderer.gd to match INNER_OCEAN_SIZE.
uniform float discard_half = 298.0;

uniform float water_level = -1.5;

uniform vec3 shallow_albedo : source_color = vec3(0.028, 0.074, 0.118);
uniform vec3 deep_albedo    : source_color = vec3(0.006, 0.018, 0.036);
uniform vec3 sky_top_color     : source_color = vec3(0.07, 0.28, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.34, 0.54, 0.78);
uniform float roughness     : hint_range(0.0, 1.0) = 0.20;
uniform float metallic      : hint_range(0.0, 1.0) = 0.0;
uniform float specular      : hint_range(0.0, 1.0) = 0.40;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.1;
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.48;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;

varying vec3 v_world_pos;
varying vec3 v_local_pos;
varying vec3 v_world_normal;
varying float v_wave_fade;

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

void vertex() {
	v_local_pos = VERTEX;
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wp = w4.xyz;

	// Distance-based amplitude fade. At the inner-mesh boundary the
	// amplitude matches what the inner shader uses (* 0.42), then quietly
	// flattens past `wave_fade_far` so the literal horizon line is calm.
	float dist_from_cam = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float wave_fade = 1.0 - smoothstep(wave_fade_near, wave_fade_far, dist_from_cam);
	v_wave_fade = wave_fade;

	float amp_scale = wave_intensity * wave_energy_multiplier * 0.42 * wave_fade;

	vec2 uv = wp.xz / length_scale_0;
	vec3 disp  = textureLod(displacement_map, vec3(uv, 0.0), 0.0).xyz;
	vec2 slope = textureLod(slope_map,        vec3(uv, 0.0), 0.0).xy;

	wp.y = water_level + disp.y * amp_scale;
	wp.x += disp.x * amp_scale;
	wp.z += disp.z * amp_scale;

	v_world_pos = wp;
	v_world_normal = normalize(vec3(-slope.x * amp_scale, 1.0, -slope.y * amp_scale));

	mat4 inv_model = inverse(MODEL_MATRIX);
	VERTEX = (inv_model * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((inv_model * vec4(v_world_normal, 0.0)).xyz);
}

void fragment() {
	// Cut a square hole exactly where the inner ocean mesh sits so it's the
	// only thing visible in the foreground. discard_half is set by
	// world_renderer to (INNER_OCEAN_SIZE * 0.5 - 15.0) — 15 m overlap prevents
	// microscopic gap seams at the boundary.
	if (abs(v_local_pos.x) < discard_half && abs(v_local_pos.z) < discard_half) {
		discard;
	}

	vec3 nm = normalize(v_world_normal);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);

	float flat_ndv = clamp(dot(nm, view_dir), 0.001, 1.0);
	float look_graze = 1.0 - pow(flat_ndv, 1.18);

	vec3 body = mix(deep_albedo, shallow_albedo, look_graze * (0.22 + near_color_lift * 0.25));

	// Dynamic sky reflection based on PBR reflection vector and sky color gradients
	vec3 ref_dir = reflect(-view_dir, nm);
	float sky_mix = clamp(ref_dir.y, 0.0, 1.0);
	vec3 sky_ref_color = mix(sky_horizon_color, sky_top_color, pow(sky_mix, 0.85));

	// Enhanced Fresnel equation for lifelike, mirror-like horizon reflection
	float fres = pow(look_graze, fresnel_power);
	vec3 col = mix(body, sky_ref_color, fres * fresnel_sky_mix);

	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
