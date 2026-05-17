shader_type sky;

// --- Time ---
uniform float sky_time = 0.0;

// --- Sky colour layers (driven by WeatherLighting) ---
uniform vec3 sky_top_color     : source_color = vec3(0.26, 0.46, 0.70);
uniform vec3 sky_horizon_color : source_color = vec3(0.48, 0.68, 0.90);
uniform vec3 sky_ground_color  : source_color = vec3(0.16, 0.14, 0.12);
// Extra deep zenith + thin haze strip (multiplies palette from script).
uniform vec3 sky_zenith_deep   : source_color = vec3(0.02, 0.08, 0.22);
uniform float sky_zenith_mix   : hint_range(0.0, 1.0) = 0.38;

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

// Night sky — driven from WorldRenderer from WeatherLighting daytime factor (sun height).
uniform float star_visibility : hint_range(0.0, 1.0) = 0.0;


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
// Sky gradient (+ cheap aerial perspective — no bland white dome)
// ---------------------------------------------------------------------------

vec3 sky_gradient(vec3 dir) {
	vec3 dn = normalize(dir);
	float up = dn.y;

	// Ground hemisphere
	if (up < -0.0) {
		float ground_t = clamp(-up / 0.05, 0.0, 1.0);
		return mix(sky_horizon_color, vec3(0.0), ground_t);
	}

	float day = smoothstep(-0.08, 0.22, sun_direction.y);

	// Vault curve: slower rise than up² → richer blue occupies more of the sky.
	float vault = pow(max(up, 0.001), 0.52);
	vec3 col = mix(sky_horizon_color, sky_top_color, vault);

	// Deep sapphire band overhead (breaks flat "printer paper" mid-dome).
	float zenith_arc = smoothstep(0.35, 0.92, up);
	col = mix(col, sky_zenith_deep, zenith_arc * sky_zenith_mix * day);

	// Thin bright haze hugging the geometric horizon — separate from washed mid-sky.
	float haze_w = smoothstep(-0.02, 0.045, dn.y) - smoothstep(0.065, 0.18, dn.y);
	haze_w = max(haze_w, 0.0);
	vec3 haze_lift = sky_horizon_color * vec3(1.06, 1.03, 0.98);
	col = mix(col, haze_lift, haze_w * 0.22 * day);

	// Sun-side warm airlight (Mie-ish scatter; strongest when sun is up).
	vec3 sund = normalize(sun_direction + vec3(1e-6));
	float sun_dot = max(dot(dn, sund), 0.0);
	float mie = pow(sun_dot, 6.0) * 0.38 + pow(sun_dot, 48.0) * 1.05;
	vec3 mie_tint = vec3(1.0, 0.72, 0.38);
	col += mie_tint * mie * day * (0.42 + storm_intensity * 0.12);

	// Slight asymmetric shift (ocean haze cooler away from sun).
	float az_cool = 0.06 * day * smoothstep(-0.12, 0.45, sund.y);
	col.b += (1.0 - sun_dot) * az_cool;

	// Storm desaturates / darkens sky
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), storm_intensity * 0.6);
	col *= 1.0 - storm_intensity * 0.35;
	return col;
}


// ---------------------------------------------------------------------------
// Cloud density and volume
// ---------------------------------------------------------------------------

float get_cloud_shape(vec3 dir) {
	if (dir.y < 0.0) return 0.0;
	// Project onto a flat sky plane. A lower addition stretches clouds towards the horizon.
	float h = dir.y + 0.15; 
	vec2 uv = dir.xz / h;
	
	// Drift
	uv += vec2(sky_time * cloud_speed, sky_time * cloud_speed * 0.45);
	
	// Layered noise for puffy shapes
	float shape = fbm(uv * 1.8) * 0.55
	            + fbm(uv * 3.8) * 0.30
	            + fbm(uv * 7.5) * 0.15;
	            
	// Carve out deep structural valleys so high-coverage never turns into a flat monotone blanket
	float valleys = fbm(uv * 2.5 + vec2(12.3, 4.5));
	shape -= pow(valleys, 2.5) * 0.5;
	            
	return shape;
}

