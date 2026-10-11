"""Original 36.5 m passenger catamaran construction kit, Blender metres.
Reference/provenance: docs/passenger-ferry-research-2026-10-09.txt.
Blender +Y bow, +Z up. Parts remain separate editable placements, never a
complete-vessel export. Shared finish maps are assigned by the game library.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[1]
HULL = ROOT/'vessels/catamaran_36x11'
PARTS = ROOT/'parts/passenger_ferry'
for p in [HULL, PARTS]: p.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0

def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def mat(name, colour, metal=0, rough=.45, alpha=1):
    m = bpy.data.materials.new(name); m.diffuse_color=(*colour,alpha); m.use_nodes=True
    p=m.node_tree.nodes['Principled BSDF']; p.inputs['Base Color'].default_value=(*colour,alpha)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    p.inputs['Alpha'].default_value=alpha
    if alpha<1: m.surface_render_method='DITHERED'
    return m

white=mat('Warm white painted steel',(.80,.81,.75))
upper=mat('Paint_HullUpper',(.81,.82,.77))
lower=mat('Paint_HullLower',(.065,.085,.09),rough=.7)
deck=mat('Paint_Deck',(.27,.30,.29),rough=.8)
red=mat('Paint_Fascia',(.55,.055,.035))
steel=mat('Fixed_Stainless',(.51,.56,.57),.8,.26)
dark=mat('Fixed_BlackHousing',(.027,.040,.045))
rubber=mat('Fixed_Rubber',(.018,.023,.024),rough=.82)
glass=mat('Optical ferry glass',(.075,.14,.16),.12,.12,.56)
cloth=mat('Paint_Upholstery',(.10,.22,.28),rough=.87)
light=mat('Ferry ceiling diffuser',(.85,.86,.76),rough=.6)
light.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value=(.8,.78,.60,1)
light.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=.7

def box(name, p, size, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(material)
    if bevel:
        b=o.modifiers.new('Formed edge','BEVEL'); b.width=bevel; b.segments=3
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o

def mesh(name, verts, faces, material, smooth=False):
    d=bpy.data.meshes.new(name); d.from_pydata(verts,[],faces); d.update()
    bm=bmesh.new(); bm.from_mesh(d); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(d); bm.free()
    o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); d.materials.append(material)
    for f in d.polygons: f.use_smooth=smooth
    return o

def beam(name, a, b, r, material, sides=12):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object; o.name=name; o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    o.data.materials.append(material)
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    return o

def socket(name,p):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=p
    return o

def export(name, folder=PARTS, collision_groups=False):
    # Merge by finish within an asset, retaining sockets and each convex hull
    # group. Repeated seat/roof modules share their source mesh on import.
    groups={}
    for ob in list(bpy.context.scene.objects):
        if ob.type!='MESH': continue
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
        key=(ob.name.split('__')[0] if collision_groups else name,ob.data.materials[0].name)
        groups.setdefault(key,[]).append(ob)
    for (group,finish),objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects: ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]; bpy.ops.object.join()
        ob=bpy.context.object; ob.name=group+'__'+finish
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(folder/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)

clear()
# Slender, rounded demihulls: fine bow entry, modest stern run, open tunnel.
stations=[(-18.25,.72),(-16,1.0),(-11,1.15),(0,1.20),(9,1.16),(13,.84),(16.5,.35),(18.25,.025)]
def width(y):
    for (a,w),(b,v) in zip(stations,stations[1:]):
        if y<=b: return w+(v-w)*max(0,(y-a)/(b-a))
    return .025
ys=sorted(set([round(-18.25+i*.25,3) for i in range(147)]+[v[0] for v in stations]))
cross=[(-1,1),(-1,.78),(-.96,.52),(-.84,.27),(-.55,.07),(0,0),(.55,.07),(.84,.27),(.96,.52),(1,.78),(1,1)]
for sign,label in [(-1,'Port'),(1,'Starboard')]:
    vs=[]
    for y in ys:
        rise=.06+.30*max(0,(y-11)/7.25)**2+.22*max(0,(-y-13)/5.25)**2
        vs.extend([(sign*4.3+x*width(y),y,rise+(3.2-rise)*h) for x,h in cross])
    k=len(cross); fs=[]
    for i in range(len(ys)-1):
        for j in range(k-1):
            a=i*k+j; fs.append((a,a+1,a+k+1,a+k))
    fs.extend([tuple(range(k-1,-1,-1)),tuple((len(ys)-1)*k+j for j in range(k))])
    hull=mesh(label+'__hull',vs,fs,lower,True)
    # Narrow white upper topsides are a separate surface with a deliberate
    # waterline break, not a cargo hull rusty plate finish.
    bm=bmesh.new(); bm.from_mesh(hull.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,2.25),plane_no=(0,0,1),dist=.000001)
    bm.to_mesh(hull.data); bm.free(); hull.data.materials.append(upper)
    for p in hull.data.polygons:
        p.material_index=int(sum(hull.data.vertices[i].co.z for i in p.vertices)/len(p.vertices)>2.25)
    box(label+'__stern cap',(sign*4.3,-18.20,2.5),(1.40,.1,1.2),upper)
# Elevated connecting deck does not descend into the water tunnel.
outline=[(-5.5,-18.25),(5.5,-18.25),(5.5,11.5),(4.5,15.5),(2,18.0),(-2,18.0),(-4.5,15.5),(-5.5,11.5)]
vs=[(x,y,z) for z in [2.88,3.2] for x,y in outline]; n=len(outline)
fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh('BridgeDeck__deck',vs,fs,deck)
socket('BowRampDatum',(0,17.5,3.2));socket('PortHullCentre',(-4.3,0,0));socket('StarboardHullCentre',(4.3,0,0))
export('catamaran_36x11',HULL,True)
(HULL/'deck_outline.json').write_text(json.dumps(dict(length_m=36.5,beam_m=11,deck_y=3.2,outline_xz=[[x,-y] for x,y in outline],openings_xz=[]),indent=2))

assets=[]
def part(aid, size, style='ferry', **kw):
    export(aid)
    assets.append(dict(id=aid,kind='furniture',style=style,model=f'res://resources/models/parts/passenger_ferry/{aid}.glb',material_context='composite_ferry',start_xz=[0,0],end_xz=size[:2],height_start_m=size[2],height_end_m=size[2],paintable=True,**kw))

# A repeatable 2.25 m saloon bay. Outer wall leans in, glazing is inset into
# gaskets with real interior sills. Origin is at the side wall's deck seam.
clear()
box('Sill',(0,0,.43),(.14,2.25,.86),white)
box('Window gasket',(-.075,0,1.58),(.08,2.21,1.48),rubber)
box('Glass',(-.12,0,1.58),(.018,2.08,1.33),glass)
# Remove solid gasket centre by using individual rails instead of a black pane.
g=bpy.data.objects.get('Window gasket'); bpy.data.objects.remove(g,do_unlink=True)
for y in [-1.085,1.085]:box('Window side gasket',(-.07,y,1.58),(.10,.055,1.47),rubber)
for z in [.875,2.285]:box('Window gasket horizontal',(-.07,0,z),(.10,2.18,.055),rubber)
for y in [-1.095,1.095]:box('Aluminium mullion',(0,y,1.55),(.15,.06,1.54),dark)
box('Header',(0,0,2.38),(.16,2.25,.18),dark)
box('Interior sill',(-.16,0,.88),(.34,2.25,.065),white,.02)
box('Lower belt',(.083,0,.10),(.03,2.25,.18),dark)
socket('EndA',(0,-1.125,0));socket('EndB',(0,1.125,0))
part('ferry_saloon_bay_225cm',[.34,2.25,2.47])

clear()
# Raked glazed saloon front, with a real one-metre central door opening.
for sign in [-1,1]:
    box('Front apron',(sign*2.65,0,.42),(4.2,.14,.84),white)
    for j in range(3):
        x=sign*(1.25+j*1.2)
        pane=box('Raked front glazing',(x,-.18,1.57),(1.14,.018,1.44),glass)
        pane.rotation_euler.x=math.radians(15)
        for side in [-1,1]:beam('Raked glazing jamb',(x+side*.59,0,.86),(x+side*.59,-.38,2.30),.032,dark)
    for z,y in [(.86,0),(2.3,-.38)]:beam('Front window belt',(sign*.55,y,z),(sign*4.7,y,z),.05,dark)
    mesh('Outer cheek',[(sign*4.7,0,0),(sign*4.7,0,2.47),(sign*4.7,-.43,2.47),(sign*4.7,-.38,2.30),(sign*4.7,0,.86)],[(0,1,2,3,4)],white)
box('Saloon brow',(0,-.30,2.385),(9.55,.43,.17),white)
part('ferry_saloon_front',[9.55,.45,2.47])

clear();box('End header',(0,0,.135),(9.42,.14,.27),white)
part('ferry_end_header',[9.42,.14,.27])

clear()
box('Insulated roof',(0,0,.11),(9.65,2.25,.22),white)
box('Headliner',(0,0,-.022),(9.28,2.25,.025),white)
for x in [-3.85,3.85]:box('Ceiling lighting rail',(x,0,-.045),(.06,2.13,.035),light)
for x in [-2.5,2.5]:box('Ventilation channel',(x,0,-.055),(.22,2.25,.055),white)
part('ferry_saloon_roof_225cm',[9.65,2.25,.22])

clear()
for sign in [-1,1]:
    box('Stairwell roof cheek',(sign*2.805,0,.11),(4.04,2.25,.22),white)
    box('Stairwell ceiling light',(sign*3.85,0,-.045),(.06,2.13,.035),light)
part('ferry_saloon_roof_open_225cm',[9.65,2.25,.22])

clear()
# Ten seats, arranged 2-3-3-2 with three clear longitudinal aisles. The
# sockets define fitted seats; the eventual passenger service can count them.
xs=[-4.10,-3.60,-2.40,-1.90,-1.40,1.40,1.90,2.40,3.60,4.10]
for i,x in enumerate(xs):
    box('Seat foot',(x,0,.045),(.28,.50,.09),steel,.025)
    box('Seat pedestal',(x,0,.28),(.07,.10,.45),dark,.015)
    box('Seat shell',(x,.025,.53),(.47,.50,.13),white,.055)
    box('Seat cushion',(x,.03,.60),(.435,.43,.085),cloth,.035)
    back=box('Contoured back',(x,-.205,.94),(.47,.11,.72),white,.055);back.rotation_euler.x=math.radians(-9)
    back=box('Back cushion',(x,-.137,.96),(.425,.075,.57),cloth,.04);back.rotation_euler.x=math.radians(-9)
    box('Headrest',(x,-.195,1.27),(.34,.13,.16),cloth,.048)
    for s in [-1,1]:
        box('Arm support',(x+s*.224,0,.70),(.025,.04,.27),steel,.008)
        box('Armrest',(x+s*.224,.025,.83),(.045,.34,.05),rubber,.02)
    socket('PassengerSeat%02d'%i,(x,.025,.63))
part('ferry_seating_row_10',[8.7,.65,1.35])

clear()
# Faceted bridge front with transparent panes; two forward raked corners.
line=[(-3.65,0),(-2.7,1.2),(2.7,1.2),(3.65,0)]
for (x1,y1),(x2,y2) in zip(line,line[1:]):
    length=math.hypot(x2-x1,y2-y1); bays=max(1,round(length/.95))
    for j in range(bays):
        a=Vector((x1+(x2-x1)*j/bays,y1+(y2-y1)*j/bays,.90))
        b=Vector((x1+(x2-x1)*(j+1)/bays,y1+(y2-y1)*(j+1)/bays,.90))
        mid=(a+b)/2
        o=box('Bridge apron',(mid.x,mid.y,.42),((b-a).length,.12,.84),red)
        o.rotation_euler.z=math.atan2(b.y-a.y,b.x-a.x)
        c=a+Vector((0,-.18,1.32));d=b+Vector((0,-.18,1.32))
        mesh('Bridge glazing',[a,b,d,c],[(0,1,2,3)],glass)
        beam('Bridge mullion',a,c,.042,dark)
        beam('Windscreen sill',a,b,.037,dark)
        beam('Windscreen header',c,d,.045,dark)
        # Independent visible wiper arm, clear of the glass.
        beam('Wiper',(mid.x,mid.y+.03,1.03),(mid.x+.15,mid.y-.09,1.78),.012,steel,8)
part('ferry_bridge_front',[7.3,1.2,2.22])

clear()
box('Bridge side apron',(0,0,.42),(.14,2,.84),red)
box('Bridge side pane',(0,0,1.56),(.018,1.90,1.31),glass)
for y in [-.97,.97]:box('Bridge side mullion',(0,y,1.56),(.12,.06,1.38),dark)
for z in [.88,2.23]:box('Bridge window belt',(0,0,z),(.12,2,.10),dark)
part('ferry_bridge_side_2m',[.14,2,2.28])

clear()
box('Bridge roof',(0,0,.1),(7.65,5.55,.20),white,.12)
box('Bridge eyebrow',(0,2.77,.06),(7.4,.35,.10),dark,.025)
part('ferry_bridge_roof',[7.65,5.9,.2])

clear()
for x in [-.92,.92]:
    box('Stair trunk side',(x,0,1.2),(.12,3.12,2.40),white)
box('Stair trunk rear',(0,-1.5,1.2),(1.9,.12,2.4),white)
box('Stair trunk roof',(0,0,2.4),(2.04,3.3,.16),white,.04)
part('ferry_bridge_stair_trunk',[2.04,3.3,2.48])

clear()
for x in [-.62,.62]:
    beam('Stair stringer',(x,0,.06),(x,3.6,2.56),.065,white)
    for y in [0,1.8,3.6]:beam('Stair guard upright',(x,y,.18+y*.7),(x,y,1.18+y*.7),.024,steel)
    for h in [.65,1.15]:beam('Sloping handrail',(x,0,h),(x,3.6,2.52+h),.027,steel)
for i in range(15):
    box('Stair tread',(0,(i+.5)*.24,(i+1)*.18-.025),(1.2,.255,.05),deck)
    box('Stair riser',(0,i*.24,(i+.5)*.18),(1.2,.035,.18),white)
socket('LowerFloor',(0,0,0));socket('UpperFloor',(0,3.6,2.7))
part('ferry_bridge_stair_270cm',[1.3,3.6,3.75],style='stair')

clear()
for x in [-.55,.55]:
    for y in [-.8,.8]:beam('Rack post',(x,y,0),(x,y,1.65),.025,steel)
for z in [.15,.85,1.6]:
    box('Luggage shelf',(0,0,z),(1.15,1.7,.04),dark,.015)
    for x in [-.57,.57]:beam('Shelf lip',(x,-.85,z+.055),(x,.85,z+.055),.02,steel)
part('ferry_luggage_rack',[1.2,1.75,1.68])

clear()
for y in [-1,1]:box('Ramp edge',(0,y,.015),(2.0,.08,.08),steel)
box('Ramp deck',(0,0,-.055),(2.0,2.05,.11),deck)
for x in [-.97,.97]:
    box('Toe board',(x,0,.09),(.05,2.05,.18),white)
    for y in [-1,0,1]:beam('Ramp upright',(x,y,.05),(x,y,1.10),.023,steel)
    for z in [.55,1.10]:beam('Ramp guard',(x,-1,z),(x,1,z),.025,steel)
socket('RampHinge',(0,-1,0));socket('RampTip',(0,1,0))
part('ferry_bow_ramp_2m',[2.05,2.05,1.12])

clear()
# Separate rubber belt, authored curved bow segment belongs in a later kit
# variant; this metre-long rail is an unscaled reusable straight section.
box('D section rubber',(0,0,0),(.18,2.25,.22),rubber,.085)
part('ferry_rubbing_strake_225cm',[.18,2.25,.22])

clear()
box('Mast shoe',(0,0,.055),(.8,.7,.11),white,.04)
for x in [-.30,.30]:beam('Mast leg',(x,0,.10),(x*.25,0,2.25),.045,white)
beam('Scanner support',(-.8,0,1.45),(.8,0,1.45),.04,white)
box('Radar pedestal',(0,0,1.57),(.20,.18,.22),white,.04)
box('Radar scanner',(0,0,1.76),(1.8,.14,.16),white,.05)
for x,y,h in [(-.62,0,2.6),(.60,0,2.9),(.08,0,3.1)]:beam('VHF aerial',(x,y,1.48),(x,y,h),.009,steel,8)
beam('Navigation bar',(-.48,0,2.22),(.48,0,2.22),.022,white)
part('ferry_radar_mast',[1.9,.7,3.1])

for aid,length in [('ferry_guard_1x3',math.sqrt(10)),('ferry_guard_3x2',math.sqrt(13))]:
    clear()
    for height in [.48,1.0]:beam('Guard tube',(0,0,height),(0,length,height),.025,steel)
    socket('SocketStart',(0,0,0));socket('SocketEnd',(0,length,0))
    # Shared endpoint posts come from the existing rail-joint assembler.
    part(aid,[0,-length,1.0],style='rail')

(PARTS/'manifest.json').write_text(json.dumps(dict(units='metres',assets=assets),indent=2)+'\n')
# Rail recipes are assembled from actual existing metre-length sections. Bow
# opening remains two metres wide for the passenger ramp.
rails=[]
def rail(a,b):
    dx=b[0]-a[0];dz=b[1]-a[1];n=round(math.hypot(dx,dz)*2)
    for i in range(n):rails.append(dict(asset_id='rail_straight_50cm',position=[a[0]+dx*i/n,3.2,a[1]+dz*i/n],yaw_degrees=math.degrees(math.atan2(-dx,-dz))))
for x in [-5.25,5.25]:rail((x,17.5),(x,12.5))
rail((-5.25,17.5),(5.25,17.5))
for name in ['rail_flat','halfwall_flat']:
    (HULL/(name+'_assembly.json')).write_text(json.dumps({'placements':rails},indent=2)+'\n')
# Original two-shaft package, not a claim about Fjordbris's exact shaft layout.
mounts=dict(version=1,hull='catamaran_36x11',units='metres',visual_max_rpm=420,max_rudder_degrees=25,
            assets={'propeller':'ferry_propeller_1450'},
            shafts=[dict(support=[s*4.3,1.05,18.0],propeller=[s*4.3,1.05,18.50],rudder=[s*4.3,1.65,19.05]) for s in [-1,1]])
(ROOT/'parts/stern_gear/mounts_cat36.json').write_text(json.dumps(mounts,indent=2)+'\n')
clear()
with bpy.data.libraries.load(str(SRC.parent/'stern_gear/propeller_1040.blend')) as (source,dest):
    dest.objects=source.objects
for ob in dest.objects:
    if ob is None:continue
    bpy.context.collection.objects.link(ob)
    if ob.type=='MESH':
        for v in ob.data.vertices:v.co*=1.45/1.04
        ob.location*=1.45/1.04
export('ferry_propeller_1450',ROOT/'parts/stern_gear')
print('COASTAL EXPRESS HULL AND MODULAR KIT EXPORTED',len(assets))
