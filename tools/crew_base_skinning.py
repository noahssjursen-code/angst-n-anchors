"""Remap the CC0 anatomical source's skin weights to the game's crew rig.

No geometry or weights are invented here. Related source twist, face and
metacarpal groups are merged into the corresponding game bone, then reduced to
four normalized influences for glTF/Godot skinning.
"""
import json
from pathlib import Path


def _game_bone(source):
    side = source[-2:] if source.endswith(('.L', '.R')) else ''
    name = source[:-2] if side else source
    if name in ('root', 'pelvis', 'spine04', 'spine05'):
        return 'hips'
    if name == 'spine03':
        return 'spine'
    if name in ('breast', 'spine01', 'spine02'):
        return 'chest'
    if name in ('neck01', 'neck02', 'neck03'):
        return 'neck'
    if name in ('clavicle', 'shoulder01'):
        return 'clavicle'+side
    for prefix, target in (
        ('upperarm', 'upper_arm'), ('lowerarm', 'forearm'),
        ('upperleg', 'thigh'), ('lowerleg', 'shin'),
        ('metacarpal', 'hand'), ('wrist', 'hand'),
        ('toe', 'foot'), ('foot', 'foot'),
    ):
        if name.startswith(prefix):
            return target+side
    if name.startswith('finger'):
        digit, joint = map(int, name[len('finger'):].split('-'))
        if digit == 1:
            return ('thumb_01' if joint <= 2 else 'thumb_02')+side
        digit_name = {2: 'index', 3: 'middle', 4: 'ring', 5: 'little'}[digit]
        return '%s_%02d%s' % (digit_name, joint, side)
    if name in ('head', 'jaw') or name.startswith((
        'eye', 'levator', 'oculi', 'orbicularis', 'oris', 'risorius',
        'special', 'temporalis', 'tongue',
    )):
        return 'head'
    raise ValueError('Unmapped anatomical source bone: '+source)


def mapped_weights(reference_dir):
    """Return original source vertex index -> {game bone: normalized weight}."""
    payload = json.loads((Path(reference_dir)/'weights.default.json').read_text(encoding='utf-8'))
    result = {}
    for source, pairs in payload['weights'].items():
        target = _game_bone(source)
        for index, weight in pairs:
            if weight <= 0:
                continue
            influences = result.setdefault(int(index), {})
            influences[target] = influences.get(target, 0.0)+float(weight)
    for index, influences in result.items():
        strongest = sorted(influences.items(), key=lambda item: (-item[1], item[0]))[:4]
        total = sum(weight for _, weight in strongest)
        result[index] = {bone: weight/total for bone, weight in strongest}
    return result
