"""Fit CC0 eye geometry to the new anatomical base's authored helper vertices.

This reads the documented MHCLO data format; it does not embed upstream addon
program code. Inputs/outputs of fit_eyes remain in source (MakeHuman) coordinates.
"""
from pathlib import Path


def fit_eyes(reference_dir, shaped_source_vertices):
    reference_dir = Path(reference_dir)
    scales = [1.0, 1.0, 1.0]
    links = []
    reading = False
    for raw in (reference_dir / 'eyes-high-poly.mhclo').read_text(encoding='utf-8').splitlines():
        bits = raw.split()
        if not bits or bits[0].startswith('#'):
            continue
        if bits[0] in ('x_scale', 'y_scale', 'z_scale'):
            axis = {'x_scale': 0, 'y_scale': 1, 'z_scale': 2}[bits[0]]
            a, b, length = int(bits[1]), int(bits[2]), float(bits[3])
            scales[axis] = abs(shaped_source_vertices[a][axis]-shaped_source_vertices[b][axis])/length
        elif bits[0] == 'verts':
            reading = True
        elif reading:
            if not bits[0].lstrip('-').isdigit():
                reading = False
                continue
            if len(bits) == 1:
                links.append(((int(bits[0]),)*3, (1., 0., 0.), (0., 0., 0.)))
            elif len(bits) == 9:
                links.append((tuple(map(int, bits[:3])), tuple(map(float, bits[3:6])), tuple(map(float, bits[6:9]))))
            else:
                raise ValueError('Unexpected eye mapping row: '+raw)
    vertices = []
    for indices, weights, offset in links:
        vertices.append(tuple(sum(shaped_source_vertices[indices[k]][axis]*weights[k] for k in range(3))+offset[axis]*scales[axis] for axis in range(3)))
    uvs, faces, face_uvs = [], [], []
    source_count = 0
    for raw in (reference_dir / 'eyes-high-poly.obj').read_text(encoding='utf-8').splitlines():
        bits = raw.split()
        if not bits:
            continue
        if bits[0] == 'v':
            source_count += 1
        elif bits[0] == 'vt':
            uvs.append(tuple(map(float, bits[1:3])))
        elif bits[0] == 'f':
            refs = [b.split('/') for b in bits[1:]]
            faces.append(tuple(int(r[0])-1 for r in refs))
            face_uvs.append(tuple(uvs[int(r[1])-1] for r in refs))
    if source_count != len(vertices):
        raise ValueError('Eye mapping vertex count does not match source mesh')
    return vertices, faces, face_uvs


def create_eyes(reference_dir, shaped_source_vertices, transform_point, objects=None):
    """Create the fitted Blender Eyes mesh; caller owns rigging and shape keys."""
    import bpy
    import bmesh
    reference_dir = Path(reference_dir)
    vertices, faces, uv_faces = fit_eyes(reference_dir, shaped_source_vertices)
    # The source contains a transparent corneal layer mapped into its atlas's
    # lower-right empty quadrant. Use its opaque eyeball alone for a stable game
    # material; smooth specular highlights provide corneal gloss without sorting.
    kept = [i for i, uv in enumerate(uv_faces) if not (sum(p[0] for p in uv)/len(uv) > .85 and sum(p[1] for p in uv)/len(uv) < .15)]
    data = bpy.data.meshes.new('Eyes')
    data.from_pydata([transform_point(p) for p in vertices], [], [faces[i] for i in kept])
    data.update()
    obj = bpy.data.objects.new('Eyes', data)
    bpy.context.collection.objects.link(obj)
    uv_layer = data.uv_layers.new(name='UVMap')
    for poly, source in zip(data.polygons, kept):
        poly.use_smooth = True
        for loop_index, uv in zip(poly.loop_indices, uv_faces[source]):
            uv_layer.data[loop_index].uv = uv
    material = bpy.data.materials.new('Eyes')
    material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .28
    shader.inputs['IOR'].default_value = 1.38
    texture = material.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = bpy.data.images.load(str(reference_dir/'brown_eye.png'), check_existing=True)
    texture.image.pack()
    material.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    data.materials.append(material)
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    if objects is not None:
        objects.append(obj)
    return obj