float cloud_density(vec3 dir, float shape) {
	if (dir.y < 0.0) return 0.0;
	
	float horizon_fade = smoothstep(0.02, 0.12, dir.y);
	
	// Storms increase overall cloud coverage and thickness
	float coverage = clamp(cloud_coverage * 1.3 + storm_intensity * 0.2, 0.0, 1.0);
	float threshold = 1.0 - coverage;
	
	// Sharpness controls how fluffy vs hard-edged the clouds are.
	// As coverage increases, we keep a wider gradient so the contours remain visible!
	float edge_softness = max(0.15, (1.0 - coverage) * 0.5) / cloud_sharpness;
	float density = smoothstep(threshold, threshold + edge_softness, shape);
	return clamp(density * horizon_fade, 0.0, 1.0);
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
// Cube face from world ray — returns (plane.xy in [-1,1], face_index 0..5 in z channel).
// ---------------------------------------------------------------------------

vec3 cube_face_plane(vec3 d) {
	vec3 ad = abs(d);

	vec2 fc;
	float fk;
	if (ad.x >= ad.y && ad.x >= ad.z) {
		float inv = 1.0 / max(ad.x, 1e-5);
		if (d.x > 0.0) {
			fc = vec2(-d.z, d.y) * inv;
			fk = 0.0;
		} else {
			fc = vec2(d.z, d.y) * inv;
			fk = 1.0;
		}
	} else if (ad.y >= ad.x && ad.y >= ad.z) {
		float inv = 1.0 / max(ad.y, 1e-5);
		if (d.y > 0.0) {
			fc = vec2(d.x, -d.z) * inv;
			fk = 2.0;
		} else {
			fc = vec2(d.x, d.z) * inv;
			fk = 3.0;
		}
	} else {
		float inv = 1.0 / max(ad.z, 1e-5);
		if (d.z > 0.0) {
			fc = vec2(d.x, d.y) * inv;
			fk = 4.0;
		} else {
			fc = vec2(-d.x, d.y) * inv;
			fk = 5.0;
		}
	}
	return vec3(fc, fk);
}


// Dense cube lattice + jittered star centres + razor core (reads as pinpoints at infinity).
float star_layer_dots(vec3 d, float face_res, vec2 salt) {
	vec3 cfp = cube_face_plane(normalize(d));
	vec2 uv = clamp(cfp.xy * 0.5 + vec2(0.5), vec2(0.002), vec2(0.998));
	float fk = cfp.z;

	vec2 gv = uv * face_res;
	vec2 cid = floor(gv);
	vec2 lw = gv - cid - vec2(0.5);

	vec2 hid = cid + vec2(fk * 113.957 + salt.x * 91.71, fk * 17.913 + salt.y * 27.419);

	vec2 jst = vec2(hash(hid + vec2(salt.y, salt.x)),
	              hash(hid.yx + vec2(salt.x * 41.93, salt.y))) - vec2(0.5);
	jst *= 0.435;

	float hv = hash(hid * vec2(7.419, 2.087) + hid.yx + salt * 71.913);
	float hv2 = hash(hid.yx + vec2(91.71 + salt.x, hid.x + salt.y));

	vec2 centred = lw - jst;
	float r = length(centred);

	float core = smoothstep(0.115, 0.014, r);
	float glint = smoothstep(0.15, 0.032, r) * 0.032;

	float tw = sin(sky_time * 5.9 + hv2 * 13.917) * 0.045 + 0.955;

	float rare = smoothstep(0.9925, 0.99985, hv);
	float faint = smoothstep(0.835, 0.9925, hv);

	return (rare * core + rare * glint + faint * core * 0.11) * tw;
}


// ---------------------------------------------------------------------------
// Stars — twin decorrelated cubic fields so no single “poster frame” dominates.
// ---------------------------------------------------------------------------

vec3 stars_contribution(vec3 dir, float clouds, float storms) {
	if (star_visibility < 1e-4 || dir.y < 0.03) {
		return vec3(0.0);
	}

	vec3 d = normalize(dir);

	vec3 dp = normalize(vec3(d.z, d.x, d.y));

	const float FACE_RES = 120.0;
	float a = star_layer_dots(d, FACE_RES, vec2(0.07, -3.418));
	float b = star_layer_dots(dp, FACE_RES * 0.953, vec2(19.51, -7.982));
	float samp = clamp(a + b * 0.58, 0.0, 2.05);

	float tint_mix = hash(d.xz * 317.917 + vec2(d.y * 113.419, samp * 41.271));
	vec3 tint = mix(vec3(0.93, 0.95, 1.025), vec3(1.0, 0.86, 0.72), smoothstep(0.48, 0.93, tint_mix));

	float elev_k = smoothstep(0.03, 0.26, d.y);
	float veil = mix(star_visibility, star_visibility * 0.42, storms * storms);
	vec3 stars = tint * samp * veil * elev_k * 0.82;
	stars *= mix(1.0, 0.06, clamp(clouds * 1.15, 0.0, 1.0));
	return stars * (1.0 - storms * 0.35);
}


// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void sky() {
	vec3 dir = EYEDIR;

	vec3 col = sky_gradient(dir);

	if (dir.y > -0.02) {
		col += stars_contribution(dir, cloud_coverage, storm_intensity);
		col += sun_contribution(dir) * (1.0 - cloud_coverage * 0.85);
		col += moon_contribution(dir) * (1.0 - cloud_coverage * 0.75);
	}

	// Clouds — Pseudo-volumetric shading
	float base_shape = get_cloud_shape(dir);
	float clouds = cloud_density(dir, base_shape);
	
	if (clouds > 0.001) {
		// 1. Self-Shadowing (Sample density slightly towards the sun)
		vec3 offset_dir = normalize(dir + sun_direction * 0.15);
		float sun_shape = get_cloud_shape(offset_dir);
		float sun_density_val = cloud_density(offset_dir, sun_shape);
		
		// If the cloud is thicker towards the sun, this pixel is in shadow.
		// Also, we mix in the raw inverted `base_shape` so that even at 100% coverage,
		// the deep valleys of the noise remain permanently darker than the peaks!
		float structural_shadow = 1.0 - clamp(base_shape * 1.2, 0.0, 1.0);
		float cast_shadow = clamp((sun_density_val - clouds) * 2.5, 0.0, 1.0);
		float shadow = clamp(cast_shadow + structural_shadow * 0.8, 0.0, 1.0);
		
		// 2. Base Color (Thicker/shadowed = darker bellies)
		// Dynamic color scaling:
		// Clear = bright (but dimmer) tops, Overcast = very moody heavy grey, Storm = nearly black thunder-grey
		vec3 base_lit = mix(vec3(0.65, 0.68, 0.72), vec3(0.12, 0.14, 0.16), cloud_coverage);
		vec3 base_dark = mix(vec3(0.35, 0.38, 0.42), vec3(0.05, 0.06, 0.07), cloud_coverage);
		
		// In storms, turn thunder gray and heavily bruise the darks
		base_lit = mix(base_lit, vec3(0.04, 0.05, 0.06), storm_intensity);
		base_dark = mix(base_dark, vec3(0.01, 0.01, 0.015), storm_intensity);
		
		vec3 ambient = mix(base_lit, base_dark, shadow);
		
		// 3. Sunlight Illumination (Light hits the unshadowed parts)
		float direct_light = 1.0 - shadow;
		vec3 cloud_col = ambient + sun_color * direct_light * 0.25 * (1.0 - storm_intensity * 0.85);
		
		// 4. Silver Linings (Forward scattering through thin cloud edges)
		float sun_dot = max(dot(dir, sun_direction), 0.0);
		float silver_lining = pow(sun_dot, 16.0) * smoothstep(0.0, 0.4, clouds) * smoothstep(1.0, 0.5, clouds);
		cloud_col += sun_color * silver_lining * 1.5 * (1.0 - storm_intensity * 0.8);
		
		// 5. Day/Night Cycle Dimming
		float day_cloud_lit = smoothstep(-0.05, 0.32, sun_direction.y);
		cloud_col *= mix(0.045, 1.0, day_cloud_lit);
		
		float moon_up = max(moon_direction.y, 0.0);
		cloud_col *= mix(1.0, 1.0 + moon_up * 0.26, 1.0 - day_cloud_lit);

		col = mix(col, cloud_col, clouds * 0.95);
	}

	COLOR = col;
}
