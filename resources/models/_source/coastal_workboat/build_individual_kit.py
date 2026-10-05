"""Build separate original Blender assets, then instance them for a contact sheet.
No procedural-game meshes, JSON geometry or legacy GLBs are read.
Run: blender --background --factory-startup --python <this file>
"""
import bpy, os, math, json
from mathutils import Vector

BASE=os.path.dirname(os.path.abspath(__file__))
# Share Blender modelling helpers and new hull design, not generated boat data.
with open(os.path.join(BASE,'build_workboat.py'),encoding='utf8') as f:
    helpers=f.read().split('stages=[',1)[0]
exec(compile(helpers,'blender_modelling_helpers','exec'),globals())

RENDER_DIR=r'C:\Users\noahs\Documents\Codex\2026-10-05\referenced-chatgpt-conversation-this-is-an\outputs\individual-models'
os.makedirs(RENDER_DIR,exist_ok=True)
KIT_ROOT=os.path.join(ROOT,'parts','marine_kit')
KIT_SOURCE=os.path.join(ROOT,'_source','marine_kit')
os.makedirs(KIT_ROOT,exist_ok=True);os.makedirs(KIT_SOURCE,exist_ok=True)
assets=[]
kit_scene=scene
kit_scene.name='INDIVIDUAL MARINE ASSETS | Blender originals'
for c in list(kit_scene.collection.children):kit_scene.collection.children.unlink(c)

def only_matching(prefixes):
    for obj in list(groups['01'].objects):
        if not any(obj.name.startswith(p) for p in prefixes):
            bpy.data.objects.remove(obj,do_unlink=True)

def hull_asset():
    hull()
    only_matching(['14m rounded steel hull','Continuous gunwale','Heavy rubber rubbing strake'])

def deck_asset():
    hull()
    only_matching(['Cambered non-slip main deck'])

def shell_asset():
    cabin()
    only_matching(['Wheelhouse lower','Wheelhouse forward','Aft bulkhead','Door header','Wheelhouse floor'])

def roof_asset():
    cabin()
    only_matching(['Rounded wheelhouse roof','Roof drip edge'])

def window_asset():
    corners=[(-.43,0,0),(.43,0,0),(.43,.06,.96),(-.43,.06,.96)]
    obj=mesh('Laminated marine window',corners,[(0,1,2,3)],glass)
    sol=obj.modifiers.new('12mm glass','SOLIDIFY');sol.thickness=.012
    tube('EPDM glazing seal',corners+[corners[0]],.031,rubber)
    tube('Aluminium glazing bead',corners+[corners[0]],.017,steel)
    tube('Wiper', [(-.30,.05,.06),(.14,.11,.65)],.011,black)

def door_asset():
    box('Door lower leaf',(0,0,.60),(.72,.055,1.20),ivory,.018)
    box('Door upper leaf',(0,0,1.86),(.72,.055,.16),ivory,.018)
    for x in [-.31,.31]:box('Door window stile',(x,0,1.49),(.10,.055,.58),ivory,.01)
    # Glazing and frame are separate selectable objects.
    corners=[(-.24,-.035,1.22),(.24,-.035,1.22),(.24,-.035,1.76),(-.24,-.035,1.76)]
    mesh('Door glazing',corners,[(0,1,2,3)],glass)
    tube('Window gasket',corners+[corners[0]],.02,rubber)
    for x in [-.405,.405]:box('Door jamb',(x,0,1.0),(.07,.11,2.04),steel,.012)
    box('Door frame header',(0,0,2.03),(.86,.11,.07),steel,.012)
    box('Door sill',(0,0,.025),(.86,.12,.05),steel,.012)
    rod('Door pull',(.25,-.1,.72),(.25,-.1,1.05),.019,steel)
    for z in [.2,1.64]:rod('Door hinge',(-.37,-.03,z),(-.37,-.03,z+.14),.025,steel)

def rail_asset():
    for x in [-.60,.60]:
        box('Welded baseplate',(x,0,.015),(.105,.105,.03),steel,.01)
        rod('Stanchion',(x,0,.025),(x,0,1.0),.022,steel)
    for z in [.50,1.0]:rod('Rail',(-.62,0,z),(.62,0,z),.022,steel)

