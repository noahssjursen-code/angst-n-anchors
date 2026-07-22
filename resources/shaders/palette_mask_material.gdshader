shader_type spatial;
render_mode cull_disabled;

uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
// A mask is linear data, not an sRGB colour texture. Keeping it out of
// `source_color` preserves exact channel weights at palette boundaries.
uniform sampler2D palette_mask : filter_linear_mipmap_anisotropic;
uniform vec4 primary_color : source_color = vec4(0.08, 0.18, 0.27, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.82, 0.81, 0.72, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(base_texture, UV);
	vec3 mask = texture(palette_mask, UV).rgb;
	float luminance = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float detail = clamp(0.58 + luminance * 0.84, 0.34, 1.25);
	vec3 primary = primary_color.rgb * detail;
	vec3 secondary = secondary_color.rgb * detail;
	vec3 albedo = mix(base.rgb, primary, mask.r);
	albedo = mix(albedo, secondary, mask.g);
	ALBEDO = albedo * tint.rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
}
