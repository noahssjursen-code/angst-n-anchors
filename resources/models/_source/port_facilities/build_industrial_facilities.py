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


# Expanded terminal kit. All dimensions are metres; each asset stays independent.
ivory=material('Office render',(.61,.63,.60),0,.85)
blue=material('Office metalwork',(.10,.18,.23),.4,.55)
timber=material('Pallet timber',(.32,.22,.12),0,.9)
orange=material('Rack safety orange',(.72,.22,.025),.25,.6)

def label(text,p,size,mat):
    bpy.ops.object.text_add(location=p,rotation=(math.pi/2,0,0))
    o=bpy.context.object;o.data.body=text;o.data.align_x='CENTER';o.data.size=size;o.data.extrude=.004
    o.data.materials.append(mat);bpy.ops.object.convert(target='MESH')

clear()
# Four-storey administration/control building, 20 x 14m, upper glazed watch floor.
box('Concrete plinth',(0,0,.2),(20.4,14.4,.4),concrete,.035)
box('Office floors',(0,0,5.2),(20,14,10),ivory,.025)
for z in [3.5,6.8,10.15]:box('Floor string course',(0,0,z),(20.18,14.18,.16),ivory,.015)
for floor in range(3):
    z=1.85+floor*3.3
    for y in [-7.04,7.04]:
        for x in [-8,-5,-2,2,5,8]:
            if floor==0 and y<0 and abs(x)<3:continue
            box('Window reveal',(x,y,z),(1.7,.18,1.95),blue,.008)
            box('Fixed glazing',(x,y+(.10 if y>0 else -.10),z),(1.5,.025,1.74),glass,.002)
            box('Window sill',(x,y,z-.97),(1.85,.36,.10),ivory,.012)
    for x in [-10.05,10.05]:
        for y in [-4.8,-1.6,1.6,4.8]:
            box('Side reveal',(x,y,z),(.18,1.7,1.95),blue,.008)
            box('Side glazing',(x+(.10 if x>0 else -.10),y,z),(.025,1.5,1.74),glass,.002)
box('Watch floor',(0,0,11.5),(20.7,14.7,2.7),blue,.02)
for y in [-7.4,7.4]:
    for i in range(10):
        x=-9.45+i*2.1
        box('Watch glazing',(x,y,11.65),(1.97,.08,2.15),glass,.005)
        box('Watch mullion',(x-1.03,y,11.65),(.09,.18,2.38),ivory,.007)
for x in [-10.4,10.4]:
    for i in range(7):box('Side watch glazing',(x,-6.3+i*2.1,11.65),(.08,1.98,2.15),glass,.005)
# Hipped roof, generous eaves and real thickness.
verts=[(-11.2,-8.2,13),(11.2,-8.2,13),(11.2,8.2,13),(-11.2,8.2,13),(-3,0,16),(3,0,16)]
mesh('Hipped roof',verts,[(0,1,5,4),(1,2,5),(2,3,4,5),(3,0,4)],roof)
for a,b in [(0,1),(1,2),(2,3),(3,0)]:rod('Eaves',verts[a],verts[b],.09,blue)
rod('Roof ridge',(-3,0,16),(3,0,16),.08,steel)
for x in [-10.15,10.15]:
    for y in [-6.8,6.8]:rod('Downpipe',(x,y,.3),(x,y,12.9),.065,blue)
box('Entrance surround',(0,-7.12,1.7),(3.5,.35,3.0),blue)
box('Entrance glass',(0,-7.33,1.7),(3.16,.06,2.66),glass)
box('Door middle',(0,-7.4,1.7),(.08,.07,2.7),steel)
for x in [-.22,.22]:rod('Door handle',(x,-7.48,1.2),(x,-7.48,1.8),.025,steel)
box('Entrance canopy',(0,-8.3,3.45),(5,2.9,.18),blue,.025)
for x in [-2.25,2.25]:rod('Canopy column',(x,-9.4,0),(x,-9.4,3.45),.07,steel)
box('Entrance landing',(0,-8.4,.1),(5,2.8,.2),concrete,.02)
label('HARBOUR AUTHORITY',(0,-7.14,9.4),.55,blue)
# Rear escape flights and landings, readable from the harbour side.
for level in range(3):
    base=level*3.3
    for i in range(17):box('Escape tread',(-7+i*.38,7.9,base+i*.194+.18),(.42,1.5,.10),steel,.004)
    box('Escape landing',(-.5,7.9,base+3.3),(1.8,1.7,.15),steel)
    for y in [7.2,8.65]:
        rod('Stair handrail',(-7,y,base+1.1),(-.6,y,base+4.25),.026,steel)
        for i in range(5):rod('Baluster',(-7+i*1.4,y,base+i*.715+.15),(-7+i*1.4,y,base+i*.715+1.1),.022,steel)