def bollard_asset():
    box('Bollard bedplate',(0,0,.025),(.42,.47,.05),navy,.023)
    for y in [-.13,.13]:
        rod('Bollard barrel',(0,y,.04),(0,y,.32),.060,steel)
        rod('Bollard horn',(-.17,y,.28),(.17,y,.28),.027,steel)
    for x in [-.16,.16]:
        for y in [-.18,.18]:rod('Anchor bolt',(x,y,.048),(x,y,.067),.015,steel,6)

def ladder_asset():
    for x in [-.26,.26]:
        tube('Bent ladder rail',[(x,0,0),(x,0,1.7),(x,.08,1.84),(x,.24,1.84)],.025,steel)
    for z in [.18,.48,.78,1.08,1.38]:rod('Anti-slip rung',(-.26,0,z),(.26,0,z),.022,steel)

def tire_asset():
    torus('Rubber tyre',(0,0,.35),.235,.092,rubber,(math.pi/2,0,0))
    tube('Rope strop',[(-.10,0,.58),(-.07,0,.89),(.07,0,.89),(.10,0,.58)],.011,black)

def hatch_asset():
    box('Raised hatch coaming',(0,0,.08),(1.65,2.15,.16),navy,.055)
    box('Hatch cover',(0,0,.18),(1.56,2.06,.06),deckmat,.045)
    for x in [-.68,.68]:
        for y in [-.80,.80]:rod('Hatch dog',(x-.085,y,.23),(x+.085,y,.23),.017,steel)

def winch_asset():
    machinery()
    only_matching(['Winch','Drum flange','Cable winding','Hydraulic'])

def exhaust_asset():
    rod('Exhaust tube',(0,0,0),(0,0,2.1),.065,steel)
    rod('Rain cap',(0,0,2.08),(0,0,2.16),.12,black)
    for z in [.3,1.4]:torus('Pipe clamp',(0,0,z),.071,.012,steel)

def raft_asset():
    box('Liferaft cradle',(0,0,.04),(.65,1.05,.08),steel,.025)
    box('GRP canister',(0,0,.30),(.60,1.0,.46),ivory,.20)
    for y in [-.31,.31]:box('Retention band',(0,y,.31),(.625,.04,.47),black,.045)

def helm_asset():
    interior()
    only_matching(['Helm','Sloped instrument','Navigation display','Throttle'])

def chair_asset():
    interior()
    only_matching(['Captain','Chair armrest'])

def locker_asset():
    box('Steel locker',(0,0,.45),(.52,.55,.90),ivory,.035)
    box('Locker door',(0,-.281,.47),(.45,.025,.80),ivory,.018)
    rod('Recessed pull',(.15,-.31,.48),(.15,-.31,.65),.012,steel)

def seat_asset():
    box('Bench base',(0,0,.25),(.55,1.0,.50),ivory,.025)
    box('Upholstered cushion',(0,0,.56),(.57,1.01,.12),black,.055)

def lamp_asset(color):
    box('Navigation light bracket',(0,0,.035),(.16,.22,.07),black,.02)
    box('Sealed navigation lens',(0,0,.125),(.12,.17,.13),color,.035)
    box('Protective cap',(0,0,.20),(.16,.21,.025),black,.01)

def flood_asset():
    box('Mounting foot',(0,0,.02),(.14,.12,.04),steel,.015)
    for x in [-.12,.12]:box('Yoke',(x,0,.12),(.025,.07,.19),steel,.01)
    box('LED flood housing',(0,0,.23),(.25,.09,.18),black,.025)
    box('Flood lens',(0,-.05,.23),(.21,.012,.14),ivory,.015)
    for x in [-.065,0,.065]:
        for z in [.195,.26]:rod('LED optic',(x,-.06,z),(x,-.065,z),.015,steel)

def mast_asset():
    box('Mast base',(0,0,.04),(.30,.35,.08),steel,.02)
    rod('Raked mast',(0,0,.08),(0,-.20,1.82),.05,steel)
    rod('Equipment crossbar',(-.60,-.15,1.15),(.60,-.15,1.15),.032,steel)

def radar_asset():
    rod('Radar pedestal',(0,0,0),(0,0,.13),.065,steel)
    box('Radar radome',(0,0,.22),(.78,.27,.14),ivory,.06)

def aerial_asset():
    rod('Antenna foot',(0,0,0),(0,0,.10),.03,steel)
    rod('VHF whip',(0,0,.10),(0,0,1.40),.008,ivory)

def buoy_asset():torus('Lifebuoy',(0,0,.36),.29,.065,orange,(math.pi/2,0,0))

