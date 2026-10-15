"""Editable harbour parts: metres, Blender +Y seaward -> Godot -Z.
Deck Z=0. Edge details descend; workshop roofs are at Z=3, never terrain height.
Materials use the approved SurfaceMaterialLibrary names. No economy in meshes.
Run: blender --background --python build_custom_harbour.py
"""
import bpy, math, json, random, sys
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
OUT=ROOT/'resources/models/parts/custom_harbour'
MANIFEST=ROOT/'resources/data/ports/custom_harbour_assets.json'
ONLY=sys.argv[sys.argv.index('--only')+1] if '--only' in sys.argv else None
PREVIOUS={row['id']:row for row in json.loads(MANIFEST.read_text(encoding='utf-8'))['assets']} if ONLY else {}
OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
bpy.context.scene.unit_settings.scale_length=1.0
bpy.context.preferences.filepaths.save_version=0
ASSETS=[]

def material(name,c,metal=0,rough=.7):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True;m.diffuse_color=(*c,1)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m
concrete=material('Concrete',(.39,.40,.37),0,.94)
steel=material('Galvanized',(.41,.46,.46),.74,.42)
dark=material('Dark steel',(.065,.074,.075),.6,.52)
rubber=material('Rubber',(.027,.029,.027),0,.94)
orange=material('Safety orange',(.92,.20,.024),0,.56)
yellow=material('Safety yellow',(.90,.58,.055),0,.58)
white=material('Ivory trim',(.78,.76,.65),0,.6)
cladding=material('Office cladding',(.32,.065,.042),0,.78)
timber=material('Pallet timber',(.49,.36,.21),0,.88)
roof=material('Roof paint',(.025,.038,.045),.2,.76)
rope=material('Fixed_Warp',(.52,.45,.31),0,.94)
glass=material('Fixed_ExteriorGlazing',(.045,.085,.11),.28,.19)
# Reflective closed windows: these buildings are scenery, with no interior.
glass.node_tree.nodes.get('Principled BSDF').inputs['Transmission Weight'].default_value=0

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(name,p,s,mat,bevel=.005,bevel_segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
    if bevel:
        m=o.modifiers.new('Real edge radius','BEVEL');m.width=bevel;m.segments=bevel_segments
        bpy.ops.object.modifier_apply(modifier=m.name)
    return o
def rod(name,a,b,r,mat,vertices=16,r2=None):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)*.5)
    o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(mat)
    for poly in o.data.polygons:poly.use_smooth=len(poly.vertices)==4
    return o
