shader_type spatial;
render_mode specular_schlick_ggx;

uniform float water_level = -1.5;

uniform vec3 shallow_albedo : source_color = vec3(0.028, 0.074, 0.118);
uniform vec3 deep_albedo    : source_color = vec3(0.006, 0.018, 0.036);
uniform vec3 horizon_tint   : source_color = vec3(0.068, 0.118, 0.172);
uniform float roughness     : hint_range(0.0, 1.0) = 0.20;
uniform float metallic      : hint_range(0.0, 1.0) = 0.0;
uniform float specular      : hint_range(0.0, 1.0) = 0.40;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.1;
uniform float fresnel_sky_mix : hint_range(0.0, 1.0) = 0.48;
uniform float near_color_lift : hint_range(0.0, 1.0) = 0.14;

varying vec3 v_world_pos;
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	// Snap strictly to the water level (flat plane)
	w4.y = water_level;
	v_world_pos = w4.xyz;
	VERTEX = (inverse(MODEL_MATRIX) * w4).xyz;
}

void fragment() {
	// Cut a square hole exactly where the high-res 600x600 ocean mesh sits.
	// We use 298.0 to give a tiny 2m overlap to prevent any microscopic gap seams.
	if (abs(v_local_pos.x) < 298.0 && abs(v_local_pos.z) < 298.0) {
		discard;
	}

	vec3 nm = vec3(0.0, 1.0, 0.0);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	float flat_ndv = clamp(dot(nm, view_dir), 0.001, 1.0);
	float look_graze = 1.0 - pow(flat_ndv, 1.18);
	
	vec3 body = mix(deep_albedo, shallow_albedo, look_graze * (0.22 + near_color_lift * 0.25));
	
	float fres = pow(look_graze, fresnel_power * 1.2);
	vec3 col = mix(body, horizon_tint, fres * fresnel_sky_mix);
	
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