def prop_asset():
    propulsion()
    only_matching(['Bronze propeller hub','Swept bronze'])

def rudder_asset():
    box('Hydrodynamic rudder',(0,0,.52),(.065,.42,1.04),navy,.03)
    rod('Rudder stock',(0,0,.7),(0,0,1.35),.04,steel)

# UGC construction surfaces: 0.5 m horizontal snap, 2.2 m storey, thin plating.
# Origin is bottom-centre on a panel's mounting plane, never a voxel centre.
def wall_asset(width=1.0):
    box('Marine sandwich wall',(0,0,1.10),(width,.065,2.20),ivory,.012)
    box('Lower sealing strip',(0,-.036,.055),(width,.018,.11),rubber,.006)

def window_panel_asset():
    box('Window wall sill',(0,0,.40),(1,.065,.80),ivory,.01)
    box('Window wall header',(0,0,2.11),(1,.065,.18),ivory,.01)
    for x in [-.4675,.4675]:box('Window wall stile',(x,0,1.41),(.065,.065,1.22),ivory,.008)
    corners=[(-.43,-.008,.85),(.43,-.008,.85),(.43,-.008,1.97),(-.43,-.008,1.97)]
    pane=mesh('Glazing',corners,[(0,1,2,3)],glass)
    sol=pane.modifiers.new('Laminated glazing','SOLIDIFY');sol.thickness=.012
    tube('EPDM seal',corners+[corners[0]],.021,rubber)
    tube('Glazing bead',corners+[corners[0]],.012,steel)

def windshield_panel_asset():
    box('Bridge sill',(0,0,.4),(1,.065,.80),ivory,.01)
    corners=[(-.465,0,.80),(.465,0,.80),(.465,.15,2.14),(-.465,.15,2.14)]
    pane=mesh('Raked bridge glazing',corners,[(0,1,2,3)],glass)
    sol=pane.modifiers.new('Laminated glazing','SOLIDIFY');sol.thickness=.014
    tube('Windshield perimeter',corners+[corners[0]],.025,steel)
    box('Top beam',(0,.15,2.17),(1,.075,.06),ivory,.01)
    tube('Wiper', [(-.28,-.04,.9),(.18,.02,1.65)],.012,black)

def door_panel_asset():
    door_asset()
    for x in [-.465,.465]:box('Door wall stile',(x,0,1.10),(.07,.07,2.20),ivory,.01)
    box('Door wall lintel',(0,0,2.13),(1,.07,.14),ivory,.01)

def corner_asset():
    # A true rounded 90-degree cabin corner, R=0.25 m, not a diagonal block.
    verts=[];faces=[]
    for z in [0,.8,2.02,2.2]:
        for i in range(17):
            a=i*math.pi/32
            verts.append((.25*math.cos(a),.25*math.sin(a),z))
    for h in range(3):
        for i in range(16):
            a=h*17+i;faces.append((a,a+1,a+18,a+17))
    obj=mesh('Curved corner panel',verts,faces,ivory,True)
    obj.data.materials.append(glass)
    for i,p in enumerate(obj.data.polygons):p.material_index=1 if 16<=i<32 else 0
    solid=obj.modifiers.new('Panel thickness','SOLIDIFY');solid.thickness=.035
    for z in [.8,2.02]:tube('Curved glazing bead',[(.25*math.cos(i*math.pi/32),.25*math.sin(i*math.pi/32),z) for i in range(17)],.014,steel)
    for x,y in [(.25,0),(0,.25)]:rod('Corner edge extrusion',(x,y,0),(x,y,2.2),.023,ivory)

def deck_module(width=2.0):
    box('Non-slip deck panel',(0,0,-.04),(width,width,.08),deckmat,.012)
    for x in [-width/2+.035,width/2-.035]:
        for y in [-width/2+.035,width/2-.035]:rod('Countersunk fastener',(x,y,-.005),(x,y,.001),.009,steel,8)

def roof_module(width=2.0):
    box('Insulated roof panel',(0,0,.05),(width,width,.10),ivory,.025)

def stair_asset():
    for i in range(6):
        y=i*.25;z=(i+1)*.1833
        box('Grated stair tread',(0,y,z),(.8,.28,.035),steel,.01)
    for x in [-.43,.43]:
        tube('Stair stringer',[(x,-.13,.10),(x,1.4,1.10)],.038,steel)
        tube('Stair handrail',[(x,-.13,1.02),(x,1.4,2.02)],.024,steel)
        for y,z in [(0,.2),(1.25,1.1)]:rod('Stair rail upright',(x,y,z),(x,y,z+.94),.02,steel)

