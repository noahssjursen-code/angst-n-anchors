import bpy,sys,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tools'))
source=root/'resources/models/_source/crew_base/crew_base.blend';out=root/'resources/models/crew_base'
bpy.ops.wm.open_mainfile(filepath=str(source));rig=bpy.data.objects['CrewRig']
for tr in rig.animation_data.nla_tracks:tr.mute=True
rig.animation_data.action=None
from crew_base_hand_grips import author_grips
author_grips(rig,json.loads((out/'hand_contacts.json').read_text()),out)
bpy.ops.wm.save_as_mainfile(filepath=str(source))
