// Shared by bark and foliage. Both representations use complementary cutouts,
// keeping depth writes rather than adding a transparent sorting dependency.
instance uniform float forest_lod_enabled : instance_index(0) = 0.0;
varying float forest_lod_mix;
float forest_distance_mix(vec3 tree_origin, vec3 camera_origin) {
	float progress = smoothstep(140.0, 200.0, length(tree_origin.xz - camera_origin.xz));
	// Distribute the transition through the stand, keeping each crown intact.
	// Screen-pixel crossfades made both tree shapes look like stippled cutouts.
	vec2 cell = floor(tree_origin.xz * 4.0);
	float tree_threshold = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
	return step(mix(0.01, 0.99, tree_threshold), progress);
}
// Keep the argument distinct from the foliage material's `distant` uniform.
// A shadowed uniform name miscompiled on the D3D12 renderer: the outer fade
// acted as the opposite representation and removed the entire middle tier.
bool forest_hidden_pixel(bool far_representation, float blend, vec2 pixel) {
	float threshold = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	return far_representation ? threshold >= blend : threshold < blend;
}
