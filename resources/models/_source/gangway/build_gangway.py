"""Reusable 4 m marine boarding gangway. +Y away from ship, Z up, metres."""
from pathlib import Path
exec((Path(__file__).resolve().parents[1]/'fishing_kit/build_fishing_kit.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'parts'/'gangway';OUT.mkdir(parents=True,exist_ok=True)
clear()
steel=mat('Fixed_Galvanized',(.50,.57,.59),.8)
grip=mat('Fixed_Nonslip',(.16,.20,.21),.15)
edge=mat('Fixed_StepEdge',(.8,.58,.09),.1)
rubber=mat('Fixed_Hydraulic',(.035,.04,.045),0)
# Continuous walking skin, folded side channels, crossmembers and anti-slip bars.
box('Non-slip walking plate',(0,2,-.035),(.90,4,.07),grip)
for side in [-1,1]:
    x=side*.47
    box('Folded structural stringer',(x,2,-.08),(.07,4,.18),steel)
    box('Toe board',(side*.45,2,.075),(.035,4,.15),steel)
    for y in [0,1.33,2.67,4]:
        cyl('Guard stanchion',(side*.49,y,.03),(side*.49,y,1.02),.023,steel)
        box('Stanchion bracket',(side*.475,y,.04),(.08,.12,.12),steel)
    for height in [.52,1.02]:
        cyl('Continuous handrail',(side*.49,0,height),(side*.49,4,height),.026,steel)
    for y in [.15,1.35,2.65,3.85]:
        cyl('Stringer fastener',(side*.49,y,-.07),(side*.514,y,-.07),.012,steel)
for y in [.18,1.1,2,2.9,3.82]:box('Underdeck crossmember',(0,y,-.092),(.89,.07,.11),steel)
for i in range(20):box('Transverse grip strip',(0,.1+i*.2,.004),(.85,.018,.008),steel)
for y in [.05,3.95]:box('High visibility threshold',(0,y,.007),(.88,.085,.008),edge)
socket('ShipEnd',(0,0,0));socket('ShoreEnd',(0,4,0))
# Group materials for a bounded draw budget; separate landing hardware is unscaled.
groups={}
for o in list(bpy.context.scene.objects):
    if o.type!='MESH':continue
    bpy.context.view_layer.objects.active=o
    for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    groups.setdefault(o.data.materials[0].name,[]).append(o)
for name,parts in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();bpy.context.object.name=name
save('boarding_gangway_4m')
clear()
for side in [-1,1]:
    x=side*.39
    box('Roller yoke',(x,0,-.04),(.19,.26,.13),steel)
    cyl('Shore rubber roller',(x-.055,0,-.07),(x+.055,0,-.07),.078,rubber)
    cyl('Roller axle',(x-.11,0,-.07),(x+.11,0,-.07),.018,steel)
box('Landing lip',(0,.13,-.01),(.88,.28,.02),steel)
save('gangway_landing_rollers')
print('GANGWAY: shared authored aluminium frame, nonslip plate, rails and shore rollers')
