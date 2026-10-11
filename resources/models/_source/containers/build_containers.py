"""Original dry-cargo containers. Exact external metres, +Z up, doors at -Y.
No runtime primitive substitutes. Door leaves retain independent hinge parents.
"""
from pathlib import Path
exec((Path(__file__).resolve().parents[1]/'access_kit/build_access.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'cargo';OUT.mkdir(parents=True,exist_ok=True)

def sheet(name, points, faces, material, thickness=.003):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(points,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(material)
    if thickness:
        mod=ob.modifiers.new('Steel sheet thickness','SOLIDIFY');mod.thickness=thickness
    return ob

def corrugation(start,end,pitch=.27):
    count=max(1,round((end-start)/pitch));step=(end-start)/count
    return [(start+step*(i+t),d) for i in range(count) for t,d in [(0,0),(.22,0),(.38,1),(.72,1),(.88,0)]]+[(end,0)]

def cast(name,p,paint):
    ob=box(name,p,(.178,.162,.118),paint)
    bpy.context.view_layer.objects.active=ob
    for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    # Three actual cast apertures; no black stickers standing in for holes.
    for axis in range(3):
        q=Vector(p);a=q.copy();b=q.copy();a[axis]-=.16;b[axis]+=.16
        cutter=cyl('Casting aperture cutter',a,b,.034,paint)
        cutter.scale[(axis+1)%3]=1.25
        bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Cast aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
        bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)

def finish_container(aid):
    # Join material batches within each hinge; articulation survives GLB export.
    groups={}
    for ob in list(bpy.context.scene.objects):
        if ob.type!='MESH':continue
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        groups.setdefault((ob.parent,ob.data.materials[0].name),[]).append(ob)
    for (parent,key),objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
        bpy.context.object.name=(parent.name if parent else 'Shell')+'_'+key
    save(aid)

def build(aid,w,l,h):
    clear()
    paint=mat('Container_Paint',(.63,.68,.70),.45)
    metal=mat('Fixed_ZincHardware',(.40,.46,.49),.8)
    gasket=mat('Fixed_DoorSeal',(.025,.032,.037),.05)
    timber=mat('Fixed_PlywoodFloor',(.27,.20,.13),.0)
    dark=mat('Fixed_Underframe',(.08,.10,.11),.5)
    # Structural rails, columns and true cast openings stay within the envelope.
    for x in [-1,1]:
        for y in [-1,1]:
            xx=x*(w/2-.089);yy=y*(l/2-.081)
            box('Corner post',(xx,yy,h/2),(.135,.12,h-.18),paint)
            for z in [.059,h-.059]:cast('Corner casting',(xx,yy,z),paint)
            socket(f'TopCorner_{x}_{y}',(xx,yy,h))
        for z,thick in [(.095,.15),(h-.065,.11)]:
            box('Side longitudinal rail',(x*(w/2-.045),0,z),(.09,l-.30,thick),paint)
    for y in [-1,1]:
        for z in [.085,h-.065]:box('End cross rail',(0,y*(l/2-.05),z),(w-.28,.10,.12),paint)
    for yy in [(-l/2+.28)+i*(l-.56)/max(1,round(l/.45)) for i in range(round(l/.45)+1)]:
        box('Floor crossmember',(0,yy,.075),(w-.18,.055,.085),dark)
    for i in range(8):box('Plywood floor',( -w/2+.14+(i+.5)*(w-.28)/8,0,.153),((w-.28)/8-.004,l-.25,.034),timber)
    # Corrugated sides are a continuous folded sheet, not overlapping bars.
    profile=corrugation(-l/2+.15,l/2-.15)
    for side in [-1,1]:
        points=[(side*(w/2-.061+.033*d),y,z) for y,d in profile for z in [.17,h-.12]]
        faces=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(profile)-1)]
        if side>0:faces=[f[::-1] for f in faces]
        sheet('Corrugated side',points,faces,paint)
    # Front end with vertical pressing and transverse roof pressings.
    profile=corrugation(-w/2+.15,w/2-.15,.25)
    sheet('Corrugated front',[(x,l/2-.055+.025*d,z) for x,d in profile for z in [.17,h-.12]],[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(profile)-1)],paint)
    profile=corrugation(-l/2+.15,l/2-.15,.30)
    sheet('Pressed roof',[(x,y,h-.035+.014*d) for y,d in profile for x in [-w/2+.08,w/2-.08]],[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(profile)-1)],paint)
    # Independent leaves with seals, stiles, hinges, lock rods, cams and handles.
    for side in [-1,1]:
        before=set(bpy.context.scene.objects)
        cx=side*(w/4-.035);dw=w/2-.14;yy=-l/2+.055
        box('Door perimeter seal',(cx,yy+.018,h/2),(dw+.022,.025,h-.24),gasket)
        box('Door steel leaf',(cx,yy,h/2),(dw,.035,h-.27),paint)
        for dx in [-dw/2+.035,dw/2-.035]:box('Door stile',(cx+dx,yy-.023,h/2),(.07,.035,h-.29),paint)
        for i in range(4):box('Door pressed rib',(cx+(i-1.5)*dw/4,yy-.036,h/2),(.07,.026,h-.42),paint)
        for z in [.25,h/2,h-.25]:
            cyl('Hinge pin',(side*(w/2-.135),yy-.025,z-.075),(side*(w/2-.135),yy-.025,z+.075),.024,metal)
            box('Hinge strap',(side*(w/2-.225),yy-.034,z),(.23,.022,.048),metal)
        for dx in [-dw*.28,dw*.28]:
            x=cx+dx
            cyl('Vertical locking rod',(x,yy-.07,.14),(x,yy-.07,h-.14),.016,metal)
            for z in [.23,.7,h-.7,h-.23]:
                box('Rod keeper',(x,yy-.05,z),(.082,.035,.045),metal)
                for xx in [-.025,.025]:cyl('Keeper rivet',(x+xx,yy-.069,z),(x+xx,yy-.081,z),.006,metal)
            for z in [.16,h-.16]:box('Lock cam',(x+side*.025,yy-.073,z),(.11,.043,.05),metal)
            cyl('Locking handle',(x,yy-.085,.90),(x+side*.18,yy-.085,.90),.012,metal)
            box('Handle latch',(x+side*.15,yy-.075,.90),(.055,.04,.07),metal)
        box('Information plate',(cx,yy-.061,.44),(.30,.004,.17),metal)
        new=[ob for ob in bpy.context.scene.objects if ob not in before]
        hinge=bpy.data.objects.new('DoorPortPivot' if side<0 else 'DoorStarboardPivot',None);bpy.context.collection.objects.link(hinge)
        hinge.location=(side*(w/2-.135),yy,h/2)
        bpy.context.view_layer.update()
        for ob in new:
            matrix=ob.matrix_world.copy();ob.parent=hinge;ob.matrix_world=matrix
    socket('LiftCentre',(0,0,h+.5));socket('FloorDatum',(0,0,0))
    finish_container(aid)

