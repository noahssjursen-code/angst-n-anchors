shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Mainland surface. Detail comes from runtime-baked maps (TerrainSurfaceMaps),
// blended by height, slope, and coastal weight (COLOR.a).

uniform sampler2D rock_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D lichen_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_map : filter_linear_mipmap, repeat_enable;

uniform float rock_scale : hint_range(0.002, 0.08) = 0.018;
uniform float moss_scale : hint_range(0.002, 0.08) = 0.012;
uniform float grass_scale : hint_range(0.004, 0.12) = 0.035;
uniform float lichen_scale : hint_range(0.004, 0.1) = 0.022;
uniform float macro_scale : hint_range(0.0002, 0.01) = 0.0016;

varying vec3 world_pos;
varying vec3 world_normal;
varying float coast_w;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	coast_w = clamp(COLOR.a, 0.0, 1.0);
}

vec3 _triplanar(sampler2D tex, vec3 pos, vec3 n, float scale) {
	vec3 blending = abs(n);
	blending = pow(max(blending, vec3(0.0001)), vec3(4.0));
	blending /= (blending.x + blending.y + blending.z);
	vec3 x_axis = texture(tex, pos.zy * scale).rgb;
	vec3 y_axis = texture(tex, pos.xz * scale).rgb;
	vec3 z_axis = texture(tex, pos.xy * scale).rgb;
	return x_axis * blending.x + y_axis * blending.y + z_axis * blending.z;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float h = world_pos.y;

	vec3 rock_s = _triplanar(rock_map, world_pos, n, rock_scale);
	vec3 moss_s = _triplanar(moss_map, world_pos, n, moss_scale);
	vec3 grass_s = _triplanar(grass_map, world_pos, n, grass_scale);
	vec3 lichen_s = _triplanar(lichen_map, world_pos, n, lichen_scale);
	vec3 macro_s = texture(macro_map, world_pos.xz * macro_scale).rgb;

	// Norwegian coastal palette: blue-grey gneiss, dark wet stone, muted heath.
	// Values stay deliberately low; daylight and fog provide the highlights.
	vec3 wet_rock = vec3(0.105, 0.125, 0.135);
	vec3 dry_rock = vec3(0.285, 0.295, 0.285);
	vec3 cliff_rock = vec3(0.235, 0.250, 0.255);
	vec3 rock = mix(wet_rock, dry_rock, rock_s.r);
	rock = mix(rock, cliff_rock, slope * 0.68);
	rock *= mix(0.76, 1.10, rock_s.b);
	rock = mix(rock, rock * 0.58, rock_s.g * 0.50); // dark fissures
	float strata = sin(h * 0.052 + world_pos.x * 0.0022 - world_pos.z * 0.0014 + macro_s.b * 5.0);
	rock *= mix(0.88, 1.07, strata * 0.5 + 0.5);

	vec3 lichen = mix(vec3(0.30, 0.29, 0.16), vec3(0.43, 0.39, 0.20), lichen_s.b);
	lichen = mix(lichen, rock, 1.0 - smoothstep(0.35, 0.75, lichen_s.r));

	vec3 moss = mix(vec3(0.045, 0.095, 0.040), vec3(0.095, 0.165, 0.060), moss_s.r);
	moss = mix(moss, moss * 0.62, moss_s.b * 0.55);
	moss += (moss_s.g - 0.5) * vec3(0.025, 0.035, 0.012);

	vec3 heath = mix(vec3(0.055, 0.105, 0.040), vec3(0.12, 0.17, 0.065), grass_s.g);
	heath = mix(heath, vec3(0.15, 0.13, 0.065), grass_s.b * 0.22);
	heath *= mix(0.80, 1.06, grass_s.r);

	vec3 snow = vec3(0.70, 0.74, 0.77);
	snow = mix(snow, vec3(0.54, 0.59, 0.63), macro_s.b * 0.28);

	// --- Weights -------------------------------------------------------------
	float wet_edge = coast_w * (1.0 - smoothstep(1.0, 4.5, h));
	float svaberg = coast_w * smoothstep(0.50, 0.94, n.y);
	float cliff = smoothstep(0.16, 0.52, slope);
	float lowland = 1.0 - smoothstep(260.0, 620.0, h);
	float soil = smoothstep(0.76, 0.96, n.y) * (1.0 - coast_w * 0.72);
	float moisture = smoothstep(0.28, 0.72, macro_s.g);
	float moss_w = soil * lowland * mix(0.12, 0.72, moisture) * mix(0.25, 0.85, moss_s.r);
	float heath_w = soil * lowland * mix(0.16, 0.68, grass_s.g);
	// Vegetation remains patchy; bare bedrock is the dominant surface.
	moss_w *= 1.0 - cliff * 0.92;
	heath_w *= (1.0 - cliff) * smoothstep(0.24, 0.57, macro_s.r);
	float snow_w = smoothstep(850.0, 1250.0, h) * smoothstep(0.72, 0.94, n.y)
		* smoothstep(0.42, 0.68, macro_s.b);
	float lichen_w = coast_w * smoothstep(0.2, 0.7, lichen_s.r)
		* (1.0 - cliff * 0.4) * smoothstep(0.5, 4.0, h);

	// Macro breakup so large faces are not a single paint bucket.
	float macro_rock = mix(0.85, 1.15, macro_s.r);
	float macro_green = mix(0.8, 1.2, macro_s.g);
	moss_w *= macro_green;
	heath_w *= macro_green;
	svaberg *= macro_rock;
	cliff *= macro_rock;

	vec3 albedo = rock;
	albedo = mix(albedo, lichen, clamp(lichen_w * 0.48, 0.0, 0.56));
	albedo = mix(albedo, mix(rock, dry_rock, 0.22), clamp(svaberg * 0.42, 0.0, 0.56));
	albedo = mix(albedo, wet_rock * mix(0.82, 1.05, rock_s.b), clamp(wet_edge, 0.0, 1.0));
	albedo = mix(albedo, cliff_rock * mix(0.78, 1.08, rock_s.r), clamp(cliff * 0.72, 0.0, 0.82));
	albedo = mix(albedo, moss, clamp(moss_w, 0.0, 0.56));
	albedo = mix(albedo, heath, clamp(heath_w, 0.0, 0.52));
	albedo = mix(albedo, snow, clamp(snow_w, 0.0, 1.0));

	// Fine contrast so mid-range mountains are not chalk-white.
	albedo *= mix(0.82, 1.04, rock_s.b * 0.45 + macro_s.b * 0.55);
	albedo = clamp(albedo, vec3(0.015), vec3(0.78));

	ALBEDO = albedo;
	ROUGHNESS = mix(0.96, 0.78, heath_w * 0.22 + snow_w * 0.5);
	// Cheap slope darkening for readable ridges without a normal map.
	ALBEDO *= mix(1.0, 0.70, cliff * 0.62);
}
