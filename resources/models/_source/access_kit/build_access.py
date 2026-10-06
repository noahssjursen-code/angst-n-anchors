"""Marine stair/landing supports. Metres; +Y ascends, +Z up.
Floor sockets are exactly 2.2 m apart vertically and 3 m horizontally.
"""
from pathlib import Path
exec((Path(__file__).resolve().parents[1]/'fishing_kit/build_fishing_kit.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'parts'/'access_kit';OUT.mkdir(parents=True,exist_ok=True)
def beam(n,a,b,w,d,m):
    a,b=Vector(a),Vector(b);o=box(n,(a+b)/2,(w,d,(b-a).length),m)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def finish(n):
    groups={}
    for ob in list(bpy.context.scene.objects):
        if ob.type!='MESH':continue
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        groups.setdefault(ob.data.materials[0].name,[]).append(ob)
    for key,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
        bpy.context.object.name=n+' '+key
    save(n)
clear()
paint=mat('Warm white painted steel',(.42,.52,.53));steel=mat('Fixed_Galvanized',(.48,.53,.54),.75)
grip=mat('Fixed_Nonslip',(.13,.17,.17),.35);yellow=mat('Fixed_StepEdge',(.76,.56,.12),.15)
ribmat=mat('Fixed_TreadGrip',(.48,.53,.54),.75)
going=3/11
for side in [-1,1]:
    x=side*.51
    beam('Plate stringer',(x,0,.035),(x,3,2.035),.06,.19,paint)
    box('Bottom shoe',(x,.06,.035),(.21,.27,.07),paint)
    box('Upper landing cleat',(x,2.94,2.145),(.21,.22,.11),paint)
    for y in [0.0,1.5,3.0]:
        level=.2+(y/3)*2.0
        cyl('Guard upright',(side*.5,y,level-.17),(side*.5,y,level+1.0),.024,steel)
    for h in [.52,1.0]:cyl('Continuous sloped handrail',(side*.5,0,.2+h),(side*.5,3,2.2+h),.026,steel)
    for y,z in [(.03,.075),(2.94,2.205)]:cyl('Holding bolt',(x,y,z),(x,y,z+.015),.016,steel)
for i in range(11):
    y=(i+.5)*going;z=(i+1)*.2
    box('Folded tread pan',(0,y,z-.035),(1.0,going+.012,.07),steel)
    box('Raised grip surface',(0,y+.012,z+.003),(.94,going-.042,.006),grip)
    box('Nosing visibility strip',(0,i*going+.026,z+.008),(.94,.038,.006),yellow)
    for row in range(5):box('Tread grip rib',(0,i*going+.061+row*.035,z+.009),(.92,.008,.004),ribmat)
    for side in [-1,1]:
        for yy in [-.075,.075]:cyl('Tread side bolt',(side*.525,y+yy,z-.035),(side*.55,y+yy,z-.035),.012,steel)
socket('LowerFloor',(0,0,0));socket('UpperFloor',(0,3,2.2))
finish('deck_stair_220cm')
clear()
# Origin at wall/top of support; extends +X two metres beneath a landing.
box('Wall attachment pad',(.025,0,-.50),(.05,.26,1.0),paint)
beam('Upper flange',(.06,0,-.09),(2,0,-.09),.13,.15,paint)
beam('Diagonal knee',(.06,0,-.98),(1.94,0,-.09),.13,.13,paint)
beam('Vertical web',(.06,0,-.98),(.06,0,-.09),.13,.13,paint)
for z in [-.16,-.84]:
    for y in [-.08,.08]:cyl('Wall bolt',(.05,y,z),(.079,y,z),.017,steel)
box('Outer deck shoe',(1.87,0,-.04),(.26,.32,.08),paint)
for ob in bpy.context.scene.objects:ob.location.z-=.1
finish('deck_bracket_2m')
assets=[]
for aid,extent,height,label in [('deck_stair_220cm',[0,-3],3.23,'stair'),('deck_bracket_2m',[2,0],1,'support')]:
    assets.append(dict(id=aid,kind='furniture',style=label,model=f'res://resources/models/parts/access_kit/{aid}.glb',start_xz=[0,0],end_xz=extent,height_start_m=height,height_end_m=height,paintable=True))
assets[0]['walk_exclude_materials']=['Fixed_Nonslip','Fixed_TreadGrip','Fixed_StepEdge']
json.dump({'units':'metres','floor_rise_m':2.2,'stair_run_m':3.0,'riser_count':11,'assets':assets},open(OUT/'manifest.json','w'),indent=2)
print('ACCESS KIT PASS: sockets 2.2 high / 3.0 run; separate landing knee')