for aid,w,l,h in [('container_20ft',2.438,6.058,2.591),('container_40ft',2.438,12.192,2.591),('legacy_breakbulk_4m',3.8,3.8,3.8)]:
    build(aid,w,l,h)
    # A separate lifting spreader meets all four castings and the crane hook.
    clear();lifting=mat('Fixed_LiftingFrame',(.66,.40,.06),.4);steel=mat('Fixed_LiftSteel',(.32,.37,.38),.8)
    end=l/2-.081;half=w/2-.089
    for x in [-.55,.55]:
        box('Spreader girder web',(x,0,h+.22),(.035,l-.16,.22),lifting)
        for z in [h+.11,h+.33]:box('Girder flange',(x,0,z),(.18,l-.16,.025),lifting)
    for y in [-end,end]:
        box('Spreader end beam',(0,y,h+.20),(w-.178,.15,.18),lifting)
        for x in [-half,half]:
            cyl('Twistlock',(x,y,h),(x,y,h+.22),.032,steel)
            box('Twistlock housing',(x,y,h+.20),(.13,.15,.13),lifting)
    box('Central suspension plate',(0,0,h+.30),(1.35,.6,.07),lifting)
    for x in [-.48,.48]:beam('Hook bridle',(x,0,h+.34),(0,0,h+.5),.03,.03,steel)
    socket('Hook',(0,0,h+.5));finish(aid+'_spreader')

# Individual twistlock bed fits two 20-foot boxes side by side in the 5 m hold.
clear();paint=mat('Warm white painted steel',(.30,.38,.38));steel=mat('Fixed_ZincHardware',(.42,.47,.49),.8)
rubber=mat('Fixed_CargoBearing',(.04,.05,.055),.05)
for x in [-1.13,1.13]:
    box('Longitudinal foundation',(x,0,.05),(.16,6.15,.10),paint)
    for y in [-2.948,2.948]:
        box('Corner bearing',(x,y,.11),(.24,.24,.04),rubber)
        cyl('Twistlock spigot',(x,y,.11),(x,y,.16),.034,steel)
        for dx in [-.09,.09]:cyl('Foundation bolt',(x+dx,y,.10),(x+dx,y,.13),.012,steel)
for y in [-2.948,2.948]:box('Bed tie',(0,y,.035),(2.42,.16,.07),paint)
socket('CargoDatum',(0,0,.13));finish('container_bed_20ft')
clear()
# Flush load deck spanning the 24 m hull opening. Top datum equals main deck.
deck=mat('Warm white painted steel',(.24,.29,.28),.4)
box('Load deck plate',(0,0,-.035),(5.06,8.06,.07),deck)
for y in [-3.8,-2.8,-1.8,-.8,.8,1.8,2.8,3.8]:
    box('Transverse girder web',(0,y,-.23),(5.06,.04,.39),deck)
    box('Girder lower flange',(0,y,-.42),(5.06,.20,.04),deck)
for x in [-1.25,1.25]:box('Longitudinal stiffener',(x,0,-.14),(.07,7.8,.22),deck)
socket('PortBed',(-1.25,0,0));socket('StarboardBed',(1.25,0,0));finish('cargo_deck_5x8')
assets=[]
for aid,style,size in [('container_bed_20ft','cargo_pad',[2.5,6.5,.16]),('cargo_deck_5x8','cargo_deck',[5.06,8.06,.0])]:
    assets.append(dict(id=aid,kind='furniture',style=style,model=f'res://resources/models/cargo/{aid}.glb',start_xz=[0,0],end_xz=size[:2],height_start_m=size[2],height_end_m=size[2],paintable=True))
(OUT/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2))
print('CONTAINERS EXPORTED: 20 ft, 40 ft, legacy cargo and 20 ft twistlock bed')
