shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

varying vec3 world_position;
varying vec4 line_colour;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	line_colour = COLOR;
}

void fragment() {
	float distance_m = length(world_position.xz - CAMERA_POSITION_WORLD.xz);
	float radius_m = clamp(abs(CAMERA_POSITION_WORLD.y - world_position.y) * 2.0, 36.0, 300.0);
	ALBEDO = line_colour.rgb;
	ALPHA = line_colour.a * (1.0 - smoothstep(radius_m / 3.0, radius_m, distance_m));
}