def corner_rail_asset():
    for x,y in [(0,0),(1,0),(0,1)]:rod('Corner rail stanchion',(x,y,0),(x,y,1.0),.022,steel)
    for z in [.5,1.0]:tube('Corner handrail',[(1,0,z),(.15,0,z),(.04,.04,z),(0,.15,z),(0,1,z)],.022,steel)

def build_asset(asset_id,title,fn,anchor=(0,0,0)):
    global groups,current,scene
    asset_scene=bpy.data.scenes.new(asset_id)
    bpy.context.window.scene=asset_scene;scene=asset_scene
    asset_scene.unit_settings.system='METRIC'
    col=bpy.data.collections.new(asset_id)
    asset_scene.collection.children.link(col)
    groups={key:col for key in ['01','02','03','04','05','06','07','08','09']}
    current='01'
    fn()
    for obj in col.objects:obj.location-=Vector(anchor)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in col.objects:obj.select_set(True)
    if col.objects:bpy.context.view_layer.objects.active=col.objects[0]
    # Convert Blender curves to editable mesh before delivery/export.
    bpy.ops.object.convert(target='MESH')
    bpy.context.view_layer.update()
    coords=[obj.matrix_world@Vector(v) for obj in col.objects if obj.type=='MESH' for v in obj.bound_box]
    mn=Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    mx=Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    folder=os.path.join(KIT_ROOT,asset_id);os.makedirs(folder,exist_ok=True)
    source_folder=os.path.join(KIT_SOURCE,asset_id);os.makedirs(source_folder,exist_ok=True)
    source_path=os.path.join(source_folder,asset_id+'.blend')
    bpy.data.libraries.write(source_path,{asset_scene},fake_user=True)
    glb_path=os.path.join(folder,asset_id+'.glb')
    bpy.ops.export_scene.gltf(filepath=glb_path,export_format='GLB',use_selection=True,use_active_scene=True,export_apply=True)
    assets.append({'id':asset_id,'title':title,'collection':col,'bounds_min':list(mn),'bounds_max':list(mx),'size_m':list(mx-mn),'blend':source_path,'glb':glb_path,'objects':len(col.objects)})
    print('INDIVIDUAL_ASSET',asset_id,len(col.objects),flush=True)

definitions=[
('coastal_hull_14m','01 / CURVED STEEL HULL',hull_asset,(0,0,0)),
('coastal_deck_14m','02 / CAMBERED DECK',deck_asset,(0,0,0)),
('wall_panel_1m','03 / WALL PANEL 1m',lambda:wall_asset(1),(0,0,0)),
('wall_panel_2m','04 / WALL PANEL 2m',lambda:wall_asset(2),(0,0,0)),
('marine_window','05 / FRAMED GLAZING',window_asset,(0,0,0)),
('watertight_door','06 / WATERTIGHT DOOR',door_asset,(0,0,0)),
('rail_section_1200','07 / TUBULAR RAIL',rail_asset,(0,0,0)),
('double_bollard','08 / MOORING BOLLARD',bollard_asset,(0,0,0)),
('boarding_ladder','09 / BOARDING LADDER',ladder_asset,(0,0,0)),
('tyre_fender','10 / TYRE FENDER',tire_asset,(0,0,0)),
('deck_hatch','11 / HATCH & COAMING',hatch_asset,(0,0,0)),
('hydraulic_winch','12 / HYDRAULIC WINCH',winch_asset,(0,-5.6,1.375)),
('exhaust_stack','13 / EXHAUST STACK',exhaust_asset,(0,0,0)),
('liferaft_canister','14 / LIFERAFT CANISTER',raft_asset,(0,0,0)),
('helm_console','15 / HELM & INSTRUMENTS',helm_asset,(0,2.25,1.46)),
('captain_chair','16 / HELM CHAIR',chair_asset,(-.32,1.23,1.48)),
('storage_locker','17 / STORAGE LOCKER',locker_asset,(0,0,0)),
('crew_bench','18 / CREW BENCH',seat_asset,(0,0,0)),
('navigation_light_port','19 / PORT LIGHT',lambda:lamp_asset(red),(0,0,0)),
('navigation_light_starboard','20 / STARBOARD LIGHT',lambda:lamp_asset(green),(0,0,0)),
('led_worklight','21 / LED WORKLIGHT',flood_asset,(0,0,0)),
('signal_mast','22 / SIGNAL MAST',mast_asset,(0,0,0)),
('radar_radome','23 / RADAR RADOME',radar_asset,(0,0,0)),
('vhf_aerial','24 / VHF AERIAL',aerial_asset,(0,0,0)),
('lifebuoy','25 / LIFEBUOY',buoy_asset,(0,0,0)),
('bronze_propeller','26 / BRONZE PROPELLER',prop_asset,(0,-6.56,-.79)),
('rudder','27 / RUDDER & STOCK',rudder_asset,(0,0,0)),
('window_wall_1m','28 / WINDOW WALL 1m',window_panel_asset,(0,0,0)),
('windshield_wall_1m','29 / RAKED WINDOW WALL',windshield_panel_asset,(0,0,0)),
('door_wall_1m','30 / DOOR WALL 1m',door_panel_asset,(0,0,0)),
('curved_corner_wall','31 / CURVED CORNER',corner_asset,(0,0,0)),
('deck_plate_1m','32 / DECK PLATE 1m',lambda:deck_module(1),(0,0,0)),
('deck_plate_2m','33 / DECK PLATE 2m',lambda:deck_module(2),(0,0,0)),
('roof_panel_1m','34 / ROOF PANEL 1m',lambda:roof_module(1),(0,0,0)),
('roof_panel_2m','35 / ROOF PANEL 2m',lambda:roof_module(2),(0,0,0)),
('marine_stair','36 / MARINE STAIR',stair_asset,(0,0,0)),
('corner_rail','37 / CORNER RAIL',corner_rail_asset,(0,0,0)),
]
for definition in definitions:build_asset(*definition)

