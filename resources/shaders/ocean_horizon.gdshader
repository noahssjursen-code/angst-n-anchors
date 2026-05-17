shader_type spatial;
render_mode specular_schlick_ggx;

uniform float water_level = -1.5;
uniform float wave_time = 0.0;

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
	
	// Apply the same high-frequency noise/grain as the local ocean shader
	vec2 xz = v_world_pos.xz;
	float wt = wave_time;
	mat2 ROT_A = mat2(vec2(0.809174, -0.587582), vec2(0.587582, 0.809174));
	mat2 ROT_B = mat2(vec2(0.422618, -0.906308), vec2(0.906308, 0.422618));
	vec2 xz_a = ROT_A * xz;
	vec2 xz_b = ROT_B * xz;
	
	vec2 jitter_c = xz_a * 21.974 + xz_b.yy * vec2(-9.834, 7.917) + wt * vec2(8.93, -6.71);
	vec2 jitter_d = xz_b.yx * vec2(17.401, -14.917) + wt * vec2(-7.61, 8.734);
	float sp = wf_vnoise(jitter_c) * 0.68 + wf_vnoise(jitter_d * 6.417 + vec2(83.917, -41.734)) * 0.32;
	
	col *= mix(0.92, 1.08, sp);
	float r_micro = clamp(roughness + 0.18 * (sp - 0.5), 0.12, 0.93);
	
	ALBEDO = col;
	ROUGHNESS = r_micro;
	METALLIC = metallic;
	SPECULAR = specular;
}
