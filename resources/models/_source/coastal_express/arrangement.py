"""Coastal Express editable measured arrangement, no complete-vessel mesh."""
import json, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
parts=[]
white={'wall':[.80,.81,.75]}
def add(a,x,y,z,yaw=0,colors=None,**kw):
    record=dict(asset_id=a,position=[x,y,z],yaw_degrees=yaw)
    if colors:record['colors']=colors
    record.update(kw);parts.append(record)
def slab(y,ring):
    add('floor_tile',0,y,0,colors=dict(surface=[.21,.27,.27],fascia=[.8,.81,.75],underside=[.8,.81,.75]),outline=ring)
def rail(a,b,y):
    dx=b[0]-a[0];dz=b[1]-a[1];n=round(math.hypot(dx,dz)*2)
    for length,aid in [(math.sqrt(10),'ferry_guard_1x3'),(math.sqrt(13),'ferry_guard_3x2')]:
        if abs(math.hypot(dx,dz)-length)<.001:
            add(aid,a[0],y,a[1],math.degrees(math.atan2(-dx,-dz)));return
    assert abs(n*.5-math.hypot(dx,dz))<.001,'Guard must use an exact authored run'
    for i in range(n): add('rail_straight_50cm',a[0]+dx*i/n,y,a[1]+dz*i/n,math.degrees(math.atan2(-dx,-dz)))

for n in range(12):
    z=-12.375+n*2.25
    for s in [-1,1]:
        add('ferry_saloon_bay_225cm',s*4.7,3.2,z,0 if s>0 else 180,white)
        add('ferry_rubbing_strake_225cm',s*5.51,2.45,z)
    add('ferry_saloon_roof_open_225cm' if n in [1,2,3] else 'ferry_saloon_roof_225cm',0,5.67,z,colors=white)
# Twenty-four rows with 0.9 m pitch; no seat intersects the main bow vestibule
# or aft entry/service area. Three longitudinal aisles continue end to end.
for row in range(24):add('ferry_seating_row_10',0,3.2,10.9-row*.9,colors=dict(upholstery=[.10,.22,.28]))
# Saloon end bulkheads use existing tested doors/windows, with a trim header
# up to the new roof height. Bow door leads into the boarding foredeck.
for z,yaw in [(13.5,270)]:
    for i in range(9):
        x=(-4.5+i) if yaw==270 else (4.5-i)
        add('cabin_door_straight' if i==4 else 'cabin_window_straight',x,3.2,z,yaw,white)
add('ferry_end_header',0,5.4,13.5,colors=white)
add('ferry_saloon_front',0,3.2,-13.5,colors=white)
add('cabin_door_straight',.5,3.2,-13.5,90,white)
# Aft waiting/luggage zone is outside the passenger saloon, beneath a canopy.
for x in [-3.6,3.6]:add('ferry_luggage_rack',x,3.2,15.6,colors=white)
for p in json.loads((ROOT/'vessels/catamaran_36x11/rail_flat_assembly.json').read_text())['placements']:parts.append(p)
# Forward elevated bridge; the upper deck extends aft around the stair opening.
slab(5.9,[[-4,-7.5],[-1,-7.5],[-1,-9.5],[1,-9.5],[1,-7.5],[4,-7.5],[4,-12.5],[3,-13.5],[-3,-13.5],[-4,-12.5]])
add('ferry_bridge_front',0,5.9,-11.8,colors=white)
for s in [-1,1]:
    for z in [-10.8,-8.8]:add('ferry_bridge_side_2m',s*3.65,5.9,z,colors=white)
for i in range(7):
    if i!=3:add('cabin_wall_straight',-3.5+i,5.9,-7.5,270,{'wall':[.55,.055,.035]})
add('ferry_bridge_roof',0,8.1,-10.3,colors=white)
add('ferry_bridge_stair_trunk',0,5.67,-6.0,colors=white)
# Stairs inside the wide central aisle; front rows are shifted out of the
# bridge stair throat, leaving circulation around both sides of the opening.
add('ferry_bridge_stair_270cm',0,3.2,-6.0,colors=white)
for x in [-1.5,-.5,.5,1.5]:add('cabin_console_straight',x,5.9,-11.65,270,white)
for x in [-1,1]:
    add('helm_chair',x,5.9,-10.4)
    add('helm_display',x,6.74,-11.6)
add('helm_wheel',-.8,6.74,-11.3)
add('helm_throttle',.4,6.74,-11.3)
add('ferry_bow_ramp_2m',0,3.2,-18.5)
for x in [-1.15,1.15]:rail((x,-13.6),(x,-16.1),3.2)
for s in [-1,1]:
    rail((s*5.25,-11.0),(s*5.25,-12.0),3.2)
    rail((s*5.25,-12.0),(s*4.25,-15.0),3.2)
    rail((s*4.25,-15.0),(s*1.25,-17.0),3.2)
    add('feeder_liferaft',s*3.7,5.95,4.0,90,white)
    add('feeder_liferaft',s*3.7,5.95,6.2,90,white)
    add('nav_port' if s<0 else 'nav_starboard',s*3.76,7.6,-11.2)
    add('deck_mushroom_vent',s*2.8,5.95,10.5,colors=white)
add('ferry_radar_mast',0,8.3,-9.5,colors=white)
add('nav_stern',0,5.5,13.7)
add('mast_lantern',0,10.55,-9.5)
d=dict(version=1,hull='catamaran_36x11',parts=parts,hull_colors=dict(upper=[.80,.81,.75],lower=[.065,.085,.09],deck=[.27,.30,.29]),engine_preset='catamaran_3600',rising_bow=False,active_floor=0,cell_offset=0,show_all_floors=True)
(ROOT/'examples/coastal_express_recipe.json').write_text(json.dumps(d,indent=2)+'\n')
print('COASTAL EXPRESS RECIPE',len(parts),'parts; 240 physical seat sockets')
