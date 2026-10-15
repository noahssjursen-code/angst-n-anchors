"""Immediate honest shape review of the new source body, before rigging."""
import bpy, sys, gzip, math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).parent))
from crew_base_face import create_eyes
root=Path(__file__).resolve().parents[1]
ref=root/'resources/models/_source/crew_base/reference'
archive=Path('C:/Users/noahs/Pictures/machinescreenshots');archive.mkdir(exist_ok=True,parents=True)
from datetime import datetime
stamp=datetime.now().strftime('%Y%m%d-%H%M%S')
bpy.ops.wm.read_factory_settings(use_empty=True)
verts=[];faces=[];group=''
for line in (ref/'base.obj').read_text().splitlines():
    bits=line.split()
    if not bits:continue
    if bits[0]=='v':verts.append(Vector(tuple(map(float,bits[1:4]))))
    elif bits[0]=='g':group=bits[1]
    elif bits[0]=='f' and group=='body':faces.append([int(v.split('/')[0])-1 for v in bits[1:]])
for line in gzip.open(ref/'caucasian-male-young.target.gz','rt').read().splitlines():
    bits=line.split()
    if len(bits)==4 and not bits[0].startswith('#'):
        verts[int(bits[0])]+=Vector(tuple(map(float,bits[1:])))
used=sorted(set(v for face in faces for v in face));index={v:i for i,v in enumerate(used)}
bottom=min(verts[i].y for i in used);top=max(verts[i].y for i in used);scale=1.8/(top-bottom)
def convert(p):return (p[0]*scale,p[2]*scale,(p[1]-bottom)*scale)
mesh=bpy.data.meshes.new('New anatomical body');mesh.from_pydata([convert(verts[i]) for i in used],[],[[index[i] for i in f] for f in faces]);mesh.update()
body=bpy.data.objects.new('New base body',mesh);bpy.context.collection.objects.link(body)
import bmesh
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
skin=bpy.data.materials.new('Base skin');skin.diffuse_color=(.51,.31,.21,1);skin.use_nodes=True
skin.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.51,.31,.21,1)
skin.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.64
mesh.materials.append(skin)
for poly in mesh.polygons:poly.use_smooth=True
create_eyes(ref,verts,convert)
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=950;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Studio');scene.world.color=(.12,.12,.12)
scene.view_settings.view_transform='AgX'
for location,power,size in [((2,3,4),450,4),((-3,1,2),250,3),((1,-2,3),550,3)]:
    data=bpy.data.lights.new('Softbox','AREA');data.energy=power;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new('Softbox',data);bpy.context.collection.objects.link(ob);ob.location=location;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200)
floor=bpy.context.object;mat=bpy.data.materials.new('Studio');mat.diffuse_color=(.055,.075,.085,1);floor.data.materials.append(mat)
data=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',data);bpy.context.collection.objects.link(cam);scene.camera=cam
data.type='ORTHO'
for label,location,target,size in [('body',(2,5,2.1),(0,0,.92),2.04),('face',(.43,2,1.78),(0,0,1.66),.43)]:
    cam.location=location;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();data.ortho_scale=size
    scene.render.filepath=str(archive/('crew-shape-'+stamp+'-'+label+'.png'));bpy.ops.render.render(write_still=True);print('CREW_SHAPE',scene.render.filepath,flush=True)
