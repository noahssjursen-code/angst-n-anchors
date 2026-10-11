"""Reusable fishing hardware, metres, Blender +Y bow/+Z up."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'parts'/'fishing_kit';OUT.mkdir(parents=True,exist_ok=True)
def mat(name,c,metal=.3):
    m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48
    return m
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(name,p,s,m):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    b=o.modifiers.new('Welded edge radius','BEVEL');b.width=.012;b.segments=3
    o.modifiers.new('Normals','WEIGHTED_NORMAL');return o
def cyl(name,a,b,r,m):
    a,b=Vector(a),Vector(b);bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object;o.name=name;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    return o
def socket(name,p):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=p
def save(name):
    bpy.ops.object.select_all(action='SELECT')
    for o in bpy.context.selected_objects:
        if o.type=='MESH':
            bpy.context.view_layer.objects.active=o;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
clear()
paint=mat('Warm white painted steel',(.24,.37,.38));steel=mat('Fixed_Galvanized',(.42,.48,.49),.8)
dark=mat('Fixed_Hydraulic',(.035,.047,.053),.4);rope=mat('Fixed_Warp',(.17,.20,.19),.45)
for y in [-.86,.86]:
    box('Bolted foot',(0,y,.06),(1.1,.30,.12),paint)
    for x in [-.34,.34]:
        box('Bearing pedestal',(x,y,.49),(.14,.20,.86),paint)
        cyl('Foot bolt',(x,y,.12),(x,y,.16),.027,steel)
    cyl('Bearing housing',(0,y-.10,.95),(0,y+.10,.95),.16,dark)
box('Base tie',(0,0,.17),(.22,1.75,.17),paint)
cyl('Hydraulic motor',(0,-1.16,.95),(0,-.97,.95),.24,paint)
for z in [.85,1.06]:
    cyl('Hydraulic feed',(.18,-1.08,z),(.42,-1.08,z),.025,dark)
box('Hydraulic manifold',(.32,-1.08,.28),(.52,.34,.32),paint)
for index,z in enumerate([.85,1.06]):
    curve=bpy.data.curves.new('Hydraulic hose','CURVE');curve.dimensions='3D';curve.bevel_depth=.022;curve.bevel_resolution=2
    spline=curve.splines.new('BEZIER');spline.bezier_points.add(3)
    for p,co in zip(spline.bezier_points,[(.42,-1.08,z),(.57+index*.09,-1.08,z-.07),(.57+index*.09,-1.08,.48),(.34+index*.12,-1.08,.45)]):
        p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    o=bpy.data.objects.new('Flexible hydraulic hose',curve);bpy.context.collection.objects.link(o);o.data.materials.append(dark)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
socket('DrumPivot',(0,0,.95));socket('PayoutSocket',(.40,0,.95))
socket('PayoutPort',(.32,-.43,.95));socket('PayoutStarboard',(.32,.43,.95))
save('trawl_winch')
clear()
cyl('Drum barrel',(0,-.72,0),(0,.72,0),.29,dark)
for y in [-.74,.74]:
    cyl('Drum flange',(0,y-.035,0),(0,y+.035,0),.48,paint)
    cyl('Axle',(0,y-.18,0),(0,y+.18,0),.08,steel)
# Two coupled warp bays retain one shaft/pivot; not independently powered drums.
cyl('Central drum divider',(0,-.028,0),(0,.028,0),.44,paint)
for side in [-1,1]:
    curve=bpy.data.curves.new('Wound warp','CURVE');curve.dimensions='3D';curve.bevel_depth=.013;curve.bevel_resolution=2
    s=curve.splines.new('POLY');n=840;s.points.add(n)
    for i,p in enumerate(s.points):
        t=i/n;a=t*2*math.pi*17;p.co=(.315*math.cos(a),side*.385-.31+.62*t,.315*math.sin(a),1)
    o=bpy.data.objects.new('Wound warp',curve);bpy.context.collection.objects.link(o);o.data.materials.append(rope)
    bpy.ops.object.select_all(action='DESELECT');bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH')
socket('DrumAxis',(0,0,0));save('trawl_drum')
clear()
# Compact above-deck insulated catch tank; closed lid avoids implying a hole in
# the continuous hull deck. Inventory and hose endpoints live in CatchHoldComponent.
for x in [-.67,.67]:box('Tank side',(x,0,.43),(.10,1.2,.78),paint)
for y in [-.55,.55]:box('Tank end',(0,y,.43),(1.24,.10,.78),paint)
box('Insulated floor',(0,0,.10),(1.4,1.2,.14),paint)
for x in [-.54,.54]:box('Skid',(x,0,.03),(.16,1.1,.06),dark)
cyl('Discharge pipe',(.7,0,.3),(.88,0,.3),.065,steel)
cyl('Hose flange',(.87,0,.3),(.91,0,.3),.10,steel)
socket('PumpConnection',(.92,0,.3));socket('HoseDrop',(.92,0,.3));socket('LidMount',(0,0,.84))
save('insulated_catch_tank')
clear();box('Insulated removable lid',(0,0,.04),(1.44,1.24,.08),paint)
for x in [-.4,.4]:
    for y in [-.10,.10]:cyl('Handle riser',(x,y,.08),(x,y,.13),.015,steel)
    cyl('Lifting handle',(x,-.1,.13),(x,.1,.13),.015,steel)
save('catch_tank_lid')
assets=[]
for id,style,height,components in [
 ('trawl_winch','winch',1.43,[{'id':'trawl_drum','pivot':'DrumPivot'}]),
 ('trawl_drum','winch_drum',.96,[]),
 ('insulated_catch_tank','catch_tank',1.0,[{'id':'catch_tank_lid','pivot':'LidMount'}]),
 ('catch_tank_lid','tank_lid',.15,[])]:
    assets.append({'id':id,'style':style,'kind':'furniture','model':'res://resources/models/parts/fishing_kit/'+id+'.glb','start_xz':[0,0],'end_xz':[1.4,1.2],'height_start_m':height,'height_end_m':height,'paintable':True,'components':components})
(OUT/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2))
print('FISHING_KIT_EXPORTED')
