"""Reusable cargo securing bed and marine exhaust. Metres; +Y bow / +Z up."""
from pathlib import Path
exec((Path(__file__).resolve().parents[1]/'access_kit/build_access.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'parts/starter_outfit';OUT.mkdir(parents=True,exist_ok=True)
clear()
paint=mat('Warm white painted steel',(.3,.38,.38))
steel=mat('Fixed_Galvanized',(.42,.47,.49),.78)
rubber=mat('Fixed_CargoBearing',(.09,.12,.12),.1)
yellow=mat('Fixed_LoadMark',(.76,.55,.1),.15)
# Fits the game's existing 4 x 4 break-bulk cargo unit, not an ISO container.
for x in [-1.88,1.88]:
    box('Welded bearing runner',(x,0,.055),(.20,3.92,.11),paint)
    box('Rubber bearing strip',(x,0,.117),(.18,3.84,.014),rubber)
for y in [-1.88,1.88]:
    box('Cross tie',(0,y,.038),(3.76,.16,.076),paint)
for x in [-1.91,1.91]:
    for y in [-1.91,1.91]:
        box('Load corner',(x,y,.045),(.18,.18,.09),yellow)
        cyl('Securing stud',(x,y,.09),(x,y,.16),.035,steel)
        for dx in [-.06,.06]:cyl('Deck fixing',(x+dx,y,.087),(x+dx,y,.105),.012,steel)
socket('CargoDatum',(0,0,.124));finish('cargo_securing_bed_4m')

clear()
dark=mat('Fixed_ExhaustOutlet',(.018,.022,.024),.1)
box('Engine casing foot',(0,0,.035),(.52,.52,.07),paint)
for x in [-.18,.18]:
    for y in [-.18,.18]:cyl('Casing bolt',(x,y,.07),(x,y,.095),.02,steel)
cyl('Exhaust casing',(0,0,.07),(0,0,1.38),.155,paint)
for z in [.2,1.1]:
    cyl('Clamp ring',(0,0,z-.025),(0,0,z+.025),.176,steel)
    box('Clamp ear',(.16,0,z),(.09,.10,.06),steel)
cyl('Outlet interior',(0,0,1.36),(0,0,1.4),.13,dark)
for x in [-.13,.13]:beam('Rain cap stay',(x,0,1.30),(x,0,1.51),.022,.035,steel)
cyl('Weather cap',(0,0,1.51),(0,0,1.55),.225,paint)
socket('ExhaustOutlet',(0,0,1.40));finish('marine_exhaust_stack')
# A 1.5 m flight gives the smaller raised bridge a generous approach between
# the hold and accommodation. Same 2.2 m rise, 3 m run and authored tread pans.
clear()
grip=mat('Fixed_Nonslip',(.13,.17,.17),.35)
ribmat=mat('Fixed_TreadGrip',(.48,.53,.54),.75)
going=3/11
for side in [-1,1]:
    x=side*.76
    beam('Plate stringer',(x,0,.035),(x,3,2.035),.06,.19,paint)
    box('Bottom shoe',(x,.06,.035),(.21,.27,.07),paint)
    box('Upper landing cleat',(x,2.94,2.145),(.21,.22,.11),paint)
    for y in [0.,1.5,3.]:
        level=.2+(y/3)*2
        cyl('Guard upright',(side*.75,y,level-.17),(side*.75,y,level+1),.024,steel)
    for h in [.52,1.]:cyl('Continuous sloped handrail',(side*.75,0,.2+h),(side*.75,3,2.2+h),.026,steel)
    for y,z in [(.03,.075),(2.94,2.205)]:cyl('Holding bolt',(x,y,z),(x,y,z+.015),.016,steel)
for i in range(11):
    y=(i+.5)*going;z=(i+1)*.2
    box('Folded tread pan',(0,y,z-.035),(1.5,going+.012,.07),steel)
    box('Raised grip surface',(0,y+.012,z+.003),(1.44,going-.042,.006),grip)
    box('Nosing visibility strip',(0,i*going+.026,z+.008),(1.44,.038,.006),yellow)
    for row in range(5):box('Tread grip rib',(0,i*going+.061+row*.035,z+.009),(1.42,.008,.004),ribmat)
    for side in [-1,1]:
        for yy in [-.075,.075]:cyl('Tread side bolt',(side*.775,y+yy,z-.035),(side*.8,y+yy,z-.035),.012,steel)
socket('LowerFloor',(0,0,0));socket('UpperFloor',(0,3,2.2))
finish('deck_stair_wide_220cm')
assets=[]
for aid,style,size in [('cargo_securing_bed_4m','cargo_pad',[4,4,.18]),('marine_exhaust_stack','vent',[.52,.52,1.55]),('deck_stair_wide_220cm','stair',[0,-3,3.23])]:
    assets.append(dict(id=aid,kind='furniture',style=style,model=f'res://resources/models/parts/starter_outfit/{aid}.glb',start_xz=[0,0],end_xz=size[:2],height_start_m=size[2],height_end_m=size[2],paintable=True))
assets[-1]['walk_exclude_materials']=['Fixed_Nonslip','Fixed_TreadGrip','Fixed_StepEdge']
(OUT/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2),encoding='utf-8')
print('STARTER OUTFIT EXPORTED: separate securing bed, exhaust stack and wide stair')
