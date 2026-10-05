"""Original Blender-authored 14 m coastal workboat. No imported legacy geometry.
Run in Blender's Python console; timer stages keep modelling visible in the UI.
Blender: X starboard, Y bow, Z up. glTF export maps bow to Godot -Z.
"""
import bpy, math, os, traceback
from mathutils import Vector

ROOT = r'C:\Users\noahs\Documents\angst-n-anchors\resources\models'
SOURCE = os.path.join(ROOT, '_source', 'coastal_workboat')
OUT = os.path.join(ROOT, 'vessels', 'coastal_workboat')
os.makedirs(SOURCE, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
scene = bpy.data.scenes.new('Coastal Workboat | original Blender model')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
groups = {}
for name in ['01 Hull and deck','02 Wheelhouse','03 Glazing and doors','04 Rails and mooring','05 Mast and lights','06 Deck machinery','07 Interior','08 Propulsion','09 Presentation']:
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    groups[name[:2]] = col
current = '01'

def mat(name, rgb, metallic=0, rough=.4, transmission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb,1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*rgb,1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    if 'Transmission Weight' in bsdf.inputs:
        bsdf.inputs['Transmission Weight'].default_value = transmission
    return m

navy=mat('Deep petrol painted steel',(.035,.115,.15),.55,.32)
oxide=mat('Red oxide antifouling',(.26,.055,.035),.05,.65)
ivory=mat('Warm white marine enamel',(.78,.80,.76),.25,.28)
deckmat=mat('Grey non-slip deck',(.24,.28,.28),.3,.8)
steel=mat('Brushed stainless steel',(.48,.55,.58),.85,.24)
rubber=mat('Rubber seals and fenders',(.018,.025,.028),0,.75)
glass=mat('Blue green marine glazing',(.035,.13,.17),.5,.12,.22)
orange=mat('Safety orange',(.85,.19,.035),.2,.42)
brass=mat('Marine bronze',(.4,.25,.085),.8,.27)
red=mat('Port red lens',(.62,.015,.008),.25,.2)
green=mat('Starboard green lens',(.01,.48,.13),.25,.2)
black=mat('Console charcoal',(.035,.043,.05),.2,.42)
screen=mat('Instrument glass',(.015,.15,.19),.2,.12)

def assign(obj, material):
    obj.data.materials.append(material)
    return obj

def move_group(obj):
    for col in list(obj.users_collection): col.objects.unlink(obj)
    groups[current].objects.link(obj)
    return obj

def bevel(obj, amount=.035, segments=3):
    mod=obj.modifiers.new('Manufactured edge radius','BEVEL')
    mod.width=amount; mod.segments=segments
    return obj

def box(name, loc, size, material, radius=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj=bpy.context.object; obj.name=name
    obj.dimensions=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    move_group(obj); assign(obj,material)
    if radius: bevel(obj,radius)
    return obj

def mesh(name, vertices, faces, material, smooth=False):
    data=bpy.data.meshes.new(name)
    data.from_pydata(vertices,[],faces); data.update()
    obj=bpy.data.objects.new(name,data); groups[current].objects.link(obj)
    assign(obj,material)
    import bmesh
    bm=bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    if smooth:
        for p in data.polygons:p.use_smooth=True
    return obj

def rod(name, a, b, radius, material, vertices=16):
    a,b=Vector(a),Vector(b); delta=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length, location=(a+b)/2)
    obj=bpy.context.object; obj.name=name
    obj.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    move_group(obj); assign(obj,material)
    bevel(obj,min(radius*.18,.012),2)
    for p in obj.data.polygons:p.use_smooth=True
    return obj

def tube(name, points, radius, material):
    data=bpy.data.curves.new(name,'CURVE'); data.dimensions='3D'
    data.resolution_u=12; data.bevel_depth=radius; data.bevel_resolution=3
    spline=data.splines.new('POLY'); spline.points.add(len(points)-1)
    for p,co in zip(spline.points,points):p.co=(*co,1)
    obj=bpy.data.objects.new(name,data); groups[current].objects.link(obj)
    assign(obj,material); return obj

def torus(name,loc,major,minor,material,rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=40,minor_segments=12,location=loc,major_radius=major,minor_radius=minor,rotation=rotation)
    obj=bpy.context.object;obj.name=name;move_group(obj);assign(obj,material)
    for p in obj.data.polygons:p.use_smooth=True
    return obj

def profile(y):
    # Naval-form stations designed here, not sampled from the game's old hull.
    anchors=[(-6.8,1.65,-.80,1.38),(-5.5,2.04,-1.16,1.32),(-3,2.25,-1.45,1.30),(0,2.28,-1.52,1.33),(2.5,2.02,-1.4,1.45),(4.5,1.45,-.95,1.66),(6,.72,-.05,1.94),(7.2,.025,1.45,2.15)]
    for i in range(len(anchors)-1):
        if y <= anchors[i+1][0]:
            a,b=anchors[i],anchors[i+1];t=(y-a[0])/(b[0]-a[0]);t=max(0,min(1,t))
            # Cubic Hermite with continuous station tangents, avoiding scallops.
            before=anchors[max(0,i-1)];after=anchors[min(len(anchors)-1,i+2)]
            span=b[0]-a[0]
            values=[]
            for j in (1,2,3):
                m0=(b[j]-before[j])/(b[0]-before[0])
                m1=(after[j]-a[j])/(after[0]-a[0])
                values.append((2*t**3-3*t*t+1)*a[j]+(t**3-2*t*t+t)*span*m0+(-2*t**3+3*t*t)*b[j]+(t**3-t*t)*span*m1)
            return tuple(values)
    return anchors[-1][1:]

def hull():
    global current
    current='01'
    ys=[-6.8+i*14/56 for i in range(57)]
    verts=[];faces=[]
    # Each section follows a rounded V from port gunwale through keel to starboard.
    for y in ys:
        beam,keel,deck=profile(y)
        for j in range(33):
            k=abs(j-16)
            if keel < -.12:
                z=keel+(-.12-keel)*k/8 if k<=8 else -.12+(deck+.12)*(k-8)/8
            else:
                z=keel+(deck-keel)*k/16
            height=max(0,min(1,(z-keel)/(deck-keel)))
            theta=math.acos(1-height**(1/.78))
            x=beam*math.sin(theta)*(-1 if j<16 else 1)
            verts.append((x,y,z))
    for i in range(56):
        for j in range(32):
            a=i*33+j;faces.append((a,a+33,a+34,a+1))
    faces += [tuple(range(32,-1,-1)),tuple(56*33+j for j in range(33))]
    obj=mesh('14m rounded steel hull',verts,faces,navy,True)
    obj.data.materials.append(oxide)
    for p in obj.data.polygons:
        z=sum(obj.data.vertices[v].co.z for v in p.vertices)/len(p.vertices)
        p.material_index=1 if z < -.12 else 0
    # A fitted cambered deck, sharing the designed sheer line.
    dv=[];df=[]
    for y in ys:
        beam,keel,d=profile(y)
        dv += [(-beam*.988,y,d), (0,y,d+.055),(beam*.988,y,d)]
    for i in range(56):
        for j in range(2):
            a=i*3+j;df.append((a,a+3,a+4,a+1))
    deck=mesh('Cambered non-slip main deck',dv,df,deckmat)
    solid=deck.modifiers.new('Deck plate thickness','SOLIDIFY');solid.thickness=.035
    for side in [-1,1]:
        points=[(side*profile(y)[0],y,profile(y)[2]+.08) for y in ys]
        tube('Continuous gunwale',points,.055,steel)
        points=[(side*(profile(y)[0]+.035),y,profile(y)[2]-.34) for y in ys[:-3]]
        tube('Heavy rubber rubbing strake',points,.095,rubber)

def cabin():
    global current
    current='02'
    # Lower shell is thin plating with a genuine open interior.
    for s in [-1,1]:
        box('Wheelhouse lower side', (s*1.40,1.1,1.88),(.065,3.7,1.02),ivory,.035)
    box('Wheelhouse forward sill',(0,2.95,1.98),(2.82,.07,1.06),ivory,.035)
    box('Aft bulkhead port',(-1.12,-.75,2.43),(.59,.07,2.08),ivory,.035)
    box('Aft bulkhead starboard',(.65,-.75,2.43),(1.47,.07,2.08),ivory,.035)
    box('Door header',(-.53,-.75,3.41),(.65,.09,.13),ivory,.02)
    roof=box('Rounded wheelhouse roof',(0,1.12,3.56),(3.14,4.05,.17),ivory,.08)
    for s in [-1,1]:
        tube('Roof drip edge',[(s*1.54,-.86,3.55),(s*1.54,3.08,3.55)],.022,steel)
    # Raised coaming keeps water off the entry without metre-thick blocks.
    box('Wheelhouse floor',(0,1.1,1.43),(2.79,3.68,.065),deckmat,.015)

def glazing():
    global current
    current='03'
    def pane(name,corners):
        obj=mesh(name,corners,[(0,1,2,3)],glass)
        mod=obj.modifiers.new('Laminated glazing','SOLIDIFY');mod.thickness=.012
        tube(name+' rubber seal',corners+[corners[0]],.032,rubber)
        tube(name+' aluminium frame',corners+[corners[0]],.018,steel)
    # Forward-leaning bridge glazing, three individually replaceable panes.
    for i in range(3):
        x0=-1.34+i*.90;x1=x0+.84
        pane('Forward windscreen %d'%(i+1),[(x0,2.98,2.47),(x1,2.98,2.47),(x1,3.04,3.44),(x0,3.04,3.44)])
        tube('Wiper arm %d'%i,[(x0+.13,3.03,2.53),(x0+.55,3.10,3.08)],.012,black)
    for s in [-1,1]:
        for i in range(3):
            y0=-.67+i*1.21;y1=y0+1.13
            pane('Side bridge glass',[(s*1.425,y0,2.44),(s*1.425,y1,2.44),(s*1.425,y1,3.45),(s*1.425,y0,3.45)])
        # Corner pillars join shell and roof.
        for y in [-.73,3.0]:rod('Bridge corner pillar',(s*1.40,y,2.39),(s*1.40,y,3.51),.045,ivory)
    box('Watertight entry door',(-.53,-.80,2.40),(.70,.06,1.91),ivory,.04)
    pane('Door window',[(-.78,-.842,2.63),(-.28,-.842,2.63),(-.28,-.842,3.17),(-.78,-.842,3.17)])
    rod('Door pull',(-.27,-.89,2.12),(-.27,-.89,2.40),.019,steel)
    for z in [1.68,2.98]:rod('Door hinge',(-.88,-.84,z),(-.88,-.84,z+.12),.025,steel)

def fittings():
    global current
    current='04'
    for s in [-1,1]:
        rail_ys=[-6.55,-5.6,-4.5,-3.4,-2.3,-1.2,-.1,1,2.1,3.2,4.3,5.3,6.1,6.65]
        for y in rail_ys:
            b,k,d=profile(y);x=s*(b-.07)
            rod('Stainless rail stanchion',(x,y,d+.03),(x,y,d+.89),.022,steel)
        for h in [.46,.90]:
            tube('Swept safety rail',[(s*(profile(y)[0]-.07),y,profile(y)[2]+h) for y in rail_ys],.022,steel)
        for y in [-5.8,4.8]:
            b,k,d=profile(y);x=s*(b-.30)
            box('Bollard foundation',(x,y,d+.035),(.38,.42,.06),navy,.025)
            for dy in [-.12,.12]:
                rod('Mooring bollard post',(x,y+dy,d+.05),(x,y+dy,d+.30),.06,steel)
                rod('Mooring horn',(x-.13,y+dy,d+.26),(x+.13,y+dy,d+.26),.026,steel)
        for y in [-4.7,-1.8,1.0]:
            b,k,d=profile(y)
            torus('Hanging tyre fender',(s*(b+.08),y,d-.40),.23,.09,rubber,(0,math.pi/2,0))
            tube('Fender lashing',[(s*(b-.06),y,d+.52),(s*(b+.14),y,d-.18)],.009,black)
    # Aft rail has a centre opening for working over the transom.
    for s in [-1,1]:
        for h in [.46,.90]:tube('Transom rail',[(s*.55,-6.58,1.38+h),(s*1.6,-6.58,1.38+h)],.022,steel)
        rod('Transom opening stanchion',(s*.55,-6.58,1.40),(s*.55,-6.58,2.28),.022,steel)
    # Boarding ladder under the port side, with realistic step spacing.
    for y in [-2.05,-1.55]:rod('Boarding ladder rail',(-2.36,y,-.3),(-2.36,y,1.45),.025,steel)
    for z in [-.1,.2,.5,.8,1.1]:rod('Boarding ladder rung',(-2.36,-2.05,z),(-2.36,-1.55,z),.02,steel)
    torus('Lifebuoy',(1.5,-.25,2.0),.29,.065,orange,(0,math.pi/2,0))

def mast():
    global current
    current='05'
    box('Mast foot',(0,.4,3.70),(.32,.38,.14),steel,.025)
    rod('Raked signal mast',(0,.4,3.72),(0,.12,5.45),.065,steel)
    rod('Radar crossbar',(-.65,.15,4.76),(.65,.15,4.76),.038,steel)
    box('Marine radar radome',(0,.18,4.95),(.72,.32,.14),ivory,.065)
    rod('VHF aerial',(.4,.12,4.82),(.4,.12,6.13),.009,ivory)
    rod('GPS stalk',(-.4,.12,4.8),(-.4,.12,5.2),.016,steel)
    box('GPS receiver',(-.4,.12,5.24),(.12,.12,.08),ivory,.04)
    for s,material in [(-1,red),(1,green)]:
        box('Navigation lamp base',(s*1.46,2.30,3.69),(.18,.25,.07),black,.025)
        box('Navigation lamp lens',(s*1.46,2.30,3.79),(.12,.17,.14),material,.035)
    rod('Masthead light body',(0,.12,5.42),(0,.12,5.61),.066,ivory)
    for s in [-1,1]:
        box('Aft worklight bracket',(s*1.08,-.64,3.67),(.06,.16,.10),steel,.015)
        obj=box('Aft LED worklight',(s*1.08,-.71,3.76),(.22,.09,.14),black,.025)
        obj.rotation_euler.x=math.radians(-20)
        box('Worklight lens',(s*1.08,-.766,3.76),(.18,.013,.10),ivory,.012)

def machinery():
    global current
    current='06'
    box('Deck hatch coaming',(0,-3.7,1.39),(1.65,2.15,.15),navy,.08)
    box('Flush hatch lid',(0,-3.7,1.49),(1.57,2.07,.06),deckmat,.055)
    for x in [-.68,.68]:
        for y in [-4.48,-2.92]:
            rod('Hatch securing dog',(x-.07,y,1.54),(x+.07,y,1.54),.018,steel)
    # Compact aft hauling winch with flanges, gearbox and independently named drum.
    box('Winch welded skid',(0,-5.6,1.45),(1.65,.83,.15),navy,.045)
    for x in [-.53,.53]:
        box('Winch bearing pedestal',(x,-5.6,1.82),(.14,.5,.65),steel,.04)
        rod('Drum flange',(x-.025,-5.6,2.02),(x+.025,-5.6,2.02),.34,navy,32)
    rod('Winch drum',(-.50,-5.6,2.02),(.50,-5.6,2.02),.22,steel,32)
    for x in [i*.027-.46 for i in range(35)]:
        torus('Cable winding',(x,-5.6,2.02),.232,.012,black,(0,math.pi/2,0))
    rod('Hydraulic drive',(.65,-5.6,2.02),(.91,-5.6,2.02),.16,navy)
    tube('Hydraulic hose',[(.82,-5.6,1.96),(.95,-5.65,1.76),(.82,-5.80,1.52)],.018,rubber)
    # Slim exhaust on aft starboard wheelhouse corner.
    rod('Exhaust riser',(1.02,-.52,1.4),(1.02,-.52,4.16),.085,steel)
    rod('Exhaust rain cap',(1.02,-.52,4.13),(1.02,-.52,4.20),.135,black)
    # Roof life raft canister, recognisable rounded manufactured form.
    box('Liferaft cradle',(-.73,.12,3.71),(.63,1.03,.08),steel,.025)
    box('Liferaft canister',(-.73,.12,3.96),(.58,.97,.43),ivory,.20)
    for y in [-.20,.43]:box('Raft retention strap',(-.73,y,3.97),(.60,.045,.44),black,.045)

def interior():
    global current
    current='07'
    console=box('Helm instrument pedestal',(0,2.28,1.97),(1.25,.55,1.02),black,.08)
    panel=box('Sloped instrument fascia',(0,2.25,2.52),(1.25,.62,.07),black,.025)
    panel.rotation_euler.x=math.radians(20)
    for x in [-.34,.34]:
        display=box('Navigation display',(x,2.26,2.60),(.44,.29,.025),screen,.02)
        display.rotation_euler.x=math.radians(20)
    torus('Helm steering rim',(-.32,1.93,2.29),.19,.014,black,(math.pi/2,0,0))
    for i in range(3):
        a=i*2*math.pi/3
        rod('Helm wheel spoke',(-.32,1.93,2.29),(-.32+math.sin(a)*.18,1.93,2.29+math.cos(a)*.18),.009,steel)
    rod('Throttle lever',(.45,2,2.36),(.45,1.94,2.60),.012,steel)
    box('Throttle grip',(.45,1.94,2.61),(.09,.07,.05),black,.02)
    rod('Captain chair pedestal',(-.32,1.23,1.48),(-.32,1.23,1.95),.055,steel)
    box('Captain upholstered seat',(-.32,1.23,2.00),(.51,.49,.10),black,.055)
    back=box('Captain chair back',(-.32,1.02,2.28),(.49,.09,.51),black,.045)
    for s in [-1,1]:rod('Chair armrest',(-.32+s*.27,1.04,2.18),(-.32+s*.27,1.45,2.18),.024,black)
    box('Port storage locker',(-1.10,.1,1.82),(.42,1.0,.75),ivory,.035)
    box('Crew bench cushion',(-1.05,.10,2.23),(.47,.96,.10),black,.045)

def propulsion():
    global current
    current='08'
    rod('Propeller shaft',(0,-4.9,-.73),(0,-6.60,-.79),.045,steel)
    rod('Bronze propeller hub',(0,-6.43,-.79),(0,-6.69,-.79),.10,brass,24)
    for i in range(4):
        angle=i*math.pi/2
        points=[]
        for r,a,y in [(.09,0,-6.56),(.39,.22,-6.55),(.43,.70,-6.48),(.15,.95,-6.51)]:
            points.append((r*math.cos(a+angle),y,-.79+r*math.sin(a+angle)))
        blade=mesh('Swept bronze propeller blade',points,[(0,1,2,3)],brass,True)
        solid=blade.modifiers.new('Blade thickness','SOLIDIFY');solid.thickness=.018
        bevel(blade,.015,3)
    box('Rudder blade',(0,-6.83,-.58),(.065,.37,1.0),navy,.025)

def presentation():
    global current
    current='09'
    world=bpy.data.worlds.new('Neutral marine studio');scene.world=world
    world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.10,.14,.18,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.5
    for name,loc,energy,size in [('Large softbox',(4,3,12),2400,9),('Port fill',(-8,0,6),1800,7),('Stern rim',(2,-9,7),2100,6)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
        obj=bpy.data.objects.new(name,data);groups[current].objects.link(obj);obj.location=loc
        obj.rotation_euler=(Vector((0,0,1.5))-obj.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('Boat overview');cam=bpy.data.objects.new('Boat overview',data)
    groups[current].objects.link(cam);cam.location=(13,18,11)
    cam.rotation_euler=(Vector((0,0,1.5))-cam.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=19;scene.camera=cam
    scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=False
    scene.view_settings.view_transform='AgX'
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False

def save_export():
    bpy.ops.object.select_all(action='DESELECT')
    for key,col in groups.items():
        if key=='09':continue
        for obj in col.objects: obj.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,'coastal_workboat.blend'))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'coastal_workboat.glb'),export_format='GLB',use_selection=True,export_apply=True)
    for key,col in groups.items():
        if key=='09':continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in col.objects:obj.select_set(True)
        name={'01':'hull_deck','02':'wheelhouse_shell','03':'glazing_doors','04':'rails_mooring','05':'mast_lights','06':'deck_machinery','07':'bridge_interior','08':'propulsion'}[key]
        folder=os.path.join(ROOT,'parts','coastal_'+name);os.makedirs(folder,exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(folder,'coastal_'+name+'.glb'),export_format='GLB',use_selection=True,export_apply=True)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,'coastal_workboat.blend'))
    with open(os.path.join(SOURCE,'build_status.txt'),'w') as f:
        f.write('Complete: original Blender boat and eight component exports.\nObjects: %d\n'%sum(len(c.objects) for k,c in groups.items() if k!='09'))

