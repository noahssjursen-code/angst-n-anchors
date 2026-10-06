#[compute]
#version 450

// Filter signed slopes, not normalized normals. Each view is one cascade/mip.
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(rg32f, set=0, binding=0) uniform readonly image2D source_slope;
layout(rg32f, set=0, binding=1) uniform writeonly image2D target_slope;

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(pixel, imageSize(target_slope)))) return;
    ivec2 source = pixel * 2;
    vec2 slope = imageLoad(source_slope, source).xy;
    slope += imageLoad(source_slope, source + ivec2(1,0)).xy;
    slope += imageLoad(source_slope, source + ivec2(0,1)).xy;
    slope += imageLoad(source_slope, source + ivec2(1,1)).xy;
    imageStore(target_slope, pixel, vec4(slope * .25, 0, 0));
}
