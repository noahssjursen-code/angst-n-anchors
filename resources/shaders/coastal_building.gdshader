shader_type spatial;
render_mode diffuse_burley;

uniform bool distant_shell = false;
uniform vec4 glass_colour : source_color = vec4(.10,.16,.17,1);
uniform float night_factor = 0.0;
varying float local_height;
varying flat float household;

void vertex() {
    local_height=VERTEX.y;
    household=INSTANCE_CUSTOM.r;
}
void fragment() {
    // Far geometry stores linear finish colour and a glazing mask in COLOR.
    float pane=distant_shell ? COLOR.a : 1.0;
    ALBEDO=distant_shell ? COLOR.rgb : glass_colour.rgb;
    ROUGHNESS=mix(.86,.28,pane);
    METALLIC=.15*pane;
    // Stable household/floor occupancy. It does not flicker with camera motion,
    // and a town never switches every window on in identical unison.
    float room=step(.30,fract(household+floor(local_height/3.0)*.371));
    float evening=smoothstep(household*.25,.65+household*.25,night_factor);
    vec3 warm=mix(vec3(1.0,.48,.19),vec3(1.0,.70,.38),household);
    EMISSION=warm*(.75*pane*room*evening);
}
