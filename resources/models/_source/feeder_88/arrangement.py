"""Produce an editable placement recipe; assemble/save it in the Shipyard editor
with tests/feeder_authoring.tscn. No complete-vessel mesh is exported.
"""
import json, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parts=[]
white={'wall':[.72,.75,.69]}
def add(a,x,y,z,yaw=0,colors=None,**kw):
    p=dict(asset_id=a,position=[x,y,z],yaw_degrees=yaw)
    if colors: p['colors']=colors
    p.update(kw);parts.append(p)
def slab(a,y,ring):
    add(a,0,y,0,outline=ring,colors=dict(surface=[.25,.30,.29],fascia=[.72,.75,.69],underside=[.72,.75,.69]))
def rail(a,b,y):
    dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
    n=round(length*2)
    for i in range(n):
        add('rail_straight_50cm',a[0]+dx*i/n,y,a[1]+dz*i/n,math.degrees(math.atan2(-dx,-dz)))
def rectangle(y):
    for i in range(6):
        add('cabin_door_straight' if i==3 else 'cabin_wall_straight',-3+i,y,42,270,white)
        add('cabin_wall_straight',3-i,y,35,90,white)
    for i in range(7):
        for s in [-1,1]:
            add('cabin_window_straight' if i in [1,3,5] else 'cabin_wall_straight',s*3,y,42-i if s<0 else 35+i,0 if s<0 else 180,white)

# Forty independent 20-foot ISO foundations. Container identity/mass belongs to
# cargo gameplay, never the preset; stock ships are sold empty.
for bay in range(10):
    for x in [-4.5,-1.5,1.5,4.5]:add('container_bed_20ft',x,5.6,-29.25+bay*6.5)
perimeter=json.loads((ROOT/'vessels/hull_88x14/halfwall_flat_assembly.json').read_text())['placements']
for p in perimeter:
    p['colors']={'wall':[.09,.19,.23]};parts.append(p)
rectangle(5.6);rectangle(7.8)
# Gallery with an open forward stair throat; upper T-deck leaves the second
# stair open to the sky rather than placing a solid slab through its headroom.
slab('floor_tile',7.805,[[-6,35],[3,35],[3,36],[6,36],[6,43],[-6,43]])
top=[[-6,35],[6,35],[6,38],[3,38],[3,43],[-6,43],[-6,41.5],[-3.5,41.5],[-3.5,38],[-6,38]]
slab('floor_tile',10.005,top)
add('deck_stair_wide_220cm',4.5,5.6,33,180,white)
add('deck_stair_wide_220cm',-4.5,7.8,41,0,white)
for a,b in [((6,36),(6,43)),((6,43),(-6,43)),((-6,43),(-6,35)),((-6,35),(-3,35)),((3,36),(3.5,36)),((5.5,36),(6,36))]:rail(a,b,7.8)
for a,b in [((3,38),(3,43)),((3,43),(-6,43)),((-6,43),(-6,41.5)),((-6,41.5),(-5.5,41.5)),((-3.5,41.5),(-3.5,38))]:rail(a,b,10.0)
# T-shaped wheelhouse: wide forward crossbar / narrow aft chart room.
ring=[[-6,35],[6,35],[6,38],[3,38],[3,42],[-3,42],[-3,38],[-6,38]]
for a,b in zip(ring,ring[1:]+ring[:1]):
    dx=b[0]-a[0];dz=b[1]-a[1];n=round(math.hypot(dx,dz))
    for i in range(n):
        x=a[0]+dx*i/n;z=a[1]+dz*i/n
        kind='cabin_window_straight'
        if z>=38 and abs(x)<=3:kind='cabin_wall_straight'
        if a[1]==42 and abs(x-.0)<.01:kind='cabin_door_straight'
        if a[1]==38 and x==-4:kind='cabin_door_straight'
        add(kind,x,10,z,math.degrees(math.atan2(-dx,-dz)),white)
slab('roof_tile',12.2,ring)
for x in [-3,3]:
    for z in [36.5,39.5,42.0]:add('deck_bracket_2m',x,7.8,z,0 if x>0 else 180,white)
for x in [-3,3]:add('deck_bracket_2m',x,10,36.5,0 if x>0 else 180,white)
for x in [-1,0,1]:add('cabin_console_straight',x,10,35.4,270,white)
add('helm_wheel',0,10.84,35.8)
add('helm_throttle',1.1,10.84,35.8)
add('helm_display',-.7,10.84,35.4)
add('helm_display',.65,10.84,35.4)
add('helm_chair',0,10,37.0)
for x in [-5.4,5.4]:add('passenger_seat',x,10,36.5)
for y in [5.6,7.8]:
    for z in [37,39]:add('cabin_bench_straight',-3,y,z)
    add('passenger_seat',1.8,y,40)
    add('wall_vent_louvre',0,y,35,colors=white)
add('cabin_console_straight',-2.5,10,40,0,white)
add('feeder_funnel',1.65,12.2,40.5,colors={'wall':[.77,.35,.085]})
add('feeder_signal_mast',0,12.2,36.8,colors=white)
# Main-deck cradles keep the upper escape/gallery passage unobstructed.
for x in [-4.6,4.6]:add('feeder_liferaft',x,5.6,40.5,90,white)
add('feeder_windlass',0,5.6,-38,colors=white)
for side in [-1,1]:add('feeder_stowed_anchor',side*5.01,4.7,-36,0 if side>0 else 180)
for x in [-1.9,1.9]:add('deck_mushroom_vent',x,5.6,-38.8,colors=white)
for x in [-6.1,6.1]:
    for z in [-31,0,31]:add('deck_floodlight',x,5.6,z,90 if x<0 else 270)
for side,aid in [(-1,'nav_port'),(1,'nav_starboard')]:add(aid,side*6.05,11.7,35.3)
add('nav_stern',0,7.3,43.7)
add('mast_lantern',0,17.0,36.8)
add('mast_lantern',0,5.6,-40.5)
d=dict(version=1,hull='hull_88x14',parts=parts,hull_colors=dict(upper=[.09,.19,.23],lower=[.29,.08,.055],deck=[.25,.30,.28]),engine_preset='feeder_1500',rising_bow=False,active_floor=0,cell_offset=0,show_all_floors=True)
(ROOT/'examples/container_feeder_40_recipe.json').write_text(json.dumps(d,indent=2)+'\n')
print('FEEDER RECIPE',len(parts),'editable placements, 40 ISO positions')
