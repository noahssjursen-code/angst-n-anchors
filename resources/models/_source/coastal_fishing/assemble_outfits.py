"""Current fishing stock: simple line fisher and sheltered crabber equipment draft."""
from pathlib import Path
import copy,json
root=Path(__file__).resolve().parents[4]
base=json.loads((Path(__file__).parent/'shared_hull_cabin.json').read_text(encoding='utf-8'))
for id,name,price in [('fishing_hook_line','Coastal Line Fisher',3200),('fishing_crab','Coastal Crabber',6400)]:
    layout=copy.deepcopy(base);parts=layout['parts']
    def add(asset,pos,yaw=0):parts.append(dict(asset_id=asset,position=pos,yaw_degrees=yaw))
    tanks=[x for x in parts if x['asset_id']=='insulated_catch_tank']
    if id=='fishing_hook_line':
        for x in tanks[1:]:parts.remove(x)
        add('bait_work_table',[-1.5,2.92,2.6])
        add('hook_line_station',[2.05,2.92,2.5])
        layout['hull_colors']['upper']=[.12,.29,.43]
    else:
        layout['hull_colors']['upper']=[.64,.18,.055]
        for part in parts:
            if part['asset_id'].startswith(('cabin_wall','cabin_door','cabin_window')):part['colors']={'wall':[.93,.89,.74]}
        add('crabber_work_shelter',[0,2.92,1.7])
        add('bait_work_table',[-1.55,2.92,3.2])
        add('pot_hauler',[2.0,2.92,3.2])
        for x in [-1.55,-.45]:
            for z in [4.3,5.15]:
                for y in [2.92,3.52,4.12]:add('crab_creel',[x,y,z])
        add('pot_rope_buoy',[1.25,2.92,4.6])
    d=dict(format_version=3,id=id,name=name,hull_id=layout['hull'],shaft_power_kw=300,price_marks=price,draft=id=='fishing_crab',brick_layout=layout)
    (root/('resources/data/vessels/prebuilt/'+id+'.json')).write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8')
    if id=='fishing_crab':(root/'resources/models/examples/coastal_crabber_draft.json').write_text(json.dumps(layout,indent=2)+'\n',encoding='utf-8')
