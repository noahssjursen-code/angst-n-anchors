shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float outline_threshold : hint_range(0.0, 1.0, 0.001) = 0.40;
uniform float outline_strength  : hint_range(0.0, 1.0)        = 0.04;
uniform vec3  outline_color     : source_color                 = vec3(0.04, 0.04, 0.05);

uniform float grain_strength : hint_range(0.0, 0.12) = 0.022;
uniform float grain_size     : hint_range(0.5, 4.0)  = 1.5;
uniform float vignette_strength : hint_range(0.0, 0.3) = 0.07;
uniform float weather_desaturation : hint_range(0.0, 0.3) = 0.0;
uniform float rain_cool_shift : hint_range(0.0, 0.1) = 0.0;
uniform float shadow_coolness : hint_range(0.0, 0.12) = 0.035;
uniform float highlight_warmth : hint_range(0.0, 0.12) = 0.025;
uniform float weather_contrast : hint_range(0.0, 0.08) = 0.018;

// Camera rays are supplied by WorldRenderer. Classifying each ray against the
// local wave tangent plane gives a correctly tilted waterline while the camera
// crosses the surface, without a second viewport or imported overlay texture.
uniform vec3 ray_top_left = vec3(-0.5, 0.5, -1.0);
uniform vec3 ray_top_right = vec3(0.5, 0.5, -1.0);
uniform vec3 ray_bottom_left = vec3(-0.5, -0.5, -1.0);
uniform vec3 ray_bottom_right = vec3(0.5, -0.5, -1.0);
uniform vec3 water_surface_normal = vec3(0.0, 1.0, 0.0);
// Positive above water, negative below the local wave surface.
uniform float camera_water_signed_distance = 10.0;
uniform float underwater_transition_m : hint_range(0.05, 1.5) = 0.45;
uniform float underwater_strength : hint_range(0.0, 1.0) = 1.0;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float rand(vec2 uv) {
	return fract(sin(dot(uv, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;

	vec3 ray_top = mix(ray_top_left, ray_top_right, uv.x);
	vec3 ray_bottom = mix(ray_bottom_left, ray_bottom_right, uv.x);
	vec3 ray_direction = normalize(mix(ray_top, ray_bottom, uv.y));
	float ray_plane_dot = dot(ray_direction, normalize(water_surface_normal));
	float ray_into_water = 1.0 - smoothstep(-0.035, 0.035, ray_plane_dot);

	float above_fade = 1.0 - smoothstep(
		0.0, underwater_transition_m, camera_water_signed_distance
	);
	float below_fade = smoothstep(
		0.0, underwater_transition_m, -camera_water_signed_distance
	);
	float underwater_mask = mix(ray_into_water * above_fade, 1.0, below_fade);
	underwater_mask *= underwater_strength;

	float submersion_m = max(-camera_water_signed_distance, 0.0);
	vec4 color = texture(screen_texture, uv);
	if (underwater_mask > 0.001) {
		// Stable screen-space blur. Distance fog is handled by Environment on
		// fully submerged frames; this softens the partial waterline too.
		float blur_radius = mix(2.0, 5.0, clamp(submersion_m / 2.5, 0.0, 1.0));
		vec2 blur_px = px * blur_radius;
		vec4 blurred = color * 2.0;
		blurred += texture(screen_texture, clamp(uv + vec2( blur_px.x, 0.0), vec2(0.001), vec2(0.999)));
		blurred += texture(screen_texture, clamp(uv + vec2(-blur_px.x, 0.0), vec2(0.001), vec2(0.999)));
		blurred += texture(screen_texture, clamp(uv + vec2(0.0,  blur_px.y), vec2(0.001), vec2(0.999)));
		blurred += texture(screen_texture, clamp(uv + vec2(0.0, -blur_px.y), vec2(0.001), vec2(0.999)));
		blurred *= 1.0 / 6.0;
		color = mix(color, blurred, underwater_mask * 0.86);
	}

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
	float outline = step(outline_threshold, edge) * outline_strength
		* (1.0 - underwater_mask * 0.88);
	color.rgb     = mix(color.rgb, outline_color, outline);

	// Animated film grain (24fps discrete steps so it doesn't shimmer)
	vec2 grain_uv = floor(uv / (px * grain_size)) * (px * grain_size);
	float grain   = rand(grain_uv + vec2(floor(TIME * 24.0) * 0.01, 0.0));
	color.rgb    += (grain - 0.5) * grain_strength * (1.0 - underwater_mask);

	// Weather grade is intentionally restrained: preserve paint identity while
	// making storms cooler and less saturated.
	float grey = luma(color.rgb);
	color.rgb = mix(color.rgb, vec3(grey), weather_desaturation);
	color.rgb *= vec3(1.0 - rain_cool_shift, 1.0, 1.0 + rain_cool_shift);

	// Maritime grade: cool low values give the water and shadowed steel depth;
	// a trace of warmth in highlights keeps lamps, crane paint and white hulls
	// distinct. This is arithmetic-only and adds no screen texture samples.
	float shadow_weight = 1.0 - smoothstep(0.08, 0.52, grey);
	float highlight_weight = smoothstep(0.42, 0.92, grey);
	color.rgb *= mix(vec3(1.0), vec3(0.92, 0.98, 1.08), shadow_weight * shadow_coolness);
	color.rgb *= mix(vec3(1.0), vec3(1.06, 1.015, 0.94), highlight_weight * highlight_warmth);
	color.rgb = (color.rgb - vec3(0.5)) * (1.0 + weather_contrast) + vec3(0.5);
	color.rgb = max(color.rgb, vec3(0.0));

	// Underwater grade: dark green absorption. Real low-range visibility is
	// supplied by depth-aware Environment fog while fully submerged.
	float depth_haze = 1.0 - exp(-submersion_m * 0.24);
	vec3 absorbed = color.rgb * vec3(0.40, 0.64, 0.43);
	absorbed = mix(absorbed, vec3(0.012, 0.070, 0.040), 0.28 + depth_haze * 0.48);
	color.rgb = mix(color.rgb, absorbed, underwater_mask);

	// Bright, refracted meniscus exactly where the local tangent plane crosses
	// the view. This is visible only while the camera is near the waterline.
	float near_surface = 1.0 - smoothstep(
		underwater_transition_m * 0.35,
		underwater_transition_m,
		abs(camera_water_signed_distance)
	);
	float waterline = (1.0 - smoothstep(0.0, 0.018, abs(ray_plane_dot))) * near_surface;
	color.rgb = mix(color.rgb, vec3(0.30, 0.58, 0.42), waterline * 0.26);

	vec2 centred = uv * 2.0 - 1.0;
	float vignette = smoothstep(0.32, 1.22, dot(centred, centred));
	color.rgb *= 1.0 - vignette * (vignette_strength + underwater_mask * 0.055);

	COLOR = color;
}
