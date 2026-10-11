"""Assemble a builder draft; never export the complete boat as one mesh."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
draft=json.loads((ROOT/'examples/coastal_trawler_draft.json').read_text())
parts=[]
for p in draft['parts']:
    if p['asset_id'].startswith(('cabin_','helm_','roof_')):
        p['position'][1]=round(p['position'][1]+.68,5)
        if p['asset_id'].startswith('roof_'):
            for vertex in p['outline']:vertex[1]+=10
        else:p['position'][2]+=10
        parts.append(p)
# Aft bridge spans z=6..10. Long central opening has 1.5 m side walkways.
parts+=json.loads((ROOT/'vessels/hull_24x8/halfwall_flat_assembly.json').read_text())['placements']
for id,pos in [('hold_coaming_5x8',[0,3.6,0]),('hatch_cover_5x4',[0,4.34,-2]),('hatch_cover_5x4',[0,4.34,2])]:
    parts.append({'asset_id':id,'position':pos,'yaw_degrees':0.0,'colors':{'wall':[.34,.40,.38]}})
draft.update(hull='hull_24x8',parts=parts,rising_bow=False)
draft['hull_colors']['upper']=[.17,.25,.30]
(ROOT/'examples/coastal_cargo_draft.json').write_text(json.dumps(draft,indent=2))
mounts=json.loads((ROOT/'parts/stern_gear/mounts_14m.json').read_text())
mounts['hull']='hull_24x8'
for key in ['support','propeller','rudder']:
    mounts[key][1]+=.2;mounts[key][2]+=5
mounts['note']='24 m external transom prototype; shared hardware, explicit mounts, no scale transform. Propulsion sizing provisional.'
(ROOT/'parts/stern_gear/mounts_24m.json').write_text(json.dumps(mounts,indent=2))
print('CARGO_EXAMPLE',len(parts),'individual placements')
