"""Fixed-length container lifting frames, metres, Blender +Z up.
Floor-relative origin matches ContainerNode. Hook datum is roof + 1.60m.
Standalone scoped rebake; does not regenerate cargo shells or gameplay data.
"""
from pathlib import Path
import sys
SOURCE=Path(__file__).resolve().parent
helper=SOURCE.parent/'provision_hoist/build_hoist.py'
# Reuse fabrication, sockets and baked worn-paint export without generating hoists.
exec(compile(helper.read_text(encoding='utf-8').split('\nclear()\n# Load seat')[0],str(helper),'exec'))
HERE=SOURCE
OUT=SOURCE.parents[1]/'cargo'

def beam(n,a,b,width,depth,m=paint):
    a,b=Vector(a),Vector(b)
    ob=box(n,(a+b)/2,(width,depth,(b-a).length),m)
    ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return ob

for aid,w,l,h in [('container_20ft',2.438,6.058,2.591),('container_40ft',2.438,12.192,2.591),('legacy_breakbulk_4m',3.8,3.8,3.8)]:
    clear()
    end=l/2-.081;half=w/2-.089
    # Fabricated twin box girders: deeper than the old thin I-bars, with
    # reinforced bearing ends. Fixed length variants, not fake telescopes.
    for x in [-.58,.58]:
        box('Main box girder',(x,0,h+.32),(.28,l-.16,.42))
        for y in [-end+.18,end-.18]:
            box('End doubler',(x,y,h+.32),(.31,.50,.45))
        for y in [-1.1,0,1.1]:
            box('Cross diaphragm',(0,y,h+.34),(1.40,.18,.35))
        for side in [-1,1]:
            beam('Tower leg',(x,side*.90,h+.53),(x*.25,0,h+1.28),.17,.20)
    box('Tower crosshead',(0,0,h+1.27),(.70,.40,.18))
    # Real open eye, oriented in the hook plane; no solid disk blocking hook.
    bpy.ops.mesh.primitive_torus_add(major_segments=32,minor_segments=8,location=(0,0,h+1.72),major_radius=.20,minor_radius=.055,rotation=(math.pi/2,0,0))
    bpy.context.object.name='Forged suspension eye';bpy.context.object.data.materials.append(silver)
    for x in [-.16,.16]:
        plate('Eye support',[(x,-.18,h+1.28),(x,.18,h+1.28),(x,.10,h+1.58),(x,-.10,h+1.58)],.055)
    # Equipment is mounted clear of the eye and roof; hoses follow the frame.
    box('Hydraulic power pack',(0,.62,h+.65),(.62,.52,.38),steel)
    rod('Pump motor',(-.22,.98,h+.65),(.22,.98,h+.65),.13,steel,20)
    for x in [-.35,.35]:
        rod('Protected oil line',(x,-end+.25,h+.57),(x,end-.25,h+.57),.014,steel,8)
    for y in [-end,end]:
        box('End transverse beam',(0,y,h+.27),(w-.07,.30,.38))
        for x in [-half,half]:
            box('Corner lock housing',(x,y,h+.20),(.21,.25,.32))
            rod('Lock shaft',(x,y,h-.03),(x,y,h+.30),.027,silver,12)
            box('Locked head',(x,y,h-.025),(.09,.045,.045),steel)
            box('Landing shoe',(x,y,h+.025),(.16,.15,.045),steel)
            box('Bearing cover',(x,y,h+.385),(.18,.20,.03),steel)
            for dx in [-.055,.055]:
                for dy in [-.065,.065]:rod('Cover bolt',(x+dx,y+dy,h+.40),(x+dx,y+dy,h+.416),.012,silver,8)
            # Angled guide plate sits outside cargo outline, not through roof.
            plate('Gathering guide',[(x,y-.13,h+.22),(x,y+.13,h+.22),(x+(1 if x>0 else -1)*.17,y+.13,h-.15),(x+(1 if x>0 else -1)*.17,y-.13,h-.15)],.026)
            socket('Lock_'+str(x)+'_'+str(y),(x,y,h))
        rod('Twistlock linkage',(-half,y,h+.43),(half,y,h+.43),.022,silver,12)
        box('Actuator guard',(0,y,h+.44),(.50,.38,.18))
        for sign in [-1,1]:
            # Alternating dark hazard patches on the outside face.
            for i in range(4):box('Hazard stripe',(sign*(.35+i*.18),y+(1 if y>0 else -1)*.154,h+.27),(.075,.008,.28),steel)
    socket('Hook',(0,0,h+1.60));socket('RoofDatum',(0,0,h))
    export(aid+'_spreader')
print('SPREADERS EXPORTED: fixed20/40/legacy, four locks, roof+1.60 hook datum')
