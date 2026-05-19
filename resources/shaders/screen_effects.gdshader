shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float outline_threshold : hint_range(0.0, 1.0, 0.001) = 0.40;
uniform float outline_strength  : hint_range(0.0, 1.0)        = 0.04;
uniform vec3  outline_color     : source_color                 = vec3(0.04, 0.04, 0.05);

uniform float grain_strength : hint_range(0.0, 0.12) = 0.022;
uniform float grain_size     : hint_range(0.5, 4.0)  = 1.5;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float rand(vec2 uv) {
	return fract(sin(dot(uv, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;

	vec4 color = texture(screen_texture, uv);

	// 4-tap cross luma gradient instead of an 8-tap Sobel. At 1080p this is
	// the difference between 18M and 10M screen-texture samples per frame
	// (every pixel, every frame). Diagonal edges fade slightly faster but
	// the outline_strength is 0.04 — the visible effect is a thin subtle
	// outline, and the cross stencil delivers it for ~45% fewer samples.
	float s_left  = luma(texture(screen_texture, uv + vec2(-px.x, 0.0 )).rgb);
	float s_right = luma(texture(screen_texture, uv + vec2( px.x, 0.0 )).rgb);
	float s_up    = luma(texture(screen_texture, uv + vec2( 0.0,  px.y)).rgb);
	float s_down  = luma(texture(screen_texture, uv + vec2( 0.0, -px.y)).rgb);

	float gx = s_right - s_left;
	float gy = s_up    - s_down;
	float edge    = length(vec2(gx, gy));
	float outline = step(outline_threshold, edge) * outline_strength;
	color.rgb     = mix(color.rgb, outline_color, outline);

	// Animated film grain (24fps discrete steps so it doesn't shimmer)
	vec2 grain_uv = floor(uv / (px * grain_size)) * (px * grain_size);
	float grain   = rand(grain_uv + vec2(floor(TIME * 24.0) * 0.01, 0.0));
	color.rgb    += (grain - 0.5) * grain_strength;

	COLOR = color;
}
