"""Original rigid bow-ramp hinge, lifting cylinders and landing rollers.
Separate fixed barrel/sliding rod geometry, with real metre stroke; no stretch.
Uses the shared marine finishes from the ferry construction kit.
"""
from pathlib import Path
exec((Path(__file__).resolve().parent/'build_ferry.py').read_text(encoding='utf-8').split('\nclear()\n# Slender')[0])
OUT=ROOT/'parts/passenger_ferry'
yellow=mat('Safety yellow',(.9,.63,.1))

clear()
box('Hinge bed',(0,0,-.035),(2.5,.32,.07),steel,.01)
for x in [-1.18,1.18]:
    box('Cylinder foundation',(x,-1,.025),(.32,.34,.05),white,.015)
    for dx in [-.10,.10]:
        box('Cylinder base clevis',(x+dx,-1,.22),(.055,.25,.39),white,.025)
    beam('Cylinder base pin',(x-.17,-1,.4),(x+.17,-1,.4),.055,steel,16)
    for y in [-1.11,-.89]:
        for dx in [-.11,.11]:beam('Foundation bolt',(x+dx,y,.05),(x+dx,y,.075),.023,steel,6)
for x in [-.91,0,.91]:
    for dx in [-.10,.10]:box('Hinge cheek',(x+dx,0,.045),(.08,.26,.19),white,.025)
    beam('Hinge pin',(x-.17,0,0),(x+.17,0,0),.05,steel,16)
export('ferry_ramp_mount',OUT)

clear()
# Barrel's -Z in Godot is +Y in Blender. Base pin centre is the origin.
beam('Cylinder barrel',(0,.12,0),(0,1.34,0),.080,white,20)
for y in [.12,1.32,1.39]:beam('Cylinder gland',(0,y-.025,0),(0,y+.025,0),.091,steel,20)
beam('Base eye',(-.06,0,0),(.06,0,0),.085,white,20)
beam('Base pin cap',(-.075,0,0),(.075,0,0),.04,steel,16)
for y in [.2,1.2]:
    beam('Hydraulic port',(.05,y,0),(.13,y,0),.023,steel,12)
beam('Hard line',(.13,.2,0),(.13,1.2,0),.009,steel,8)
export('ferry_ramp_cylinder',OUT)

clear()
beam('Chrome piston',(0,0,0),(0,1.35,0),.036,steel,20)
beam('Rod eye',(-.055,1.35,0),(.055,1.35,0),.071,white,20)
beam('Rod pin',(-.09,1.35,0),(.09,1.35,0),.036,steel,16)
export('ferry_ramp_rod',OUT)

clear()
# Root matches the existing ramp centre. Toe lip covers the roller step.
verts=[(x,y,z) for x in [-1,1] for y,z in [(1,0),(1.45,-.20),(1.45,-.23),(1,-.03)]]
mesh('Landing toe',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],deck)
for x in [-.78,.78]:
    beam('Landing roller',(x-.09,1,-.09),(x+.09,1,-.09),.08,rubber,20)
    beam('Roller axle',(x-.15,1,-.09),(x+.15,1,-.09),.028,steel,12)
    for dx in [-.12,.12]:box('Roller cheek',(x+dx,1,-.055),(.035,.20,.15),steel,.012)
for x in [-1.18,1.18]:
    box('Ram connection',(x,.6,-.035),(.42,.26,.07),white,.02)
    beam('Leaf clevis pin',(x-.10,.6,0),(x+.10,.6,0),.034,steel,16)
export('ferry_ramp_landing',OUT)
print('FERRY BOARDING GEAR EXPORTED')
