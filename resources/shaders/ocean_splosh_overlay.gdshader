shader_type spatial;
render_mode blend_add,depth_draw_never,cull_disabled,unshaded;

/* White splosh overlay only. It rides the same Gerstner displacement as ocean_waves.gdshader. */
uniform float wave_time;
uniform float water_level = -1.5;
uniform float amplitude_1 = 0.30;
uniform float frequency_1 = 0.18;
uniform float speed_1 = 0.75;
uniform vec2 dir_1 = vec2(1.0, 0.6);
uniform float steepness_1 = 0.45;
uniform float amplitude_2 = 0.12;
uniform float frequency_2 = 0.18;
uniform float speed_2 = 1.2;
uniform vec2 dir_2 = vec2(-0.5, 1.0);
uniform float steepness_2 = 0.35;
uniform float amplitude_3 = 0.22;
uniform float frequency_3 = 0.05;
uniform float speed_3 = 0.6;
uniform vec2 dir_3 = vec2(0.23, -0.97);
uniform float steepness_3 = 0.40;
uniform float amplitude_4 = 0.08;
uniform float frequency_4 = 0.32;
uniform float speed_4 = 1.5;
uniform vec2 dir_4 = vec2(-0.91, -0.2);
uniform float steepness_4 = 0.25;
uniform float wave_intensity = 1.0;
uniform float wave_energy_multiplier = 1.0;

uniform vec4 boat_coupling = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 boat_coupling_axes = vec2(1.0, 1.0);
uniform vec2 boat_velocity = vec2(0.0, 0.0);

uniform float splosh_intensity : hint_range(0.0, 2.0) = 0.0;
uniform float splosh_density : hint_range(0.2, 6.0) = 1.0;
uniform float short_wave_factor : hint_range(0.0, 1.0) = 0.0;
uniform float splosh_wavelength : hint_range(1.0, 18.0) = 8.0;
uniform float splosh_height_offset = 0.035;

varying vec3 v_world_pos;
varying vec2 v_surface_grad;
varying float v_wave_steep;
varying float v_boat_wake;


float hash21(vec2 p) {
	vec2 hp = fract(p * vec2(127.1, 311.7));
	hp += dot(hp, hp + 33.3);
	return fract(hp.x * hp.y * 71.9);
}

float wf_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	vec4 w4 = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 wp = w4.xyz;

	vec2 d1n = normalize(dir_1);
	vec2 d2n = normalize(dir_2);
	vec2 d3n = normalize(dir_3);
	vec2 d4n = normalize(dir_4);
	float amp_scale = wave_intensity * wave_energy_multiplier;
	float a1 = amplitude_1 * amp_scale;
	float a2 = amplitude_2 * amp_scale;
	float a3 = amplitude_3 * amp_scale;
	float a4 = amplitude_4 * amp_scale;
	float q1 = clamp(steepness_1, 0.0, 0.98);
	float q2 = clamp(steepness_2, 0.0, 0.98);
	float q3 = clamp(steepness_3, 0.0, 0.98);
	float q4 = clamp(steepness_4, 0.0, 0.98);

	float ph1 = (wp.x * d1n.x + wp.z * d1n.y) * frequency_1 + wave_time * speed_1;
	float ph2 = (wp.x * d2n.x + wp.z * d2n.y) * frequency_2 + wave_time * speed_2;
	float ph3 = (wp.x * d3n.x + wp.z * d3n.y) * frequency_3 + wave_time * speed_3;
	float ph4 = (wp.x * d4n.x + wp.z * d4n.y) * frequency_4 + wave_time * speed_4;
	float s1 = sin(ph1); float c1 = cos(ph1);
	float s2 = sin(ph2); float c2 = cos(ph2);
	float s3 = sin(ph3); float c3 = cos(ph3);
	float s4 = sin(ph4); float c4 = cos(ph4);

	vec2 disp_xz = vec2(0.0);
	disp_xz += d1n * (q1 * a1 * c1);
	disp_xz += d2n * (q2 * a2 * c2);
	disp_xz += d3n * (q3 * a3 * c3);
	disp_xz += d4n * (q4 * a4 * c4);
	float disp_y = a1 * s1 + a2 * s2 + a3 * s3 + a4 * s4;

	vec3 displaced_world = vec3(
		wp.x + disp_xz.x,
		water_level + disp_y,
		wp.z + disp_xz.y
	);

	float boat_dip = 0.0;
	float ddip_dx = 0.0;
	float ddip_dz = 0.0;
	float wake = 0.0;
	if (boat_coupling.z > 0.0001) {
		float bx = boat_coupling.x;
		float bz = boat_coupling.y;
		float amp = boat_coupling.z;
		float sx = max(boat_coupling_axes.x, 0.01);
		float sz = max(boat_coupling_axes.y, 0.01);
		float dx = displaced_world.x - bx;
		float dz = displaced_world.z - bz;
		float u = dx / sx;
		float v = dz / sz;
		float g = -0.5 * (u * u + v * v);
		if (g > -8.0) {
			boat_dip = amp * exp(g);
			ddip_dx = -boat_dip * u / sx;
			ddip_dz = -boat_dip * v / sz;
		}

		// Trailing wake
		float v_len = length(boat_velocity);
		if (v_len > 0.5) {
			vec2 v_dir = boat_velocity / v_len;
			float along = dx * v_dir.x + dz * v_dir.y;
			float across = dx * -v_dir.y + dz * v_dir.x;
			
			// Behind the boat
			if (along < 0.0 && along > -v_len * 3.0) {
				float trail_width = mix(sz * 1.2, sz * 3.0, -along / (v_len * 3.0));
				float t_u = across / trail_width;
				float t_v = along / (v_len * 3.0); 
				
				float t_g = -0.5 * (t_u * t_u);
				if (t_g > -5.0) {
					// Mask for foam wake
					wake = exp(t_g) * (1.0 + t_v) * clamp(v_len * 0.1, 0.0, 1.0);
					
					// Slight physical dip
					float trail_amp = amp * 0.3 * wake;
					boat_dip += trail_amp;
				}
			}
		}
	}
	displaced_world.y -= boat_dip;

	float dydx = (
		a1 * frequency_1 * d1n.x * c1 + a2 * frequency_2 * d2n.x * c2
		+ a3 * frequency_3 * d3n.x * c3 + a4 * frequency_4 * d4n.x * c4
		- ddip_dx
	);
	float dydz = (
		a1 * frequency_1 * d1n.y * c1 + a2 * frequency_2 * d2n.y * c2
		+ a3 * frequency_3 * d3n.y * c3 + a4 * frequency_4 * d4n.y * c4
		- ddip_dz
	);
	float dydy = (
		q1 * a1 * frequency_1 * s1 + q2 * a2 * frequency_2 * s2
		+ q3 * a3 * frequency_3 * s3 + q4 * a4 * frequency_4 * s4
	);
	
	// GPU Gems standard approximation for Gerstner normals.
	vec3 world_n = normalize(vec3(-dydx, max(1.0 - dydy, 0.05), -dydz));

	// Crucial fix: Offset the splosh mesh ALONG THE NORMAL, not just straight up in Y!
	// If we just add +Y, the splosh mesh cuts through the base mesh when the wave face is vertical.
	displaced_world += world_n * splosh_height_offset;

	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced_world, 1.0)).xyz;
	NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_n, 0.0)).xyz);

	v_world_pos = displaced_world;
	v_surface_grad = vec2(dydx, dydz);
	v_wave_steep = 1.0 - clamp(world_n.y, 0.0, 1.0);
	v_boat_wake = wake;
}


