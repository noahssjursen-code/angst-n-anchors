"""Editable 32 m coaster arrangement. Individual parts, exact grid endpoints."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
draft=json.loads((ROOT/'examples/coastal_cargo_draft.json').read_text(encoding='utf-8'))
parts=[]
def add(a,x,y,z,yaw=0,colors=None,**extra):
    record=dict(asset_id=a,position=[x,y,z],yaw_degrees=yaw)
    if colors is not None:record['colors']=colors
    record.update(extra);parts.append(record)
paint={'wall':[.73,.78,.76]}
surfaces={'surface':[.32,.40,.39],'fascia':[.72,.77,.75],'underside':[.72,.77,.75]}
# Lower accommodation 5 x 6 m, aft entrance.
for i in range(5):
    add('cabin_door_straight' if i==2 else 'cabin_wall_straight',-2.5+i,4.5,15,270,paint)
    add('cabin_window_straight' if i in [1,3] else 'cabin_wall_straight',2.5-i,4.5,9,90,paint)
for i in range(6):
    style='window' if i in [1,3,4] else 'wall'
    add('cabin_'+style+'_straight',-2.5,4.5,15-i,0,paint)
    starboard_style='window' if i in [1,2,4] else 'wall'
    add('cabin_'+starboard_style+'_straight',2.5,4.5,9+i,180,paint)
deck=[[-2.5,9],[2.5,9],[2.5,12],[4.5,12],[4.5,15],[-2.5,15]]
# 5 mm floor finish clears the lower wall's horizontal top cap; floor datum
# and stair sockets remain at 6.7. No coplanar top surfaces at the deck seam.
add('floor_tile',0,6.705,0,colors=surfaces,outline=deck)
# Upper bridge: 2:1 shoulders, 45-degree corners, 3 m front glazing.
for i in range(5):add('cabin_window_straight' if i in [1,3] else 'cabin_wall_straight',-2.5+i,6.7,14,270,paint)
for i in range(3):
    add('cabin_window_straight',-2.5,6.7,14-i,0,paint)
    add('cabin_door_straight' if i==1 else 'cabin_window_straight',2.5,6.7,11+i,180,paint)
add('cabin_window_26_port',-2.5,6.7,11,0,paint)
add('cabin_window_45_port',-2,6.7,10,0,paint)
for i in range(3):add('cabin_window_straight',-1.5+i,6.7,9.5,270,paint)
add('cabin_window_45_port',1.5,6.7,9.5,270,paint)
add('cabin_window_26_starboard',2,6.7,10,180,paint)
outline=[[-2.5,14],[2.5,14],[2.5,11],[2,10],[1.5,9.5],[-1.5,9.5],[-2,10],[-2.5,11]]
add('roof_tile',0,8.9,0,colors=surfaces,outline=outline,crown=True,visor_direction=1)
console={'wall':[.22,.31,.33]}
add('cabin_console_26p',-2.5,6.7,11,0,console)
add('cabin_console_45p',-2,6.7,10,0,console)
for i in range(3):add('cabin_console_straight',-1.5+i,6.7,9.5,270,console)
add('cabin_console_45p',1.5,6.7,9.5,270,console)
add('cabin_console_26s',2,6.7,10,180,console)
add('helm_chair',0,6.7,11.1)
add('helm_wheel',0,7.55,9.86)
add('helm_throttle',.68,7.55,9.86)
add('helm_display',-.7,7.55,9.8)
add('passenger_seat',-1.55,6.7,12.8)
for z in [13,12,11]:add('cabin_bench_straight',-2.5,4.5,z,0)
# Exact flight ends at the balcony; leave a 1 m stair-head opening.
add('deck_stair_220cm',3.5,4.5,9,180,paint)
for z in [12.4,14.6]:add('deck_bracket_2m',2.5,6.7,z,0,paint)
for z in [12,13,14]:add('rail_straight_100cm',4.5,6.7,z,180)
for x in [-2.5,-1.5,-.5,.5,1.5,2.5,3.5]:add('rail_straight_100cm',x,6.7,15,270)
add('rail_straight_100cm',-2.5,6.7,15,0)
add('rail_straight_50cm',2.5,6.7,12,270)
add('rail_straight_50cm',4,6.7,12,270)
parts+=json.loads((ROOT/'vessels/hull_32x10/halfwall_flat_assembly.json').read_text(encoding='utf-8'))['placements']
add('hold_coaming_6x12',0,4.5,0,colors={'wall':[.30,.38,.40]})
for z in [-4.5,-1.5,1.5,4.5]:add('hatch_cover_6x3',0,5.24,z,colors={'wall':[.40,.47,.47]})
draft.update(hull='hull_32x10',parts=parts,rising_bow=False,active_floor=0,cell_offset=0)
draft['hull_colors']={'upper':[.085,.18,.27],'lower':[.29,.07,.045],'deck':[.32,.36,.35]}
(ROOT/'examples/coastal_32m_draft.json').write_text(json.dumps(draft,indent=2),encoding='utf-8')
print('COASTER_EXAMPLE',len(parts),'individual placements; lighting fitted separately')
