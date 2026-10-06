"""Reusable mooring and unloading hardware; metres, Blender +Z up/+Y forward."""
import bpy, math
from mathutils import Vector
from pathlib import Path
HERE=Path(__file__).resolve().parent;OUT=HERE.parents[1]/'parts/port_kit';OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
def mat(n,c,metal=.6):
    m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48;return m
paint=mat('Warm white painted steel',(.14,.22,.23));steel=mat('Fixed_Galvanized',(.47,.53,.55))
dark=mat('Fixed_DarkMetal',(.06,.085,.095));yellow=mat('Paint_Bollard',(.75,.46,.07),.25)
rubber=mat('Fixed_Rubber',(.025,.033,.04),0)
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(n,p,s,m=steel):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    mod=o.modifiers.new('Manufactured edge','BEVEL');mod.width=.012;mod.segments=2
    bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name);return o
def rod(n,a,b,r,m=steel,v=24,r2=None):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=v,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m);return o
def socket(n,p):
    o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=p
def export(n):
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.object.name=n
    bpy.ops.object.select_all(action='SELECT');bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(n+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(n+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
clear()
box('Bitt foundation',(0,0,.045),(.8,.42,.09),dark)
for x in [-.24,.24]:
    rod('Bitt',(x,0,.09),(x,0,.61),.092,steel)
    rod('Cap',(x,0,.61),(x,0,.65),.13,steel)
rod('Cross horn',(-.45,0,.51),(.45,0,.51),.046,steel)
for x in [-.33,.33]:
    for y in [-.15,.15]:rod('Stud',(x,y,.09),(x,y,.12),.027,steel,6)
socket('RopeAnchor',(0,0,.52));export('deck_double_bitt')
clear()
box('Quay anchor flange',(0,0,.05),(.60,.58,.10),yellow)
rod('Tee neck',(0,0,.10),(0,0,.55),.16,yellow,r2=.12)
box('Tee crown',(0,0,.64),(.60,.29,.20),yellow)
for x in [-.23,.23]:
    for y in [-.21,.21]:
        rod('Anchor washer',(x,y,.102),(x,y,.116),.048,dark)
        rod('Anchor nut',(x,y,.116),(x,y,.155),.032,steel,6)
socket('RopeAnchor',(0,0,.52));export('quay_tee_bollard')
# Pump modules share the original plant's origin and hose connection; no capacity change.
clear()
for y in [-2.05,2.05]:box('Skid rail',(-.15,y,.65),(7.6,.18,.18))
for x in [-3.75,3.45]:box('Cross rail',(x,0,.65),(.18,4.3,.18))
for x in [-3.35,3.05]:
    for y in [-1.78,1.78]:
        rod('Tyre',(x,y-.17,.54),(x,y+.17,.54),.54,rubber,32)
        rod('Wheel hub',(x,y-.18,.54),(x,y+.18,.54),.22,steel)
for x in [-2.6,2.3]:
    for y in [-1.55,1.55]:box('Separator support',(x,y,2.22),(.16,.16,3.45))
for y in [-1.55,1.55]:rod('Diagonal',(-2.6,y,.78),(2.3,y,3.82),.07)
socket('SeparatorMount',(-.2,0,3.35));export('landing_skid')
clear()
axis=Vector((math.sin(math.radians(72)),0,math.cos(math.radians(72))));center=Vector((-.2,0,3.35))
rod('Vacuum separator',center-axis*2.4,center+axis*2.4,1.05)
for t in [-1.4,1.4]:rod('Retaining band',center+axis*(t-.08),center+axis*(t+.08),1.075,dark)
rod('Inspection cover',(-1.65,.98,3.04),(-1.65,1.12,3.04),.34,dark)
for a in range(0,360,45):
    t=math.radians(a);x=-1.65+.27*math.cos(t);z=3.04+.27*math.sin(t)
    rod('Cover fastener',(x,1.12,z),(x,1.15,z),.023,steel,6)
for a,b in [((-2.35,0,2.65),(-2.8,0,2.1)),((-2.8,0,2.1),(-3.3,0,1.72))]:rod('Discharge',a,b,.24)
export('landing_separator')
clear()
rod('Motor',(1.0,.82,1.35),(2.45,.82,1.35),.48,paint)
for i in range(10):rod('Cooling fin',(1.05+i*.13,.82,1.35),(1.09+i*.13,.82,1.35),.54,paint)
rod('Pump casing',(2.35,.82,1.35),(3.1,.82,1.35),.60,dark)
rod('Suction pipe',(3.1,.82,1.35),(3.70,.82,1.35),.16)
rod('Suction flange',(3.66,.82,1.35),(3.72,.82,1.35),.24,dark)
pipe=[(3.0,.82,1.7),(3.35,.82,2.05),(3.35,.82,3.78),(2.15,.52,4.58),(1.45,.18,4.48)]
for a,b in zip(pipe,pipe[1:]):rod('Separator inlet pipe',a,b,.18)
for x in [1.15,2.35]:box('Motor foot',(x,.82,.96),(.16,.65,.75))
box('Control cabinet',(1.65,-1.52,1.78),(1.05,.58,1.75),paint)
box('Control panel',(1.65,-1.82,2.15),(.78,.025,.44),dark)
for i in range(3):rod('Control button',(1.36+i*.28,-1.84,1.75),(1.36+i*.28,-1.90,1.75),.055,yellow)
socket('HoseConnection',(3.72,.82,1.35));export('landing_pump_drive')
clear()
box('Trough floor',(-3.35,0,1.02),(2.45,2.65,.12),dark)
for y in [-1.32,1.32]:box('Trough side',(-3.35,y,1.40),(2.55,.12,.78))
box('Trough end',(-4.58,0,1.40),(.12,2.65,.78))
for x in [-4.35,-2.4]:
    for y in [-1.1,1.1]:box('Trough leg',(x,y,.52),(.1,.1,.98))
socket('FillDatum',(-3.28,0,1.10));export('landing_trough')
print('PORT_KIT_EXPORTED: six independent Blender/GLB parts')
