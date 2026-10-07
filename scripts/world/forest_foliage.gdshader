shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "forest_lod.gdshaderinc"

uniform sampler2D foliage_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float canopy_height = 7.0;
uniform float tree_height = 11.0;
uniform bool distant = false;
varying vec3 canopy_normal_world;
varying vec3 tree_position;
varying float forest_outer_fade;
uniform float forest_world_canopy = 0.0;

void vertex() {
	forest_outer_fade = smoothstep(1950.0,2180.0,length(MODEL_MATRIX[3].xz-MAIN_CAM_INV_VIEW_MATRIX[3].xz));
	forest_lod_mix = forest_distance_mix(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	if (distant) {
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 delta = vec3(INV_VIEW_MATRIX[3].x - MODEL_MATRIX[3].x, 0.0, INV_VIEW_MATRIX[3].z - MODEL_MATRIX[3].z);
		vec3 toward_camera = length(delta) > 0.001 ? normalize(delta) : vec3(0.0, 0.0, 1.0);
		vec3 right = normalize(cross(up, toward_camera));
		mat4 facing = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0), vec4(up * length(MODEL_MATRIX[1].xyz), 0.0), vec4(toward_camera * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * facing;
		// Shade the silhouette as a rounded crown, independent of the flat
		// supporting plane. Sun and ambient still come from the live scene.
		vec3 crown = right * (UV.x - 0.5) * 1.4 + up * (0.65 - UV.y) * 0.45 + toward_camera * 0.4;
		canopy_normal_world = normalize(crown);
	} else {
	// Light the foliage volume, not the arbitrary rectangle supporting a spray.
	// Retain an upward component so back-facing cards cannot turn into black
	// rectangles or abruptly flip to lime green when the camera crosses them.
	vec3 crown = vec3(VERTEX.x * 0.6, 0.25 + max(VERTEX.y - canopy_height, 0.0) * 0.22, VERTEX.z * 0.6);
	canopy_normal_world = normalize(MODEL_NORMAL_MATRIX * normalize(crown));
	}
	tree_position = VERTEX;
	if (forest_lod_enabled > 0.5 && ((distant && forest_lod_mix <= 0.0) || (!distant && forest_lod_mix >= 1.0))) VERTEX = vec3(0.0);
}

void fragment() {
	if (forest_lod_enabled > 0.5 && forest_hidden_pixel(distant, forest_lod_mix, FRAGCOORD.xy)) discard;
	if (forest_lod_enabled > 0.5 && forest_hidden_pixel(false, forest_outer_fade, FRAGCOORD.xy)) discard;
	if (forest_world_canopy > 0.5 && forest_hidden_pixel(true, forest_outer_fade, FRAGCOORD.xy)) discard;
	vec4 foliage = texture(foliage_texture, UV);
	// The branch bake is diffuse colour. Crown depth supplies the occlusion
	// absent from overlapping cutout cards, without adding emissive fill.
	float height_fraction = clamp(tree_position.y / tree_height, 0.0, 1.0);
	float crown_edge = clamp(length(tree_position.xz) / 2.8, 0.0, 1.0);
	float occlusion = distant ? 1.0 : mix(0.38, 1.0, max(crown_edge, height_fraction * height_fraction));
	ALBEDO = foliage.rgb * COLOR.rgb * vec3(0.58, 0.64, 0.62) * occlusion;
	ALPHA = foliage.a;
	ALPHA_SCISSOR_THRESHOLD = 0.28;
	NORMAL = normalize((VIEW_MATRIX * vec4(canopy_normal_world, 0.0)).xyz);
	ROUGHNESS = 0.95;
	AO = occlusion;
}
