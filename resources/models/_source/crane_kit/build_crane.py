"""Separate metre-scale harbour crane parts. Blender +Y outreach, +Z up.
Existing gameplay contract: 30 m boom, 10 m rest wire, mouth 1.6 m below hook.
"""
import bpy, bmesh, math
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
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    if min(s)>.06:
        mod=o.modifiers.new('Fabricated edge radius','BEVEL');mod.width=min(.025,min(s)*.15);mod.segments=3
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o
def rod(n,a,b,r,m=paint,verts=32):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
    for poly in o.data.polygons:poly.use_smooth=len(poly.vertices)==4
    return o
def plate(n,outline,thickness,m=paint):
    normal=(Vector(outline[1])-Vector(outline[0])).cross(Vector(outline[2])-Vector(outline[0])).normalized()
    vs=[tuple(Vector(p)+normal*offset) for offset in [-thickness/2,thickness/2] for p in outline];k=len(outline)
    fs=[tuple(reversed(range(k))),tuple(range(k,2*k))]+[(i,(i+1)%k,(i+1)%k+k,i+k) for i in range(k)]
    data=bpy.data.meshes.new(n);data.from_pydata(vs,[],fs);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    ob=bpy.data.objects.new(n,data);bpy.context.collection.objects.link(ob);data.materials.append(m);return ob
def socket(n,p):
    o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=p;return o
def export(n):
    # One origin-centred mesh per GLB; cable length scales about its upper endpoint.
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(True)
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
for i in range(12):
    angle=i*math.tau/12
    g=plate('Radial base gusset',[(1.06,0,.28),(1.62,0,.28),(1.06,0,1.04)],.065)
    g.rotation_euler.z=angle
for i in range(24):
    a=i*math.tau/24;x=1.22*math.cos(a);y=1.22*math.sin(a)
    rod('Slew race bolt',(x,y,2.28),(x,y,2.32),.035,silver,6)
box('Pedestal access panel',(0,-1.113,1.2),(.62,.035,.72),steel)
for x in [-.25,.25]:
    for z in [.91,1.49]:rod('Panel fixing',(x,-1.13,z),(x,-1.16,z),.026,silver,6)
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
# Continuous guardrails with a rear boarding gate; 0.5 m midrail/toe plate.
for x in [-3.0,1.1]:
    for y in [-2.48,-1.2,0,1.35]:rod('Guard stanchion',(x,y,0),(x,y,1.08),.028,silver)
    for z in [.52,1.08]:rod('Side guard',(x,-2.48,z),(x,1.35,z),.028,silver)
    box('Toe plate',(x,-.565,.07),(.035,3.83,.14),paint)
for a,b in [(-3,-.45),(.45,1.1)]:
    for z in [.52,1.08]:rod('Rear guard',(a,-2.48,z),(b,-2.48,z),.028,silver)
