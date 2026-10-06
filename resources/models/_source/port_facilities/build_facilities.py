"""Individual harbour components, metres. Blender +Y exports to Godot -Z.
Quay pieces: X along edge, +Y water, Z=0 pavement. No baked layout.
"""
import bpy, math
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
OUT=HERE.parents[1]/'parts/port_facilities'
OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
def material(name,color,metal=0,rough=.7):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m
concrete=material('Concrete',(.43,.43,.39),0,.95)
steel=material('Galvanized',(.42,.49,.50),.75,.4)
dark=material('Dark steel',(.055,.075,.08),.65,.5)
rubber=material('Rubber',(.025,.029,.03),0,.9)
yellow=material('Safety yellow',(.85,.56,.07),.1,.55)
wall=material('Wall paint',(.25,.34,.35),.25,.7)
roof=material('Roof paint',(.095,.135,.15),.45,.6)
glass=material('Fixed glass',(.09,.19,.23),.5,.2)
white=material('Light diffuser',(.9,.92,.83),0,.3)
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(name,p,s,mat,bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
    if bevel:
        m=o.modifiers.new('Edge radii','BEVEL');m.width=bevel;m.segments=2
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o
def rod(name,a,b,r,mat,vertices=20,r2=None):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(mat)
    for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
    return o
def mesh(name,verts,faces,mat):
    m=bpy.data.meshes.new(name);m.from_pydata(verts,[],faces);m.update()
    o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);o.data.materials.append(mat);return o
def socket(name,p):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=p
def export(name):
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join()
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.object.name=name
    bpy.ops.object.select_all(action='SELECT');bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)

red=material('Office cladding',(.26,.065,.043),0,.75)
cream=material('Ivory trim',(.72,.70,.59),0,.65)
timber=material('Dunnage timber',(.24,.16,.075),0,.9)
def text_obj(text,p,size,mat):
    bpy.ops.object.text_add(location=p,rotation=(math.pi/2,0,0))
    o=bpy.context.object;o.data.body=text;o.data.align_x='CENTER';o.data.size=size;o.data.extrude=.003
    o.data.materials.append(mat);bpy.ops.object.convert(target='MESH')
clear()
# Office: single storey, 12 x 8m. Entrance front -Y. Fixed exterior assembly.
box('Plinth',(0,0,.12),(12,8,.24),concrete,.02)
box('Office body',(0,0,1.8),(11.9,7.9,3.36),red,.006)
for y in [-4,4]:
    for i in range(61):box('Timber cover strip',(-6+i*.2,y,1.9),(.04,.035,3.25),red,.003)
for x in [-6,6]:
    for i in range(41):box('Timber cover strip',(x,-4+i*.2,1.9),(.035,.04,3.25),red,.003)
for x in [-5.94,5.94]:
    for y in [-3.94,3.94]:box('Corner boards',(x,y,1.85),(.16,.16,3.42),cream)
for side in [-1,1]:
    o=box('Roof slope',(side*3.12,0,4.18),(6.55,8.8,.13),roof,.008);o.rotation_euler.y=side*math.radians(13)
for y in [-4.01,4.01]:mesh('Gable',[(-6,y,3.49),(6,y,3.49),(0,y,4.90)],[(0,1,2),(2,1,0)],red)
rod('Ridge',(0,-4.43,4.9),(0,4.43,4.9),.085,roof)
for x in [-6.25,6.25]:
    box('Gutter',(x,0,3.48),(.16,8.7,.14),steel)
    for y in [-3.6,3.6]:rod('Downpipe',(x,y,3.5),(x,y,.20),.05,steel)
for y in [-4.06,4.06]:
    for x in [-4,-1.7,1.7,4]:
        box('Window surround',(x,y,2.05),(1.65,.14,1.5),cream)
        box('Window glass',(x,y+(.08 if y>0 else -.08),2.05),(1.43,.035,1.28),glass)
        box('Mullion',(x,y+(.105 if y>0 else -.105),2.05),(.06,.03,1.3),cream)
        box('Sill',(x,y,1.30),(1.76,.28,.06),cream)
box('Entry frame',(0,-4.11,1.35),(1.65,.20,2.4),cream)
box('Glass entry',(0,-4.23,1.35),(1.4,.07,2.16),glass)
rod('Pull handle',(.48,-4.3,1.15),(.48,-4.3,1.6),.021,steel)
box('Entrance landing',(0,-4.85,.11),(2.5,1.6,.22),concrete)
box('Porch roof',(0,-4.90,3.12),(3.1,2.1,.14),roof)
for x in [-1.25,1.25]:rod('Porch support',(x,-5.5,.22),(x,-5.5,3.1),.045,steel)
box('Office sign',(0,-4.12,3.45),(4.6,.16,.48),dark)
text_obj('HARBOUR OFFICE',(0,-4.215,3.30),.32,cream)
box('Notice cabinet',(2.3,-4.18,.82),(1.2,.14,.72),dark)
for x in [1.96,2.32,2.68]:box('Notice sheet',(x,-4.26,.83),(.27,.012,.49),cream,.001)
socket('PublicEntrance',(0,-5.8,0));export('harbour_office')
clear()
# 8 x 8m open-sided cargo shelter, repeatable without a solid box enclosure.
for x in [-3.7,3.7]:
    for y in [-3.7,3.7]:
        box('Column base',(x,y,.045),(.42,.42,.09),steel)
        box('Column',(x,y,2.55),(.16,.16,5.1),dark)
        for dx in [-.13,.13]:rod('Anchor',(x+dx,y,.09),(x+dx,y,.14),.022,steel,6)
