shader_type sky;
render_mode use_half_res_pass;
uniform sampler3D cloud_volume : filter_linear_mipmap, repeat_enable;

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
uniform vec3  sun_direction = vec3(0.0, 1.0, 0.0);
// Angular radius in radians (about half a degree across).
uniform float sun_size      : hint_range(0.001, 0.02) = 0.00465;
uniform float sun_bloom     : hint_range(0.0, 5.0) = 1.8;
uniform vec3  sun_color     : source_color          = vec3(1.0, 0.94, 0.82);

// --- Moon disk (world-space direction TO the moon, passed from GDScript each frame) ---
uniform vec3  moon_direction = vec3(0.0, -1.0, 0.0);
uniform float moon_size      : hint_range(0.001, 0.02) = 0.0045;
uniform vec3  moon_color     : source_color          = vec3(0.82, 0.86, 0.96);

// --- Cloud layer ---
uniform float cloud_coverage  : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_speed     : hint_range(0.0, 0.5) = 0.04;
uniform vec3  cloud_light     : source_color          = vec3(1.00, 0.98, 0.96);
uniform vec3  cloud_dark      : source_color          = vec3(0.44, 0.46, 0.52);
uniform float cloud_altitude  : hint_range(0.0, 1.0) = 0.28;
uniform float cloud_thickness : hint_range(0.0, 1.0) = 0.22;

// --- Storm darkening ---
uniform float storm_intensity : hint_range(0.0, 1.0) = 0.0;

// Night sky — driven from WorldRenderer from WeatherLighting daytime factor (sun height).
uniform float star_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float daylight_factor : hint_range(0.0, 1.0) = 1.0;


// ---------------------------------------------------------------------------
// Hash / noise utilities
// ---------------------------------------------------------------------------

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
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

	float day = daylight_factor;

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

// Kilometre-space shallow cloud volume, integrated at half resolution.
// The immutable 64^3 field is baked offline; no runtime noise generation.
float volume_density(vec3 p, float footprint) {
    float base = mix(0.8, 1.8, cloud_altitude);
    float thickness = mix(0.4, 1.1, cloud_thickness);
    float h = (p.y - base) / thickness;
    if (h <= 0.0 || h >= 1.0) return 0.0;
    vec3 drift = vec3(sky_time * cloud_speed * .025, 0.0, sky_time * cloud_speed * .011);
    float broad = textureLod(cloud_volume, p * .28 + drift, max(log2(footprint*.28*64.0),0.0)).r;
    float detail = textureLod(cloud_volume, p * .95 + drift * 2.0 + vec3(.37,.19,.53), max(log2(footprint*.95*64.0),0.0)).r;
    float coverage = clamp(cloud_coverage + storm_intensity * .15, 0.0, 1.0);
    float threshold = mix(.77, .20, coverage);
    float rounded_top = h * h * .12;
    float shape = broad - detail * .20 - rounded_top;
    float envelope = smoothstep(0.0,.12,h) * (1.0-smoothstep(.7,1.0,h));
    return smoothstep(threshold, threshold+.11, shape) * envelope;
}

