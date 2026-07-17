shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Coarsest terrain ring. Vertex colour already contains the coast/inland
// palette, so distant land needs only one low-frequency canopy lookup instead
// of the near shader's twelve triplanar texture reads plus detail maps.

uniform sampler2D forest_map : filter_linear_mipmap, repeat_disable;
uniform float forest_world_half_extent_m = 20000.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 terrain_tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	terrain_tint = COLOR;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float coast_w = clamp(terrain_tint.a, 0.0, 1.0);
	vec3 albedo = terrain_tint.rgb;

	vec2 forest_uv = world_pos.xz / max(forest_world_half_extent_m * 2.0, 1.0) + vec2(0.5);
	float forest_w = texture(forest_map, clamp(forest_uv, vec2(0.0), vec2(1.0))).r;
	forest_w *= (1.0 - slope * 0.85) * (1.0 - coast_w * 0.7);
	albedo = mix(albedo, vec3(0.022, 0.048, 0.026), clamp(forest_w * 0.82, 0.0, 0.78));

	float snow_w = smoothstep(850.0, 1250.0, world_pos.y) * smoothstep(0.72, 0.94, n.y);
	albedo = mix(albedo, vec3(0.62, 0.66, 0.69), snow_w);
	albedo *= mix(1.0, 0.72, slope * 0.75);

	ALBEDO = clamp(albedo, vec3(0.015), vec3(0.72));
	ROUGHNESS = 0.94;
}
