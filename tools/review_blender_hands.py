import bpy, sys, time
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
label=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'review'
archive=Path('C:/Users/noahs/Pictures/machinescreenshots');archive.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(root/'resources/models/_source/characters/mariner.blend'))
rig=bpy.data.objects['MarinerRig'];rig.data.pose_position='REST'
for block in bpy.data.objects['Hands'].data.shape_keys.key_blocks:block.value=0
for track in rig.animation_data.nla_tracks:track.mute=True
for ob in bpy.data.objects:ob.hide_render=ob.name!='Hands'
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=760;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.world.color=(.16,.18,.20);scene.view_settings.view_transform='AgX'
def aim(ob,at,up='Y'):ob.rotation_euler=(Vector(at)-ob.location).to_track_quat('-Z',up).to_euler()
for label_light,loc,power,size in [('Key',(1,2,2),100,1.4),('Fill',(-1,-2,1.3),80,1.4),('Top',(0,0,3),60,1.2)]:
 light=bpy.data.lights.new(label_light,'AREA');light.energy=power;light.shape='DISK';light.size=size
 ob=bpy.data.objects.new(label_light,light);bpy.context.collection.objects.link(ob);ob.location=loc;aim(ob,(0,0,.86))
for side in ['L','R']:
 bpy.context.view_layer.update()
 rest=rig.data.bones['hand.'+side].matrix_local
 points=[bpy.data.objects['Hands'].matrix_world@v.co for v in bpy.data.objects['Hands'].data.vertices if (v.co.x>0)==(side=='L')]
 center=sum(points,Vector())/len(points)
 for name,local_offset in [('palm',(0,0,-.45)),('back',(0,0,.45)),('side',(.45,0,0))]:
  data=bpy.data.cameras.new('Hand_%s_%s'%(side,name));data.type='ORTHO';data.clip_start=.005
  camera=bpy.data.objects.new(data.name,data);bpy.context.collection.objects.link(camera)
  camera.location=center+rest.to_3x3()@Vector(local_offset)
  forward=(center-camera.location).normalized();up=-rest.to_3x3().col[1]
  right=forward.cross(up).normalized();up=right.cross(forward)
  from mathutils import Matrix
  camera.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler()
  proj=[Vector(((p-center).dot(right),(p-center).dot(up))) for p in points]
  xmin,xmax=min(p.x for p in proj),max(p.x for p in proj)
  ymin,ymax=min(p.y for p in proj),max(p.y for p in proj)
  camera.location+=right*((xmin+xmax)/2)+up*((ymin+ymax)/2)
  data.ortho_scale=max(ymax-ymin,(xmax-xmin)*900/760)*1.50
  scene.camera=camera
  bpy.context.view_layer.update()
  path=archive/('hands-blender-%s-%s-%s-%d.png'%(label,side,name,time.time_ns()))
  scene.render.filepath=str(path);bpy.ops.render.render(write_still=True);print('CAPTURE',path,flush=True)
