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
uniform float cloud_sharpness : hint_range(0.5, 8.0) = 3.5;
uniform float cloud_speed     : hint_range(0.0, 0.5) = 0.04;
uniform vec3  cloud_light     : source_color          = vec3(0.95, 0.93, 0.90);
uniform vec3  cloud_dark      : source_color          = vec3(0.38, 0.38, 0.42);
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
	// Only upper hemisphere.
	if (dir.y < 0.02) return 0.0;

	// Soft fade near horizon (prevents hard edge) and near zenith (thinner cover overhead).
	float horizon_fade = smoothstep(0.02, 0.18, dir.y);
	float zenith_fade  = 1.0 - smoothstep(0.72, 0.96, dir.y);
	float sky_fade     = horizon_fade * zenith_fade;

	// Hemispherical projection: add a softening bias so UVs don't explode near the horizon.
	// Without this, dividing by a tiny dir.y stretches the pattern into a ring.
	float h  = dir.y + 0.25;
	vec2  uv = dir.xz / h;

	// Scroll with time
	uv += vec2(sky_time * cloud_speed, sky_time * cloud_speed * 0.45);

	float shape = fbm(uv * 1.8) * 0.6 + fbm(uv * 3.6) * 0.3 + fbm(uv * 7.2) * 0.1;

	// Coverage threshold
	float threshold = 1.0 - cloud_coverage;
	float raw = (shape - threshold) / (1.0 - threshold + 0.001);
	return clamp(pow(raw, cloud_sharpness) * 1.8, 0.0, 1.0) * sky_fade;
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
	// Disk — dimmer than the sun
	float disk   = step(1.0 - moon_size, cos_angle) * 1.4;
	// Tight soft edge only
	float corona = pow(max(cos_angle, 0.0), 256.0) * 0.5;
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

	// Clouds — lit by sun elevation
	float clouds = cloud_density(dir);
	if (clouds > 0.001) {
		float sun_up   = max(sun_direction.y, 0.0);
		vec3 cloud_col = mix(cloud_dark, cloud_light, sun_up * (1.0 - storm_intensity * 0.7));
		cloud_col      = mix(cloud_col, vec3(0.28, 0.30, 0.34), storm_intensity * 0.5);
		col = mix(col, cloud_col, clouds);
	}

	COLOR = col;
}
