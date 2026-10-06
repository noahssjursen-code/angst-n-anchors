shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_position;
float hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float noise2(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p=world_position.xz;
    float grain=noise2(p*20.0);
    float patches=noise2(p*.18);
    float detail=1.0-smoothstep(.01,.08,length(fwidth(p)));
    ALBEDO=vec3(.031,.035,.038)*(0.96+patches*.08)+(grain-.5)*.004*detail;
    ROUGHNESS=.94;
    SPECULAR=.18;
}
