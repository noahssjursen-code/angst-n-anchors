// One habitat/material policy for every terrain LOD. No vertex-colour fallback.
#include "terrain_canopy.gdshaderinc"
#include "terrain_tile.gdshaderinc"
uniform sampler2D stone_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D heath_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D heath_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D heath_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_map : filter_linear_mipmap, repeat_disable;
uniform float forest_world_half_extent_m = 20000.0;
varying vec3 world_pos;
varying vec3 world_normal;
varying float coast_w;
vec3 terrain_weights(vec3 n) {
    vec3 w = pow(abs(n),vec3(4.0));
    return w / max(w.x+w.y+w.z,0.001);
}
vec3 terrain_tri(sampler2D map,vec3 p,vec3 w) {
    return texture(map,p.zy).rgb*w.x+texture(map,p.xz).rgb*w.y+texture(map,p.xy).rgb*w.z;
}
float terrain_rough(vec3 p,vec3 w) {
    return texture(stone_roughness,p.zy).r*w.x+texture(stone_roughness,p.xz).r*w.y+texture(stone_roughness,p.xy).r*w.z;
}
vec3 terrain_gradient(sampler2D map,vec3 p,vec3 w) {
    vec3 a=texture(map,p.zy).xyz*2.0-1.0;
    vec3 b=texture(map,p.xz).xyz*2.0-1.0;
    vec3 c=texture(map,p.xy).xyz*2.0-1.0;
    return vec3(0,a.y,a.x)*w.x+vec3(b.x,0,b.y)*w.y+vec3(c.x,c.y,0)*w.z;
}
// Returns rock, woodland soil and open heath proportions.
vec3 terrain_habitat(vec3 p,vec3 n,float coast,float forest,vec3 macro) {
    float slope=1.0-clamp(n.y,0.0,1.0);
    float stone=smoothstep(.065,.32,slope);
    stone=max(stone,coast*(1.0-smoothstep(1.0,12.0,p.y)));
    stone=max(stone,smoothstep(.65,.84,macro.r)*.55);
    float woodland=clamp(forest*1.35,0.0,1.0)*(1.0-stone);
    return vec3(stone,woodland,max(0.0,1.0-stone-woodland));
}