# A contact sheet of linked collection instances; the source models remain separate.
bpy.context.window.scene=kit_scene;scene=kit_scene
sheet=bpy.data.collections.new('Asset sheet instances');kit_scene.collection.children.link(sheet)
groups={'09':sheet};current='09'
tilemat=mat('Asset sheet plinth',(.115,.145,.17),.1,.64)
for index,a in enumerate(assets):
    x=(index%5-2)*5.0;y=(3-index//5)*5.2
    mn=Vector(a['bounds_min']);mx=Vector(a['bounds_max']);size=mx-mn
    scale=2.65/max(size.x,size.y,size.z)
    instance=bpy.data.objects.new(a['id'],None)
    instance.instance_type='COLLECTION';instance.instance_collection=a['collection']
    instance.scale=(scale,)*3
    instance.location=(x-(mx.x+mn.x)*.5*scale,y-(mx.y+mn.y)*.5*scale,-mn.z*scale+.10)
    sheet.objects.link(instance)
    box('Display plinth',(x,y,-.08),(4.65,4.6,.16),tilemat,.12)
    curve=bpy.data.curves.new(a['title'],'FONT');curve.body=a['title'];curve.align_x='CENTER';curve.size=.19;curve.extrude=0
    label=bpy.data.objects.new(a['title'],curve);sheet.objects.link(label)
    label.location=(x,y-2.13,.018);assign(label,ivory)

world=bpy.data.worlds.new('Studio world');scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.16,.19,.23,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.65
for name,loc,energy,size in [('Key',(0,-5,24),9000,20),('Fill',(-15,8,18),8000,18)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);sheet.objects.link(obj);obj.location=loc
    obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Contact sheet camera');cam=bpy.data.objects.new('Contact sheet camera',data);sheet.objects.link(cam)
cam.location=(0,-24,49);cam.rotation_euler=(Vector((0,-2,0))-cam.location).to_track_quat('-Z','Y').to_euler()
data.type='ORTHO';data.ortho_scale=46;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=2100;scene.render.resolution_y=3000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.filepath=os.path.join(RENDER_DIR,'marine-kit-contact-sheet.png')
scene.render.image_settings.file_format='PNG'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(KIT_SOURCE,'marine_kit.blend'))
with open(os.path.join(KIT_ROOT,'manifest.json'),'w') as f:
    json.dump({'description':'Individual original Blender-authored UGC construction models. Display instances are scaled to fit tiles; sources use metres. No gameplay or collision integration yet.', 'snap_m':.5,'wall_height_m':2.2,'assets':[{k:v for k,v in a.items() if k!='collection'} for a in assets]},f,indent=2)