rod('Aerial mast',(0,0,15.9),(0,0,20.5),.05,steel)
for z in [18,19,20]:rod('Antenna',(-.65,0,z),(.65,0,z),.018,steel)
socket('PublicEntrance',(0,-10,0));export('harbour_authority_20m')

clear()
# Open pallet, genuine fork openings. Stacks instance this small model.
for x in [-.47,0,.47]:
    for y in [-.30,.30]:box('Block',(x,y,.075),(.15,.15,.15),timber,0)
for x in [-.47,0,.47]:box('Bottom bearer',(x,0,.025),(.15,.8,.05),timber,0)
for i in range(5):box('Top board',(-.49+i*.245,0,.175),(.19,.8,.05),timber,0)
export('yard_pallet')
clear()
for x in [-1.5,1.5]:
    for y in [-.6,.6]:
        box('Rack upright',(x,y,2.4),(.09,.09,4.8),blue,0)
        box('Base plate',(x,y,.04),(.26,.26,.08),orange,0)
    for z in [1,2.5,4.3]:rod('Rack diagonal',(x,-.6,z-.7),(x,.6,z+.7),.025,steel,6)
for z in [.3,1.8,3.3]:
    for y in [-.6,.6]:box('Shelf beam',(0,y,z),(3.08,.08,.15),orange,0)
    box('Shelf',(0,0,z+.09),(2.95,1.2,.06),steel,0)
    for x in [-.95,0,.95]:
        box('Wrapped pallet load',(x,0,z+.68),(.86,1.03,1.1),ivory,.01)
        for y in [-.52,.52]:box('Packing band',(x,y,z+.68),(.055,.014,1.1),timber,0)
export('loaded_storage_rack')

clear()
# Large LNG terminal storage tank: 24m diameter, 22m shell, domed roof and service ring.
rod('Concrete ring',(0,0,0),(0,0,.65),12.4,concrete,96)
rod('Insulated outer shell',(0,0,.65),(0,0,22.2),12,ivory,96)
for z in [5,10,15,20,22.2]:
    bpy.ops.mesh.primitive_torus_add(major_radius=12,minor_radius=.045,major_segments=96,minor_segments=6,location=(0,0,z));bpy.context.object.data.materials.append(steel)
rod('Low domed roof',(0,0,22.2),(0,0,25.2),12.1,ivory,96,r2=1.0)
rod('Roof vent',(0,0,25.1),(0,0,27),.22,steel)
for i in range(48):
    a=i*math.tau/48
    rod('Roof guardrail post',(11.7*math.cos(a),11.7*math.sin(a),22.35),(11.7*math.cos(a),11.7*math.sin(a),23.45),.035,steel,8)
for z in [22.9,23.45]:
    bpy.ops.mesh.primitive_torus_add(major_radius=11.7,minor_radius=.035,major_segments=96,minor_segments=6,location=(0,0,z));bpy.context.object.data.materials.append(steel)
for x in [-.35,.35]:rod('Service ladder',(x,-12.25,.2),(x,-12.25,23.5),.045,steel)
for i in range(76):rod('Ladder rung',(-.35,-12.25,.3+i*.3),(.35,-12.25,.3+i*.3),.022,steel,8)
for x in [-2,2]:
    rod('Transfer riser',(x,-12.4,1.0),(x,-12.4,20),.20,steel)
    rod('Transfer pipe',(x,-12.4,1.0),(x,-15,1.0),.20,steel)
    rod('Pipe flange',(x,-14.8,1.0),(x,-15,1.0),.32,steel)
box('Service platform',(0,-13.8,.40),(6,3,.8),concrete)
export('lng_terminal_tank_24m')
