"""Blender-authored continuous neck/head poses shared by source and GLB export."""
from mathutils import Vector, Matrix


def add_head_morphs(body):
    if body.data.shape_keys:
        body.shape_key_clear()
    body.shape_key_add(name='Basis')
    rest_positions = []
    weights = []
    rest = body.shape_key_add(name='WaterRest')
    for source, vertex in zip(body.data.vertices, rest.data):
        t = min(1., max(0., (source.co.y - .055) / .15))
        weight = t*t*(3.-2.*t)
        # Raise and draw back the upper neck; keep head/bill level, chest fixed.
        vertex.co = source.co + Vector((0, -.045, .110)) * weight
        rest_positions.append(vertex.co.copy())
        weights.append(weight)
    rest.value = 0
    for name, angle, axis in [('NeckLift', .12, 'X'), ('LookLeft', .65, 'Z'), ('LookRight', -.65, 'Z')]:
        key = body.shape_key_add(name=name)
        pivot = Vector((0, .100, .185))
        for source, vertex, at_rest, weight in zip(body.data.vertices, key.data, rest_positions, weights):
            posed = pivot + Matrix.Rotation(angle * weight, 3, axis) @ (at_rest - pivot)
            if name == 'NeckLift':
                posed += Vector((0, 0, .028)) * weight
            # Additive idle deltas authored around WaterRest, not the flight neck.
            vertex.co = source.co + (posed - at_rest)
        key.value = 0
    call = body.shape_key_add(name='Call')
    for source, vertex in zip(body.data.vertices, call.data):
        # Lower mandible only; upper bill and skull stay fixed.
        weight = min(1., max(0., (source.co.y - .310) / .080))
        if source.co.z < .123 and source.co.y > .310:
            vertex.co.z -= .018 * weight
    call.value = 0
