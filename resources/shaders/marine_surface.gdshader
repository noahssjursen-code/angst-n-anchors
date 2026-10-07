shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Metre-space projection in the asset's rest frame. These rows are installed
// once, so moving ships, doors and control pivots carry their finish with them.
instance uniform vec4 finish_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 finish_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 finish_z = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D colour_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 repeat_metres = vec2(1.0);
uniform float source_mean = 0.5;
uniform float colour_contrast = 0.5;
uniform float source_colour = 0.0;
uniform float roughness_low = 0.3;
uniform float roughness_high = 0.8;
uniform float relief = 0.5;
uniform float metal_amount = 0.0;
uniform bool use_metal_map = false;
uniform bool use_authored_colour = false;
uniform sampler2D authored_colour : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D corrosion_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float corrosion = 0.0;
uniform float corrosion_metres = 2.4;
uniform float corrosion_base_band = 0.0;
varying vec3 finish_position;
varying vec3 finish_normal;
varying mat3 finish_to_view;

void vertex() {
	mat3 frame = transpose(mat3(finish_x.xyz, finish_y.xyz, finish_z.xyz));
	finish_position = frame * VERTEX + vec3(finish_x.w, finish_y.w, finish_z.w);
	finish_normal = normalize(transpose(inverse(frame)) * NORMAL);
	finish_to_view = MODELVIEW_NORMAL_MATRIX * transpose(frame);
}

vec4 project_texture(sampler2D map, vec2 x, vec2 y, vec2 z, vec3 weights) {
	return texture(map, x) * weights.x + texture(map, y) * weights.y + texture(map, z) * weights.z;
}

void fragment() {
	vec3 n = normalize(finish_normal) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 signs = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), n));
	vec3 weights = pow(abs(n), vec3(8.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec2 x = vec2(-signs.x * finish_position.z, finish_position.y) / repeat_metres;
	vec2 y = vec2(finish_position.x, -signs.y * finish_position.z) / repeat_metres;
	vec2 z = vec2(signs.z * finish_position.x, finish_position.y) / repeat_metres;
	vec3 pigment = project_texture(colour_map, x, y, z, weights).rgb;
	float luminance = dot(pigment, vec3(0.2126, 0.7152, 0.0722));
	float variation = mix(1.0, clamp(luminance / source_mean, 0.2, 1.8), colour_contrast);
	// Paint retains its selectable colour. Bare/weathered source finishes can
	// retain the source colour instead (timber, corrosion, unpainted concrete).
	ALBEDO = mix(base_color.rgb * variation, pigment * base_color.rgb, source_colour);
	// Retain authored markings and edge wear where a model already has an atlas.
	// The measured surface grain/roughness still comes from the shared source.
	if (use_authored_colour) ALBEDO *= texture(authored_colour, UV).rgb;
	float r = project_texture(roughness_map, x, y, z, weights).r;
	ROUGHNESS = mix(roughness_low, roughness_high, r);
	METALLIC = metal_amount;
	if (use_metal_map) METALLIC *= project_texture(metal_map, x, y, z, weights).r;
	if (corrosion > 0.0) {
		// Use the orange iron-oxide regions of the source plate, retaining its
		// actual streak pattern. Intact paint and zinc remain their selected colour.
		vec3 stain = project_texture(corrosion_map, x * repeat_metres / corrosion_metres,
			y * repeat_metres / corrosion_metres, z * repeat_metres / corrosion_metres, weights).rgb;
		float oxide = smoothstep(0.018, 0.11, stain.r - stain.b);
		float band = corrosion_base_band > 0.0 ? 1.0 - smoothstep(0.05, corrosion_base_band, finish_position.y) : 1.0;
		float wear = oxide * corrosion * band;
		ALBEDO = mix(ALBEDO, stain, wear);
		ROUGHNESS = mix(ROUGHNESS, 0.92, wear);
		METALLIC *= 1.0 - wear;
	}
	vec2 nx = texture(normal_map, x).rg * 2.0 - 1.0;
	vec2 ny = texture(normal_map, y).rg * 2.0 - 1.0;
	vec2 nz = texture(normal_map, z).rg * 2.0 - 1.0;
	vec3 detail = vec3(0.0, nx.y, -signs.x * nx.x) * weights.x
		+ vec3(ny.x, 0.0, -signs.y * ny.y) * weights.y
		+ vec3(signs.z * nz.x, nz.y, 0.0) * weights.z;
	NORMAL = normalize(finish_to_view * normalize(n + detail * relief));
}