vec4 cloud_layer(vec3 dir, vec2 screen_uv) {
    if (dir.y <= .008 || cloud_coverage <= .001) return vec4(0.0);
    vec3 origin = vec3(POSITION.x, min(POSITION.y, 500.0), POSITION.z) * .001;
    float base = mix(.8,1.8,cloud_altitude);
    float top = base + mix(.4,1.1,cloud_thickness);
    float start = max((base-origin.y)/dir.y,0.0);
    float end = min((top-origin.y)/dir.y, 28.0);
    if (end <= start) return vec4(0.0);
    float step_length = (end-start)/64.0;
    float sample_offset = mix(.15,.85,hash(screen_uv*vec2(1536.0,864.0)));
    vec3 light_dir = normalize(mix(moon_direction,sun_direction,daylight_factor));
    vec3 radiance = vec3(0.0);
    float transmission = 1.0;
    float sun_facing = pow(max(dot(dir,light_dir),0.0),8.0);
    for (int i=0;i<64;i++) {
        float distance = start+(float(i)+sample_offset)*step_length;
        vec3 p = origin + dir*distance;
        float density = volume_density(p,step_length);
        if (density>.001) {
            float shade = volume_density(p+light_dir*.08,max(step_length,.08*.5))*.08
                        + volume_density(p+light_dir*.18,max(step_length,.18*.5))*.10
                        + volume_density(p+light_dir*.36,max(step_length,.36*.5))*.18
                        + volume_density(p+light_dir*.70,max(step_length,.70*.5))*.34;
            float illumination = exp(-shade*15.0);
            float opacity = 1.0-exp(-density*step_length*18.0);
            float h = clamp((p.y-base)/(top-base),0.0,1.0);
            vec3 ambient = mix(cloud_dark,cloud_light,.08+h*.3);
            vec3 direct = mix(moon_color*.045, sun_color*.65,daylight_factor);
            vec3 light = ambient*.65 + direct*illumination*(.65+sun_facing*.6);
            // Aerial perspective softens remote banks without outlining them.
            light = mix(light,sky_gradient(dir),1.0-exp(-max(distance-3.0,0.0)*.13));
            opacity *= 1.0-smoothstep(18.0,28.0,distance);
            radiance += transmission*opacity*light;
            transmission *= 1.0-opacity;
            if (transmission<.015) break;
        }
    }
    float horizon_fade = smoothstep(.008,.04,dir.y);
    return vec4(radiance*horizon_fade,(1.0-transmission)*horizon_fade);
}


// ---------------------------------------------------------------------------
// Sun — bright disk with wide atmospheric haze so it's findable in blue sky
// ---------------------------------------------------------------------------

vec3 sun_contribution(vec3 dir) {
	float cos_angle = dot(dir, sun_direction);
	// Antialiased HDR core. Environment glow now owns bloom; the sky shader
	// provides a controlled source instead of a clipped white step.
	float disk_edge = 0.0003;
	float separation = length(dir - sun_direction);
	float radius = 2.0 * sin(sun_size * 0.5);
	float disk = (1.0 - smoothstep(radius - disk_edge, radius + disk_edge, separation)) * 8.0;
	float corona = pow(max(cos_angle, 0.0), 512.0) * sun_bloom * 1.8;
	// Wide atmospheric glow keeps the sun findable without whitening the dome.
	float glow   = pow(max(cos_angle, 0.0), 8.0) * sun_bloom * 0.15;
	// Fade out as sun drops below the horizon so glow doesn't bleed at night
	float elev_fade = smoothstep(-0.10, 0.05, sun_direction.y);
	vec3 hot_core = vec3(1.0, 0.97, 0.90) * disk;
	vec3 warm_scatter = sun_color * (corona + glow);
	return (hot_core + warm_scatter) * elev_fade;
}


// ---------------------------------------------------------------------------
// Moon — finite angular disk with restrained atmospheric corona.
// ---------------------------------------------------------------------------

vec3 moon_contribution(vec3 dir) {
	float cos_angle = dot(dir, moon_direction);
	// Disk — visually present but not bright enough to bathe the scene in light.
	float separation = length(dir - moon_direction);
	float radius = 2.0 * sin(moon_size * 0.5);
	float disk = (1.0 - smoothstep(radius - 0.0003, radius + 0.0003, separation)) * 0.65;
	// Very faint soft corona
	float corona = pow(max(cos_angle, 0.0), 4096.0) * 0.025;
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
    if (AT_HALF_RES_PASS) {
        vec4 clouds = cloud_layer(dir, SCREEN_UV);
        COLOR = clouds.rgb;
        ALPHA = clouds.a;
    } else {
        vec3 col = sky_gradient(dir);
        if (dir.y > -.02) {
            col += stars_contribution(dir,0.0,0.0);
            col += sun_contribution(dir);
            col += moon_contribution(dir);
        }
        // Cloud radiance is premultiplied; the same opacity occludes celestial
        // disks, stars and sky, and is included in the reflection cubemap.
        COLOR = col*(1.0-HALF_RES_COLOR.a)+HALF_RES_COLOR.rgb;
    }
}
