"""Cycles-authored paint finish baked to portable glTF maps in rest pose.

Authored local edge distances concentrate wear; metre-space noise breaks it up.
No runtime world-space projection: articulation carries the wear.
"""
import bpy
from pathlib import Path


def author_paint(material):
    material['crane_paint'] = True
    tree = material.node_tree
    nodes, links = tree.nodes, tree.links
    p = nodes.get('Principled BSDF')
    p.inputs['Metallic'].default_value = 0.0  # intact paint is a dielectric
    geo = nodes.new('ShaderNodeNewGeometry')

    def noise(scale, vector=None):
        n = nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = scale
        n.inputs['Detail'].default_value = 3
        links.new(vector or geo.outputs['Position'], n.inputs['Vector'])
        return n.outputs['Fac']

    def math(op, a, b):
        n = nodes.new('ShaderNodeMath'); n.operation = op
        for index, value in enumerate((a, b)):
            if isinstance(value, (int, float)): n.inputs[index].default_value = value
            else: links.new(value, n.inputs[index])
        return n.outputs[0]

    def ramp(source, stops):
        n = nodes.new('ShaderNodeValToRGB')
        r = n.color_ramp
        for i, (position, color) in enumerate(stops):
            e = r.elements[i] if i < 2 else r.elements.new(position)
            e.position = position; e.color = (*color, 1)
        links.new(source, n.inputs[0]); return n.outputs[0]

    coarse, fine = noise(3.5), noise(65)
    # Replaced per source object by the authored edge/collar distance field.
    edge_node = nodes.new('ShaderNodeValue'); edge_node.name = 'AuthoredWear'
    edge_node.outputs[0].default_value = .025
    edge = edge_node.outputs[0]
    chips = ramp(math('ADD', math('MULTIPLY', noise(22), .60), edge),
                 [(.54, (0, 0, 0)), (.62, (1, 1, 1))])
    streak_vector = nodes.new('ShaderNodeVectorMath'); streak_vector.operation = 'MULTIPLY'
    links.new(geo.outputs['Position'], streak_vector.inputs[0])
    streak_vector.inputs[1].default_value = (7, 7, .32)
    streak = noise(1, streak_vector.outputs[0])
    stain = math('MULTIPLY', math('MAXIMUM', math('SUBTRACT', streak, .58), 0), 1.8)
    faded = ramp(coarse, [(.15, (.50, .32, .06)), (.85, (.63, .43, .09))])
    dirty = nodes.new('ShaderNodeMixRGB'); dirty.blend_type = 'MIX'
    links.new(stain, dirty.inputs[0]); links.new(faded, dirty.inputs[1])
    dirty.inputs[2].default_value = (.20, .13, .045, 1)
    rust = ramp(coarse, [(.25, (.075, .027, .012)), (.75, (.23, .075, .025))])
    mix = nodes.new('ShaderNodeMixRGB'); links.new(chips, mix.inputs[0])
    links.new(dirty.outputs[0], mix.inputs[1]); links.new(rust, mix.inputs[2])
    links.new(mix.outputs[0], p.inputs['Base Color'])
    rough = math('ADD', .48, math('ADD', math('MULTIPLY', coarse, .14), math('MULTIPLY', chips, .23)))
    links.new(rough, p.inputs['Roughness'])
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .3
    bump.inputs['Distance'].default_value = .002
    links.new(math('SUBTRACT', fine, chips), bump.inputs['Height'])
    links.new(bump.outputs['Normal'], p.inputs['Normal'])


