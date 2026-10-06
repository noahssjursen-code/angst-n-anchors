"""Finish official starter arrangements from the individually editable model kits.

Run with ordinary Python. The generated version-3 prebuilts are the shared source
for onboarding, shipwright stock and editor copies; example fixtures stay intact.
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT.parent / 'data/vessels/prebuilt'
OUT.mkdir(parents=True, exist_ok=True)

def load(name):
    return json.loads((ROOT / f'examples/{name}_draft.json').read_text(encoding='utf-8'))

def add(d, asset, x, y, z, yaw=0, colors=None, **extra):
    p = dict(asset_id=asset, position=[x,y,z], yaw_degrees=yaw)
    if colors is not None: p['colors'] = copy.deepcopy(colors)
    p.update(extra)
    d['parts'].append(p)

def finish(d, pid, name, power, price):
    d.update(format='imported_models', hull_id=d['hull'], active_floor=0, cell_offset=0, show_all_floors=True)
    d['engine_preset']={'trawler_hull_14m':'compact_300','hull_24x8':'coastal_700','hull_32x10':'freighter_1100'}[d['hull']]
    preset = dict(format_version=3, id=pid, name=name, hull_id=d['hull'],
                  shaft_power_kw=power, price_marks=price, draft=False, brick_layout=d)
    (OUT / (pid+'.json')).write_text(json.dumps(preset, indent=2)+'\n', encoding='utf-8')
    print(name, len(d['parts']), 'individual editable parts')

def cabin_seats(d, y, aft, side=1):
    add(d,'passenger_seat',-.85,y,aft-1.2)
    add(d,'cabin_bench_straight',1.5,y,aft-2,180)

def repaint(d, upper, wall):
    d['hull_colors'] = {'upper':upper,'lower':[.29,.075,.055],'deck':[.28,.33,.33]}
    for p in d['parts']:
        if p['asset_id'].startswith(('cabin_wall','cabin_window','cabin_door','halfwall')):
            p['colors'] = {'wall':wall}

trawler = load('coastal_trawler')
repaint(trawler,[.15,.30,.35],[.76,.78,.70])
cabin_seats(trawler,2.92,0)
# Roof edge outside the walk route. These housings are static equipment.
add(trawler,'marine_exhaust_stack',1.08,5.228,-.55,colors={'wall':[.21,.28,.29]})
add(trawler,'wall_vent_louvre',1,2.92,0,180)
finish(trawler,'fishing_trawler','Coastal Trawler',300,5600)

cargo = load('coastal_cargo')
cargo['parts'] = [p for p in cargo['parts'] if p['asset_id'] not in ['hatch_cover_5x4','hold_coaming_5x8']]
# Raise the complete existing bridge one standard 2.2 m floor; keep its parts.
for p in cargo['parts']:
    if p['asset_id'].startswith(('cabin_','helm_')) or p['asset_id']=='roof_tile':
        p['position'][1] = round(p['position'][1]+2.2,4)
    if p['asset_id']=='mast_lantern':
        p['position'] = [3.15,5.8,10.55]
paint = {'wall':[.76,.75,.65]}
for i in range(3):
    add(cargo,'cabin_door_straight' if i==1 else 'cabin_wall_straight',-1.5+i,3.6,10,270,paint)
    add(cargo,'cabin_wall_straight',1.5-i,3.6,6,90,paint)
for i in range(4):
    for side in [-1,1]:
        add(cargo,'cabin_window_straight' if i in [1,2] else 'cabin_wall_straight',side*1.5,3.6,10-i if side<0 else 6+i,0 if side<0 else 180,paint)
add(cargo,'floor_tile',0,5.805,0,outline=[[-1.5,6],[1.5,6],[1.5,8.5],[3.5,8.5],[3.5,11],[-1.5,11]],colors={'surface':[.30,.35,.33],'fascia':[.76,.75,.65],'underside':[.76,.75,.65]})
add(cargo,'deck_stair_wide_220cm',2.75,3.6,5.5,180,paint)
for z in [8.8,10.5]: add(cargo,'deck_bracket_2m',1.5,5.8,z,colors=paint)
for z in [8.5,9.5]: add(cargo,'rail_straight_100cm',3.5,5.8,z,180)
add(cargo,'rail_straight_50cm',3.5,5.8,10.5,180)
for x in [-1.5,-.5,.5,1.5,2.5]: add(cargo,'rail_straight_100cm',x,5.8,11,270)
add(cargo,'rail_straight_100cm',-1.5,5.8,11)
for x in [1.5]: add(cargo,'rail_straight_50cm',x,5.8,8.5,270)
add(cargo,'cargo_deck_5x8',0,3.6,0)
for x in [-1.25,1.25]: add(cargo,'container_bed_20ft',x,3.6,0)
cabin_seats(cargo,5.8,10)
for z in [8,9]: add(cargo,'cabin_bench_straight',-1.5,3.6,z)
add(cargo,'deck_mushroom_vent',-2.5,3.6,9.5,colors=paint)
add(cargo,'wall_vent_louvre',0,3.6,6,colors=paint)
add(cargo,'marine_exhaust_stack',1.08,8.108,9.45,colors={'wall':[.25,.29,.26]})
for part in cargo['parts']:
    if part['asset_id']=='deck_floodlight' and part['position'][0]>0:part['position']=[3.6,3.6,4.5]
repaint(cargo,[.42,.22,.08],[.76,.75,.65])
finish(cargo,'28_10_m','Harbour Cargo',700,10500)

bulk = load('coastal_bulk')
bulk['parts'] = [p for p in bulk['parts'] if p['asset_id']!='hatch_cover_5x4']
repaint(bulk,[.12,.28,.20],[.75,.79,.72])
cabin_seats(bulk,3.6,10)
add(bulk,'deck_mushroom_vent',-2.6,3.6,9.5,colors=paint)
add(bulk,'marine_exhaust_stack',1.08,5.908,9.45,colors={'wall':[.18,.27,.22]})
finish(bulk,'bulk_small','Coastal Bulk',700,10500)

coaster = load('coastal_32m')
coaster['parts'] = [p for p in coaster['parts'] if p['asset_id']!='hatch_cover_6x3']
repaint(coaster,[.08,.17,.29],[.73,.78,.76])
for z in [10,11,12]: add(coaster,'cabin_bench_straight',2.5,4.5,z,180)
add(coaster,'marine_exhaust_stack',1.9,9.001,13.4,colors={'wall':[.20,.28,.35]})
finish(coaster,'coastal_coaster','Coastal Freighter',1100,16500)