stages=[hull,cabin,glazing,fittings,mast,machinery,interior,propulsion,presentation,save_export]
stage_index=0
def step():
    global stage_index
    try:
        fn=stages[stage_index]
        fn()
        with open(os.path.join(SOURCE,'progress.txt'),'w') as f:f.write('%d/%d %s'%(stage_index+1,len(stages),fn.__name__))
        for area in bpy.context.screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.shading.type='SOLID'
                area.spaces.active.shading.color_type='MATERIAL'
                area.spaces.active.shading.light='STUDIO'
                area.spaces.active.clip_end=500
                if stage_index<8:
                    region=area.spaces.active.region_3d
                    region.view_distance=21
                    region.view_location=(0,0,1.5)
                    region.view_rotation=Vector((12,16,10)).to_track_quat('Z','Y')
                area.tag_redraw()
        stage_index+=1
        return 2.0 if stage_index<len(stages) else None
    except Exception:
        with open(os.path.join(SOURCE,'build_error.txt'),'w') as f:f.write(traceback.format_exc())
        traceback.print_exc()
        return None

# Leave the console immediately so the user sees the actual modelling stages.
if bpy.context.area and bpy.context.area.type=='CONSOLE':bpy.context.area.type='VIEW_3D'
if bpy.app.background:
    for fn in stages:
        fn()
        print('BLENDER_STAGE', fn.__name__, flush=True)
    render_dir=r'C:\Users\noahs\Documents\Codex\2026-10-05\referenced-chatgpt-conversation-this-is-an\outputs\blender-workboat'
    os.makedirs(render_dir,exist_ok=True)
    for name,position,target in [('bow',(13,18,11),(0,0,1.5)),('stern',(-13,-18,10),(0,0,1.5)),('profile',(20,0,7),(0,0,1.5))]:
        scene.camera.location=position
        scene.camera.rotation_euler=(Vector(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=os.path.join(render_dir,name+'.png')
        bpy.ops.render.render(write_still=True)
else:
    bpy.app.timers.register(step,first_interval=.5)