def wear_space(obj, source, cylinder=False):
    """Bake-only coordinates survive joining via an unexported reference empty.

    Panel wear follows the second nearest bounding face (the edge on a face),
    cylinder wear follows end collars. This avoids per-object pointiness turning
    a curved tube or an entire disconnected plate into a uniform rust field.
    """
    from mathutils import Vector
    if source not in list(obj.data.materials): return
    material = source.copy(); obj.data.materials[0] = material
    tree = material.node_tree; nodes, links = tree.nodes, tree.links
    space = bpy.data.objects.new('_WearSpace_' + obj.name, None)
    bpy.context.collection.objects.link(space)
    bpy.context.view_layer.update(); space.matrix_world = obj.matrix_world.copy()
    tex = nodes.new('ShaderNodeTexCoord'); tex.object = space
    split = nodes.new('ShaderNodeSeparateXYZ'); links.new(tex.outputs['Object'], split.inputs[0])
    bounds = [Vector(v) for v in obj.bound_box]
    low = [min(v[i] for v in bounds) for i in range(3)]
    high = [max(v[i] for v in bounds) for i in range(3)]

    def math(op, a, b):
        n = nodes.new('ShaderNodeMath'); n.operation = op
        for i, value in enumerate((a, b)):
            if isinstance(value, (int, float)): n.inputs[i].default_value = value
            else: links.new(value, n.inputs[i])
        return n.outputs[0]

    distances = [math('MINIMUM', math('SUBTRACT', split.outputs[i], low[i]),
                      math('SUBTRACT', high[i], split.outputs[i])) for i in range(3)]
    if cylinder: distance = distances[2]
    else:
        x, y, z = distances
        distance = math('MINIMUM', math('MINIMUM', math('MAXIMUM', x, y), math('MAXIMUM', x, z)), math('MAXIMUM', y, z))
    # Three-centimetre transition at handling edges, broken up by noise in the
    # main material. Faces retain a trace of isolated damage rather than spots.
    band = math('MAXIMUM', math('SUBTRACT', 1, math('DIVIDE', distance, .035)), 0)
    wear = math('ADD', .025, math('MULTIPLY', band, .32))
    old = nodes.get('AuthoredWear')
    for link in list(old.outputs[0].links): links.new(wear, link.to_socket)


def bake_paint(obj, source, asset_name, directory):
    if not any(slot.material and slot.material.get('crane_paint') for slot in obj.material_slots): return
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'; scene.cycles.samples = 8
    scene.render.bake.margin = 12
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
    directory = Path(directory); directory.mkdir(parents=True, exist_ok=True)
    images = {}
    # Non-paint surfaces also need an active target for Blender's bake operator;
    # their values are unused because their original materials remain separate.
    size = 1024 if asset_name in ('crane_cabin', 'crane_pedestal', 'crane_boom_30m') else 512
    if 'barrel' in asset_name: size = 256
    for channel, bake_type in [('basecolor', 'DIFFUSE'), ('roughness', 'ROUGHNESS'), ('normal', 'NORMAL')]:
        image = bpy.data.images.new(asset_name + '_' + channel, width=size, height=size)
        if channel != 'basecolor': image.colorspace_settings.name = 'Non-Color'
        targets = []
        for material in set(slot.material for slot in obj.material_slots if slot.material):
            node = material.node_tree.nodes.new('ShaderNodeTexImage'); node.image = image
            material.node_tree.nodes.active = node; targets.append((material, node))
        scene.render.bake.use_pass_direct = False; scene.render.bake.use_pass_indirect = False
        scene.render.bake.use_pass_color = True
        bpy.ops.object.bake(type=bake_type)
        image.filepath_raw = str(directory / (image.name + '.png')); image.file_format = 'PNG'; image.save()
        image.pack(); images[channel] = image
        for material, node in targets: material.node_tree.nodes.remove(node)
    baked = bpy.data.materials.new('Paint_Ochre_' + asset_name); baked.use_nodes = True
    p = baked.node_tree.nodes.get('Principled BSDF')
    for channel, socket in [('basecolor', 'Base Color'), ('roughness', 'Roughness')]:
        n = baked.node_tree.nodes.new('ShaderNodeTexImage'); n.image = images[channel]
        baked.node_tree.links.new(n.outputs['Color'], p.inputs[socket])
    texture = baked.node_tree.nodes.new('ShaderNodeTexImage'); texture.image = images['normal']
    normal = baked.node_tree.nodes.new('ShaderNodeNormalMap')
    baked.node_tree.links.new(texture.outputs['Color'], normal.inputs['Color'])
    baked.node_tree.links.new(normal.outputs['Normal'], p.inputs['Normal'])
    for slot in obj.material_slots:
        if slot.material and slot.material.get('crane_paint'): slot.material = baked
    # Joining the bake sources leaves one slot per source object. Compact equal
    # materials before export so a lattice boom does not become 124 draw calls.
    unique, remap = [], {}
    for index, slot in enumerate(obj.material_slots):
        if slot.material not in unique: unique.append(slot.material)
        remap[index] = unique.index(slot.material)
    indices = [remap[face.material_index] for face in obj.data.polygons]
    obj.data.materials.clear()
    for material in unique: obj.data.materials.append(material)
    for face, index in zip(obj.data.polygons, indices): face.material_index = index
    # Coordinate references are authoring helpers, never gameplay sockets.
    for helper in list(bpy.context.scene.objects):
        if helper.name.startswith('_WearSpace_'): bpy.data.objects.remove(helper, do_unlink=True)
