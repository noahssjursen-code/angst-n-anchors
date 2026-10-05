"""Render the saved source, not a generated illustration. No source-file mutation."""
import bpy, sys, math
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
args=sys.argv[sys.argv.index('--')+1:]
out=Path(args[0]); look=args[1] if len(args)>1 else 'sailor'
bpy.ops.wm.open_mainfile(filepath=str(root/'resources/models/_source/characters/mariner.blend'))
hidden={'Body_Torso','Body_Arms','Body_Legs','Body_Feet','Base_Shorts','Hair_Crop','Outerwear_Vest','Headwear_Hardhat','Eyewear_Glasses','Utility_Belt'}
if look=='worker':
    hidden-={'Outerwear_Vest','Headwear_Hardhat','Eyewear_Glasses','Utility_Belt'}
    hidden|={'Headwear_Cap','Accessory_Pipe','FacialHair_Moustache'}
for o in bpy.data.objects:
    o.hide_render=o.name in hidden
rig=bpy.data.objects['MarinerRig']
for tr in rig.animation_data.nla_tracks:tr.mute=True
rig.animation_data.action=bpy.data.actions['idle']
bpy.context.scene.frame_set(0)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=900;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.world.color=(.16,.18,.20)
bpy.ops.mesh.primitive_plane_add(size=200)
floor=bpy.context.object;floor.location.z=-.012
mat=bpy.data.materials.new('Studio backdrop');mat.diffuse_color=(.075,.10,.115,1);floor.data.materials.append(mat)
def aim(o,at):o.rotation_euler=(Vector(at)-o.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size,color in [('Key',(2,3,4),450,4,(1,.88,.75)),('Fill',(-3,1,2.4),250,3,(.65,.8,1)),('Rim',(1,-2,3),450,2,(1,.67,.4))]:
    light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size;light.color=color
    ob=bpy.data.objects.new(name,light);bpy.context.collection.objects.link(ob);ob.location=loc;aim(ob,(0,0,1))
camera=bpy.data.cameras.new('Review camera');cam=bpy.data.objects.new('Review camera',camera);bpy.context.collection.objects.link(cam)
cam.location=(2.1,4.6,2.0);aim(cam,(0,0,.93));camera.type='ORTHO';camera.ortho_scale=2.1;scene.camera=cam
scene.view_settings.view_transform='AgX'
scene.render.filepath=str(out);bpy.ops.render.render(write_still=True)
