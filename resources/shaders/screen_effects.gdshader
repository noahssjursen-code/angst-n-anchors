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

	// 3x3 luma Sobel edge detection — works on colour boundaries without depth
	float s00 = luma(texture(screen_texture, uv + vec2(-px.x,  px.y)).rgb);
	float s10 = luma(texture(screen_texture, uv + vec2( 0.0,   px.y)).rgb);
	float s20 = luma(texture(screen_texture, uv + vec2( px.x,  px.y)).rgb);
	float s01 = luma(texture(screen_texture, uv + vec2(-px.x,  0.0 )).rgb);
	float s21 = luma(texture(screen_texture, uv + vec2( px.x,  0.0 )).rgb);
	float s02 = luma(texture(screen_texture, uv + vec2(-px.x, -px.y)).rgb);
	float s12 = luma(texture(screen_texture, uv + vec2( 0.0,  -px.y)).rgb);
	float s22 = luma(texture(screen_texture, uv + vec2( px.x, -px.y)).rgb);

	float gx = -s00 + s20 - 2.0*s01 + 2.0*s21 - s02 + s22;
	float gy = -s00 - 2.0*s10 - s20 + s02 + 2.0*s12 + s22;
	float edge    = length(vec2(gx, gy));
	float outline = step(outline_threshold, edge) * outline_strength;
	color.rgb     = mix(color.rgb, outline_color, outline);

	// Animated film grain (24fps discrete steps so it doesn't shimmer)
	vec2 grain_uv = floor(uv / (px * grain_size)) * (px * grain_size);
	float grain   = rand(grain_uv + vec2(floor(TIME * 24.0) * 0.01, 0.0));
	color.rgb    += (grain - 0.5) * grain_strength;

	COLOR = color;
}
