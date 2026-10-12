"""Taskekrabbe, Cancer pagurus. Original low-poly mesh.
Metres, Blender +Z up, front +X. Carapace width is 1 m so a later
length_cm/100 scale matches the fish. Reference photos were not copied.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

SRC = Path(__file__).resolve().parent
OUT = SRC.parents[1] / "fishing_items"
OUT.mkdir(parents=True, exist_ok=True)

def mat(name, color, rough=0.62):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1)
    principled.inputs["Roughness"].default_value = rough
    principled.inputs["Metallic"].default_value = 0.0
    return material

SHELL = mat("Taskekrabbe shell", (0.62, 0.13, 0.07), 0.58)
BELLY = mat("Taskekrabbe underside", (0.86, 0.62, 0.38), 0.72)
JOINT = mat("Taskekrabbe joint", (0.45, 0.16, 0.08), 0.7)
TIP = mat("Taskekrabbe claw tip", (0.015, 0.012, 0.01), 0.4)
EYE = mat("Taskekrabbe eye", (0.01, 0.01, 0.012), 0.25)

def link(name, mesh, material):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    for face in mesh.polygons:
        face.use_smooth = False
    return obj

def poly(name, verts, faces, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    return link(name, mesh, material)

def segment(name, start, end, radius, material, flatten=1.0):
    start, end = Vector(start), Vector(end)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(start + end) / 2)
    obj = bpy.context.object
    obj.name = name
    direction = end - start
    obj.rotation_euler = direction.to_track_quat("X", "Z").to_euler()
    obj.scale = (direction.length, radius * 2, radius * 2 * flatten)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = False
    return obj

def nub(name, at, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = False
    return obj

def shell():
    # Wider than long. The anterolateral rim carries the pie-crust teeth.
    verts = [(0.02, 0.0, 0.14)]
    rings = []
    specs = ((0.10, 0.18, 0.32), (0.05, 0.28, 0.46), (0.012, 0.32, 0.50))
    for z, rx, ry in specs:
        row = []
        for i in range(18):
            angle = i * math.tau / 18
            teeth = 1.0
            if math.cos(angle) > -0.05:
                teeth = 1.0 + 0.075 * (0.5 + 0.5 * math.cos(angle * 9.0))
            row.append(len(verts))
            verts.append((0.02 + math.cos(angle) * rx * teeth, math.sin(angle) * ry * teeth, z))
        rings.append(row)
    faces = []
    for i in range(18):
        faces.append((0, rings[0][i], rings[0][(i + 1) % 18]))
    for ring in range(2):
        for i in range(18):
            a, b = rings[ring][i], rings[ring][(i + 1) % 18]
            c, d = rings[ring + 1][i], rings[ring + 1][(i + 1) % 18]
            faces.append((a, c, d, b))
    center = len(verts)
    verts.append((0.02, 0.0, -0.03))
    for i in range(18):
        faces.append((center, rings[2][(i + 1) % 18], rings[2][i]))
    mesh = bpy.data.meshes.new("Carapace")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Carapace", mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(SHELL)
    mesh.materials.append(BELLY)
    for face in mesh.polygons:
        face.use_smooth = False
        face.material_index = 1 if face.normal.z < 0.2 and face.center.z < 0.02 else 0
    return obj

def claw(side, crusher):
    sign = 1.0 if side > 0 else -1.0
    thick = 0.09 if crusher else 0.062
    segment("Claw arm", (0.10, 0.18 * sign, 0.03), (0.26, 0.36 * sign, 0.05), 0.042, JOINT, 0.7)
    segment("Claw wrist", (0.26, 0.36 * sign, 0.05), (0.40, 0.30 * sign, 0.06), 0.046, SHELL, 0.75)
    segment("Claw palm", (0.40, 0.28 * sign, 0.055), (0.64, 0.16 * sign, 0.05), thick, SHELL, 0.62)
    segment("Fixed finger", (0.58, 0.14 * sign, 0.03), (0.78, 0.06 * sign, 0.015), thick * 0.36, SHELL, 0.55)
    segment("Movable finger", (0.56, 0.20 * sign, 0.09), (0.78, 0.10 * sign, 0.04), thick * 0.34, SHELL, 0.55)
    segment("Claw tip", (0.74, 0.08 * sign, 0.028), (0.84, 0.05 * sign, 0.012), thick * 0.26, TIP, 0.7)

def legs(side):
    sign = 1.0 if side > 0 else -1.0
    for index, origin in enumerate((0.12, 0.0, -0.12, -0.22)):
        y0 = 0.42 * sign
        y1 = 0.78 * sign
        back = origin - 0.20
        segment("Leg merus", (origin, y0, 0.015), (origin - 0.04, y1, -0.01), 0.03, SHELL, 0.65)
        segment("Leg carpus", (origin - 0.04, y1, -0.01), (back + 0.06, y1 * 0.82, -0.07), 0.024, JOINT, 0.7)
        segment("Leg dactyl", (back + 0.06, y1 * 0.82, -0.07), (back, y1 * 0.62, -0.16), 0.016, TIP, 0.55)

def eyes():
    for sign in (-1.0, 1.0):
        segment("Eye stalk", (0.26, 0.08 * sign, 0.09), (0.36, 0.11 * sign, 0.15), 0.016, SHELL, 1.0)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.02, location=(0.38, 0.12 * sign, 0.16))
        eye = bpy.context.object
        eye.name = "Eye"
        eye.data.materials.append(EYE)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

def pie_crust():
    for i in range(8):
        angle = -1.15 + i * 2.3 / 7.0
        x = 0.02 + math.cos(angle) * 0.36
        y = math.sin(angle) * 0.55
        nub("Pie crust", (x, y, 0.035), (0.05, 0.055, 0.032), SHELL)
        nub("Pie crust", (x, -y, 0.035), (0.05, 0.055, 0.032), SHELL)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
shell()
pie_crust()
claw(1, True)
claw(-1, False)
legs(1)
legs(-1)
eyes()
nub("Mouth", (0.30, 0.0, 0.02), (0.04, 0.06, 0.02), TIP)
hook = bpy.data.objects.new("MouthHook", None)
bpy.context.collection.objects.link(hook)
hook.empty_display_type = "PLAIN_AXES"
hook.empty_display_size = 0.03
hook.location = (0.34, 0.0, 0.02)

bpy.ops.object.select_all(action="SELECT")
for obj in list(bpy.context.selected_objects):
    if obj.type == "MESH":
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.ops.wm.save_as_mainfile(filepath=str(SRC / "taskekrabbe.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "taskekrabbe.glb"),
    export_format="GLB",
    export_apply=True,
)

# A studio still, so the shell, claws and pie-crust rim can be checked.
bpy.ops.object.light_add(type="SUN", location=(2.0, -1.5, 3.0))
bpy.context.object.rotation_euler = (0.9, 0.2, 0.6)
bpy.context.object.data.energy = 4.5
world = bpy.context.scene.world
if world is None:
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
world.color = (0.55, 0.62, 0.66)
bpy.ops.object.camera_add(location=(1.55, -1.35, 0.72))
camera = bpy.context.object
aim = Vector((0.05, 0.0, 0.05)) - camera.location
camera.rotation_euler = aim.to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = camera
bpy.context.scene.render.resolution_x = 1100
bpy.context.scene.render.resolution_y = 760
engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys() else "BLENDER_EEVEE"
bpy.context.scene.render.engine = engine
shot = Path("C:/Users/noahs/Pictures/machinescreenshots/taskekrabbe-authored.png")
shot.parent.mkdir(parents=True, exist_ok=True)
bpy.context.scene.render.filepath = str(shot)
bpy.ops.render.render(write_still=True)
print("AUTHORED taskekrabbe", shot)