def torus(name,p,major,minor,mat,rotation=(math.pi/2,0,0),segments=40,minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(major_segments=segments,minor_segments=minor_segments,location=p,rotation=rotation,major_radius=major,minor_radius=minor)
    o=bpy.context.object;o.name=name;o.data.materials.append(mat)
    for poly in o.data.polygons:poly.use_smooth=True
    return o
def mesh(name,verts,faces,mat,smooth=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);data.materials.append(mat)
    for p in data.polygons:p.use_smooth=smooth
    return o
def empty(name,p=(0,0,0)):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=p;return o
def parent(o,node):
    world=o.matrix_world.copy();o.parent=node;o.matrix_world=world
def bolt(p,axis=(0,0,1),r=.018):
    p=Vector(p);axis=Vector(axis)
    rod('Zinc washer',p,p+axis*.005,r*1.5,steel,16)
    rod('Hex anchor',p+axis*.005,p+axis*.018,r,steel,6)
def label(text,p,size,mat):
    bpy.ops.object.text_add(location=p,rotation=(math.pi/2,0,0));o=bpy.context.object
    o.name='Permanent safety marking';o.data.body=text;o.data.size=size;o.data.align_x='CENTER';o.data.align_y='CENTER';o.data.extrude=.0005;o.data.materials.append(mat)
    bpy.ops.object.convert(target='MESH');return bpy.context.object
def socket(name,p):return empty(name,p)
def godot(p):return [round(p[0],4),round(p[2],4),round(-p[1],4)]
def collider(p,s,**extra):return {'position_m':godot(p),'size_m':[s[0],s[2],s[1]],**extra}
def export(aid,name,fp,h,category,kind='surface',snap=.5,colliders=None,notes='',**extra):
    if ONLY and aid!=ONLY:
        if aid in PREVIOUS: ASSETS.append(PREVIOUS[aid])
        return
    bpy.context.view_layer.update()
    sockets={o.name:godot(o.location) for o in bpy.context.scene.objects if o.type=='EMPTY' and not o.name.endswith('Pivot')}
    # Preserve the door hinge; static details share one mesh with material surfaces.
    groups={}
    for o in list(bpy.context.scene.objects):
        if o.type=='MESH':groups.setdefault(o.parent.name if o.parent else '',[]).append(o)
    for parent_name,group in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:o.select_set(True)
        bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join();o=bpy.context.object
        o.name='DoorLeaf' if parent_name=='DoorPivot' else 'Structure'
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.cube_project(cube_size=1.0);bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()
    pts=[o.matrix_world@Vector(v) for o in bpy.context.scene.objects if o.type=='MESH' for v in o.bound_box]
    lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(aid+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_cameras=False,export_lights=False,export_extras=True)
    ASSETS.append({'id':aid,'name':name,'model_path':'res://resources/models/parts/custom_harbour/'+aid+'.glb','source_path':'res://resources/models/_source/custom_harbour/'+aid+'.blend','footprint_m':fp,'height_m':h,'category':category,'snap_m':snap,'placement_kind':kind,'colliders':colliders or [],'sockets':sockets,'bounds_m':{'min':[round(lo[0],4),round(lo[2],4),round(-hi[1],4)],'max':[round(hi[0],4),round(hi[2],4),round(-lo[1],4)]},'triangles':tris,'notes':notes,**extra})

clear()
# Broad tractor tyre section with open sidewalls, shoulders and chevron tread.
profile=[(.36,-.16),(.39,-.21),(.50,-.235),(.61,-.20),(.675,-.145),(.69,-.07),(.69,.07),(.675,.145),(.61,.20),(.50,.235),(.39,.21),(.36,.16)]
verts=[];n=48
for i in range(n):
    a=2*math.pi*i/n
    for radius,y in profile:verts.append((math.sin(a)*radius,.34+y,-1.12+math.cos(a)*radius))
m=len(profile);faces=[]
for i in range(n):
    for j in range(m):faces.append((i*m+j,((i+1)%n)*m+j,((i+1)%n)*m+(j+1)%m,i*m+(j+1)%m))
mesh('Open tractor tyre carcass',verts,faces,rubber,True)
for i in range(18):
    a=2*math.pi*i/18
    for side in [-1,1]:
        p=(math.sin(a)*.69,.34+side*.085,-1.12+math.cos(a)*.69)
        o=box('Worn tractor chevron',p,(.12,.215,.045),rubber,.012,1);o.rotation_euler=(0,a,side*.50)
for side in [-1,1]:
    torus('Moulded sidewall bead',(0,.34+side*.205,-1.12),.58,.009,rubber,segments=24,minor_segments=4)
for x in [-.35,.35]:
    # The coping cap finishes at +.024m. Anchor hardware sits on top of it;
    # the old plate top was coplanar with both the quay and the concrete slab.
    box('Anchor plate',(x,-.13,.039),(.18,.27,.024),steel,.004)
    for y in [-.22,-.04]:bolt((x,y,.052))
    rod('Raised anchor eye',(x,-.13,.052),(x,-.13,.092),.022,steel,10)
    # The upper connector crosses over the lip instead of disappearing inside
    # the coping. Alternating links elongate in their plane, not along the normal.
    rod('Anchor bow',(x,-.13,.092),(x,.045,.072),.013,steel,10)
    for j in range(9):
        t=j/8;p=(x*(1-.15*t),.055+.285*t+.03*math.sin(math.pi*t),.062-.747*t)
        rotation=(math.pi/2,0,0) if j%2==0 else (math.pi/2,0,math.pi/2)
        o=torus('Galvanized chain link',p,.036,.009,steel,rotation,10,4);o.scale.y=1.55
socket('Edge',(0,0,0));socket('Contact',(0,.57,-1.12))
export('tractor_tire_fender','Hanging tractor tyre',[1.5,.62],1.88,'Quay fittings','edge',.5,[collider((0,.34,-1.12),(1.42,.47,1.42))],'Deck datum at anchor plates; hangs below the lip. No berth capacity implied.')

clear()
box('Foot plate',(0,0,.025),(.36,.36,.05),steel)
for x in [-.12,.12]:
    for y in [-.12,.12]:bolt((x,y,.05))
box('Safety post',(0,0,1.02),(.085,.085,1.95),steel)
box('Safety backboard',(0,-.06,1.31),(.91,.06,1.38),white,.025)
box('Red identification header',(0,-.101,1.88),(.88,.018,.23),orange,.012)
label('LIVBØYE',(0,-.114,1.88),.105,white)
torus('Orange lifebuoy',(0,-.19,1.32),.30,.072,orange)
for a in [0,math.pi/2,math.pi,math.pi*1.5]:
    o=box('Reflective lifebuoy band',(.30*math.sin(a),-.19,1.32+.30*math.cos(a)),(.10,.15,.13),white,.015);o.rotation_euler.y=a
for x in [-.34,.34]:rod('Grab rope',(x,-.18,1.07),(x,-.18,1.56),.013,rope,10)
rod('Grab rope',(-.27,-.18,1.64),(.27,-.18,1.64),.013,rope,10)
rod('Grab rope',(-.27,-.18,1.0),(.27,-.18,1.0),.013,rope,10)
box('Throw line canister',(0,-.15,.68),(.52,.22,.25),orange,.035)
label('REDNING',(0,-.266,.69),.07,white)
export('lifering_station','Lifebuoy and throw line',[1.0,.6],2.02,'Quay fittings',colliders=[collider((0,0,1),(.2,.2,2))],notes='Decorative safety fitting; rescue interaction is not implemented.')

clear()
box('Precast edge beam',(0,-.34,-.214),(4,.68,.452),concrete,.008)
box('Steel edge angle vertical',(0,.016,-.036),(4,.032,.12),steel,.003)
box('Steel edge angle top',(0,-.07,.019),(4,.14,.010),steel,.003)
for x in [-1.65,-.55,.55,1.65]:
    rod('Flush lifting recess',(x,-.42,.012),(x,-.42,.015),.032,dark)
    rod('Recess plug',(x,-.42,.015),(x,-.42,.017),.019,steel)
    bolt((x,.032,-.07),(0,1,0),.013)
for x in [-1,1]:box('Casting joint',(x,-.345,-.20),(.008,.675,.38),dark,0)
socket('Start',(-2,0,0));socket('End',(2,0,0));socket('Edge',(0,0,0))
export('quay_edge_4m','Flush quay edge · 4 m',[4,.7],.45,'Quay fittings','edge',4,[collider((0,-.34,-.22),(4,.68,.44))],'Flush coping with no raised trip kerb. Foundations remain separate.',footprint_polygon_m=[[-2,0],[2,0],[2,.68],[-2,.68]])

def pallet(z):
    for x in [-.50,0,.50]:
        for y in [-.31,0,.31]:box('Pallet block',(x,y,z+.065),(.14,.14,.10),timber,.004)
    for x in [-.50,0,.50]:box('Bottom runner',(x,0,z+.013),(.14,.8,.026),timber,.003)
    for y in [-.32,0,.32]:box('Cross bearer',(0,y,z+.117),(1.2,.14,.026),timber,.003)
    for i in range(7):
        x=-.52+i*.1733;box('Pallet deck board',(x,0,z+.145),(.145,.8,.03),timber,.004)
        for y in [-.31,.31]:rod('Nail head',(x,y,z+.160),(x,y,z+.161),.004,dark,6)
clear()
for z in [0,.164,.328]:pallet(z)
export('pallet_stack','Three empty timber pallets',[1.2,.8],.489,'Cargo details',colliders=[collider((0,0,.245),(1.2,.8,.49))],notes='Visual prop, not an inventory quantity or container slot.')

clear()
for y in [-1.55,0,1.55]:box('Dunnage bearer',(0,y,.09),(1.3,.14,.18),timber,.007)
rng=random.Random(772)
for layer in range(5):
    for lane in range(7):box('Sawn timber',((lane-3)*.17,0,.26+layer*.175),(.158,3.95+rng.uniform(-.045,.045),.158),timber,.007)
for y in [-1.40,1.40]:
    box('Steel band crown',(0,y,1.048),(1.23,.035,.012),dark,.002)
    for x in [-.61,.61]:box('Steel band side',(x,y,.61),(.012,.035,.88),dark,.002)
    box('Band seal',(.52,y,1.06),(.09,.065,.025),steel,.003)
export('timber_bundle','Strapped sawn timber',[1.3,4.0],1.08,'Cargo details',snap=1,colliders=[collider((0,0,.54),(1.3,4,1.08))],notes='Visual stock bundle; quantities and ownership come from port stock records.')

def wall_sections(opening=None):
    spans=[(-2,2,0,3)] if not opening else [(-2,opening[0],0,3),(opening[1],2,0,3),(opening[0],opening[1],0,opening[2]),(opening[0],opening[1],opening[3],3)]
    for a,b,c,d in spans:
        if b-a<.001 or d-c<.001:continue
        box('Insulated timber panel',((a+b)/2,0,(c+d)/2),(b-a,.18,d-c),white,0)
        count=max(1,round((b-a)/.16));w=(b-a)/count
        for i in range(count):box('Vertical painted board',(a+(i+.5)*w,.112,(c+d)/2),(w-.005,.044,d-c),cladding,.002)
        box('Base flashing',((a+b)/2,.138,c+.05),(b-a,.025,.1),roof,.002)
    box('Top beam',(0,0,2.94),(4,.23,.12),white,.002)
    socket('Start',(-2,0,0));socket('End',(2,0,0));socket('RoofDatum',(0,0,3))
    return [collider(((a+b)/2,0,(c+d)/2),(b-a,.28,d-c)) for a,b,c,d in spans if b-a>.001 and d-c>.001]
clear();cols=wall_sections()
export('workshop_wall_4m','Workshop wall · 4 m',[4,.28],3,'Workshop','building',4,cols,paint_regions=['Office cladding','Ivory trim'])

clear();cols=wall_sections((-1.18,1.18,.95,2.35))
for x in [-1.23,1.23]:box('Window surround',(x,.15,1.65),(.10,.10,1.50),white,.002)
for z in [.90,2.40]:box('Window surround',(0,.15,z),(2.56,.10,.10),white,.002)
# Cap the exposed board end rather than leaving it above the sill surface.
box('Window sill',(0,.21,.96),(2.65,.24,.075),white,.003)
for x in [-.60,.60]:box('Sealed glazing',(x,.025,1.65),(1.12,.018,1.29),glass,.001)
for x in [-1.16,0,1.16]:box('Window mullion',(x,.07,1.65),(.055,.11,1.4),white,.003)
box('Window crossbar',(0,.07,1.65),(2.36,.11,.045),white,.002)
cols.append(collider((0,0,1.65),(2.36,.12,1.4)))
export('workshop_window_4m','Workshop window · 4 m',[4,.38],3,'Workshop','building',4,cols,paint_regions=['Office cladding','Ivory trim'])

clear();cols=wall_sections((-.66,.66,0,2.30))
for x in [-.71,.71]:box('Door jamb',(x,.12,1.15),(.10,.13,2.30),white,.003)
box('Door head',(0,.12,2.35),(1.52,.13,.1),white,.003)
box('Flush threshold',(0,0,.012),(1.32,.28,.024),steel,.002)
new=[]
new.append(box('Insulated door',(0,0,1.13),(1.25,.075,2.24),roof,.005))
new.append(box('Door glazing gasket',(0,.043,1.69),(.89,.02,.67),rubber,.005))
new.append(box('Door glazing',(0,.055,1.69),(.83,.012,.61),glass,.002))
new.append(box('Kick plate',(0,.043,.21),(1.14,.008,.32),steel,.001))
for side in [-1,1]:
    new.append(box('Lever escutcheon',(.48,side*.051,1.05),(.045,.025,.18),steel,.005))
    new.append(rod('Door lever',(.48,side*.083,1.07),(.34,side*.083,1.07),.012,steel))
for z in [.32,1.12,1.98]:new.append(rod('Door hinge',(-.63,0,z-.065),(-.63,0,z+.065),.021,steel))
cols.append(collider((0,0,1.13),(1.32,.28,2.26)))
export('workshop_door_4m','Decorative closed door · 4 m',[4,.28],3,'Workshop','building',4,cols,
       notes='Closed exterior decoration with solid collision. No doorway interaction or interior.',
       paint_regions=['Office cladding','Ivory trim'])

clear();cols=wall_sections((-1.60,1.60,0,2.65))
for x in [-1.65,1.65]:box('Loading bay jamb',(x,.15,1.325),(.10,.14,2.65),white,.003)
box('Roller shutter cover',(0,.02,2.86),(3.42,.42,.28),roof,.018)
box('Closed roller shutter',(0,.03,1.325),(3.20,.09,2.65),roof,.008)
for i in range(25):box('Shutter horizontal rib',(0,.085,.07+i*.105),(3.20,.035,.027),steel,.002)
box('Shutter bottom rail',(0,.10,.035),(3.20,.10,.07),steel,.004)
for x in [-.95,.95]:rod('Recessed shutter handle',(x-.13,.105,.76),(x+.13,.105,.76),.018,dark,12)
cols.append(collider((0,0,1.325),(3.20,.28,2.65)))
for x in [-1.85,1.85]:
    box('Impact guard',(x,.25,.48),(.11,.16,.96),yellow,.01)
    for z in [.15,.65]:box('Guard stripe',(x,.338,z),(.11,.009,.13),dark,.001)
export('workshop_open_bay_4m','Closed workshop shutter · 4 m',[4,.52],3,'Workshop','building',4,cols,notes='Decorative closed 3.2m roller shutter. Solid collision; no interior. Asset ID retained for existing port saves.',paint_regions=['Office cladding','Ivory trim'])

clear()
box('Roof insulated cassette',(0,0,3.06),(4,4,.12),white,0)
box('Standing seam roof sheet',(0,0,3.13),(4,4,.025),roof,0)
for x in [-1.75,-1.25,-.75,-.25,.25,.75,1.25,1.75]:box('Folded roof seam',(x,0,3.159),(.024,4,.035),roof,.003)
for name,p in [('WallTop',(0,0,3)),('North',(0,2,3)),('South',(0,-2,3)),('East',(2,0,3)),('West',(-2,0,3))]:socket(name,p)
export('workshop_roof_4m','Workshop roof · 4 × 4 m',[4,4],3.18,'Workshop','building',4,[collider((0,0,3.08),(4,4,.16))],'Underside fixed at deck +3m. Repeat across any rectangular building.',layer='roof')

clear()
box('Roof edge fascia',(0,.03,3.06),(4,.08,.24),white,.002)
box('Folded verge top',(0,-.035,3.195),(4,.23,.03),roof,.003)
box('Gutter bottom',(0,.18,2.98),(4,.18,.025),steel,.002)
for y in [.09,.27]:box('Gutter upstand',(0,y,3.025),(4,.02,.09),steel,.002)
for x in [-1.75,-.75,.25,1.25]:box('Gutter bracket',(x,.18,2.95),(.025,.20,.04),steel,.003)
export('workshop_roof_edge_4m','Workshop gutter edge · 4 m',[4,.35],3.22,'Workshop','building',4,[],layer='roof_edge')

clear()
box('Corner cover X',(0,.14,1.5),(.28,.035,3),white,.001)
box('Corner cover Y',(.14,0,1.5),(.035,.28,3),white,.001)
export('workshop_corner_trim','Workshop corner trim',[.32,.32],3,'Workshop','building',.5,[],layer='trim')

def polygon_prism(name, polygon, top, bottom, mat):
    # Stored polygon is Godot-local X/Z, counter-clockwise in the plan.
    # Blender's +Y exports to Godot -Z, so the upper face reverses that order.
    count=len(polygon)
    verts=[(x,-z,y) for y in [bottom,top] for x,z in polygon]
    faces=[tuple(range(count)),tuple(range(2*count-1,count-1,-1))]
    for i in range(count):
        j=(i+1)%count
        faces.append((i,count+i,count+j,j))
    return mesh(name,verts,faces,mat)

def foundation_shape(aid, name, polygon, edges, is_quay):
    clear()
    polygon_prism('Authored deck cap',polygon,-.004 if is_quay else 0,-.24,concrete)
    datum=empty('SupportDatum',(0,0,-.24))
    support=polygon_prism('Extendable foundation skirt',polygon,0,-.76,concrete)
    support.parent=datum
    if is_quay:
        for edge_index in edges:
            a=Vector(polygon[edge_index]);b=Vector(polygon[(edge_index+1)%len(polygon)])
            delta=b-a;length=delta.length;inside=Vector((-delta.y,delta.x))/length
            midpoint=(a+b)*.5+inside*.04
            angle=math.atan2(-delta.y,delta.x)
            cap=box('Flush edge angle',(midpoint.x,-midpoint.y,-.009),(length-.002,.078,.018),steel,.002)
            cap.rotation_euler.z=angle
            midpoint=(a+b)*.5+inside*.011
            face=box('Vertical edge angle',(midpoint.x,-midpoint.y,-.065),(length-.002,.024,.13),steel,.002)
            face.rotation_euler.z=angle
            # Washers/nuts face seawards, below the walking surface.
            for i in range(max(1,int(length/1.4))):
                t=(i+.5)/max(1,int(length/1.4));p=a.lerp(b,t)-inside*.004
                bolt((p.x,-p.y,-.09),(-inside.x,inside.y,0),.012)
    for i,(x,z) in enumerate(polygon):socket('PlanCorner'+str(i),(x,-z,0))
    for i in edges:
        a=Vector(polygon[i]);b=Vector(polygon[(i+1)%len(polygon)])
        mid=(a+b)*.5;socket('WaterEdge'+str(i),(mid.x,-mid.y,0))
    export(aid,name,[4,4],1,'Foundations','foundation',4,[],
           'Deck datum Y0. Exact polygon top/collision; SupportDatum extends below the cap to the sampled seabed. No invisible square in the cut corner.',
           footprint_polygon_m=polygon,water_edge_indices=edges,
           foundation={'support_node':'SupportDatum','cap_thickness_m':.24,'authored_support_depth_m':.76,'default_depth_m':1.0},
           layer='foundation',surface='quay' if is_quay else 'foundation')

triangle=[[-2,-2],[2,2],[-2,2]]
chamfer=[[-2,-2],[1,-2],[2,-1],[2,2],[-2,2]]
foundation_shape('foundation_triangle_4m','Triangle foundation · 4 m',triangle,[0],False)
foundation_shape('quay_triangle_4m','Diagonal quay · 4 m',triangle,[0],True)
foundation_shape('foundation_chamfer_4m','Chamfered foundation · 4 m',chamfer,[1],False)
foundation_shape('quay_chamfer_4m','Chamfered quay · 4 m',chamfer,[0,1,2],True)

# The waterfront kit is authored in the same Blender session, uses the same
# materials/export contract, and remains individually placeable in port JSON.
exec(compile((HERE/'waterfront_parts.py').read_text(encoding='utf-8'), str(HERE/'waterfront_parts.py'), 'exec'))

# Direct catalogue refs to approved existing Blender assets. No duplicated mesh.
existing=[
 ('quay_bollard','Tee mooring bollard','port_kit/quay_tee_bollard.glb',[1.1,.9],1.1,'surface',.5,[collider((0,0,.43),(1.05,.78,.86))]),
 ('quay_ladder','Quay rescue ladder','harbour_kit/quay_ladder.glb',[.8,.65],3.5,'edge',1,[]),
 ('quay_light','Harbour light','harbour_kit/quay_light.glb',[.5,.5],7.8,'surface',1,[collider((0,0,3.7),(.22,.22,7.4))]),
 ('arch_fender','Rubber arch fender','harbour_kit/arch_fender.glb',[.8,.5],1.65,'edge',1,[collider((0,.23,-.90),(.8,.46,1.5))]),
 ('drain_2m','Flush drainage grate','harbour_kit/drain_2m.glb',[2,.32],.11,'surface',1,[])]
for aid,name,path,fp,h,kind,snap,cols in existing:
    ASSETS.append({'id':aid,'name':name,'model_path':'res://resources/models/parts/'+path,'source_path':'res://resources/models/_source/'+path.replace('.glb','.blend'),'footprint_m':fp,'height_m':h,'category':'Quay fittings','snap_m':snap,'placement_kind':kind,'colliders':cols,'sockets':{},'existing_asset':True})
MANIFEST.write_text(json.dumps({'version':1,'units':'metres','axis':'Godot +Y up; local -Z is exterior / water','datum':'Finished deck y=0; roofs at y=3m; edge fittings hang below y=0','assets':ASSETS},indent=2)+'\n',encoding='utf-8')
print('CUSTOM_HARBOUR_ASSETS',len(ASSETS),'TRIANGLES',sum(a.get('triangles',0) for a in ASSETS))
