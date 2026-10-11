// Three overlapping source samples on a triangular lattice replace repeated
// square tiles. Position is absolute world space in every terrain LOD. Colour,
// normal and roughness use the same offsets; no animated noise or new textures.
// Tiling/blending background: Deliot & Heitz, GPU Zen 2 (2019).
vec2 terrain_tile_hash(vec2 cell) {
    return fract(sin(vec2(dot(cell,vec2(127.1,311.7)),
        dot(cell,vec2(269.5,183.3))))*43758.5453);
}
void terrain_tile_coordinates(vec2 uv,out vec2 a,out vec2 b,out vec2 c,out vec3 weights) {
    vec2 skew=vec2(uv.x-uv.y*.57735027,uv.y*1.15470054);
    vec2 cell=floor(skew);
    vec2 f=fract(skew);
    a=cell;
    b=cell+vec2(1,0);
    c=cell+vec2(0,1);
    weights=vec3(1.0-f.x-f.y,f.x,f.y);
    if(f.x+f.y>1.0) {
        a=cell+vec2(1,1);
        weights=vec3(f.x+f.y-1.0,1.0-f.y,1.0-f.x);
    }
    // Narrow overlaps preserve more photographed detail than a broad average.
    weights=weights*weights*weights;
    weights/=max(dot(weights,vec3(1)),.00001);
    a=uv+terrain_tile_hash(a);
    b=uv+terrain_tile_hash(b);
    c=uv+terrain_tile_hash(c);
}
// Godot requires separate sampler functions for different texture hints.
vec4 terrain_tile_colour(sampler2D map,vec2 uv) {
    vec2 a,b,c;vec3 w;terrain_tile_coordinates(uv,a,b,c,w);
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    return textureGrad(map,a,dx,dy)*w.x+textureGrad(map,b,dx,dy)*w.y+textureGrad(map,c,dx,dy)*w.z;
}
vec4 terrain_tile_normal(sampler2D map,vec2 uv) {
    vec2 a,b,c;vec3 w;terrain_tile_coordinates(uv,a,b,c,w);
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    return textureGrad(map,a,dx,dy)*w.x+textureGrad(map,b,dx,dy)*w.y+textureGrad(map,c,dx,dy)*w.z;
}
vec4 terrain_tile_roughness(sampler2D map,vec2 uv) {
    vec2 a,b,c;vec3 w;terrain_tile_coordinates(uv,a,b,c,w);
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    return textureGrad(map,a,dx,dy)*w.x+textureGrad(map,b,dx,dy)*w.y+textureGrad(map,c,dx,dy)*w.z;
}