for z in [.52,1.08]:rod('Front guard',(-3,1.35,z),(1.1,1.35,z),.028,silver)
# Board from rear ladder; the whole access travels with the upperworks.
for x in [-.38,.38]:rod('Ladder stile',(x,-2.62,-2.0),(x,-2.62,1.02),.035,silver)
for i in range(9):rod('Serrated rung',(-.38,-2.62,-1.95+i*.25),(.38,-2.62,-1.95+i*.25),.025,silver)
for z in [.3,1.08]:rod('Boarding gate',(-.38,-2.48,z),(.38,-2.48,z),.025,paint)
for z in [.12,1.62]:box('Front glazing gasket',(0,.945,z),(1.56,.028,.045),steel)
for x in [-.77,.77]:box('Glazing side gasket',(x,.945,1.05),(.04,.028,1.12),steel)
rod('Wiper blade',(-.38,.975,.69),(.17,.975,1.48),.014,steel)
rod('Wiper arm',(.32,.98,.58),(-.08,.98,1.11),.017,steel)
box('Roof rain gutter',(0,1.09,1.7),(1.88,.045,.065),steel)
box('Door inset',(0,-.715,.97),(1.28,.035,1.23),steel)
box('Door panel',(0,-.742,.96),(1.20,.035,1.14),paint)
rod('Door handle',(.43,-.79,.98),(.43,-.79,1.15),.017,silver)
for z in [.5,1.4]:rod('Door hinge',(-.64,-.75,z-.055),(-.64,-.75,z+.055),.028,silver)
for x in [-.45,.45]:rod('Control joystick',(x,.47,.87),(x,.45,1.02),.018,steel)
# Rear hoist drum, bearings and motor inside an open service cradle.
for x in [-2.48,-1.02]:box('Winch bearing block',(x,-1,1.84),(.16,.70,.58),steel)
rod('Hoist drum',(-2.4,-1,2.1),(-1.1,-1,2.1),.38,steel,48)
for x in [-2.4,-1.1]:rod('Drum flange',(x-.035,-1,2.1),(x+.035,-1,2.1),.47,paint,48)
for i in range(30):rod('Wire winding',(-2.33+i*.039,-1,2.1),(-2.31+i*.039,-1,2.1),.392,silver,48)
rod('Hoist motor',(-2.91,-1,2.1),(-2.5,-1,2.1),.26,steel)
socket('WinchLeadLeft',(-1.93,-1,2.49));socket('WinchLeadRight',(-1.57,-1,2.49))
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
for x in [-.18,.18]:
    rod('Tip sheave',(x-.045,29.66,0),(x+.045,29.66,0),.34,steel,48)
    rod('Tip axle',(x-.09,29.66,0),(x+.09,29.66,0),.09,silver)
    rod('Boom-top wire',(x,0,.75),(x,29.66,.34),.028,steel)
    socket('HeelLeadLeft' if x<0 else 'HeelLeadRight',(x,0,.75))
for y in [0,6,12,18,24,29.66]:
    w=.72-(y/30)*.43
    rod('Upper wire support',(-w,y,.62-y*.008),(w,y,.62-y*.008),.04,silver)
for x in [-.38,.38]:plate('Sheave cheek',[(x,29.15,-.3),(x,30.05,-.3),(x,30.05,.3),(x,29.15,.3)],.05)

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
box('Grab power enclosure',(0,0,-.29),(.92,.58,.46),paint)
for x in [-.5,.5]:
    plate('Head side cheek',[(x,-.29,-.08),(x,.29,-.08),(x,.42,-.65),(x,-.42,-.65)],.08,steel)
for x in [-.18,.18]:rod('Cable termination',(x,0,.035),(x,0,-.22),.065,silver)
for i in range(7):box('Power pack grille',(0,-.3,-.13-i*.05),(.68,.025,.018),steel)
for side in [-1,1]:
    rod('Actuator head pin',(-.27,side*.26,-.35),(.27,side*.26,-.35),.07,silver)
    socket('ActuatorBaseRight' if side<0 else 'ActuatorBaseLeft',(0,side*.26,-.35))

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
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
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
    for x in [-.91,.91]:
        rod('Jaw bearing boss',(x-.04,0,0),(x+.04,0,0),.15,paint)
        rod('Pivot cap',(x-.055,0,0),(x+.055,0,0),.075,silver,6)
    rod('Actuator jaw pin',(-.24,side*.72,-.12),(.24,side*.72,-.12),.07,silver)
    for x in [-.30,.30]:rod('Jaw stiffener',(x,side*.82,-.05),(x,side*.10,-.58),.035,steel)
    socket('ActuatorEnd',(0,side*.72,-.12))
    lip=socket('CuttingLip',(0,0,-.6))
    # Runtime closed rotations are right +6deg / left -6deg around Godot X.
    closed=6 if side==-1 else -6
    correction=Matrix.Rotation(math.radians(-closed),4,'X')
    bpy.context.view_layer.update()
    for obj in list(bpy.context.scene.objects):obj.matrix_world=correction@obj.matrix_world
    export('grab_jaw_right' if side==-1 else 'grab_jaw_left')
clear()
rod('Grab cylinder barrel',(0,0,0),(0,0,.55),.085,paint)
rod('Cylinder gland',(0,0,.50),(0,0,.55),.10,steel)
rod('Base bearing',(-.12,0,0),(.12,0,0),.065,silver)
export('grab_actuator_barrel')
clear();rod('Grab piston rod',(0,0,0),(0,0,.5),.045,silver)
# The fixed eye is on the jaw pin; only the piston shaft stretches at runtime.
export('grab_actuator_rod')
print('CRANE_KIT_EXPORTED: eleven independent Blender/GLB pairs')
