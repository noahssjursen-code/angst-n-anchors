"""Offline mesh LODs derived from the shipped Blender facility exports.
Run in Blender background mode. No viewport/image impostors or gameplay nodes.
"""
import bpy, json, hashlib, math
from pathlib import Path
SRC = Path(__file__).resolve().parent
MODELS = SRC.parents[1]
OUT = MODELS / "scenery/port_distance"
ASSETS = {
    "harbour_authority_20m": ("port_facilities", 260),
    "harbour_office": ("port_facilities", 180),
    "warehouse_12x18": ("harbour_kit", 220),
    "lng_terminal_tank_24m": ("port_facilities", 300),
    "grain_silo": ("port_facilities", 240),
    "liquid_tank": ("port_facilities", 180),
    "insulated_gas_vessel": ("port_facilities", 160),
}
manifest = {}
for name, (family, distance) in ASSETS.items():
    path = MODELS / "parts" / family / (name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    before = sum(len(o.data.loop_triangles) for o in objects)
    for ob in objects:
        ob.data.calc_loop_triangles()
    before = sum(len(o.data.loop_triangles) for o in objects)
    for ob in objects:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True); bpy.context.view_layer.objects.active = ob
        xf = ob.matrix_world.copy(); ob.parent = None; ob.matrix_world = xf
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # Remove bevel segmentation and flat-face subdivision first, keeping
        # material borders, roof outlines and window recesses.
        mod = ob.modifiers.new("Planar reduction", "DECIMATE")
        mod.decimate_type = "DISSOLVE"; mod.angle_limit = math.radians(12)
        mod.delimit = {"MATERIAL", "UV"}
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod = ob.modifiers.new("Distance reduction", "DECIMATE")
        mod.ratio = .22
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    ob = bpy.context.object; ob.name = name + "_lod1"
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    for other in list(bpy.context.scene.objects):
        if other != ob: bpy.data.objects.remove(other, do_unlink=True)
    # Large surfaces keep their authored colour/UV; tiny normal/specular detail
    # is not useful on the far variant. Never bake illumination into the mesh.
    for mat in ob.data.materials:
        if not mat or not mat.use_nodes: continue
        node = mat.node_tree.nodes.get("Principled BSDF")
        if node:
            node.inputs["Roughness"].default_value = max(.7, node.inputs["Roughness"].default_value)
    ob.data.calc_loop_triangles(); after = len(ob.data.loop_triangles)
    assert after < before * .5, (name, before, after)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC / (name + "_lod1.blend")))
    target = OUT / (name + "_lod1.glb")
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True, export_apply=True)
    manifest["res://resources/models/parts/" + family + "/" + name + ".glb"] = {
        "mesh": "res://resources/models/scenery/port_distance/" + target.name,
        "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "detailed_triangles": before, "lod_triangles": after,
        "switch_m": distance, "margin_m": 20,
    }
    print("FACILITY_LOD", name, before, after, flush=True)
(OUT / "facility_lods.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
