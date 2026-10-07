"""Reusable provision hoist parts. Blender +Y outreach, +Z up.
Load seat at origin; sheave tangents +/-0.30m at +0.85m; 10m rope rest length.
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "crane_kit"))
from paint_bake import author_paint, bake_paint, wear_space
OUT=HERE.parents[1]/'parts/provision_hoist';OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
def mat(n,c,metal=.3):
    m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48
    return m
paint=mat('Ochre painted steel',(.66,.42,.075));steel=mat('Fixed_DarkSteel',(.065,.085,.10),.65)
author_paint(paint)
glass=mat('Fixed_CabinGlass',(.12,.26,.31),.35);silver=mat('Fixed_PinSteel',(.38,.43,.46),.8)
glass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.28
glass.diffuse_color=(.12,.26,.31,.28);glass.surface_render_method='DITHERED'
def purge_authoring_orphans():
    # Every source blend is standalone; do not carry previous parts' packed maps.
    for mesh in list(bpy.data.meshes):
        if mesh.users==0:bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        if material.users==0 and material not in (paint,steel,glass,silver):bpy.data.materials.remove(material)
    for image in list(bpy.data.images):
        if image.users==0:bpy.data.images.remove(image)

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    purge_authoring_orphans()
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
    for o in meshes:
        wear_space(o, paint, o.data.name.startswith('Cylinder'))
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.context.object.name=n
    bake_paint(bpy.context.object, paint, n, HERE/'textures')
    purge_authoring_orphans()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(n+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(n+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
clear()
# Load seat remains at the gameplay origin. The sheave and guards sit above it.
for y in [-.16,.16]:
    plate('Cheek guard',[(-.38,y,.54),(-.34,y,1.11),(-.23,y,1.22),(.23,y,1.22),(.34,y,1.11),(.38,y,.54),(.16,y,.40),(-.16,y,.40)],.055)
rod('Sheave tread',(0,-.10,.85),(0,.10,.85),.287,steel,48)
for y in [-.11,.11]:
    rod('Sheave flange',(0,y-.014,.85),(0,y+.014,.85),.315,steel,48)
rod('Through axle',(0,-.23,.85),(0,.23,.85),.065,silver,16)
for x in [-.22,.22]:
    for z in [.57,1.08]:rod('Guard fastener',(x,-.205,z),(x,-.18,z),.027,silver,8)
rod('Swivel housing',(0,0,.36),(0,0,.50),.12,steel)
rod('Forged shank',(0,0,.20),(0,0,.40),.065,silver)
# Swept tapered forged hook, not a rectangular chain of boxes.
points=[(0,.30),(-.10,.23),(-.15,.10),(-.12,-.04),(0,-.11),(.14,-.06),(.20,.06),(.18,.17)]
curve=bpy.data.curves.new('Forged hook profile','CURVE');curve.dimensions='3D';curve.resolution_u=8
curve.bevel_depth=.065;curve.bevel_resolution=3;curve.use_fill_caps=True
s=curve.splines.new('BEZIER');s.bezier_points.add(len(points)-1)
for i,((x,z),p) in enumerate(zip(points,s.bezier_points)):
    p.co=(x,0,z+.16);p.handle_left_type='AUTO';p.handle_right_type='AUTO';p.radius=1 if i<5 else [1,.75,.32][i-5]
o=bpy.data.objects.new('Forged load hook',curve);bpy.context.collection.objects.link(o);curve.materials.append(silver)
bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH')
rod('Spring safety latch',(.015,0,.39),(.18,0,.33),.017,steel,12)
# Visible reeving around lower half of the sheave; two straight falls meet tangents.
for i in range(24):
    a=math.pi+i*math.pi/24;b=math.pi+(i+1)*math.pi/24
    rod('Rope in groove',(.30*math.cos(a),0,.85+.30*math.sin(a)),(.30*math.cos(b),0,.85+.30*math.sin(b)),.012,steel,8)
socket('LoadSeat',(0,0,0));socket('RopeLeft',(-.30,0,.85));socket('RopeRight',(.30,0,.85))
export('provision_hook_block')
clear()
for x in [-.30,.30]:rod('Hoist fall',(x,0,0),(x,0,-10),.012,steel,10)
socket('RopeTop',(0,0,0));socket('RopeBottom',(0,0,-10))
export('provision_rope_pair_10m')
clear()
# Four running wheels bear on the existing +/-0.42m rails (rail top = +.06).
for x in [-.42,.42]:
    for y in [-.50,.50]:
        rod('Running wheel',(x-.055,y,.24),(x+.055,y,.24),.18,steel,24)
        for side in [-1,1]:rod('Wheel flange',(x+side*.065-.012,y,.24),(x+side*.065+.012,y,.24),.205,steel,24)
        rod('Wheel axle',(x-.15,y,.24),(x+.15,y,.24),.043,silver,16)
        box('Bearing hanger',(x*1.48,y,.02),(.10,.24,.62))
for x in [-.61,.61]:box('Carriage channel',(x,0,-.25),(.14,1.4,.20))
for y in [-.58,.58]:box('Cross beam',(0,y,-.25),(1.25,.16,.20))
box('Service tread',(0,0,-.15),(.86,1.0,.045),steel)
for x in [-.47,.47]:
    for y in [-.13,.13]:
        plate('Sheave hanger',[(x-.13,y,-.26),(x+.13,y,-.26),(x+.12,y,-1.14),(x-.12,y,-1.14)],.055)
    rod('Head sheave',(x,-.075,-1.05),(x,.075,-1.05),.17,steel,32)
    rod('Head sheave pin',(x,-.20,-1.05),(x,.20,-1.05),.037,silver,16)
box('Limit switch',(.68,.35,-.34),(.16,.25,.17),steel)
rod('Switch roller',(.69,.35,-.18),(.69,.35,.02),.024,silver,12)
socket('RopeLeft',(-.30,0,-1.05));socket('RopeRight',(.30,0,-1.05))
export('provision_trolley')
