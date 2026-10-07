"""Reusable 5m crane mast and jib modules. Metres, Blender +Y outreach/+Z up.
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "crane_kit"))
from paint_bake import author_paint, bake_paint, wear_space
OUT=HERE.parents[1]/'parts/provision_structure';OUT.mkdir(parents=True,exist_ok=True)
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
# Five-metre mast with actual load paths, joint flanges and an internal ladder.
for x in [-1,1]:
    for y in [-1,1]:
        box('Corner chord',(x,y,2.5),(.20,.20,5))
        for z in [.045,4.955]:
            box('Joint flange',(x,y,z),(.34,.34,.09))
            for dx in ([-.12,.12] if z<1 else []):
                for dy in [-.12,.12]:rod('Joint stud',(x+dx,y+dy,-.105),(x+dx,y+dy,.105),.022,steel,6)
for z in [.14,2.5,4.86]:
    for side in [-1,1]:
        rod('Horizontal tie',(-1,side,z),(1,side,z),.065,paint,10)
        rod('Horizontal tie',(side,-1,z),(side,1,z),.065,paint,10)
for low in [.14,2.5]:
    high=2.5 if low<1 else 4.86
    for side in [-1,1]:
        rod('Face diagonal',(-1,side,low),(1,side,high),.065,paint,10)
        rod('Side diagonal',(side,1,low),(side,-1,high),.065,paint,10)
for x in [.35,.85]:rod('Ladder stile',(x,.55,0),(x,.55,5),.026,steel,10)
for step in range(17):
    z=.15+step*(5/17)
    rod('Ladder rung',(.35,.55,z),(.85,.55,z),.016,steel,8)
# A staggered rest landing leaves a real ladder opening.
box('Rest landing',(-.36,0,2.51),(1.08,1.75,.04),steel)
for y in [-.85,.85]:
    rod('Landing rail',(-.88,y,3.5),(.15,y,3.5),.023,steel,8)
    for x in [-.88,.15]:rod('Landing post',(x,y,2.53),(x,y,3.5),.023,steel,8)
socket('ModuleBottom',(0,0,0));socket('ModuleTop',(0,0,5))
export('mast_section_5m')
clear()
# Triangular jib: bottom chords retain the existing rail support datum.
for x in [-.6,.6]:rod('Lower chord',(x,0,-.55),(x,5,-.55),.09,paint,12)
rod('Upper chord',(0,0,1.1),(0,5,1.1),.09,paint,12)
for y in [0,2.5]:
    rod('Bottom tie',(-.6,y,-.55),(.6,y,-.55),.055,paint,10)
    for x in [-.6,.6]:rod('End triangle',(x,y,-.55),(0,y,1.1),.055,paint,10)
for i in range(2):
    y=i*2.5
    for x in [-.6,.6]:rod('Side diagonal',(x,y,-.55),(0,y+2.5,1.1),.052,paint,10)
    rod('Plan diagonal',(-.6,y,-.55),(.6,y+2.5,-.55),.045,paint,10)
for y in [.08,4.92]:
    for x,z in [(-.6,-.55),(.6,-.55),(0,1.1)]:
        rod('Pinned chord sleeve',(x,y-.08,z),(x,y+.08,z),.12,paint,12)
        rod('Connection pin',(x-.16,y,z),(x+.16,y,z),.033,steel,8)
# Central service strip below braces, with enough space above the trolley.
box('Service strip',(0,2.5,-.44),(.5,5,.035),steel)
socket('ModuleStart',(0,0,0));socket('ModuleEnd',(0,5,0))
export('jib_section_5m')

clear()
rod('End lower tie',(-.6,0,-.55),(.6,0,-.55),.055,paint,10)
for x in [-.6,.6]:rod('End triangle',(x,0,-.55),(0,0,1.1),.055,paint,10)
export('jib_end_frame')
for length in [5,3]:
    clear()
    for x in [-.42,.42]:
        o=box('Continuous trolley rail',(x,length/2,-.78),(.10,length,.12),steel)
        o.modifiers.clear() # mating faces must remain flat, without end bevel gaps
    for y in ([.5,3.0] if length==5 else [.5]):
        box('Rail cross bearer',(0,y,-.56),(1.2,.08,.10),steel)
        for x in [-.42,.42]:box('Rail hanger',(x,y,-.665),(.08,.08,.23),steel)
    for o in bpy.context.scene.objects:
        for modifier in o.modifiers:
            if modifier.type=='BEVEL': modifier.segments=1; modifier.width=.008
    socket('RailStart',(0,0,-.78));socket('RailEnd',(0,length,-.78))
    export('trolley_rails_'+str(length)+'m')
