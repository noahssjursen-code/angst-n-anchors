import bpy,sys,math,time
from pathlib import Path
from mathutils import Vector,Matrix
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'resources/models/_source/crew_base/crew_base.blend'))
rig=bpy.data.objects['CrewRig'];scene=bpy.context.scene
for tr in rig.animation_data.nla_tracks:tr.mute=True
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
scene.frame_set(0);scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=900;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.world.color=(.12,.12,.12)
def aim(ob,target):ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
for name,p,power,size in [('Key',(2,3,3),300,4),('Fill',(-3,1,2),120,3),('Rim',(0,-3,2.5),200,3)]:
 l=bpy.data.lights.new(name,'AREA');l.energy=power;l.size=size;ob=bpy.data.objects.new(name,l);bpy.context.collection.objects.link(ob);ob.location=p;aim(ob,(0,0,1))
c=bpy.data.cameras.new('Review');cam=bpy.data.objects.new('Review',c);bpy.context.collection.objects.link(cam);scene.camera=cam;c.type='ORTHO'
folder=Path('C:/Users/noahs/Pictures/machinescreenshots');stamp=str(int(time.time()))
def capture(label,pos,target,size):
 cam.location=pos;aim(cam,target);c.ortho_scale=size;scene.render.filepath=str(folder/('crew-rig-'+stamp+'-'+label+'.png'));bpy.ops.render.render(write_still=True);print('REVIEW',scene.render.filepath,flush=True)
rig.data.pose_position='REST'
capture('rest-front',(0,4,.96),(0,0,.96),2.03)
capture('rest-threequarter',(2,4,1.6),(0,0,.94),2.05)
capture('rest-hands',(1.3,1.4,1.05),(.42,.05,.86),.42)
capture('rest-feet',(.7,1,.25),(0,.07,.1),.48)
rig.data.pose_position='POSE'
for clip,frame in [('idle',30),('walk',15),('run',9),('seated',0)]:
 rig.animation_data.action=bpy.data.actions[clip];scene.frame_set(frame);bpy.context.view_layer.update()
 capture(clip,(2,4,1.6),(0,0,.94),2.05)
