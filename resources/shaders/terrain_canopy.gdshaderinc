// Distant crown relief on the existing terrain, not extra world geometry.
// Nine neighbouring cells avoid a visible square grid; derivatives suppress
// subpixel crown contrast at the horizon. Both terrain LOD shaders share it.
vec2 canopy_hash(vec2 p) {
    return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
vec3 canopy_colour(vec2 world_xz) {
    vec2 p = world_xz / 9.0;
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float nearest = 8.0;
    float variation = 0.5;
    for (int y=-1;y<=1;y++) {
        for (int x=-1;x<=1;x++) {
            vec2 offset = vec2(float(x),float(y));
            vec2 jitter = canopy_hash(cell+offset);
            vec2 delta = offset + 0.15 + jitter*0.7 - f;
            float d = dot(delta,delta);
            if (d < nearest) { nearest = d; variation = jitter.x; }
        }
    }
    float resolved = 1.0-smoothstep(0.35,1.1,length(fwidth(p)));
    float crown = mix(0.55,1.15,1.0-smoothstep(0.03,0.5,nearest));
    crown = mix(0.88,crown,resolved);
    return mix(vec3(0.022,0.036,0.014),vec3(0.040,0.057,0.022),variation*resolved)*crown;
}
