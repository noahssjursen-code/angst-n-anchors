"""Bake the existing in-house mariner's seated pose for cheap manifest crowds.
Does not edit the player model, rig, clips or locomotion. Static crowd geometry
keeps the source's UVs/materials and is batched at runtime, without 240 skeletons.
"""
import bpy, json
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[1]
OUT=ROOT/'characters/passengers'
OUT.mkdir(parents=True,exist_ok=True)
# Consume the approved runtime export, avoiding Blender-version-specific UI
# data in the original artist file. The upstream source remains mariner.blend.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'characters/mariner.glb'))
bpy.context.preferences.filepaths.save_version=0
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for track in rig.animation_data.nla_tracks:track.mute=True
action=next(track.strips[0].action for track in rig.animation_data.nla_tracks if track.name=='seated')
rig.animation_data.action=action
bpy.context.scene.frame_set(30)
hidden={'Body_Torso','Body_Arms','Body_Legs','Body_Feet','Base_Shorts','Outerwear_Vest',
        'Headwear_Cap','Headwear_Hardhat','FacialHair_Moustache','Eyewear_Glasses',
        'Accessory_Pipe','Utility_Belt'}
originals=list(bpy.context.scene.objects)
frozen=[]
graph=bpy.context.evaluated_depsgraph_get()
for obj in originals:
    if obj.type!='MESH' or obj.name in hidden:continue
    evaluated=obj.evaluated_get(graph)
    mesh=bpy.data.meshes.new_from_object(evaluated,depsgraph=graph)
    for vertex in mesh.vertices:
        vertex.co=obj.matrix_world@vertex.co
        # A slender civilian variation of the same angular mariner. Seat pitch
        # is 0.5 m, so the crew model's broad shoulders need a narrower build.
        vertex.co.x*=.78
        vertex.co.z-=.40
    baked=bpy.data.objects.new(obj.name+'_Seated',mesh)
    bpy.context.collection.objects.link(baked);frozen.append(baked)
for obj in originals:bpy.data.objects.remove(obj,do_unlink=True)
stats={}
for lod,budget in [('near',7000),('far',1800)]:
    copies=[]
    triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in frozen)
    for original in frozen:
        obj=original.copy();obj.data=original.data.copy()
        bpy.context.collection.objects.link(obj);copies.append(obj)
        bpy.context.view_layer.objects.active=obj
        dec=obj.modifiers.new('Crowd detail budget','DECIMATE');dec.ratio=min(1,budget/triangles)
        bpy.ops.object.modifier_apply(modifier=dec.name)
        obj.data.validate(clean_customdata=False);obj.data.update()
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies:obj.select_set(True)
    stats[lod]={'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in copies),
                'parts':len(copies)}
    bpy.ops.export_scene.gltf(filepath=str(OUT/('seated_passenger_'+lod+'.glb')),
        export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_yup=True)
    for obj in copies:bpy.data.objects.remove(obj,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'seated_passenger.blend'))
(OUT/'mesh_stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
print('SEATED PASSENGER',stats)
