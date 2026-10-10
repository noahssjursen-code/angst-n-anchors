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
    // Metre-scale source detail with matching non-repeating blends in every LOD.
    vec3 rock=terrain_tri(stone_color,world_pos*.25,w);
    vec3 heath=terrain_tile_colour(heath_color,world_pos.xz/2.1).rgb*vec3(.38,.53,.47);
    vec3 soil=terrain_tile_colour(soil_color,world_pos.xz/1.4).rgb;
    // Broad irregular moss patches; the old 28 m mask repeated visibly in rows.
    vec2 turned=mat2(vec2(.8,.6),vec2(-.6,.8))*world_pos.xz;
    float moss_field=texture(macro_map,world_pos.xz*.011+vec2(.31,.73)).g*.6
        +texture(macro_map,turned*.017+vec2(.19,.47)).b*.4;
    float moss_patches=smoothstep(.36,.64,moss_field);
    soil=mix(soil,heath,.12+moss_patches*.22);
    vec3 albedo=rock*habitat.x+soil*habitat.y+heath*habitat.z;
    albedo*=mix(.78,1.12,macro.g);
    float wet=coast_w*(1.0-smoothstep(.2,2.8,world_pos.y));
    albedo*=mix(1.0,.48,wet);
    float damp=rain_wetness*mix(.8,1.0,macro.b);
    albedo*=1.0-damp*dot(habitat,vec3(.32,.28,.12));
    float snow=smoothstep(850.0,1250.0,world_pos.y)*smoothstep(.7,.95,n.y);
    albedo=mix(albedo,vec3(.65,.69,.72),snow);
    // Canopy is only a distant coverage substitute; near trees sit on soil.
    float canopy=smoothstep(600.0,1300.0,length(VERTEX))*habitat.y;
    albedo=mix(albedo,canopy_colour(world_pos.xz),canopy);
    ALBEDO=albedo;
    SPECULAR=.25;
    ROUGHNESS=mix(.92,.48,wet);
    float detail=1.0-smoothstep(80.0,200.0,length(VERTEX));
    if(detail>0.001) {
        vec3 gradient=terrain_gradient(stone_normal,world_pos*.25,w)*habitat.x;
        vec3 hn=terrain_tile_normal(heath_normal,world_pos.xz/2.1).xyz*2.0-1.0;
        vec3 sn=terrain_tile_normal(soil_normal,world_pos.xz/1.4).xyz*2.0-1.0;
        gradient+=vec3(hn.x,0,hn.y)*habitat.z+vec3(sn.x,0,sn.y)*habitat.y;
        gradient-=n*dot(n,gradient);
        NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+gradient*.65*detail),0)).xyz);
        float rough=terrain_rough(world_pos*.25,w)*habitat.x
            +terrain_tile_roughness(heath_roughness,world_pos.xz/2.1).r*habitat.z
            +terrain_tile_roughness(soil_roughness,world_pos.xz/1.4).r*habitat.y;
        ROUGHNESS=mix(ROUGHNESS,mix(rough,.4,wet),detail);
    }
    // Bedrock sheds water; organic ground remains rough. Distant canopy and
    // snow must not turn into glossy ground when the near/far LOD changes.
    float damp_rough=dot(habitat,vec3(.40,.72,.86));
    ROUGHNESS=mix(ROUGHNESS,min(ROUGHNESS,damp_rough),damp*(1.0-canopy)*(1.0-snow));
}
