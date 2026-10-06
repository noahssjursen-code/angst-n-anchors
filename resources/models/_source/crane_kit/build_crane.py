"""Separate metre-scale harbour crane parts. Blender +Y outreach, +Z up.
Existing gameplay contract: 30 m boom, 10 m rest wire, mouth 1.6 m below hook.
"""
import bpy, math
from mathutils import Vector, Matrix
from pathlib import Path
HERE=Path(__file__).resolve().parent
OUT=HERE.parents[1]/'parts/crane_kit';OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
def mat(n,c,metal=.3):
    m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48
    return m
paint=mat('Warm white painted steel',(.66,.42,.075));steel=mat('Fixed_DarkSteel',(.065,.085,.10),.65)
glass=mat('Fixed_CabinGlass',(.12,.26,.31),.35);silver=mat('Fixed_PinSteel',(.38,.43,.46),.8)
glass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.28
glass.diffuse_color=(.12,.26,.31,.28);glass.surface_render_method='DITHERED'
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(n,p,s,m=paint):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m);return o
def rod(n,a,b,r,m=paint,verts=12):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m);return o
def socket(n,p):
    o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=p;return o
def export(n):
    # One origin-centred mesh per GLB; cable length scales about its upper endpoint.
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.context.object.name=n
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(n+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(n+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
clear()
box('Anchor plate',(0,0,.13),(3.6,3.6,.26),steel)
rod('Pedestal',(0,0,.26),(0,0,2.12),1.12)
rod('Slew race',(0,0,2.12),(0,0,2.29),1.35,steel,48)
for x in [-1.5,1.5]:
    for y in [-1.5,1.5]:rod('Anchor stud',(x,y,.26),(x,y,.36),.09,silver)
socket('SlewAxis',(0,0,2.29));export('crane_pedestal')
clear()
box('Service deck',(-.95,-.55,-.06),(4.2,4,.12),steel)
box('Cab lower apron',(0,.13,.24),(1.65,1.7,.48))
box('Cab roof',(0,.13,1.72),(1.85,1.92,.12))
for x in [-.79,.79]:
    for y in [-.66,.92]:rod('Window mullion',(x,y,.48),(x,y,1.68),.045)
box('Windscreen',(0,.915,1.08),(1.49,.035,1.12),glass)
for x in [-.79,.79]:box('Side glass',(x,.13,1.08),(.035,1.47,1.12),glass)
box('Rear door',(0,-.67,.95),(1.5,.07,1.4))
box('Seat',(0,-.32,.42),(.55,.5,.12),steel)
box('Seat back',(0,-.54,.73),(.55,.08,.55),steel)
box('Control desk',(0,.52,.75),(1.3,.38,.24),steel)
box('Machinery housing',(-1.9,-1,.78),(1.9,2.7,1.55))
for i in range(9):box('Cooling louvre',(-2.864,-1,.35+i*.11),(.035,1.8,.045),steel)
for x in [-2.5,-1.0]:
    rod('Mast upright',(x,.25,0),(x,.25,3.7),.17)
    rod('Mast brace',(x,-1.9,.1),(x,.25,3.7),.12)
rod('Boom hinge',(-2.65,.25,3.7),(-.85,.25,3.7),.23,silver,24)
for x in [-1.98,-1.52]:
    rod('Cylinder lower support',(x,.25,.15),(x,2,1.2),.13)
    rod('Cylinder upper support',(x,.25,2.7),(x,2,1.2),.13)
rod('Cylinder fixed clevis',(-2.05,2,1.2),(-1.45,2,1.2),.18,steel)
for x in [-2.98,1.08]:
    for y in [-2.48,-1.6]:rod('Guard post',(x,y,0),(x,y,1.05),.035,silver)
    rod('Service guard',(x,-2.48,1.05),(x,-1.6,1.05),.035,silver)
rod('Rear guard',(-2.98,-2.48,1.05),(1.08,-2.48,1.05),.035,silver)
socket('BoomHinge',(-1.75,.25,3.7));socket('OperatorSeat',(0,-.32,.42));export('crane_cabin')
clear()
def corners(y):
    w=.72-(y/30)*.43;h=.58-(y/30)*.30
    return [(-w,y,-h),(w,y,-h),(w,y,h),(-w,y,h)]
for k in range(10):
    a,b=corners(k*3),corners((k+1)*3)
    for j in range(4):
        rod('Chord',a[j],b[j],.085)
        rod('Diagonal',a[j],b[(j+1)%4],.044)
        rod('Frame',a[j],a[(j+1)%4],.055)
for x in [-.21,.21]:rod('Tip sheave',(x-.045,30,0),(x+.045,30,0),.34,steel,32)
socket('HoistTop',(0,30,0));export('crane_boom_30m')
clear()
rod('Luff cylinder',(0,0,0),(0,0,3.8),.17)
rod('Cylinder gland',(0,0,3.65),(0,0,3.8),.21,steel)
rod('Foot pin',(-.3,0,0),(.3,0,0),.16,silver)
export('crane_luff_barrel')
clear()
rod('Piston rod',(0,0,0),(0,0,4),.10,silver)
export('crane_luff_rod')
clear()
for x in [-.18,.18]:rod('Hoist rope',(x,0,0),(x,0,-10),.028,steel)
socket('RestLower',(0,0,-10));export('crane_wire_10m')
clear()
rod('Head sheave',(-.35,0,-.22),(.35,0,-.22),.27,steel,24)
for x in [-.78,.78]:
    rod('Suspension',(x*.3,0,-.22),(x,0,-1),.055)
rod('Jaw hinge',(-1,0,-1),(1,0,-1),.095,silver)
socket('JawAxis',(0,0,-1));socket('Mouth',(0,0,-1.6));export('grab_head')
for side in [-1,1]:
    clear();vertices=[];faces=[]
    # Thick curved pan, closed end plates; common cutting edge at y=0,z=-.6.
    profile=[(side*.85*math.sin(t*math.pi/2),-.6*math.cos(t*math.pi/2)) for t in [i/8 for i in range(9)]]
    profile += [(y*.94,z+.045) for y,z in reversed(profile)]
    for x in [-.9,.9]:vertices.extend([(x,y,z) for y,z in profile])
    n=len(profile);faces.append(tuple(reversed(range(n))));faces.append(tuple(range(n,2*n)))
    for i in range(n):j=(i+1)%n;faces.append((i,j,j+n,i+n))
    mesh=bpy.data.meshes.new('Pan');mesh.from_pydata(vertices,[],faces);mesh.update()
    o=bpy.data.objects.new('Grab pan',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(paint)
    # Welded end cheeks retain material; these move with their own jaw.
    cheek=[(0,0)]+profile[:9]
    for x in [-.88,.88]:
        verts=[(xx,y,z) for xx in [x-.02,x+.02] for y,z in cheek];c=len(cheek)
        fs=[tuple(reversed(range(c))),tuple(range(c,2*c))]
        for i in range(c):j=(i+1)%c;fs.append((i,j,j+c,i+c))
        me=bpy.data.meshes.new('Cheek');me.from_pydata(verts,[],fs);me.update()
        ob=bpy.data.objects.new('End cheek',me);bpy.context.collection.objects.link(ob);ob.data.materials.append(paint)
    for x in [-.89,.89]:
        rod('Side rib',(x,0,-.58),(x,side*.8,-.04),.045,steel)
    rod('Cutting edge',(-.91,0,-.6),(.91,0,-.6),.028,steel)
    lip=socket('CuttingLip',(0,0,-.6))
    # Runtime closed rotations are right +6deg / left -6deg around Godot X.
    closed=6 if side==-1 else -6
    correction=Matrix.Rotation(math.radians(-closed),4,'X')
    bpy.context.view_layer.update()
    for obj in list(bpy.context.scene.objects):obj.matrix_world=correction@obj.matrix_world
    export('grab_jaw_right' if side==-1 else 'grab_jaw_left')
print('CRANE_KIT_EXPORTED: nine independent Blender/GLB pairs')
