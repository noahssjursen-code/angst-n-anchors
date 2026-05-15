shader_type sky;

// --- Time ---
uniform float sky_time = 0.0;

// --- Sky colour layers (driven by WeatherLighting) ---
uniform vec3 sky_top_color     : source_color = vec3(0.26, 0.46, 0.70);
uniform vec3 sky_horizon_color : source_color = vec3(0.48, 0.68, 0.90);
uniform vec3 sky_ground_color  : source_color = vec3(0.16, 0.14, 0.12);

// --- Sun disk (world-space direction TO the sun, passed from GDScript each frame) ---
uniform vec3  sun_direction : source_color = vec3(0.0, 1.0, 0.0);
uniform float sun_size      : hint_range(0.0, 0.2) = 0.003;
uniform float sun_bloom     : hint_range(0.0, 5.0) = 2.5;
uniform vec3  sun_color     : source_color          = vec3(1.0, 0.94, 0.82);

// --- Moon disk (world-space direction TO the moon, passed from GDScript each frame) ---
uniform vec3  moon_direction : source_color = vec3(0.0, -1.0, 0.0);
uniform float moon_size      : hint_range(0.0, 0.1) = 0.004;
uniform vec3  moon_color     : source_color          = vec3(0.82, 0.86, 0.96);

// --- Cloud layer ---
uniform float cloud_coverage  : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_sharpness : hint_range(0.5, 8.0) = 1.8;
uniform float cloud_speed     : hint_range(0.0, 0.5) = 0.04;
uniform vec3  cloud_light     : source_color          = vec3(1.00, 0.98, 0.96);
uniform vec3  cloud_dark      : source_color          = vec3(0.44, 0.46, 0.52);
uniform float cloud_altitude  : hint_range(0.0, 1.0) = 0.28;
uniform float cloud_thickness : hint_range(0.0, 1.0) = 0.22;

// --- Storm darkening ---
uniform float storm_intensity : hint_range(0.0, 1.0) = 0.0;


// ---------------------------------------------------------------------------
// Hash / noise utilities
// ---------------------------------------------------------------------------

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i),                hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// Fractional Brownian Motion — 4 octaves for performance.
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p  = p * 2.1 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}


// ---------------------------------------------------------------------------
// Sky gradient
// ---------------------------------------------------------------------------

vec3 sky_gradient(vec3 dir) {
	float up = clamp(dir.y, 0.0, 1.0);

	// Ground
	if (dir.y < -0.05) {
		float ground_t = clamp((-dir.y - 0.05) / 0.3, 0.0, 1.0);
		return mix(sky_horizon_color, sky_ground_color, ground_t);
	}

	vec3 col = mix(sky_horizon_color, sky_top_color, up * up);
	// Storm desaturates / darkens sky
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), storm_intensity * 0.6);
	col *= 1.0 - storm_intensity * 0.35;
	return col;
}


// ---------------------------------------------------------------------------
// Cloud density at a given sky direction
// ---------------------------------------------------------------------------

float cloud_density(vec3 dir) {
	// Only upper hemisphere — hard cutoff well below horizon.
	if (dir.y < 0.02) return 0.0;

	// Fade near horizon (prevents hard ring edge); clouds visible almost to zenith.
	float horizon_fade = smoothstep(0.03, 0.14, dir.y);
	float zenith_fade  = 1.0 - smoothstep(0.88, 0.98, dir.y);
	float sky_fade     = horizon_fade * zenith_fade;

	// Hemispherical projection with moderate bias. Lower bias (0.18) vs old 0.25 lets
	// clouds spread more naturally across mid-elevations.
	float h  = dir.y + 0.18;
	vec2  uv = dir.xz / h;

	uv += vec2(sky_time * cloud_speed, sky_time * cloud_speed * 0.45);

	// Large-scale formation (2.2) + medium detail (4.5) + fine wisp (9.0).
	// Larger base scale creates more convincing cloud formations instead of
	// a uniform speckled haze.
	float shape = fbm(uv * 2.2) * 0.60
	            + fbm(uv * 4.5) * 0.28
	            + fbm(uv * 9.0) * 0.12;

	// Give coverage more weight so clouds appear at moderate values.
	float threshold = 1.0 - clamp(cloud_coverage * 1.2, 0.0, 1.0);
	float raw = clamp((shape - threshold) / (1.0 - threshold + 0.001), 0.0, 1.0);

	// Lower sharpness = softer rounded edges; higher multiplier = more opaque fill.
	return clamp(pow(raw, cloud_sharpness) * 2.8, 0.0, 1.0) * sky_fade;
}


// ---------------------------------------------------------------------------
// Sun — bright disk with wide atmospheric haze so it's findable in blue sky
// ---------------------------------------------------------------------------

vec3 sun_contribution(vec3 dir) {
	float cos_angle = dot(dir, sun_direction);
	// Hard bright core
	float disk   = step(1.0 - sun_size, cos_angle) * 6.0;
	// Tight inner corona (bright ring just outside the disk)
	float corona = pow(max(cos_angle, 0.0), 512.0) * sun_bloom * 3.5;
	// Wide atmospheric glow — makes the sun locatable against blue sky (~25° spread)
	float glow   = pow(max(cos_angle, 0.0), 8.0) * sun_bloom * 0.22;
	// Fade out as sun drops below the horizon so glow doesn't bleed at night
	float elev_fade = smoothstep(-0.10, 0.05, sun_direction.y);
	return sun_color * (disk + corona + glow) * elev_fade;
}


// ---------------------------------------------------------------------------
// Moon — cool silver disk, no wide haze (moon doesn't scatter atmosphere)
// ---------------------------------------------------------------------------

vec3 moon_contribution(vec3 dir) {
	float cos_angle = dot(dir, moon_direction);
	// Disk — visually present but not bright enough to bathe the scene in light.
	float disk   = step(1.0 - moon_size, cos_angle) * 0.65;
	// Very faint soft corona
	float corona = pow(max(cos_angle, 0.0), 256.0) * 0.18;
	// Fade out when moon is below the horizon
	float elev_fade = smoothstep(-0.08, 0.04, moon_direction.y);
	return moon_color * (disk + corona) * elev_fade;
}


// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void sky() {
	vec3 dir = EYEDIR;

	vec3 col = sky_gradient(dir);

	if (dir.y > -0.02) {
		col += sun_contribution(dir) * (1.0 - cloud_coverage * 0.85);
		col += moon_contribution(dir) * (1.0 - cloud_coverage * 0.75);
	}

	// Clouds — shaded with sun elevation AND cloud density (denser core = darker).
	float clouds = cloud_density(dir);
	if (clouds > 0.001) {
		float sun_up = max(sun_direction.y, 0.0);

		// Edge-brightening: cloud edges are lit more than dense interiors.
		// This gives the illusion of volume without ray-marching.
		float interior = smoothstep(0.3, 1.0, clouds) * 0.55;
		vec3 cloud_col = mix(cloud_light, cloud_dark, interior);

		// Night/dusk: darken clouds proportionally to sun height.
		cloud_col = mix(cloud_col * 0.25, cloud_col, smoothstep(0.0, 0.35, sun_up));

		// Storm: desaturate to dark greenish-grey.
		cloud_col = mix(cloud_col, vec3(0.24, 0.27, 0.30), storm_intensity * 0.65);

		col = mix(col, cloud_col, clouds * 0.95);
	}

	COLOR = col;
}
