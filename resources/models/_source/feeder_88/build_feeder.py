"""Original 88 x 14 m deck-container carrier and reusable outfit. Blender metres.

Arrangement reference: Damen Combi Freighter 3850 (aft accommodation, long cargo
deck, raised counter), not a reproduction or a certified naval architecture design.
Hull construction edges follow our 0.5 m lattice and 2:1 / 1:1 bow contract.
Run Blender --background --python this_file; runtime applies the approved marine
material library to the named paint/metal/rubber regions.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent
MODELS = HERE.parents[1]
exec((MODELS/'_source/hull_24x8/build_cargo.py').read_text().split('clear()\nupper=')[0])
SRC = HERE
OUT = MODELS/'vessels/hull_88x14'
OUT.mkdir(parents=True, exist_ok=True)
DECK = 5.6
clear()
upper = material('Paint_HullUpper', (.09,.19,.23))
lower = material('Paint_HullLower', (.29,.08,.055))
stripe = material('Fixed_BootStripe', (.035,.045,.048))
deck = material('Paint_Deck', (.25,.30,.28), .1)
cross = [(-1,1),(-.998,.8),(-.99,.6),(-.96,.4),(-.88,.22),(-.72,.10),(-.46,.025),(0,0),(.46,.025),(.72,.10),(.88,.22),(.96,.4),(.99,.6),(.998,.8),(1,1)]
def width(y):
    return 7 if y <= 32 else (7-(y-32)*.5 if y <= 42 else 44-y)
vs=[]; fs=[]
for i in range(353):
    y=-44+i*.25
    fore=max(0,(y-28)/16); aft=max(0,(-y-35)/9)
    bottom=.16+1.2*fore**2+4.25*aft**2
    for x,h in cross:
        vs.append((x*width(y), y+3.6*aft**2*(1-h)**1.5, bottom+(DECK-bottom)*h))
k=len(cross)
for i in range(352):
    for j in range(k-1):
        a=i*k+j;fs.append((a,a+1,a+k+1,a+k))
for j in range(k//2): fs.append(tuple(dict.fromkeys((j,k-1-j,k-2-j,j+1))))
shell=mesh('Feeder formed shell',vs,fs,upper)
bm=bmesh.new();bm.from_mesh(shell.data)
for z in [3.65,3.83]:
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,z),plane_no=(0,0,1),dist=.000001)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(shell.data);bm.free()
shell.data.materials.append(lower);shell.data.materials.append(stripe)
for p in shell.data.polygons:
    z=sum(shell.data.vertices[i].co.z for i in p.vertices)/len(p.vertices)
    p.material_index=1 if z<3.65 else (2 if z<3.83 else 0)
    p.use_smooth=len(p.vertices)<=4
box('Continuous load deck',(0,-6,5.53),(14,76,.14),deck)
mesh('Foredeck',[(-7,32,DECK),(-2,42,DECK),(0,44,DECK),(2,42,DECK),(7,32,DECK)],[(0,1,2,3,4)],deck)
# A welded rubbing strake is part of the shell, not a repeated railing joint.
for side in [-1,1]:
    box('Side rubbing strake',(side*7,-6,4.88),(.08,75.8,.16),stripe,.015)
socket('DeckDatum',(0,-34,DECK));socket('EngineSeat',(0,-36,1.0))
save('hull_88x14',OUT)
outline=[[-7,44],[-7,-32],[-2,-42],[0,-44],[2,-42],[7,-32],[7,44]]
(OUT/'deck_outline.json').write_text(json.dumps(dict(length_m=88,beam_m=14,deck_y=DECK,outline_xz=outline,openings_xz=[]),indent=2))

# The accepted perimeter cross sections already contain these exact corner
# miters. Generate assembly recipes, never scale the existing modular segments.
source=(MODELS/'_source/hull_32x10/build_perimeter.py').read_text()
source=source.replace("OUT=str(MODELS/'parts/coaster_perimeter')", "OUT=str(MODELS/'parts/feeder_perimeter')")
source=source.replace("x=-5*sign;y=-16", "x=-7*sign;y=-44").replace('range(24)', 'range(76)')
source=source.replace('range(10):\n            run', 'range(14):\n            run').replace('i<6','i<10')
source=source.replace('y==16','y==44').replace("range(10):segments.append", "range(14):segments.append").replace("-5+i,-16", "-7+i,-44")
source=source.replace('[x,4.5,-y]','[x,5.6,-y]').replace("'vessels/hull_32x10'", "'vessels/hull_88x14'")
source=source.replace("'/coaster_perimeter/'", "'/feeder_perimeter/'")
exec(compile(source, str(HERE/'perimeter_recipe.py'), 'exec'))

# Model existing proven machine primitives at the required physical dimensions;
# output meshes have applied transforms and their own editable Blender sources.
engine_source=(MODELS/'_source/marine_engines/build_engines.py').read_text().split('\nfor values in')[0]
exec(engine_source)
SRC=HERE; OUT=MODELS/'machinery'
engine('marine_v12_feeder',3.5,2.05,2.55,True)

gear_source=(MODELS/'_source/stern_gear/build_coaster_gear.py').read_text()
exec((MODELS/'_source/stern_gear/build_stern_gear.py').read_text().split('\nclear()\nbronze=')[0])
SOURCE=HERE
original_export=export
def export(aid, pivot):
    scale=2.6/1.8 if aid=='propeller_1800' else 3/2.1
    for ob in bpy.context.scene.objects:
        ob.location *= scale
        if ob.type=='MESH':
            for v in ob.data.vertices: v.co *= scale
    names={'propeller_1800':'propeller_2600','rudder_2100':'rudder_3000','coaster_shaft_support':'feeder_shaft_support'}
    original_export(names[aid],pivot)
body=gear_source[gear_source.index('\ndef normals():'):gear_source.index("(OUT/'mounts_32m.json')")]
exec(body)
(OUT/'mounts_88m.json').write_text(json.dumps(dict(version=1,hull='hull_88x14',units='metres',assets=dict(support='feeder_shaft_support',propeller='propeller_2600',rudder='rudder_3000'),support=[0,2,41.35],propeller=[0,2,42.42],rudder=[0,3.786,43.779],max_rudder_degrees=28,visual_max_rpm=160),indent=2))

# Individually selectable, paintable outfit. Small details are merged by finish.
exec((MODELS/'_source/access_kit/build_access.py').read_text().split('\nclear()\npaint=')[0])
SRC=HERE; OUT=MODELS/'parts/feeder_outfit';OUT.mkdir(parents=True,exist_ok=True)
clear()
for existing in list(bpy.data.materials):
    bpy.data.materials.remove(existing)
paint=mat('Warm white painted steel',(.77,.77,.68));steel=mat('Fixed_Galvanized',(.43,.49,.51),.8)
dark=mat('Fixed_ExhaustOutlet',(.06,.065,.06));rubber=mat('Fixed_Rubber',(.035,.04,.04),0)
orange=mat('Fixed_FloatOrange',(.82,.26,.055),0)
clear()
box('Funnel base',(0,0,.14),(2.4,2.2,.28),paint)
box('Casing',(0,0,1.9),(2,1.8,3.5),paint)
box('Heat shield cap',(0,0,3.69),(2.18,1.98,.12),dark)
for x in [-.55,.55]:
    cyl('Exhaust pipe',(x,0,3.5),(x,0,4.25),.24,dark)
    cyl('Pipe rim',(x,0,4.15),(x,0,4.27),.28,steel)
for side in [-1,1]:
    box('Vent shadow',(side*1.008,0,1.3),(.025,1.2,1.2),rubber)
    for i in range(9):box('Louvre',(side*1.045,0,.77+i*.125),(.08,1.24,.055),steel)
finish('feeder_funnel')
clear()
for x in [-.42,.42]:
    cyl('Mast leg',(x,0,0),(x*.42,0,5.8),.075,paint)
for h in [.2,1.5,2.8,4.1,5.4]:
    cyl('Diagonal brace',(-.42*(1-h/10),0,h),(.42*(1-(h+1.1)/10),0,h+1.1),.035,steel)
cyl('Signal pole',(0,0,5),(0,0,7),.055,paint)
for h,w in [(3.8,1.8),(5.6,1.2)]:
    cyl('Signal yard',(-w,0,h),(w,0,h),.055,paint)
    for x in [-w,w]:cyl('Antenna',(x,0,h),(x,0,h+.8),.015,steel)
for z in range(1,16):cyl('Ladder rung',(-.2,-.14,z*.3),(.2,-.14,z*.3),.012,steel)
socket('Masthead',(0,0,7));finish('feeder_signal_mast')
clear()
for x in [-.65,.65]:
    box('Raft cradle',(x,0,.3),(.12,1.1,.6),steel)
cyl('Liferaft container',(0,-.9,.78),(0,.9,.78),.48,paint)
for y in [-.64,.64]:cyl('Securing band',(0,y-.03,.78),(0,y+.03,.78),.49,rubber)
box('Release housing',(.48,0,.65),(.14,.25,.24),orange)
finish('feeder_liferaft')
clear()
box('Windlass base',(0,0,.12),(2.8,1.45,.24),paint)
for x in [-.75,.75]:
    box('Gear stand',(x,0,.66),(.24,1.0,1.1),paint)
    cyl('Chain gypsy',(x-.25,0,1.1),(x+.25,0,1.1),.42,steel)
    cyl('Warping drum',(x-.42,0,1.1),(x+.42,0,1.1),.28,dark)
    for xx in [x-.44,x+.44]:cyl('Drum flange',(xx-.04,0,1.1),(xx+.04,0,1.1),.38,paint)
cyl('Drive shaft',(-1.3,0,1.1),(1.3,0,1.1),.10,steel)
box('Gearbox',(0,0,.73),(.7,1.0,1.05),paint)
finish('feeder_windlass')
clear()
# Stowed stockless anchor, separate from the windlass and hull. Origin is the
# hawse mouth on the starboard shell; a half turn fits the port station.
bpy.ops.mesh.primitive_torus_add(major_radius=.25,minor_radius=.055,major_segments=32,minor_segments=10,rotation=(0,math.pi/2,0))
bpy.context.object.name='Hawse lip';bpy.context.object.data.materials.append(steel)
cyl('Hawse dark recess',(-.025,0,0),(.01,0,0),.205,rubber)
beam('Anchor shank',(.08,0,-.12),(.12,0,-1.25),.14,.15,steel)
cyl('Anchor crown pin',(.12,-.5,-1.25),(.12,.5,-1.25),.105,steel)
for side in [-1,1]:
    v=[(.07,side*.12,-1.37),(.07,side*.70,-1.20),(.35,side*.63,-.54),(.42,side*.23,-1.23)]
    vertices=v+[(x+.075,y,z) for x,y,z in v]
    faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
    mesh('Forged anchor fluke',vertices,faces,steel)
finish('feeder_stowed_anchor')
assets=[]
for aid,ext,h,style in [('feeder_funnel',[2.4,2.2],4.3,'vent'),('feeder_signal_mast',[3.6,.4],7,'furniture'),('feeder_liferaft',[1.4,2.0],1.26,'furniture'),('feeder_windlass',[2.8,1.45],1.55,'furniture'),('feeder_stowed_anchor',[.5,1.4],1.65,'furniture')]:
    assets.append(dict(id=aid,style=style,kind='furniture',model=f'res://resources/models/parts/feeder_outfit/{aid}.glb',start_xz=[0,0],end_xz=ext,height_start_m=h,height_end_m=h,paintable=True))
(OUT/'manifest.json').write_text(json.dumps(dict(units='metres',assets=assets),indent=2))
print('FEEDER ASSETS EXPORTED: hull, perimeter, machinery, stern gear, reusable outfit')
