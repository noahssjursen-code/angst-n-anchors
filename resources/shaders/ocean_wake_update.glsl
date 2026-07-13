#[compute]
#version 450

// Persistent world-space vessel wake. R = aerated foam, G = subsurface churn.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rg16f, set = 0, binding = 0) uniform readonly image2D previous_field;
layout(rg16f, set = 0, binding = 1) uniform writeonly image2D next_field;

struct WakeEmitter {
	vec4 segment; // previous_xz, current_xz
	vec4 axis_shape; // trailing axis xz, half beam, speed
	vec4 strength; // foam, churn, active, priority
	vec4 extra; // shoulder length, teleport flag, reserved
};

layout(set = 0, binding = 2, std430) restrict readonly buffer Emitters {
	WakeEmitter data[];
} emitters;

layout(push_constant, std430) uniform WakeParams {
	vec2 current_origin;
	vec2 previous_origin;
	float extent;
	float delta_time;
	uint resolution;
	uint emitter_count;
} params;

float hash21(vec2 p) {
	vec2 hp = fract(p * vec2(123.344, 445.891));
	hp += dot(hp, hp + 341.743);
	return fract(hp.x * hp.y * 9571.834);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float denom = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(p - a, ab) / denom, 0.0, 1.0);
	return length(p - (a + ab * t));
}

vec2 load_previous(ivec2 id, ivec2 origin_shift) {
	ivec2 source_id = id + origin_shift;
	if (source_id.x < 0 || source_id.y < 0
			|| source_id.x >= int(params.resolution)
			|| source_id.y >= int(params.resolution)) {
		return vec2(0.0);
	}
	return imageLoad(previous_field, source_id).rg;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= int(params.resolution) || id.y >= int(params.resolution)) {
		return;
	}

	float texel_m = params.extent / float(params.resolution);
	ivec2 origin_shift = ivec2(round(
		(params.current_origin - params.previous_origin) / texel_m
	));
	vec2 center = load_previous(id, origin_shift);
	vec2 north = load_previous(id + ivec2(0, 1), origin_shift);
	vec2 south = load_previous(id + ivec2(0, -1), origin_shift);
	vec2 east = load_previous(id + ivec2(1, 0), origin_shift);
	vec2 west = load_previous(id + ivec2(-1, 0), origin_shift);

	vec2 neighbor_average = (north + south + east + west) * 0.25;
	vec2 diffusion = vec2(0.025, 0.09) * clamp(params.delta_time * 30.0, 0.0, 1.5);
	vec2 field = mix(center, neighbor_average, diffusion);
	field.x *= exp(-params.delta_time / 16.0);
	field.y *= exp(-params.delta_time / 9.0);

	vec2 world = params.current_origin + (vec2(id) + vec2(0.5)) * texel_m;
	for (uint i = 0; i < params.emitter_count; ++i) {
		WakeEmitter e = emitters.data[i];
		if (e.strength.z < 0.5 || e.extra.y > 0.5) {
			continue;
		}
		vec2 previous_pos = e.segment.xy;
		vec2 current_pos = e.segment.zw;
		vec2 trail = normalize(e.axis_shape.xy + vec2(0.00001));
		vec2 side = vec2(-trail.y, trail.x);
		float half_beam = max(e.axis_shape.z, texel_m * 0.65);
		float speed = e.axis_shape.w;

		float core_radius = max(texel_m * 1.1, half_beam * 0.32);
		float core_distance = segment_distance(world, previous_pos, current_pos);
		float core = exp(-core_distance * core_distance / max(core_radius * core_radius, 0.2));

		vec2 rel = world - current_pos;
		float along = dot(rel, trail);
		float across = dot(rel, side);
		float plume_length = max(half_beam * 2.0, 8.0 + speed * 1.6);
		float plume_gate = smoothstep(-1.0, 1.2, along)
			* (1.0 - smoothstep(plume_length * 0.6, plume_length, along));
		float plume_width = max(texel_m * 0.9, half_beam * (
			0.18 + 0.28 * max(along, 0.0) / max(plume_length, 1.0)
		));
		float plume = exp(-across * across / max(plume_width * plume_width, 0.15)) * plume_gate;

		float shoulder_length = max(e.extra.x * 0.65, half_beam * 4.0);
		float shoulder_gate = smoothstep(0.0, 1.5, along)
			* (1.0 - smoothstep(shoulder_length * 0.72, shoulder_length, along));
		float shoulder_center = along * 0.354;
		float shoulder_distance = abs(abs(across) - shoulder_center);
		float shoulder_width = max(texel_m * 0.75, half_beam * 0.1 + along * 0.014);
		float shoulders = exp(
			-shoulder_distance * shoulder_distance / max(shoulder_width * shoulder_width, 0.1)
		) * shoulder_gate * smoothstep(0.6, 3.5, speed);

		// Soft lace — keep enough energy that fragment foam stays readable.
		float lace = mix(0.62, 1.0, hash21(floor(world * 0.45)));

		float foam_stamp = max(core * 0.8, plume);
		foam_stamp = max(foam_stamp, shoulders * 0.12) * lace * max(e.strength.x, 0.2);
		float churn_stamp = max(core, plume * 0.95);
		churn_stamp = max(churn_stamp, shoulders * 0.65) * max(e.strength.y, 0.25);

		field = max(field, vec2(foam_stamp, churn_stamp));
	}

	imageStore(next_field, id, vec4(clamp(field, vec2(0.0), vec2(1.0)), 0.0, 0.0));
}
