"""An editable arrangement; every structural component remains a placement."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
draft=json.loads((ROOT/'examples/coastal_cargo_draft.json').read_text())
parts=[]
for record in draft['parts']:
    if record['asset_id'].startswith(('cabin_','helm_','roof_')):
        record['position'][1]=round(record['position'][1]+.9,5)
        if record['asset_id'].startswith('roof_'):
            for vertex in record['outline']:vertex[1]+=4
        else:record['position'][2]+=4
        parts.append(record)
parts+=json.loads((ROOT/'vessels/hull_32x10/halfwall_flat_assembly.json').read_text())['placements']
parts.append({'asset_id':'hold_coaming_6x12','position':[0,4.5,0],'yaw_degrees':0,'colors':{'wall':[.30,.38,.40]}})
for z in [-4.5,-1.5,1.5,4.5]:
    parts.append({'asset_id':'hatch_cover_6x3','position':[0,5.24,z],'yaw_degrees':0,'colors':{'wall':[.40,.47,.47]}})
draft.update(hull='hull_32x10',parts=parts,rising_bow=False,active_floor=0,cell_offset=0)
draft['hull_colors']={'upper':[.085,.18,.27],'lower':[.29,.07,.045],'deck':[.32,.36,.35]}
(ROOT/'examples/coastal_32m_draft.json').write_text(json.dumps(draft,indent=2))
mounts=json.loads((ROOT/'parts/stern_gear/mounts_24m.json').read_text())
mounts.update(hull='hull_32x10',support=[0,1.2,15.0],propeller=[0,1.2,15.48],rudder=[0,1.85,16.03])
mounts['note']='32 m raked stern installation, explicit metre coordinates. Shared hardware sizing remains provisional.'
(ROOT/'parts/stern_gear/mounts_32m.json').write_text(json.dumps(mounts,indent=2))
print('COASTER_EXAMPLE',len(parts),'individual placements')
