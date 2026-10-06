"""Add removable lighting placements to the supplied example drafts, idempotently.
Run after rebuilding any of the example arrangements. No user drafts are touched.
"""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ids={'deck_floodlight','nav_port','nav_starboard','nav_stern','mast_lantern'}
for name,deck,beam,front,rear,house in [
    ('coastal_trawler_draft',2.92,5,-2.5,6.5,-.5),
    ('coastal_cargo_draft',3.6,8,-5.1,11.5,9.5),
    ('coastal_bulk_draft',3.6,8,-5.1,11.5,9.5),
    ('coastal_32m_draft',4.5,10,-7,15.5,13.5),
]:
    p=ROOT/'examples'/f'{name}.json';draft=json.loads(p.read_text(encoding='utf-8'))
    parts=[r for r in draft['parts'] if r['asset_id'] not in ids]
    def add(id,x,z,yaw=0):parts.append({'asset_id':id,'position':[x,deck,z],'yaw_degrees':yaw,'colors':{'wall':[.58,.63,.62]}})
    # Lamps sit on their own metre-scale standards. No floating roof placements.
    add('nav_port',-beam/2+.3,front+.45)
    add('nav_starboard',beam/2-.3,front+.45)
    add('nav_stern',.9,rear)
    if beam==10:
        add('mast_lantern',4,14.4)
        parts[-1]['position'][1]=6.7
    else:add('mast_lantern',1.85,house)
    if beam==5:
        add('deck_floodlight',-2.12,.5,215);add('deck_floodlight',2.12,.5,145)
    else:
        add('deck_floodlight',-beam/2+.85,5 if beam==8 else 7,325)
        add('deck_floodlight',beam/2-.85,5 if beam==8 else 7,35)
    draft['parts']=parts;p.write_text(json.dumps(draft,indent=2),encoding='utf-8')
    print(name,len(parts),'placements including six independent lights')
