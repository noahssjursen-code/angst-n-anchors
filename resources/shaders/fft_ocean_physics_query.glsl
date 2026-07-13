#[compute]
#version 450

// Exact 4x4 box reduction of the live 512² macro-height field. RG stores
// (height, vertical velocity), leaving the approved render FFT untouched.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform readonly image2DArray source_displacement;
layout(rgba32f, set = 0, binding = 1) uniform image2DArray physics_query;
layout(rgba32f, set = 0, binding = 2) uniform image2DArray previous_displacement;

layout(push_constant, std430) uniform QueryParams {
	float delta_time;
	uint has_previous;
	uint source_resolution;
	uint query_resolution;
} params;

void main() {
	ivec3 out_coord = ivec3(gl_GlobalInvocationID.xyz);
	if (out_coord.x >= int(params.query_resolution)
			|| out_coord.y >= int(params.query_resolution)
			|| out_coord.z >= 4) {
		return;
	}

	int ratio = int(params.source_resolution / params.query_resolution);
	ivec2 source_origin = out_coord.xy * ratio;
	vec3 displacement_sum = vec3(0.0);
	for (int y = 0; y < ratio; ++y) {
		for (int x = 0; x < ratio; ++x) {
			displacement_sum += imageLoad(
				source_displacement,
				ivec3(source_origin + ivec2(x, y), out_coord.z)
			).xyz;
		}
	}
	vec3 displacement = displacement_sum / float(ratio * ratio);
	vec3 old_displacement = imageLoad(previous_displacement, out_coord).xyz;
	vec3 velocity = params.has_previous != 0
		? (displacement - old_displacement) / max(params.delta_time, 0.001)
		: vec3(0.0);
	// One bad device frame must never inject an unbounded physics impulse.
	velocity = clamp(velocity, vec3(-20.0), vec3(20.0));
	imageStore(
		physics_query,
		out_coord,
		vec4(displacement.y, velocity.x, velocity.y, velocity.z)
	);
	imageStore(previous_displacement, out_coord, vec4(displacement, 0.0));
}
