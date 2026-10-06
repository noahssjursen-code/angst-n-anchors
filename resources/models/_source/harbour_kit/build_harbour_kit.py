"""Individual harbour components, metres. Blender +Y exports to Godot -Z.
Quay pieces: X along edge, +Y water, Z=0 pavement. No baked layout.
"""
import bpy, math
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
OUT=HERE.parents[1]/'parts/harbour_kit'
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
clear()
# 2m flush coping; the outside face descends rather than creating a trip kerb.
box('Precast coping',(0,-.3,-.20),(1.99,.60,.40),concrete,.008)
box('Steel nosing',(0,-.025,-.03),(1.995,.05,.06),steel,.003)
for x in [-.65,.65]:rod('Recessed lifting plug',(x,-.32,-.002),(x,-.32,.001),.025,dark,12)
socket('Start',(-1,0,0));socket('End',(1,0,0));export('quay_coping_2m')
clear()
# Hollow arch rubber profile, extruded vertically; flange fasteners on both feet.
profile=[(-.39,0),(-.25,0),(-.15,.28),(.15,.28),(.25,0),(.39,0),(.26,.46),(-.26,.46)]
verts=[(x,y,z) for z in [-1.65,-.15] for x,y in profile];n=len(profile)
faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh('Hollow moulded arch',verts,faces,rubber)
for x in [-.32,.32]:
    for z in [-1.45,-.9,-.35]:
        rod('Anchor washer',(x,.012,z),(x,.05,z),.042,steel)
        rod('Anchor nut',(x,.05,z),(x,.075,z),.027,steel,6)
export('arch_fender')
clear()
# Clear 0.52m between rails; 0.30m rung pitch, offset off quay face.
for x in [-.29,.29]:
    rod('Ladder stringer',(x,.23,-2.7),(x,.23,.8),.032,yellow)
    rod('Handhold return',(x,.23,.8),(x,-.28,.8),.032,yellow)
    rod('Top return leg',(x,-.28,.8),(x,-.28,.06),.032,yellow)
    box('Deck bracket',(x,-.28,.025),(.16,.20,.05),steel)
    for z in [-2.4,-1.2,-.2]:
        rod('Stand off',(x,0,z),(x,.23,z),.035,steel)
        box('Wall plate',(x,-.015,z),(.13,.04,.20),steel)
for i in range(10):
    z=-2.55+i*.3;rod('Non slip rung',(-.29,.23,z),(.29,.23,z),.022,steel)
export('quay_ladder')
clear()
box('Pole base',(0,0,.06),(.38,.38,.12),dark)
for x in [-.13,.13]:
    for y in [-.13,.13]:rod('Anchor',(x,y,.12),(x,y,.17),.024,steel,6)
rod('Tapered column',(0,0,.12),(0,0,7.5),.105,steel,r2=.055)
box('Service hatch',(0,-.10,.65),(.12,.035,.32),dark)
rod('Outreach',(0,0,7.4),(0,1.1,7.65),.043,steel)
box('Luminaire',(0,1.20,7.64),(.44,.85,.12),dark,.04)
box('LED lens',(0,1.2,7.573),(.35,.69,.018),white,.015)
socket('Light',(0,1.2,7.5));export('quay_light')
clear()
# Drain gutter sits flush; grate bars are recessed rather than floating.
box('Gutter frame',(0,0,-.055),(2,.32,.11),dark,.004)
for i in range(40):box('Grate rib',(-.975+i*.05,0,.002),(.018,.30,.014),steel,.002)
export('drain_2m')
clear()
# 12 x 18m industrial envelope with vertical profiled cladding, real trim,
# independent future door pivot socket. Solid shell: no promised interior.
box('Concrete plinth',(0,0,.20),(12,18,.4),concrete,.025)
box('Building envelope',(0,0,2.8),(11.92,17.92,5.2),wall,.012)
for x in [-6,6]:
    for i in range(61):box('Side standing seam',(x,-9+i*.3,2.9),(.045,.045,5.0),wall,.004)
for y in [-9,9]:
    for i in range(41):box('End standing seam',(-6+i*.3,y,2.9),(.045,.045,5.0),wall,.004)
# Roof and gable end are explicit pitched geometry, not a squashed cube.
for side in [-1,1]:
    o=box('Pitched roof',(side*3.15,0,5.94),(6.51,18.7,.12),roof,.005)
    o.rotation_euler.y=side*math.radians(15)
for y in [-9.02,9.02]:mesh('Gable infill',[(-6,y,5.4),(6,y,5.4),(0,y,6.78)],[(0,1,2),(2,1,0)],wall)
rod('Ridge cap',(0,-9.36,6.79),(0,9.36,6.79),.10,roof)
for x in [-6.23,6.23]:
    box('Eaves gutter',(x,0,5.15),(.16,18.6,.14),steel)
    for y in [-8.6,8.6]:rod('Downpipe',(x,y,5.15),(x,y,.20),.065,steel)
# Loading front is Blender -Y -> Godot +Z, towards pier.
box('Roller door surround',(-1.5,-9.08,2.37),(4.5,.20,4.4),white)
box('Roller door',(-1.5,-9.20,2.35),(4.1,.08,4.12),dark)
for i in range(20):box('Door slat',(-1.5,-9.25,.42+i*.202),(4.04,.025,.025),steel,.002)
box('Personnel surround',(3.5,-9.09,1.4),(1.3,.16,2.35),white)
box('Personnel door',(3.5,-9.19,1.4),(1.1,.06,2.15),roof)
rod('Door handle',(3.86,-9.26,1.23),(3.86,-9.26,1.43),.016,steel)
for x in [-4.8,3.5]:
    box('Window trim',(x,-9.08,4.25),(1.25,.12,.85),white)
    box('Window',(x,-9.15,4.25),(1.09,.035,.68),glass)
    box('Mullion',(x,-9.18,4.25),(.035,.025,.7),steel)
box('Loading canopy',(-1.5,-10.1,4.85),(5.4,2.2,.14),roof)
for x in [-3.9,.9]:rod('Canopy brace',(x,-9.1,3.7),(x,-10.9,4.76),.045,steel)
socket('LoadingDoor',(-1.5,-9.3,0));socket('PersonnelDoor',(3.5,-9.3,0))
export('warehouse_12x18')
