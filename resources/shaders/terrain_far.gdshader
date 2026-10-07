shader_type spatial;
render_mode cull_back, diffuse_burley;
#include "terrain_surfaces.gdshaderinc"
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
    coast_w=clamp(COLOR.a,0.0,1.0);
}
void fragment() {
    vec3 n=normalize(world_normal);
    vec3 w=terrain_weights(n);
    vec3 macro=texture(macro_map,world_pos.xz*.0016).rgb;
    vec2 forest_uv=world_pos.xz/(forest_world_half_extent_m*2.0)+vec2(.5);
    float forest=texture(forest_map,clamp(forest_uv,vec2(0),vec2(1))).r;
    vec3 habitat=terrain_habitat(world_pos,n,coast_w,forest,macro);
    // Metre-scale source tiles, identical UVs in every LOD.
    vec3 rock=terrain_tri(stone_color,world_pos*.25,w);
    vec3 heath=texture(heath_color,world_pos.xz/2.1).rgb*vec3(.45,.62,.55);
    vec3 soil=texture(soil_color,world_pos.xz/1.4).rgb;
    float moss_patches=smoothstep(.35,.66,texture(macro_map,world_pos.xz*.035+vec2(.31,.73)).g);
    soil=mix(soil,heath,.12+moss_patches*.22);
    vec3 albedo=rock*habitat.x+soil*habitat.y+heath*habitat.z;
    albedo*=mix(.78,1.12,macro.g);
    float wet=coast_w*(1.0-smoothstep(.2,2.8,world_pos.y));
    albedo*=mix(1.0,.48,wet);
    float snow=smoothstep(850.0,1250.0,world_pos.y)*smoothstep(.7,.95,n.y);
    albedo=mix(albedo,vec3(.65,.69,.72),snow);
    // Canopy is only a distant coverage substitute; near trees sit on soil.
    float canopy=smoothstep(600.0,1300.0,length(VERTEX))*habitat.y;
    albedo=mix(albedo,canopy_colour(world_pos.xz),canopy);
    ALBEDO=albedo;
    SPECULAR=.25;
    ROUGHNESS=mix(.92,.48,wet);

}
