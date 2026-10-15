"""Bake efficient seated crowds from the new crew base's actual posed skin.

Run with Blender --background --python tools/build_crew_passengers_blender.py.
The source blend is read only. Exported origins are measured cushion contact
points, so the manifest's seat positions need no model-specific height offset.
"""
import bpy
import json
import time
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'resources/models/_source/crew_base/crew_base.blend'
OUT = ROOT/'resources/models/crew_base/passengers'
ARCHIVE = Path('C:/Users/noahs/Pictures/machinescreenshots')


def triangles(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def aim(obj, target):
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z', 'Y').to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rig = next((obj for obj in bpy.data.objects if obj.type == 'ARMATURE'), None)
if rig is None or 'hips' not in rig.pose.bones:
    raise RuntimeError('The new crew base must be rigged before passenger baking')
action = bpy.data.actions.get('seated')
if action is None:
    raise RuntimeError('The new crew base has no seated action')
rig.animation_data_create()
for track in rig.animation_data.nla_tracks:
    track.mute = True
rig.animation_data.action = action
if action.slots:
    rig.animation_data.action_slot = action.slots[0]
for obj in bpy.data.objects:
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks[1:]:
            key.value = 0
bpy.context.scene.frame_set(0)
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
def part(name):
    return next((obj for obj in bpy.data.objects if obj.type == 'MESH' and obj.name.split('.')[0] == name), None)


body = part('Body')
if body is None:
    raise RuntimeError('The new crew base Body mesh is missing')

# Find the skin underside of the seated pelvis, not the feet or rig origin.
hips = rig.matrix_world @ rig.pose.bones['hips'].head
hip_group = body.vertex_groups.get('hips')
if hip_group is None:
    raise RuntimeError('Body has no pelvis skin weights for measuring seat contact')
evaluated = body.evaluated_get(depsgraph)
posed = evaluated.to_mesh()
contacts = []
for source_vertex, vertex in zip(body.data.vertices, posed.vertices):
    if sum(group.weight for group in source_vertex.groups if group.group == hip_group.index) < .4:
        continue
    point = body.matrix_world @ vertex.co
    if abs(point.x-hips.x) < .22 and -.22 < point.y-hips.y < .06 and -.30 < point.z-hips.z < 0:
        contacts.append(point.z)
evaluated.to_mesh_clear()
if len(contacts) < 12:
    raise RuntimeError('Cannot measure seated pelvis contact from the actual mesh')
seat_origin = Vector((hips.x, hips.y, min(contacts)))

templates = []
for obj in [part(name) for name in ('Body', 'Head', 'Neck', 'Hands', 'Eyes')]:
    if obj is None:
        continue
    evaluated = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    for vertex in mesh.vertices:
        vertex.co = obj.matrix_world @ vertex.co-seat_origin
    templates.append((obj.name.split('.')[0], mesh))
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
# The animated base separates skin parts for first-person visibility. A static
# passenger does not need those boundaries: weld them before simplification so
# different LOD reductions cannot open cracks at the wrists and neck.
skin_parts = []
eye_template = None
for name, mesh in templates:
    if name == 'Eyes':
        eye_template = mesh
        continue
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.select_set(True)
    skin_parts.append(obj)
bpy.context.view_layer.objects.active = skin_parts[0]
bpy.ops.object.join()
welded = bpy.context.object
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=.00001)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
templates = [('Body', welded.data)]
if eye_template is not None:
    templates.append(('Eyes', eye_template))
bpy.data.objects.remove(welded, do_unlink=True)
OUT.mkdir(parents=True, exist_ok=True)
ARCHIVE.mkdir(parents=True, exist_ok=True)
report = {'source': str(SOURCE.relative_to(ROOT)), 'seat_origin_in_source_m': list(seat_origin), 'seat_origin': 'underside of posed pelvis at cushion contact', 'lods': {}}
near = []
for lod, budgets in [
    ('near', {'Body': 6500, 'Eyes': 360}),
    ('far', {'Body': 1650, 'Eyes': 120}),
]:
    meshes = []
    bpy.ops.object.select_all(action='DESELECT')
    for name, template in templates:
        obj = bpy.data.objects.new(name, template.copy())
        bpy.context.collection.objects.link(obj)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        count = triangles(obj.data)
        modifier = obj.modifiers.new('Static passenger LOD', 'DECIMATE')
        modifier.ratio = min(1., budgets[name]/max(1, count))
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.select_set(False)
        meshes.append(obj)
    for obj in meshes:
        obj.select_set(True)
    path = OUT/('seated_passenger_'+lod+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_animations=False, export_skins=False, export_morph=False, export_yup=True)
    count = sum(triangles(obj.data) for obj in meshes)
    assert count <= (7000 if lod == 'near' else 1800), (lod, count)
    report['lods'][lod] = {'triangles': count, 'meshes': len(meshes), 'file': path.name}
    if lod == 'near':
        near = meshes
        for obj in near:
            obj.hide_render = True
    else:
        for obj in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
for obj in near:
    obj.hide_render = False
(OUT/'passenger_contract.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

# A contact-plane review uses the actual exported LOD geometry. The seat slab is
# only a diagnostic prop and is excluded from both exports.
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 12
scene.cycles.use_denoising = True
scene.render.resolution_x = 960
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.world.color = (.12, .12, .12)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -.035))
seat = bpy.context.object
seat.name = 'Review cushion contact plane'
seat.scale = (.47, .43, .07)
mat = bpy.data.materials.new('Review seat')
mat.diffuse_color = (.06, .11, .14, 1)
seat.data.materials.append(mat)
for name, point, energy in [('Key', (2, 3, 3), 400), ('Fill', (-2, 1, 2), 160)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.shape = 'DISK'
    data.size = 3
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = point
    aim(obj, (0, 0, .35))
data = bpy.data.cameras.new('Passenger review')
camera = bpy.data.objects.new('Passenger review', data)
bpy.context.collection.objects.link(camera)
camera.location = (2, 3, 1.3)
aim(camera, (0, .13, .25))
data.type = 'ORTHO'
data.ortho_scale = 1.8
scene.camera = camera
scene.render.filepath = str(ARCHIVE/('crew-seated-'+str(int(time.time()))+'.png'))
bpy.ops.render.render(write_still=True)
print('PASSENGER_BAKE', json.dumps(report))
print('PASSENGER_REVIEW', scene.render.filepath)