void fragment() {
	vec2 uv = v_world_pos.xz;

	// Foam advection: foam slides down the slope of the wave.
	// gradient points "uphill", so subtract it to slide "downhill".
	vec2 advection_offset = -v_surface_grad * mix(1.8, 3.5, short_wave_factor);
	vec2 advected_uv = uv + advection_offset;

	float freq = 6.283185 / max(splosh_wavelength, 0.1);
	vec2 wind_a = normalize(vec2(0.86, 0.32));
	vec2 side_a = vec2(-wind_a.y, wind_a.x);

	// Add noise to the advected_uv so the crest lines are squiggly, not straight!
	// Scale the noise intensity inversely with short_wave_factor so calm water has broken streaks, and choppy water has scattered sploshes.
	float noise_scale = mix(3.5, 1.2, short_wave_factor);
	float warp_noise = wf_vnoise(advected_uv * 0.2 + wave_time * 0.1) * 2.0 - 1.0;
	vec2 squiggly_uv = advected_uv + wind_a * (warp_noise * noise_scale) + side_a * (warp_noise * noise_scale * 0.7);

	// Short wave crests form the primary unstable edge.
	// Add an extra noise lookup into the phase itself to break the continuous sine wave.
	float phase_breakup = wf_vnoise(squiggly_uv * 0.45) * 1.5;
	float short_a = sin(dot(squiggly_uv, wind_a) * freq + wave_time * mix(1.2, 3.9, short_wave_factor) + phase_breakup);
	float crest_core = smoothstep(mix(0.96, 0.82, short_wave_factor), 1.0, short_a);
	float crest_feather = smoothstep(mix(0.86, 0.66, short_wave_factor), 1.0, short_a) * 0.35;
	float short_mask = max(crest_core, crest_feather);

	// Large, slow breakup gates whole crest segments; avoid small hash cells / spraypaint dots.
	// We use the advected UVs here so the foam patches slide down.
	float along = dot(advected_uv, wind_a);
	float across = dot(advected_uv, side_a);
	
	// Temporal delay: make the breakup noise evolve slower so foam "lingers" after a crest breaks.
	vec2 lingering_time = wave_time * vec2(0.06, -0.02);
	float segment_noise = hash21(vec2(along * 0.10, across * 0.035) + lingering_time);
	
	// Add an extra layer of high-frequency noise to break up the "blocky" rectangle feel
	float micro_breakup = wf_vnoise(squiggly_uv * 1.8 + lingering_time * 2.0);
	segment_noise = mix(segment_noise, micro_breakup, 0.45);
	
	float segment_gate = smoothstep(mix(0.84, 0.58, short_wave_factor), 1.0, segment_noise);
	
	float width_fade = smoothstep(0.30, 1.0, fract(across * 0.08 + segment_noise * 0.37));
	width_fade *= 1.0 - smoothstep(0.88, 1.0, fract(across * 0.08 + segment_noise * 0.37));
	
	float steep_mask = smoothstep(
		mix(0.30, 0.08, short_wave_factor),
		mix(0.72, 0.34, short_wave_factor),
		v_wave_steep
	);
	
	float breakup = segment_gate * mix(0.55, 1.0, width_fade);
	float instability = max(steep_mask, short_mask * short_wave_factor);
	
	// Add lingering trail foam behind steep waves based on advection distance.
	float trail_alpha = breakup * steep_mask * clamp(length(advection_offset) * 0.4, 0.0, 1.0);
	
	// Forcefully trigger splosh inside the boat wake mask
	float boat_foam = v_boat_wake * breakup * 2.5; 
	
	float alpha = (short_mask * instability * breakup + trail_alpha) * splosh_intensity + boat_foam;

	ALBEDO = vec3(0.92, 0.96, 1.0);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
