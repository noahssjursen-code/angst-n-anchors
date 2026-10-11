"""Independent deck ventilator and wall intake, original game-scale fabrication.
Metres, Blender +Y forward/+Z up. Static fittings; no airflow simulation.
"""
import bmesh
from pathlib import Path
exec((Path(__file__).resolve().parents[1]/'access_kit/build_access.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'parts'/'ventilation_kit';OUT.mkdir(parents=True,exist_ok=True)
def lathe(name,profile,material):
    v=[];f=[];n=64
    for r,z in profile:
        for i in range(n):
            a=math.tau*i/n;v.append((r*math.cos(a),r*math.sin(a),z))
    for k in range(len(profile)-1):
        for i in range(n):f.append((k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i))
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);me.materials.append(material)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    for face in me.polygons:face.use_smooth=True
    split=ob.modifiers.new('Fabricated profile breaks','EDGE_SPLIT');split.split_angle=math.radians(35);split.use_edge_angle=True;split.use_edge_sharp=False
    return ob
clear()
paint=mat('Warm white painted steel',(.54,.63,.62));steel=mat('Fixed_VentSteel',(.36,.43,.45),.75)
dark=mat('Fixed_VentRecess',(.025,.034,.036),.1)
# Hollow pipe and open rain hood, bolted foot and screened annular throat.
lathe('Welded ventilation trunk',[(.18,0),(.18,.7),(.164,.7),(.164,0),(.18,0)],paint)
lathe('Mounting flange',[(.27,0),(.27,.045),(.164,.045),(.164,0),(.27,0)],paint)
for i in range(8):
    a=math.tau*i/8;x=.225*math.cos(a);y=.225*math.sin(a)
    cyl('Flange bolt',(x,y,.045),(x,y,.071),.017,steel)
lathe('Mushroom hood',[(.385,.73),(.4,.755),(.4,.80),(.37,.90),(.25,.965),(.1,.987),(0,.99),(0,.973),(.1,.97),(.25,.947),(.354,.886),(.382,.791),(.382,.755),(.385,.73)],paint)
cyl('Hood retaining screw',(0,0,.986),(0,0,1.006),.028,steel)
box('Screwdriver slot',(0,0,1.007),(.033,.004,.003),dark)
cyl('Screen shadow',(0,0,.60),(0,0,.80),.195,dark)
for z in [.615,.665,.715,.765]:lathe('Screen hoop',[(.2,z),(.203,z+.003),(.2,z+.006),(.197,z+.003),(.2,z)],steel)
for i in range(32):
    a=math.tau*i/32;x=.201*math.cos(a);y=.201*math.sin(a)
    cyl('Screen vertical',(x,y,.61),(x,y,.78),.002,steel)
for i in range(4):
    a=math.tau*i/4;x=.245*math.cos(a);y=.245*math.sin(a)
    cyl('Hood stay',(x*.68,y*.68,.64),(x,y,.935),.012,steel)
socket('Airway',(0,0,0));socket('HoodCentre',(0,0,.8))
finish('deck_mushroom_vent')
clear()
# Deck-origin wall mounting: lower edge .85 m, upper edge 1.65 m, faces -Z in Godot.
box('Dark intake throat',(0,.026,1.25),(.76,.02,.68),dark)
for x in [-.425,.425]:box('Side mounting frame',(x,.055,1.25),(.05,.11,.8),paint)
for z in [.875,1.625]:box('Frame crossbar',(0,.055,z),(.9,.11,.05),paint)
for i in range(8):
    blade=box('Downturned louvre blade',(0,.07,.96+i*.084),(.79,.13,.014),steel)
    blade.rotation_euler.x=math.radians(32)
box('Drip sill',(0,.10,.85),(.93,.2,.035),paint)
box('Top rain eyebrow',(0,.10,1.67),(.96,.22,.045),paint)
for x in [-.425,.425]:
    for z in [.91,1.59]:cyl('Frame screw',(x,.111,z),(x,.126,z),.011,steel)
socket('WallFace',(0,0,1.25))
# Authored mounting datum is the shared wall centreline, not its outer skin.
# Standard wall skin is 60 mm forward of that datum.
for ob in bpy.context.scene.objects:ob.location.y+=.06
finish('wall_vent_louvre')
assets=[]
for aid,extent,height in [('deck_mushroom_vent',[.8,.8],1.01),('wall_vent_louvre',[.96,.22],1.7)]:
    assets.append(dict(id=aid,kind='furniture',style='vent',model=f'res://resources/models/parts/ventilation_kit/{aid}.glb',start_xz=[0,0],end_xz=extent,height_start_m=height,height_end_m=height,paintable=True))
json.dump({'units':'metres','assets':assets},open(OUT/'manifest.json','w'),indent=2)
print('VENTILATION KIT: two individual fittings, fixed screens and paintable fabricated housings')
