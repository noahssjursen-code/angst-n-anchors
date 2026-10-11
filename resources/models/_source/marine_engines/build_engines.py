"""Original marine diesels with separate output coupling; metres, +Y forward."""
from pathlib import Path
exec((Path(__file__).resolve().parents[1]/'access_kit/build_access.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'machinery';OUT.mkdir(parents=True,exist_ok=True)

def pipe(name,points,r,material):
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=r;curve.bevel_resolution=2
    spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
    for point,co in zip(spline.bezier_points,points):
        point.co=co;point.handle_left_type='AUTO';point.handle_right_type='AUTO'
    ob=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(ob);curve.materials.append(material)
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH')

def engine(aid,L,W,H,vbank=False):
    clear()
    paint=mat('Engine_Paint',(.16,.31,.28),.4)
    steel=mat('Fixed_MachinedSteel',(.48,.53,.55),.8)
    hose=mat('Fixed_Rubber',(.028,.034,.039),.05)
    exhaust=mat('Fixed_HeatShield',(.36,.38,.35),.5)
    amber=mat('Fixed_ServiceCaps',(.85,.50,.07),.2)
    # Mounting feet and elastomer isolators are part of the engine package.
    for x in [-W*.34,W*.34]:
        box('Foundation rail',(x,0,.045),(.14,L+.4,.09),paint)
        for y in [-L*.38,L*.38]:
            box('Isolator base',(x,y,.10),(.22,.22,.06),steel)
            cyl('Isolation mount',(x,y,.12),(x,y,.22),.072,hose)
            cyl('Mount stud',(x,y,.2),(x,y,.28),.019,steel)
            box('Engine mounting foot',(x,y,.255),(.26,.2,.045),paint)
    box('Cast oil sump',(0,0,H*.23),(W*.53,L*.94,H*.23),paint)
    box('Crankcase',(0,0,H*.46),(W*.66,L,H*.32),paint)
    for side in [-1,1]:
        for i in range(6):
            y=(i-2.5)*L/6
            box('Inspection cover',(side*W*.342,y,H*.46),(.026,L*.133,H*.22),paint)
            for z in [H*.38,H*.54]:
                for yy in [-L*.049,L*.049]:cyl('Cover bolt',(side*W*.345,y+yy,z),(side*W*.371,y+yy,z),.010,steel)
    # Six separate head covers; the larger unit has two outward V banks.
    for bank in ([-1,1] if vbank else [0]):
        for i in range(6):
            y=(i-2.5)*L/6
            ob=box('Cylinder head',(bank*W*.20,y,H*.72),(W*(.35 if vbank else .56),L*.148,H*.32),paint)
            ob.rotation_euler.y=bank*math.radians(25)
            ob=box('Rocker cover',(bank*W*.27,y,H*.87),(W*(.33 if vbank else .53),L*.142,H*.10),paint)
            ob.rotation_euler.y=bank*math.radians(25)
            for dx in [-.08,.08]:cyl('Rocker cover fastener',(bank*W*.27+dx,y,H*.92),(bank*W*.27+dx,y,H*.935),.010,steel)
    # Intake/charge cooler to port, jacketed exhaust and turbo to starboard.
    cyl('Water-jacket exhaust manifold',(W*.40,-L*.48,H*.72),(W*.40,L*.43,H*.72),W*.10,exhaust)
    box('Charge air cooler',(-W*.40,0,H*.70),(W*.19,L*.91,H*.19),paint)
    for i in range(6):
        y=(i-2.5)*L/6
        pipe('Exhaust branch',[(W*.24,y,H*.76),(W*.34,y,H*.78),(W*.40,y,H*.72)],.035,exhaust)
        pipe('Fuel injector line',[(-W*.37,y,H*.57),(-W*.32,y,H*.84),(-W*.15,y,H*.88)],.009,steel)
    cyl('Turbo turbine',(W*.40,-L*.53,H*.82),(W*.40,-L*.37,H*.82),W*.16,exhaust)
    cyl('Turbo compressor',(W*.40,-L*.70,H*.82),(W*.40,-L*.54,H*.82),W*.14,steel)
    pipe('Charge pipe',[(W*.40,-L*.65,H*.82),(W*.28,-L*.69,H*1.02),(-W*.30,-L*.64,H*.96),(-W*.40,-L*.40,H*.72)],.047,steel)
    cyl('Air filter housing',(W*.40,-L*.84,H*.82),(W*.40,-L*.69,H*.82),W*.18,hose)
    for y in [-L*.81,-L*.72]:cyl('Filter clamp',(W*.40,y-.008,H*.82),(W*.40,y+.008,H*.82),W*.186,steel)
    pipe('Wet exhaust outlet',[(W*.40,-L*.44,H*.93),(W*.49,-L*.40,H*1.02),(W*.50,-L*.10,H*1.04)],.058,exhaust)
    # Cooling circuit and serviceable filters; routed ends actually meet housings.
    cyl('Heat exchanger',(-W*.40,L*.32,H*.68),(-W*.40,L*.53,H*.68),W*.145,paint)
    for z in [H*.46,H*.57]:
        pipe('Coolant hose',[(-W*.40,L*.41,H*.68),(-W*.5,L*.5,z),(-W*.40,L*.23,z)],.028,hose)
    for y in [-.13,.13]:
        cyl('Spin-on service filter',(-W*.40,y,H*.25),(-W*.40,y,H*.5),W*.07,steel)
        cyl('Filter cap',(-W*.40,y,H*.49),(-W*.40,y,H*.53),W*.08,paint)
    cyl('Oil filler cap',(0,L*.28,H*.91),(0,L*.28,H*.96),.045,amber)
    # Front pulley/belt guarded in normal use; visible cutouts and bolts.
    for z,rad in [(H*.42,W*.15),(H*.68,W*.095)]:
        cyl('Accessory pulley',(0,L*.51,z),(0,L*.55,z),rad,steel)
    for x in [-W*.14,W*.14]:beam('Belt side',(x,L*.552,H*.42),(x*.67,L*.552,H*.68),.024,.015,hose)
    box('Belt guard',(0,L*.58,H*.54),(W*.43,.05,H*.46),paint)
    for i in range(6):box('Guard cooling slot',(0,L*.608,H*.36+i*H*.064),(W*.30,.005,.018),hose)
    # Aft reduction gearbox with flange and output mount toward Godot +Z.
    cyl('Flywheel housing',(0,-L*.51,H*.40),(0,-L*.65,H*.40),W*.31,paint)
    box('Marine reduction gear',(0,-L*.83,H*.39),(W*.55,L*.33,H*.36),paint)
    for side in [-1,1]:
        box('Gear access cover',(side*W*.282,-L*.83,H*.40),(.025,L*.22,H*.24),steel)
    cyl('Output bearing',(0,-L*1.035,H*.32),(0,-L*.96,H*.32),W*.14,steel)
    socket('OutputCoupling',(0,-L*1.045,H*.32))
    socket('EngineCentre',(0,0,H*.52))
    socket('ExhaustOutlet',(W*.50,-L*.10,H*1.04))
    finish(aid)

for values in [('marine_i6_compact',1.35,.82,1.25,False),('marine_i6_coastal',1.8,1.10,1.65,False),('marine_v12_freighter',2.1,1.42,1.9,True)]:engine(*values)
clear();metal=mat('Fixed_MachinedSteel',(.43,.47,.48),.8);rubber=mat('Fixed_Rubber',(.03,.035,.04),.1)
cyl('Drive coupling flange',(0,-.09,0),(0,.02,0),.11,metal)
cyl('Flexible coupling',(0,-.07,0),(0,-.015,0),.115,rubber)
for i in range(8):
    a=i*math.tau/8;x=.082*math.cos(a);z=.082*math.sin(a)
    cyl('Coupling bolt',(x,-.105,z),(x,-.083,z),.009,metal)
socket('ShaftEnd',(0,-.105,0));finish('marine_drive_coupling')
print('MARINE ENGINES EXPORTED: compact I6, coastal I6, freighter V12, separate coupling')
