uniform sampler2DArray displacement_map : filter_linear, repeat_enable;
uniform sampler2DArray slope_map : filter_linear, repeat_enable;
uniform vec4 length_scales = vec4(256.0, 64.0, 16.0, 4.0);
uniform vec4 cascade_fade_end = vec4(5500.0, 1536.0, 384.0, 96.0);

uniform float wave_time = 0.0;
uniform float water_level = -1.5;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;
uniform float geomorph_strength : hint_range(0.0, 1.0) = 1.0;

uniform vec3 shallow_albedo : source_color = vec3(0.02, 0.08, 0.12);
uniform vec3 deep_albedo : source_color = vec3(0.004, 0.02, 0.04);
uniform vec3 sky_top_color : source_color = vec3(0.07, 0.28, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.34, 0.54, 0.78);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.8);
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.52;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;
uniform float glint_strength : hint_range(0.0, 4.0) = 0.35;
uniform float foam_strength : hint_range(0.0, 2.0) = 0.55;
uniform float foam_steep_start : hint_range(0.0, 1.0) = 0.22;
uniform float foam_steep_end : hint_range(0.0, 1.0) = 0.65;

uniform sampler2D land_shelter_map : filter_linear, repeat_disable;
uniform vec2 land_shelter_origin = vec2(0.0);
uniform float land_shelter_size = 0.0;
uniform vec4 debug_tint : source_color = vec4(0.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_wave_steep;
varying float v_fresnel;

#include "res://resources/shaders/ocean_surface_common.gdshaderinc"

void vertex() {
	VERTEX.xz = mix(VERTEX.xz, UV2, geomorph_strength);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float distance_to_camera = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	vec3 displacement = vec3(0.0);
	vec2 slopes = vec2(0.0);

	for (int i = 0; i < OCEAN_CASCADE_COUNT; i++) {
		float weight = 1.0 - smoothstep(
			cascade_fade_end[i] * 0.75,
			cascade_fade_end[i],
			distance_to_camera
		);
		vec2 uv = wp.xz / length_scales[i];
		displacement += textureLod(displacement_map, vec3(uv, float(i)), 0.0).xyz * weight;
		slopes += textureLod(slope_map, vec3(uv, float(i)), 0.0).xy * weight;
	}

	float shelter = 1.0;
	if (land_shelter_size > 0.0) {
		vec2 shelter_uv = (wp.xz - land_shelter_origin) / land_shelter_size;
		if (shelter_uv.x >= 0.0 && shelter_uv.x <= 1.0
				&& shelter_uv.y >= 0.0 && shelter_uv.y <= 1.0) {
			shelter = textureLod(land_shelter_map, shelter_uv, 0.0).r;
		}
	}

	float amplitude = wave_intensity * wave_energy_multiplier * 0.42 * shelter;
	displacement *= amplitude;
	slopes *= amplitude;
	vec3 displaced_world = vec3(
		wp.x + displacement.x,
		water_level + displacement.y,
		wp.z + displacement.z
	);
	vec3 world_normal = normalize(vec3(-slopes.x, 1.0, -slopes.y));

	mat4 inverse_model = inverse(MODEL_MATRIX);
	VERTEX = (inverse_model * vec4(displaced_world, 1.0)).xyz;
	NORMAL = normalize((inverse_model * vec4(world_normal, 0.0)).xyz);
	v_world_pos = displaced_world;
	v_world_normal = world_normal;
	v_wave_steep = pow(1.0 - clamp(world_normal.y, 0.0, 1.0), 1.15);
}

void fragment() {
	vec3 normal_world = normalize(v_world_normal);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 sun_dir = normalize(sun_direction);
	float distance_to_camera = length(CAMERA_POSITION_WORLD - v_world_pos);
	float fresnel = ocean_fresnel(normal_world, view_dir);
	float crest_noise = ocean_vnoise(v_world_pos.xz * 0.55 + wave_time * 0.12);
	float crest = ocean_crest(v_world_pos, normal_world, water_level, wave_time, wave_intensity);
	vec3 body = ocean_body(
		deep_albedo, shallow_albedo, normal_world, view_dir, v_world_pos,
		water_level, near_color_lift, crest, crest_noise
	);
	vec3 color = ocean_sky_reflection(
		body, sky_horizon_color, sky_top_color, normal_world, view_dir,
		fresnel, fresnel_sky_mix
	);

	float glint = ocean_glint(normal_world, view_dir, sun_dir, distance_to_camera);
	color += sun_color * glint * glint_strength * clamp(sun_dir.y, 0.0, 1.0)
			* (0.2 + fresnel * 0.5);

#if OCEAN_FOAM
	float jacobian = textureLod(
		displacement_map,
		vec3(v_world_pos.xz / length_scales.x, 0.0),
		0.0
	).w * 0.75;
	jacobian += textureLod(
		displacement_map,
		vec3(v_world_pos.xz / length_scales.y, 1.0),
		0.0
	).w * 0.45;
	float erosion = ocean_fbm(
		v_world_pos.xz * vec2(0.91, 0.63)
		+ wave_time * vec2(0.4, -0.32)
	);
	float foam = smoothstep(
		0.15 + erosion * 0.45,
		0.85,
		clamp(jacobian, 0.0, 1.0) + v_wave_steep * 0.3
	) * foam_strength;
	foam = clamp(foam, 0.0, 1.0);
	vec3 foam_color = mix(vec3(0.75, 0.84, 0.88), vec3(0.97, 0.98, 1.0), foam);
	color = mix(color, foam_color, foam * 0.9);
	ROUGHNESS = mix(0.68, 0.95, foam);
#else
	ROUGHNESS = 0.76;
#endif

	color = mix(color, debug_tint.rgb, debug_tint.a);
	v_fresnel = fresnel;
	ALBEDO = color;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float ndl = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ndl * 0.08;
		vec3 half_vector = normalize(VIEW + LIGHT);
		float ndh = max(dot(NORMAL, half_vector), 0.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(ndh, 72.0) * v_fresnel * 0.25;
	}
}
