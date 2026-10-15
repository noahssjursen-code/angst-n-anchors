"""Build and preview the new CC0 anatomical crew base. No legacy geometry is loaded."""
import bpy,sys,math,gzip,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'resources/models/_source/crew_base/reference'
OUT=ROOT/'resources/models/crew_base';OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'resources/models/_source/crew_base';SOURCE.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'tools'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
verts=[];uvs=[];faces=[];faceuv=[];group=''
for line in (REF/'base.obj').read_text(encoding='utf-8').splitlines():
 b=line.split()
 if not b:continue
 if b[0]=='v':verts.append(Vector(tuple(map(float,b[1:4]))))
 elif b[0]=='vt':uvs.append(tuple(map(float,b[1:3])))
 elif b[0]=='g':group=b[1]
 elif b[0]=='f' and group=='body':
  refs=[x.split('/') for x in b[1:]];faces.append(tuple(int(x[0])-1 for x in refs));faceuv.append(tuple(uvs[int(x[1])-1] for x in refs))
for line in gzip.decompress((REF/'caucasian-male-young.target.gz').read_bytes()).decode().splitlines():
 b=line.split()
 if not b or b[0].startswith('#'):continue
 verts[int(b[0])]+=Vector(tuple(map(float,b[1:4])))
body_ids=sorted(set(i for f in faces for i in f));bottom=min(verts[i].y for i in body_ids);top=max(verts[i].y for i in body_ids);scale=1.80/(top-bottom)
def transform(p):return Vector((p[0]*scale,p[2]*scale,(p[1]-bottom)*scale))
index={old:new for new,old in enumerate(body_ids)}
data=bpy.data.meshes.new('Crew anatomical body');data.from_pydata([transform(verts[i]) for i in body_ids],[],[tuple(index[i] for i in f) for f in faces]);data.update()
body=bpy.data.objects.new('Body',data);bpy.context.collection.objects.link(body)
uv=data.uv_layers.new(name='UVMap')
for poly,coords in zip(data.polygons,faceuv):
 poly.use_smooth=True
 for loop,p in zip(poly.loop_indices,coords):uv.data[loop].uv=p
skin=bpy.data.materials.new('Skin');skin.use_nodes=True
bs=skin.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.50,.37,.27,1);bs.inputs['Roughness'].default_value=.72;bs.inputs['Specular IOR Level'].default_value=.2
data.materials.append(skin)
from crew_base_face import create_eyes
objects=[body];create_eyes(REF,verts,transform,objects)
from crew_base_rig import build
rig,bones=build(REF,OUT,verts,transform,body,objects)
# Save the complete independently editable rigged source.
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'crew_base.blend'))
bpy.ops.object.select_all(action='DESELECT')
for ob in objects+[rig]:ob.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'crew_base.glb'),use_selection=True,export_format='GLB',export_animations=True,export_animation_mode='NLA_TRACKS',export_skins=True,export_yup=True)
print('CREW_BASE_EXPORTED',str(OUT/'crew_base.glb'),flush=True)
for tr in rig.animation_data.nla_tracks:tr.mute=True
rig.data.pose_position='REST'
bpy.context.view_layer.update()
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.world.color=(.12,.12,.12)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for name,p,power,size in [('Key',(2,3,3),400,4),('Fill',(-3,1,2),180,3),('Rim',(0,-3,2.5),300,3)]:
 light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
 ob=bpy.data.objects.new(name,light);bpy.context.collection.objects.link(ob);ob.location=p;aim(ob,(0,0,1))
camd=bpy.data.cameras.new('Review');cam=bpy.data.objects.new('Review',camd);bpy.context.collection.objects.link(cam);scene.camera=cam;camd.type='ORTHO'
folder=Path('C:/Users/noahs/Pictures/machinescreenshots');folder.mkdir(parents=True,exist_ok=True)
import time
stamp=str(int(time.time()))
for label,position,target,size in [('new-base-body',(2,4,1.6),(0,0,.94),2.05),('new-base-face',(.5,2,1.7),(0,0,1.66),.44)]:
 cam.location=position;aim(cam,target);camd.ortho_scale=size;scene.render.filepath=str(folder/('crew-base-'+stamp+'-'+label+'.png'));bpy.ops.render.render(write_still=True);print('NEW BASE IMAGE',scene.render.filepath)
