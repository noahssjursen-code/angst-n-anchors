shader_type spatial;
render_mode diffuse_burley;
#include "forest_lod.gdshaderinc"
uniform sampler2D bark_colour : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
void vertex() {
	forest_lod_mix = forest_distance_mix(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	if (forest_lod_enabled > 0.5 && forest_lod_mix >= 1.0) VERTEX = vec3(0.0);
}
void fragment() {
	if (forest_lod_enabled > 0.5 && forest_hidden_pixel(false, forest_lod_mix, FRAGCOORD.xy)) discard;
	ALBEDO = texture(bark_colour, UV).rgb;
	NORMAL_MAP = texture(bark_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.94;
}
