// Shared by bark and foliage. Both representations use complementary cutouts,
// keeping depth writes rather than adding a transparent sorting dependency.
instance uniform float forest_lod_enabled : instance_index(0) = 0.0;
varying float forest_lod_mix;
float forest_distance_mix(vec3 tree_origin, vec3 camera_origin) {
	return smoothstep(140.0, 200.0, length(tree_origin.xz - camera_origin.xz));
}
bool forest_hidden_pixel(bool distant, float blend, vec2 pixel) {
	float threshold = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	return distant ? threshold >= blend : threshold < blend;
}
