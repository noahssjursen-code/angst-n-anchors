shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_position;
varying vec3 world_normal;
uniform vec3 pavement_color = vec3(.031,.035,.038);
uniform sampler2D colour_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_scan = true;
uniform float rain_wetness = 0.0;
float hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float noise2(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
    world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_normal=MODEL_NORMAL_MATRIX*NORMAL;
}
void fragment() {
    vec2 p=world_position.xz;
    float grain=noise2(p*20.0);
    float patches=noise2(p*.18);
    float detail=1.0-smoothstep(.01,.08,length(fwidth(p)));
	ALBEDO=pavement_color*(0.96+patches*.08)+(grain-.5)*.004*detail;
    ROUGHNESS=.94;
    SPECULAR=.18;
    float damp=rain_wetness*mix(.78,1.0,patches);
    if (use_scan) {
        // One world-space phase across road polygons, parcels and junctions.
        // Fine aggregate is the original ambientCG Asphalt033 scan, in metres.
        vec2 uv=p/2.5;
        vec3 scan=texture(colour_map,uv).rgb;
        ALBEDO=pavement_color*clamp(scan/.085,vec3(.35),vec3(2.1));
        ROUGHNESS=mix(.76,.98,texture(roughness_map,uv).r);
        vec2 detail_normal=texture(normal_map,uv).rg*2.0-1.0;
        NORMAL=normalize((VIEW_MATRIX*vec4(normalize(world_normal+vec3(detail_normal.x,0,detail_normal.y)*.35*mix(1.0,.7,damp)),0)).xyz);
    }
    ALBEDO*=mix(1.0,.55,damp);
    ROUGHNESS=mix(ROUGHNESS,.24,damp);
    SPECULAR=mix(SPECULAR,.45,damp);
}
