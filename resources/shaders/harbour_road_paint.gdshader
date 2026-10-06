shader_type spatial;
render_mode blend_mix, depth_draw_never, shadows_disabled, cull_disabled;
uniform float paint_width = 0.16;
varying float paint_fraction;

// Paint is depth-tested, but biased 3cm toward the eye to avoid coplanar flicker.
// Filtering is in screen pixels, so narrow markings don't break into dotted lines.
void vertex() {
	vec4 center_view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float pixel_world = max(0.0001, -center_view.z * 2.0 / (PROJECTION_MATRIX[0][0] * VIEWPORT_SIZE.x));
	float raster_width = max(paint_width, pixel_world * 2.0);
	paint_fraction = paint_width / raster_width;
	VERTEX.x *= raster_width / paint_width;
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.z += 0.03;
	POSITION = PROJECTION_MATRIX * view;
}
void fragment() {
	float aa = max(fwidth(UV.x), 0.001);
	float coverage = clamp((paint_fraction * 0.5 - abs(UV.x-0.5)) / aa + 0.5, 0.0, 1.0);
	ALBEDO = vec3(0.67, 0.66, 0.59);
	ROUGHNESS = 0.96;
	SPECULAR = 0.0;
	ALPHA = coverage;
}
