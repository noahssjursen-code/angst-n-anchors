"""Original modular sjark equipment; reference notes in docs/fishing-outfits.txt.
Metres; Blender +Y bow / +Z up. No downloaded geometry.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'parts'/'coastal_fishing'
OUT.mkdir(parents=True,exist_ok=True)
def mat(name,c,metal=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.55
    return m
steel=mat('Fixed_Stainless',(.52,.56,.58),.8)
rubber=mat('Fixed_Rubber',(.025,.03,.032))
paint=mat('Warm white marine enamel',(.76,.79,.73))
rope=mat('Fixed_Warp',(.20,.34,.20))
orange=mat('Fixed_FloatOrange',(.95,.22,.045))
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(n,p,s,m):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    return o
def bar(n,a,b,r,m,vertices=12):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();o.data.materials.append(m);return o
def ring(n,p,r,thick,m,rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=6,location=p,major_radius=r,minor_radius=thick,rotation=rotation)
    o=bpy.context.object;o.name=n;o.data.materials.append(m)
def socket(n,p):
    o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=p
assets=[]
def save(name,style,size):
    bpy.ops.object.select_all(action='SELECT')
    for o in bpy.context.selected_objects:
        if o.type=='MESH':
            bpy.context.view_layer.objects.active=o;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    assets.append(dict(id=name,style=style,kind='furniture',model='res://resources/models/parts/coastal_fishing/'+name+'.glb',start_xz=[0,0],end_xz=size[:2],height_start_m=size[2],height_end_m=size[2],paintable=False,components=[]))
# The articulated spinning rod is authored in the fishing_items source kit.
assets.append(dict(id='hook_line_station',style='hook_line',kind='furniture',model='res://resources/models/parts/coastal_fishing/hook_line_station.glb',start_xz=[0,0],end_xz=[.4,2.1],height_start_m=2.1,height_end_m=2.1,paintable=False,components=[]))
clear()
for x in [-.48,.48]:
    for y in [-.28,.28]:bar('Table leg',(x,y,0),(x,y,.88),.027,steel)
box('Cleaning board',(0,0,.90),(1.1,.7,.06),paint)
for y in [-.34,.34]:box('Raised lip',(0,y,.96),(1.1,.025,.10),steel)
box('Bait tray',(-.32,0,.96),(.32,.34,.08),orange)
save('bait_work_table','fishing_table',[1.1,.7,1.02])
clear()
# Rectangular creel: weighted base, wire mesh, two funnel entrances and hatch.
for z in [.035,.57]:
    for y in [-.32,.32]:bar('Frame',(-.48,y,z),(.48,y,z),.022,steel)
    for x in [-.48,.48]:bar('Frame',(x,-.32,z),(x,.32,z),.022,steel)
for x in [-.48,.48]:
    for y in [-.32,.32]:bar('Upright',(x,y,.035),(x,y,.57),.018,steel)
for i in range(13):
    x=-.48+i*.08
    for y in [-.32,.32]:bar('Mesh vertical',(x,y,.04),(x,y,.56),.003,rope,6)
    bar('Top mesh',(x,-.32,.57),(x,.32,.57),.003,rope,6)
for i in range(7):
    z=.06+i*.08
    for y in [-.32,.32]:bar('Mesh horizontal',(-.48,y,z),(.48,y,z),.003,rope,6)
for x in [-.48,.48]:
    ring('Entrance hoop',(x,0,.30),.21,.014,rope,(0,math.pi/2,0))
    ring('Inner funnel',(x*.45,0,.30),.09,.012,rope,(0,math.pi/2,0))
    for i in range(16):
        a=i*math.tau/16
        bar('Funnel mesh',(x,.21*math.cos(a),.30+.21*math.sin(a)),(x*.45,.09*math.cos(a),.30+.09*math.sin(a)),.004,rope,6)
for x in [-.36,.36]:box('Ballast runner',(x,0,.03),(.08,.66,.06),rubber)
# Two grip bars on top of the frame, in the gap under the next stacked creel.
for x, name in ((-.24,'LeftHandle'),(.24,'RightHandle')):
    bar('Handle riser',(x,-.10,.57),(x,-.10,.60),.01,steel)
    bar('Handle riser',(x,.10,.57),(x,.10,.60),.01,steel)
    bar('Carry handle',(x,-.10,.60),(x,.10,.60),.012,steel)
    socket(name,(x,0,.60))
socket('BridleSocket',(0,0,.6));save('crab_creel','crab_trap',[1,.7,.60])
clear()
box('Mount base',(0,0,.05),(.38,.38,.10),steel)
bar('Hauler pedestal',(0,0,.1),(0,0,1.15),.08,steel)
bar('Outboard davit',(0,0,1.1),(.65,0,1.65),.055,steel)
bar('Hydraulic sheave',(.65,-.10,1.65),(.65,.10,1.65),.20,orange,24)
bar('Pin',(.65,-.14,1.65),(.65,.14,1.65),.05,steel)
box('Drive housing',(0,-.15,.92),(.3,.25,.35),paint)
bar('Rope guide',(.20,0,1.18),(.55,0,1.48),.025,rubber)
socket('HaulPoint',(.65,0,1.65));save('pot_hauler','pot_hauler',[.9,.5,1.9])
clear()
for j in range(4):
    ring('Coiled pot rope',(0,0,.035+j*.035),.24,.018,rope)
bar('Buoy stem',(.42,0,.08),(.42,0,.73),.027,steel)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.19,location=(.42,0,.31))
o=bpy.context.object;o.name='Marker buoy';o.scale=(1,1,1.35);o.data.materials.append(orange)
save('pot_rope_buoy','pot_rope',[.7,.55,.76])
clear()
# Hook with a short snood above a terminal sinker. Origin is the sinker datum.
bar('Terminal leader',(0,0,0),(0,0,.55),.0025,rope,6)
bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=.035,location=(0,0,.055))
o=bpy.context.object;o.name='Terminal sinker';o.scale=(1,1,2);o.data.materials.append(steel)
bar('Hook snood',(0,0,.42),(.12,0,.33),.0025,rope,6)
for i in range(12):
    a=math.pi+i*math.pi/12;b=math.pi+(i+1)*math.pi/12
    bar('Hook bend',(.145+.025*math.cos(a),0,.30+.025*math.sin(a)),(.145+.025*math.cos(b),0,.30+.025*math.sin(b)),.003,steel,6)
bar('Hook shank',(.12,0,.30),(.12,0,.36),.003,steel,6)
save('hook_sinker_rig','terminal_tackle',[.2,.1,.56])
clear()
# Open-sided weather shelter, 2.15 m head clearance; separate reusable outfit.
for x in [-1.85,1.85]:
    for y in [-.85,.85]:
        box('Shelter foot',(x,y,.04),(.22,.22,.08),steel)
        bar('Shelter stanchion',(x,y,.08),(x,y,2.16),.04,steel)
for y in [-.85,.85]:bar('Roof cross beam',(-1.85,y,2.16),(1.85,y,2.16),.05,steel)
box('Weather roof',(0,0,2.22),(3.95,2.0,.12),paint)
for x in [-1.96,1.96]:box('Roof drip edge',(x,0,2.18),(.035,2,.16),steel)
save('crabber_work_shelter','work_shelter',[3.95,2,2.28])
(OUT/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2),encoding='utf-8')