for y in [-3.7,0,3.7]:
    box('Roof beam',(0,y,4.98),(7.65,.15,.25),dark)
    for side in [-1,1]:rod('Knee brace',(side*3.7,y,4),(side*2.7,y,5),.043,steel)
for x in [-3.75,3.75]:box('Eave beam',(x,0,5.08),(.14,8,.2),dark)
o=box('Single pitch roof',(0,0,5.28),(8.4,8.4,.10),roof,.005);o.rotation_euler.x=.05
for i in range(22):
    o=box('Roof seam',(-4.1+i*.39,0,5.345),(.03,8.4,.028),roof,.002);o.rotation_euler.x=.05
export('cargo_shelter_8m')
clear()
box('Kerb',(0,0,.10),(1.98,.22,.20),concrete,.025);export('kerb_2m')
clear()
box('Parking stop',(0,0,.085),(1.65,.17,.17),concrete,.035)
for x in [-.58,.58]:rod('Anchor',(x,0,.15),(x,0,.18),.025,dark,6)
export('wheel_stop')
clear()
# Straight divider, no side bevel on mating end faces.
box('Concrete foot',(0,0,.15),(4,1.0,.30),concrete,.005)
box('Divider',(0,0,1.35),(4,.32,2.4),concrete,.006)
for x in [-1.25,1.25]:
    box('Wall tie recess',(x,-.168,1.3),(.075,.01,.075),dark,.002)
export('bulk_divider_4m')
clear()
for x in [-2,2]:
    box('Fence post',(x,0,1.1),(.065,.065,2.2),steel)
    box('Foot',(x,0,.035),(.20,.20,.07),steel)
for z in [.20,2.10]:rod('Fence rail',(-2,0,z),(2,0,z),.022,steel)
for i in range(21):rod('Vertical infill',(-2+i*.2,0,.2),(-2+i*.2,0,2.1),.007,steel,6)
for i in range(10):rod('Horizontal infill',(-2,0,.2+i*.2),(2,0,.2+i*.2),.007,steel,6)
export('yard_fence_4m')
clear()
box('Pallet runners',(0,0,.08),(1.2,.8,.16),timber,.006)
for i in range(5):box('Top board',(-.49+i*.245,0,.185),(.19,.8,.05),timber,.004)
export('empty_pallet')
clear()
# Grain hopper silo: independent legs, hopper, corrugated cylinder and conical roof.
for i in range(6):
    a=i*math.tau/6;x,y=2.2*math.cos(a),2.2*math.sin(a)
    box('Leg shoe',(x,y,.07),(.48,.48,.14),concrete)
    rod('Support leg',(x,y,.14),(x,y,3.6),.10,steel)
rod('Hopper',(0,0,1.15),(0,0,3.2),.30,steel,48,r2=2.55)
rod('Storage cylinder',(0,0,3.2),(0,0,10),2.55,steel,64)
for i in range(24):
    z=3.25+i*.28
    bpy.ops.mesh.primitive_torus_add(major_radius=2.55,minor_radius=.018,major_segments=64,minor_segments=6,location=(0,0,z));bpy.context.object.data.materials.append(steel)
rod('Conical roof',(0,0,10),(0,0,11.3),2.65,roof,64,r2=.1)
rod('Discharge pipe',(0,0,.45),(0,0,1.2),.18,dark)
for x in [-.25,.25]:rod('Access ladder',(x,-2.7,.3),(x,-2.7,10),.025,steel)
for i in range(32):rod('Rung',(-.25,-2.7,.4+i*.3),(.25,-2.7,.4+i*.3),.017,steel)
export('grain_silo')
clear()
# Atmospheric liquid storage, fixed process artwork, no invented inventory.
box('Tank footing',(0,0,.12),(6.5,6.5,.24),concrete)
rod('Tank wall',(0,0,.24),(0,0,6.2),3,cream,64)
rod('Roof',(0,0,6.2),(0,0,6.6),3.08,cream,64,r2=.2)
for z in [2.1,4.1,6.15]:
    bpy.ops.mesh.primitive_torus_add(major_radius=3.0,minor_radius=.025,major_segments=64,minor_segments=8,location=(0,0,z));bpy.context.object.data.materials.append(steel)
rod('Outlet',(0,-2.95,.8),(0,-3.7,.8),.12,steel)
rod('Vent',(0,0,6.6),(0,0,7.0),.10,dark)
for x in [-.3,.3]:rod('Ladder',(x,3.2,.25),(x,3.2,6.7),.03,steel)
for i in range(21):rod('Rung',(-.3,3.2,.4+i*.3),(.3,3.2,.4+i*.3),.02,steel)
export('liquid_tank')
clear()
# Insulated horizontal vessel family to distinguish LNG from atmospheric tanks.
for y in [-2.5,2.5]:box('Saddle',(0,y,.55),(3.3,.65,1.1),concrete)
rod('Insulated vessel',(0,-3.4,2.1),(0,3.4,2.1),1.6,white,64)
for y in [-3.4,3.4]:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48,ring_count=24,radius=1,location=(0,y,2.1));o=bpy.context.object;o.scale=(1.6,.65,1.6);o.data.materials.append(white)
rod('Relief riser',(0,0,3.65),(0,0,4.6),.06,steel)
box('Valve cabinet',(2.2,-2.5,.9),(.8,1.2,1.8),steel)
export('insulated_gas_vessel')
