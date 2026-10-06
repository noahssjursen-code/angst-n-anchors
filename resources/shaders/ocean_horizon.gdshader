shader_type spatial;
render_mode diffuse_burley, cull_disabled;


// Horizon ring — cascade 0 only. Same water shading language as the inner mesh
// so the seam doesn't turn into a plastic mirror.

uniform sampler2DArray displacement_map : filter_linear, repeat_enable;
uniform sampler2DArray slope_map        : filter_linear, repeat_enable;
uniform float length_scale_0 = 256.0;

uniform float wave_time = 0.0;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;

uniform float wave_fade_near : hint_range(200.0, 5000.0) = 4125.0;
uniform float wave_fade_far  : hint_range(1000.0, 12000.0) = 5500.0;
uniform float discard_half = 298.0;
uniform float geomorph_strength : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D land_shelter_map : filter_linear, repeat_disable;
uniform vec2 land_shelter_origin = vec2(0.0);
uniform float land_shelter_size = 0.0;

uniform float water_level = -1.5;

uniform vec3 shallow_albedo : source_color = vec3(0.02, 0.08, 0.12);
uniform vec3 deep_albedo    : source_color = vec3(0.004, 0.02, 0.04);
uniform vec3 sky_top_color     : source_color = vec3(0.07, 0.28, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.34, 0.54, 0.78);
uniform vec3 sun_direction     = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color         : source_color = vec3(1.0, 0.9, 0.8);

uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.52;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;
uniform float glint_strength : hint_range(0.0, 4.0) = 0.18;
uniform vec4 debug_tint : source_color = vec4(0.0);

varying vec3 v_world_pos;
varying vec3 v_local_pos;
varying vec3 v_world_normal;
varying float v_fresnel;

void vertex() {
	VERTEX.xz = mix(VERTEX.xz, UV2, geomorph_strength);
	v_local_pos = VERTEX;
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wp = w4.xyz;

	float dist_from_cam = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float wave_fade = 1.0 - smoothstep(wave_fade_near, wave_fade_far, dist_from_cam);
	float shelter = 1.0;
	if (land_shelter_size > 0.0) {
		vec2 shelter_uv = (wp.xz - land_shelter_origin) / land_shelter_size;
		if (shelter_uv.x >= 0.0 && shelter_uv.x <= 1.0
				&& shelter_uv.y >= 0.0 && shelter_uv.y <= 1.0) {
			shelter = textureLod(land_shelter_map, shelter_uv, 0.0).r;
		}
	}

	float amp_scale = wave_intensity * wave_energy_multiplier * 0.42 * wave_fade * shelter;

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
	if (discard_half > 0.0 && abs(v_local_pos.x) < discard_half && abs(v_local_pos.z) < discard_half) {
		discard;
	}
	vec3 nm = normalize(v_world_normal);
	if (!FRONT_FACING) {
		nm = -nm;
	}
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 sun_n = normalize(sun_direction);
	float sun_up = clamp(sun_n.y, 0.0, 1.0);

	float ndv = clamp(dot(nm, view_dir), 0.001, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	v_fresnel = fres;

	float facing = pow(ndv, 0.7);
	float height_rel = clamp((v_world_pos.y - water_level) * 0.45, -0.4, 0.8);
	// Steepness from normal; avoid height-only stripes on long swell ridges.
	float steep = clamp(1.0 - nm.y, 0.0, 1.0);
	float crest_noise = fract(sin(dot(v_world_pos.xz * 0.07, vec2(12.9898, 78.233))) * 43758.5453);
	float crest = smoothstep(0.2, 0.7, steep * 0.85 + max(height_rel, 0.0) * 0.2)
			* mix(0.45, 1.0, crest_noise);
	crest *= mix(1.0, 0.5, clamp((wave_intensity - 0.8) * 0.4, 0.0, 1.0));

	vec3 col = mix(deep_albedo, shallow_albedo, 0.08 + crest * 0.10);
	col = mix(col, debug_tint.rgb, debug_tint.a);

	ALBEDO = col;
	ROUGHNESS = 0.22;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
