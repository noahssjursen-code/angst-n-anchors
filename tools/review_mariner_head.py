"""Isolated face art review, without writing production asset exports."""
import sys, time
from pathlib import Path
import bpy
from mathutils import Vector

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'tools'))
from mariner_head import rebuild_head
bpy.ops.wm.open_mainfile(filepath=str(root/'resources/models/_source/characters/mariner.blend'))
rig=bpy.data.objects.get('MarinerRig')
if rig:
    rig.data.pose_position='REST'
    if rig.animation_data:
        for track in rig.animation_data.nla_tracks: track.mute=True
for obj in bpy.data.objects:
    if obj.type=='MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:key.value=0
g={'objects':[o for o in bpy.data.objects if o.type=='MESH'],
   'skin':bpy.data.materials['Skin'],'hair':bpy.data.materials['Hair'],'lip':bpy.data.materials['Lips']}
rebuild_head(g)
visible={'Head','Face','Neck','Hair_Crop','Top_Sweater','Top_Trim'}
for obj in bpy.data.objects:obj.hide_render=obj.name not in visible
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.cycles.use_denoising=True
scene.render.resolution_x=850;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.23,.25,.28,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.4
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=-1.2
def aim(obj,at):obj.rotation_euler=(Vector(at)-obj.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size in [('Key',(-.6,.8,2.2),45,.7),('Fill',(.5,.4,1.6),14,.6),('Rim',(.3,-.5,1.9),30,.5)]:
    light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
    obj=bpy.data.objects.new(name,light);bpy.context.collection.objects.link(obj);obj.location=loc;aim(obj,(0,0,1.66))
stamp=str(time.time_ns())
archive=Path('C:/Users/noahs/Pictures/machinescreenshots');archive.mkdir(parents=True,exist_ok=True)
for label,pos in [('front',(0,1,1.67)),('three-quarter',(.65,1,1.69)),('side',(1,.015,1.67))]:
    cam=bpy.data.cameras.new(label);cam.type='ORTHO';cam.ortho_scale=.40;cam.clip_start=.01
    obj=bpy.data.objects.new(label,cam);bpy.context.collection.objects.link(obj);obj.location=pos;aim(obj,(0,0,1.65));scene.camera=obj
    scene.render.filepath=str(archive/('mariner-head-'+stamp+'-'+label+'.png'))
    bpy.ops.render.render(write_still=True)
    print('CAPTURE',scene.render.filepath,flush=True)
