shader_type spatial;
render_mode cull_disabled;
uniform sampler2D adult_atlas : source_color, filter_linear_mipmap;
uniform sampler2D juvenile_atlas : source_color, filter_linear_mipmap;
instance uniform float maturity : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	ALBEDO = mix(texture(juvenile_atlas, UV).rgb, texture(adult_atlas, UV).rgb, maturity);
	ROUGHNESS = 0.78;
}
