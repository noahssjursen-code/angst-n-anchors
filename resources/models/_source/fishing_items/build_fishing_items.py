"""Original fishing assets, metres. Run with Blender --background --python.
Rod references: PENN Pursuit IV boat spinning combo (unbranded interpretation).
Species silhouettes: Institute of Marine Research cod / pollack / mackerel.
Fish are authored at one metre, head +X. Portable rod points Blender +Y.
"""
import bpy, math, random
from pathlib import Path
from mathutils import Vector
SRC = Path(__file__).resolve().parent
OUT = SRC.parents[1] / 'fishing_items'
OUT.mkdir(parents=True, exist_ok=True)

def material(name, color, metallic=0, rough=.45):
    m = bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metallic
    return m
carbon=material('Graphite blank',(.025,.034,.039),.35,.28)
foam=material('EVA grip',(.035,.037,.034),0,.9)
alloy=material('Anodised reel',(.10,.12,.14),.8,.28)
silver=material('Guide stainless',(.65,.69,.70),.85,.22)
gold=material('Brass trim',(.62,.40,.08),.65,.3)
braid=material('Olive braided line',(.35,.39,.19),0,.8)

def empty(name, parent=None, pos=(0,0,0)):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o);o.parent=parent;o.location=pos;return o
def rodbar(name,a,b,r,m,parent=None,r2=None):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=r,radius2=r if r2 is None else r2,depth=(b-a).length,location=(a+b)*.5)
    o=bpy.context.object;o.name=name;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();o.data.materials.append(m);o.parent=parent
    for p in o.data.polygons:p.use_smooth=True
    return o
def curve(name,pts,r,m,parent=None):
    c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=2;c.bevel_depth=r;c.bevel_resolution=2
    s=c.splines.new('POLY');s.points.add(len(pts)-1)
    for p,co in zip(s.points,pts):p.co=(*co,1)
    o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.data.materials.append(m);o.parent=parent;return o
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def save(name,out=OUT):
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(out/(name+'.glb')),export_format='GLB',export_apply=True)

def make_rod():
    root=empty('FishingRod')
    rodbar('Butt grip',(0,-.32,0),(0,-.07,0),.015,foam,root)
    rodbar('Butt cap',(0,-.33,0),(0,-.31,0),.018,alloy,root)
    rodbar('Reel seat',(0,-.07,0),(0,.09,0),.012,alloy,root)
    rodbar('Foregrip',(0,.09,0),(0,.20,0),.014,foam,root)
    for y in [-.08,.09,.20]:rodbar('Trim',(0,y,0),(0,y+.008,0),.015,gold,root)
    # 6,000-class spinning reel: 58 mm spool, suspended below the blank.
    rodbar('Reel foot',(0,.035,0),(0,.03,-.075),.008,alloy,root)
    rodbar('Gear housing',(0,-.025,-.09),(0,.05,-.09),.028,alloy,root)
    rodbar('Spool arbor',(0,.045,-.09),(0,.12,-.09),.018,alloy,root)
    rodbar('Spool braid',(0,.07,-.09),(0,.115,-.09),.026,braid,root)
    for y in [.067,.115]:rodbar('Spool lip',(0,y,-.09),(0,y+.005,-.09),.029,gold,root)
    bail=[(.034*math.cos(t),.126+.018*math.sin(t),-.09+.034*math.sin(t)) for t in [i*math.pi/16 for i in range(33)]]
    curve('Bail wire',bail,.0017,silver,root)
    crank=empty('ReelCrank',root,(-.034,0,-.09))
    rodbar('Crank arm',(0,0,0),(-.021,-.055,0),.004,silver,crank)
    rodbar('Knob spindle',(-.021,-.055,0),(-.082,-.055,0),.0035,silver,crank)
    rodbar('Crank knob',(-.037,-.055,0),(-.082,-.055,0),.012,foam,crank)
    # Heavy ocean outfit: transverse conventional reel, replacing the spinning spool.
    for obj in list(bpy.data.objects):
        if obj.name.startswith(('Reel foot','Gear housing','Spool','Bail wire')):
            bpy.data.objects.remove(obj,do_unlink=True)
    rodbar('Heavy reel foot',(0,.035,0),(0,.015,-.078),.013,alloy,root)
    rodbar('Heavy reel drum',(-.038,.015,-.078),(.038,.015,-.078),.043,braid,root)
    for x in [-.046,.046]:
        rodbar('Reel side plate',(x-.004,.015,-.078),(x+.004,.015,-.078),.053,alloy,root)
    for y in [-.025,.055]:
        rodbar('Reel cage brace',(-.046,y,-.105),(.046,y,-.105),.004,silver,root)
    parent=root
    for i in range(9):
        joint=empty('RodFlex%02d'%i,parent,(0,.20 if i==0 else .155,0))
        radius=.011*(1-i/10)+.0012
        rodbar('Tapered graphite',(0,0,0),(0,.155,0),radius,carbon,joint,radius-.00055)
        size=.017*(1-i/10)+.002
        pts=[(size*math.cos(t),.150,-size+size*math.sin(t)) for t in [j*math.tau/24 for j in range(25)]]
        curve('Ceramic guide',pts,.0012,silver,joint)
        rodbar('Guide binding',(0,.139,0),(0,.155,0),radius+.0006,foam,joint)
        parent=joint
    empty('LineTip',parent,(0,.155,-.004))
    empty('RightGrip',root,(.012*math.sin(math.radians(20)),.025,.012*math.cos(math.radians(20))))
    empty('LeftGrip',crank,(-.060,-.055,0))
    return root

clear();make_rod();save('spinning_rod')
clear();r=make_rod();r.location=(0,0,1.0);r.rotation_euler.x=math.radians(33)
rodbar('Pedestal',(0,0,.06),(0,0,.85),.026,silver)
rodbar('Bolted rod holder',(0,-.13,.75),(0,0,.95),.024,alloy)
save('hook_line_station',SRC.parents[1]/'parts'/'coastal_fishing')

# Species assets use their own anatomical mesh/texture authoring pass.
import runpy
import sys
if '--rod-only' not in sys.argv:
    runpy.run_path(str(SRC/'build_fish_meshes.py'), run_name='__main__')
