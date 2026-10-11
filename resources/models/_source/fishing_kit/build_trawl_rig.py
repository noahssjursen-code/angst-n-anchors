"""Reusable trawl deck/deployed components. Original game geometry, metres.
Blender +Y bow/+Z up. Net mouth at origin, codend along -Y. No baked illumination.
"""
import bmesh, sys
from pathlib import Path
exec((Path(__file__).resolve().parent/'build_fishing_kit.py').read_text(encoding='utf-8').split('\nclear()\npaint=')[0])
OUT=SRC.parents[1]/'parts'/'trawl_rig';OUT.mkdir(parents=True,exist_ok=True)

def beam(n,a,b,w,d,m):
    a,b=Vector(a),Vector(b);o=box(n,(a+b)/2,(w,d,(b-a).length),m)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def mesh(n,v,f,m):
    me=bpy.data.meshes.new(n);me.from_pydata(v,[],f);me.update()
    ob=bpy.data.objects.new(n,me);bpy.context.collection.objects.link(ob);me.materials.append(m)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    return ob
def line(n,points,r,m):
    c=bpy.data.curves.new(n,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=1;c.resolution_u=1
    s=c.splines.new('POLY');s.points.add(len(points)-1)
    for p,co in zip(s.points,points):p.co=(*co,1)
    o=bpy.data.objects.new(n,c);bpy.context.collection.objects.link(o);o.data.materials.append(m)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
    return o
def ball(n,p,s,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=p)
    o=bpy.context.object;o.name=n;o.scale=s;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    for f in o.data.polygons:f.use_smooth=True
    return o
def finish(n):
    if '--net-only' in sys.argv and not n.startswith('trawl_net_'):return
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH':
            for f in ob.data.polygons:
                if len(f.vertices)>4:f.use_smooth=False
    # Static geometry inside one reusable asset needs few draw calls, not one
    # mesh node per strand/chain link. Keep empties and animation pivots separate.
    groups={}
    for ob in list(bpy.context.scene.objects):
        if ob.type!='MESH':continue
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        key=ob.data.materials[0].name;groups.setdefault(key,[]).append(ob)
    for key,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        bpy.context.object.name=n+' '+key
    save(n)
clear()
paint=mat('Warm white painted steel',(.23,.37,.39))
doorpaint=mat('Warm white painted steel',(.72,.30,.07))
steel=mat('Fixed_Galvanized',(.40,.46,.48),.78)
dark=mat('Fixed_Bearing',(.035,.045,.044),.25)
net=mat('Fixed_NetTwine',(.10,.19,.15),0)
rope=mat('Fixed_Boltrope',(.27,.30,.19),0)
for m in [net,rope]:m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9
orange=mat('Fixed_FloatOrange',(.78,.24,.045),0)

# Legs, fore/aft braces and boxed crosshead, clear of the working deck centre.
for side in [-1,1]:
    x=side*1.85
    box('Gantry foot',(x,0,.045),(.46,1.00,.09),paint)
    beam('Raked gantry leg',(x,0,.09),(side*1.60,0,2.80),.20,.24,paint)
    for y in [-.40,.40]:
        beam('Fore aft knee',(x,y,.1),(side*1.72,0,1.6),.10,.12,paint)
        for xx in [-.15,.15]:cyl('Foot holding bolt',(x+xx,y,.09),(x+xx,y,.125),.019,steel)
    beam('Crosshead knee',(side*1.72,0,2.2),(side*1.16,0,2.8),.14,.18,paint)
box('Boxed crosshead',(0,0,2.83),(3.60,.32,.30),paint)
for x in [-.95,.95]:
    box('Pulley hanger lug',(x,0,2.61),(.12,.22,.26),paint)
    cyl('Hanger pin',(x-.10,0,2.57),(x+.10,0,2.57),.036,steel)
socket('PortBlockMount',(-.95,0,2.55));socket('StarboardBlockMount',(.95,0,2.55))
socket('PortDoorStow',(-1.62,-.12,.08));socket('StarboardDoorStow',(1.62,-.12,.08))
for side in [-1,1]:
    box('Door shoe stow cradle',(side*1.62,-.12,.035),(.34,1.36,.07),paint)
    for y in [-.58,.34]:beam('Cradle tie',(side*1.62,y,.04),(side*1.85,0,.07),.07,.08,paint)
socket('NetStow',(0,-.95,.34))
finish('trawl_gantry_4m')

clear()
for x in [-.075,.075]:
    # Separate cheek plates leave the sheave visible between them.
    outline=[(x,-.12,-.50),(x,.12,-.50),(x,.20,-.36),(x,.13,-.08),(x,-.13,-.08),(x,-.20,-.36)]
    ob=mesh('Block cheek',outline,[tuple(range(6))],paint)
    mod=ob.modifiers.new('Cheek plate thickness','SOLIDIFY');mod.thickness=.025
    mod=ob.modifiers.new('Rounded plate edges','BEVEL');mod.width=.016;mod.segments=3
cyl('Block suspension',(0,0,.02),(0,0,-.13),.053,steel)
cyl('Sheave pin',(-.11,0,-.33),(.11,0,-.33),.036,steel)
socket('SheavePivot',(0,0,-.33))
for i in range(9):
    a=math.pi*i/8;socket('WarpLead'+str(i),(0,.191*math.cos(a),-.33+.191*math.sin(a)))
finish('trawl_block')

clear()
cyl('Grooved pulley core',(-.047,0,0),(.047,0,0),.172,dark)
for x in [-.052,.052]:
    cyl('Pulley flange',(x-.012,0,0),(x+.012,0,0),.20,steel)
    cyl('Pulley hub',(x-.022,0,0),(x+.022,0,0),.065,steel)
finish('trawl_sheave')

# Mirrored steel doors: cambered plate, shallow V, wear shoe, internal ribs and
# two-leg towing chain. Dimensions suit a compact game rig, not a certified design.
for side,name in [(1,'trawl_door_port'),(-1,'trawl_door_starboard')]:
    clear();v=[];f=[];rows,cols=10,16
    def skin(y,z):return side*(.12*(1-(y/.72)**2)+.16*abs(z-.55))
    for i in range(rows+1):
        z=i/rows*1.1;width=.72-.1*max(0,(abs(z-.55)-.40)/.15)**2
        for j in range(cols+1):
            y=-width+2*width*j/cols;v.append((skin(y,z),y,z))
    for i in range(rows):
        for j in range(cols):
            a=i*(cols+1)+j;f.append((a,a+1,a+cols+2,a+cols+1))
    ob=mesh('Cambered V door plate',v,f,doorpaint)
    sol=ob.modifiers.new('Steel plate thickness','SOLIDIFY');sol.thickness=.016
    for face in ob.data.polygons:face.use_smooth=True
    for z in [.03,.55,1.07]:
        line('Edge and middle stiffener',[(skin(y,z)+side*.025,y,z) for y in [-.60+i*1.2/24 for i in range(25)]],.022,doorpaint)
    for y in [-.42,.42]:
        line('Vertical stiffener',[(skin(y,z)+side*.035,y,z) for z in [.1+i*.09 for i in range(11)]],.028,doorpaint)
    box('Replaceable wear shoe',(side*.14,0,.02),(.23,1.20,.07),steel)
    for y in [-.5,-.25,0,.25,.5]:cyl('Shoe bolt',(side*.02,y,.025),(side*.28,y,.025),.016,steel)
    tow=Vector((side*.48,.18,.56))
    for y in [-.48,.48]:
        anchor=Vector((skin(y,.55)+side*.035,y,.55))
        cyl('Tow lug foot',(anchor.x-side*.04,y,.50),(anchor.x+side*.04,y,.60),.045,steel)
        d=tow-anchor;n=12
        for j in range(n):
            bpy.ops.mesh.primitive_torus_add(major_radius=.028,minor_radius=.007,major_segments=12,minor_segments=6,location=anchor+d*(j+.5)/n)
            o=bpy.context.object;o.name='Tow bridle chain';o.rotation_euler=d.to_track_quat('Y','Z').to_euler();o.rotation_euler.y+=math.pi/2*(j%2);o.data.materials.append(steel)
    socket('TowPoint',tow)
    socket('BridleUpper',(skin(-.58,.91),-.58,.91));socket('BridleLower',(skin(-.58,.19),-.58,.19))
    finish(name)

clear()
def netpoint(t,a):
    return ((2.40*(1-t)**.8+.14)*math.cos(a),-6*t,(.78*(1-t)**.85+.10)*math.sin(a)-.28*t)
for direction in [-1,1]:
    for j in range(32):
        line('Diamond net strand',[netpoint(i/96,j*math.tau/32+direction*i/96*math.tau*2) for i in range(97)],.008,net)
line('Mouth boltrope',[netpoint(0,i*math.tau/96) for i in range(97)],.024,rope)
for j in range(9):
    a=.15+(math.pi-.30)*j/8;p=netpoint(0,a);ball('Headline float',p,(.115,.085,.085),orange)
for j in range(9):
    a=math.pi+.2+(math.pi-.4)*j/8;p=Vector(netpoint(0,a));cyl('Footrope weight',p+Vector((0,-.04,0)),p+Vector((0,.04,0)),.05,dark)
for side,name in [(-1,'Port'),(1,'Starboard')]:
    socket(name+'WingUpper',(side*2.54*math.cos(.55),0,.88*math.sin(.55)))
    socket(name+'WingLower',(side*2.54*math.cos(.55),0,-.88*math.sin(.55)))
line('Codend binding',[netpoint(.99,i*math.tau/48) for i in range(49)],.026,rope)

def packed(co):
    # A compact coiled bag for presentation, not a cloth/seabed simulation.
    t=max(0,min(1,-co.y/6))
    w=2.40*(1-t)**.8+.14;h=.78*(1-t)**.85+.10
    a=math.atan2((co.z+.28*t)/h,co.x/w)
    rho=math.hypot(co.x/w,(co.z+.28*t)/h)
    r=.29+(rho-1)*min(w,h)
    x=(1.25-.12*t)*(1-2*math.acos(math.cos(a))/math.pi)
    return Vector((x,r*math.sin(a)*math.cos(3*math.tau*t),r*math.sin(a)*math.sin(3*math.tau*t)))

for ob in list(bpy.context.scene.objects):
    if ob.type!='MESH':continue
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    centre=ob.location.copy()
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    ob.shape_key_add(name='Basis');key=ob.shape_key_add(name='Stowed')
    target=None
    # Floats and weights remain rigid while the flexible strands gather.
    if ob.name.startswith(('Headline float','Footrope weight')):
        target=packed(centre)
    for vertex in key.data:vertex.co=vertex.co+target-centre if target is not None else packed(vertex.co)
for ob in list(bpy.context.scene.objects):
    if ob.type=='EMPTY' and 'Wing' in ob.name:
        socket(ob.name+'Stowed',packed(ob.location))
finish('trawl_net_open')

# Bake the identical closed shape for the editor's stationary/collidable bundle.
# This makes the visible swap at the cradle exact, with no second unrelated mesh.
for ob in list(bpy.context.scene.objects):
    if ob.type=='EMPTY':bpy.data.objects.remove(ob,do_unlink=True);continue
    if ob.type!='MESH':continue
    positions=[p.co.copy() for p in ob.data.shape_keys.key_blocks['Stowed'].data]
    ob.shape_key_clear()
    for vertex,co in zip(ob.data.vertices,positions):vertex.co=co
finish('trawl_net_bundle')

assets=[]
for name,style,size,components in [
 ('trawl_gantry_4m','trawl_gantry',[4.16,1.28,2.98],[{'id':'trawl_block','pivot':'PortBlockMount'},{'id':'trawl_block','pivot':'StarboardBlockMount'},{'id':'trawl_door_port','pivot':'PortDoorStow'},{'id':'trawl_door_starboard','pivot':'StarboardDoorStow'},{'id':'trawl_net_bundle','pivot':'NetStow'}]),
 ('trawl_block','trawl_block',[.26,.42,.55],[{'id':'trawl_sheave','pivot':'SheavePivot'}]),
 ('trawl_sheave','trawl_sheave',[.15,.4,.4],[]),
 ('trawl_door_port','trawl_door',[.5,1.45,1.15],[]),
 ('trawl_door_starboard','trawl_door',[.5,1.45,1.15],[]),
 ('trawl_net_bundle','trawl_bundle',[2.5,.66,.66],[])]:
    assets.append({'id':name,'kind':'furniture','style':style,'model':'res://resources/models/parts/trawl_rig/'+name+'.glb','start_xz':[0,0],'end_xz':size[:2],'height_start_m':size[2],'height_end_m':size[2],'paintable':True,'components':components})
if '--net-only' not in sys.argv:(OUT/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2),encoding='utf-8')
print('TRAWL_RIG_EXPORTED: gantry, block, sheave, mirrored doors, open net, stowed net')