bpy.ops.render.render(write_still=True)
print('INDIVIDUAL_KIT_COMPLETE',len(assets),flush=True)

# Build a CUSTOM layout from the same asset references. No bespoke cabin mesh.
demo=bpy.data.scenes.new('UGC example | assembled from individual assets')
bpy.context.window.scene=demo;scene=demo;demo.world=world
assembly=bpy.data.collections.new('UGC placements');demo.collection.children.link(assembly)
by_id={a['id']:a for a in assets};placements=[]
def place(asset_id,position=(0,0,0),yaw=0):
    instance=bpy.data.objects.new(asset_id,None);instance.instance_type='COLLECTION'
    instance.instance_collection=by_id[asset_id]['collection'];instance.location=position
    instance.rotation_euler.z=math.radians(yaw);assembly.objects.link(instance)
    placements.append({'asset_id':asset_id,'position_m':[position[0],position[2],-position[1]],'yaw_degrees':yaw})
    return instance
place('coastal_hull_14m');place('coastal_deck_14m')
floor_z=1.50
# 3m x 4m wheelhouse, freely assembled as 1m panels around an empty interior.
for x in [-1,0,1]:
    place('window_wall_1m',(x,3,floor_z),180)
    place('door_wall_1m' if x==0 else 'wall_panel_1m',(x,-1,floor_z))
for y in [-.5,.5,1.5,2.5]:
    for side in [-1,1]:place('window_wall_1m',(side*1.5,y,floor_z),90 if side==1 else -90)
for x in [-1,0,1]:
    for y in [-.5,.5,1.5,2.5]:
        place('deck_plate_1m',(x,y,floor_z))
        place('roof_panel_1m',(x,y,floor_z+2.2))
place('helm_console',(0,2.2,floor_z));place('captain_chair',(-.32,1.1,floor_z))
place('crew_bench',(-1,.1,floor_z));place('storage_locker',(1,.1,floor_z))
place('signal_mast',(0,.2,3.8));place('radar_radome',(0,.02,5.06));place('vhf_aerial',(.42,.02,5.08))
place('navigation_light_port',(-1.38,2.5,3.8));place('navigation_light_starboard',(1.38,2.5,3.8))
for x in [-1,1]:place('led_worklight',(x,-.85,3.8))
place('liferaft_canister',(-.65,.25,3.8));place('exhaust_stack',(1.15,-.75,1.50))
place('deck_hatch',(0,-3.7,1.36));place('hydraulic_winch',(0,-5.6,1.4))
for side in [-1,1]:
    for y in [-5.6,-4.4,-3.2,-2.,-.8,.4]:
        beam,keel,d=profile(y);place('rail_section_1200',(side*(beam-.09),y,d),90)
    for y in [-5.8,4.8]:
        beam,keel,d=profile(y);place('double_bollard',(side*(beam-.3),y,d))
    for y in [-4.7,-1.8,1]:
        beam,keel,d=profile(y);place('tyre_fender',(side*(beam+.03),y,d-.75),90)
place('boarding_ladder',(-2.34,-2.,-.25),90)
place('lifebuoy',(1.55,.0,1.6),90)
place('bronze_propeller',(0,-6.56,-.79));place('rudder',(0,-6.83,-1.1))
for obj in sheet.objects:
    if obj.type=='LIGHT':demo.collection.objects.link(obj)
camera=bpy.data.objects.new('UGC overview',data.copy());demo.collection.objects.link(camera)
camera.location=(13,18,11);camera.rotation_euler=(Vector((0,0,1.8))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale=18.5;demo.camera=camera
demo.render.engine='CYCLES';demo.cycles.samples=32
demo.render.resolution_x=1600;demo.render.resolution_y=1100;demo.render.resolution_percentage=100
demo.view_settings.view_transform='AgX'
demo.render.image_settings.file_format='PNG';demo.render.filepath=os.path.join(RENDER_DIR,'ugc-assembly.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(KIT_SOURCE,'marine_kit.blend'))
with open(os.path.join(KIT_ROOT,'example_ugc_layout.json'),'w') as f:json.dump({'version':1,'units':'metres','geometry':'Separate Blender-authored GLB assets','placements':placements},f,indent=2)
bpy.ops.render.render(write_still=True)
print('UGC_ASSEMBLY_COMPLETE',len(placements),flush=True)
