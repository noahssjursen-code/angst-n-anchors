"""Reusable passenger-terminal/pile-pier kit for isolated ferry development.
See the Skyss terminal study in docs/passenger-ferry-research-2026-10-09.txt.
Original game architecture; not a reproduction of a named terminal.
"""
from pathlib import Path
exec((Path(__file__).resolve().parent/'build_ferry.py').read_text(encoding='utf-8').split('\nclear()\n# Slender')[0])
OUT=ROOT/'parts/passenger_terminal';OUT.mkdir(parents=True,exist_ok=True)
concrete=mat('Concrete',(.50,.49,.45),rough=.9)
cladding=mat('Deep petrol painted steel',(.21,.28,.29),rough=.65)
roof=mat('Roof paint',(.12,.17,.18),rough=.6)
wood=mat('Pallet timber',(.42,.29,.15),rough=.8)
yellow=mat('Safety yellow',(.90,.63,.10))
assets=[]
def finish(aid):
    export(aid,OUT)
    assets.append(dict(id=aid,model=f'res://resources/models/parts/passenger_terminal/{aid}.glb'))
def text_mesh(label,p,size,material,rotation=(math.pi/2,0,0)):
    curve=bpy.data.curves.new(label,'FONT');curve.body=label;curve.size=size;curve.align_x='CENTER';curve.extrude=.002
    o=bpy.data.objects.new(label,curve);bpy.context.collection.objects.link(o);o.location=p;o.rotation_euler=rotation;o.data.materials.append(material)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')

clear()
box('Concrete cap',(0,0,-.28),(6,6,.56),concrete,.025)
for x in [-2.2,2.2]:
    for y in [-2.2,2.2]:
        beam('Steel pile',(x,y,-.54),(x,y,-4.3),.19,steel,20)
        box('Pile bearing',(x,y,-.58),(.6,.6,.18),steel,.04)
finish('passenger_pier_6m')

clear()
for x in [-1.45,1.45]:box('Terminal column',(x,0,1.65),(.10,.16,3.3),cladding)
box('Spandrel',(0,0,.42),(2.9,.16,.84),cladding)
box('Window',(0,-.025,1.93),(2.78,.018,2.05),glass)
for z in [.88,2.99]:box('Glazing transom',(0,0,z),(2.9,.10,.06),dark)
box('Window mullion',(0,0,1.93),(.055,.10,2.08),dark)
box('Head beam',(0,0,3.15),(3,.19,.30),cladding)
box('Interior sill',(0,.10,.9),(2.9,.29,.07),wood,.015)
finish('terminal_glazed_bay_3m')

clear()
box('Insulated wall',(0,0,1.65),(3,.18,3.3),cladding)
for x in [-1.4+i*.20 for i in range(15)]:box('Standing seam',(x,-.103,1.65),(.018,.025,3.3),cladding)
finish('terminal_solid_bay_3m')

clear()
for x in [-1.45,1.45]:box('Door jamb',(x,0,1.65),(.10,.18,3.3),cladding)
box('Door header',(0,0,2.85),(3,.22,.90),cladding)
for s in [-1,1]:
    box('Side glazing',(s*1.25,0,1.15),(.38,.018,2.30),glass)
    for x in [s*1.05,s*1.45]:box('Glazing stile',(x,0,1.15),(.055,.08,2.3),dark)
# Door leaves park at the sides; a two-metre clear opening stays walkable.
text_mesh('PASSASJERTERMINAL',(0,-.125,2.76),.20,white)
finish('terminal_entry_3m')

clear()
verts=[(x,y,z) for x in [-1.5,1.5] for y,z in [(-5.2,0),(0,.68),(5.2,0)]]
mesh('Folded roof',verts,[(0,3,4,1),(1,4,5,2)],roof)
for y in [-5.2,5.2]:box('Eaves gutter',(0,y,-.01),(3,.16,.16),cladding)
box('Ceiling',(0,0,-.09),(3,10,.14),white)
for x in [-.8,.8]:box('Ceiling strip',(x,0,-.17),(.10,8,.03),light)
finish('terminal_roof_3x10m')

clear()
mesh('Gable closure',[(-.05,-5,0),(-.05,0,.66),(-.05,5,0),(.05,-5,0),(.05,0,.66),(.05,5,0)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],cladding)
finish('terminal_gable_10m')

clear()
beam('Canopy leg',(-1.5,-1.6,0),(-1.5,-1.6,3.0),.05,steel)
box('Canopy beam',(0,-1.6,3.0),(3,.14,.20),steel)
box('Canopy roof',(0,0,3.12),(3,4.0,.16),roof)
box('Canopy diffuser',(0,0,3.01),(.14,3.0,.025),light)
finish('terminal_canopy_3m')

clear();beam('Canopy end leg',(0,0,0),(0,0,3.0),.05,steel)
finish('terminal_canopy_post')

clear()
for x in [-1.0,1.0]:
    box('Bench foot',(x,0,.04),(.22,.6,.08),steel,.025)
    beam('Bench upright',(x,0,.06),(x,0,.44),.04,steel)
for y in [-.18,0,.18]:box('Seat slat',(0,y,.48),(2.6,.16,.075),wood,.015)
for z in [.75,.94]:box('Back slat',(0,.29,z),(2.6,.07,.16),wood,.015)
for x in [-1.25,0,1.25]:beam('Bench armrest',(x,-.24,.71),(x,.27,.71),.025,steel)
finish('terminal_waiting_bench')

clear()
box('Information plinth',(0,0,.10),(.7,.5,.2),concrete,.05)
box('Pylon casing',(0,0,1.30),(.65,.20,2.4),cladding,.035)
box('Timetable glass',(0,-.112,1.30),(.54,.018,1.3),glass)
text_mesh('RUTE',(0,-.121,2.13),.15,white)
text_mesh('01',(0,-.124,1.78),.21,white)
text_mesh('KYSTEKSPRESS',(0,-.124,1.46),.063,white)
text_mesh('OMBORDSTIGNING',(0,-.124,.45),.055,white)
finish('terminal_information_pylon')

clear()
box('Berth fender',(0,0,-.40),(1.1,.35,.8),rubber,.12)
for x in [-.43,.43]:box('Fender clamp',(x,0,-.35),(.09,.4,.72),steel,.02)
box('Berth edge strip',(0,0,.015),(1.2,.12,.03),yellow)
finish('passenger_berth_fender')

clear()
for z in [.55,1.1]:beam('Pier guard rail',(-1.5,0,z),(1.5,0,z),.028,steel)
finish('passenger_pier_guard_3m')

clear();beam('Pier guard post',(0,0,0),(0,0,1.1),.025,steel)
finish('passenger_pier_guard_post')

(OUT/'manifest.json').write_text(json.dumps(dict(units='metres',assets=assets),indent=2)+'\n')
print('PASSENGER TERMINAL KIT EXPORTED',len(assets))
