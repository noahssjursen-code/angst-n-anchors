"""Original herring gull asset. Blender 4.5: source, GLB, plumage atlases, review renders."""
import bpy, math, sys
import numpy as np
from pathlib import Path
from datetime import datetime
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from gull_head_morphs import add_head_morphs
ASSETS=ROOT/'resources/models/wildlife'
SOURCE=ROOT/'resources/models/_source/wildlife'
OUT=Path('C:/Users/noahs/Pictures/machinescreenshots')/('gull-v2-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
for p in (ASSETS,SOURCE,OUT): p.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0

# One atlas/material for the whole bird; both age endpoints use identical UVs.
# Tiles: body, mantle, secondary, primary, tail, bill, feet, eye/iris, red spot.
def make_atlas(juvenile):
    n=1024; tile=n//4; rgba=np.ones((n,n,4),dtype=np.float32)
    rng=np.random.default_rng(761)
    y,x=np.mgrid[0:tile,0:tile]/float(tile)
    fine=rng.normal(0,.008,(tile,tile))
    for k in range(16):
        color=np.array((.92,.935,.91))
        if k in (1,2): color=np.array((.51,.56,.61))
        if k==3: color=np.array((.028,.036,.045))
        if k==5: color=np.array((.90,.68,.18))
        if k==6: color=np.array((.69,.43,.39))
        if k==7: color=np.array((.74,.68,.37))
        if k==8: color=np.array((.008,.012,.015))
        if k==9: color=np.array((.66,.06,.025))
        c=np.broadcast_to(color,(tile,tile,3)).copy()
        if k==0 and not juvenile:
            back=np.clip(np.sin(x*math.tau)*4-1,0,1)*np.clip((y-.07)*20,0,1)*np.clip((.66-y)*18,0,1)
            c=c*(1-back[:,:,None])+np.array((.51,.56,.61))*back[:,:,None]
        if k<=4:
            # Subtle barbs and shafts along feather UV; no slabs or thick outlines.
            c += (fine+.018*np.sin((y+abs(x-.5)*.8)*190))[:,:,None]
            shaft=np.exp(-((x-.5)/.009)**2)*.08
            c+=shaft[:,:,None]
            if k in (2,3):
                tip=np.clip((y-.91)*22,0,1)
                c=c*(1-tip[:,:,None])+np.array((.88,.91,.91))*tip[:,:,None]
            if k==3:
                mirror=np.clip(1-((x-.5)/.34)**2-((y-.82)/.058)**2,0,1)
                c=c*(1-mirror[:,:,None])+mirror[:,:,None]*.92
            if juvenile:
                base=np.array((.48,.38,.29)) if k in (1,2) else np.array((.68,.61,.50))
                scallops=np.sin(y*310+np.cos(x*155)*1.8)*np.sin(x*170-y*43)
                mottled=np.clip((scallops+.2)*2,0,1)
                if k in (0,1,2): c=base[None,None,:]+(mottled*.24-.12+fine)[:,:,None]
                if k==3: c=np.broadcast_to(np.array((.16,.12,.09)),c.shape).copy()+fine[:,:,None]
                if k==4: c*=np.where((y>.66)&(y<.91),.18, .86)[:,:,None]
        if juvenile and k in (5,7): c[:]=(.105,.08,.065) if k==5 else (.19,.13,.08)
        if juvenile and k==9: c[:]=(.12,.085,.07)
        row,col=divmod(k,4); rgba[row*tile:(row+1)*tile,col*tile:(col+1)*tile,:3]=np.clip(c,0,1)
    name='gull_juvenile' if juvenile else 'gull_adult'
    im=bpy.data.images.new(name,width=n,height=n,alpha=True)
    im.pixels.foreach_set(rgba.ravel()); im.filepath_raw=str(ASSETS/(name+'.png')); im.file_format='PNG'; im.save()
    return im
adult=make_atlas(False); juvenile=make_atlas(True)
mat=bpy.data.materials.new('GullPlumage'); mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF'); bs.inputs['Roughness'].default_value=.76
tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=adult
mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
root=bpy.data.objects.new('CoastalGull',None); bpy.context.collection.objects.link(root)

def uv_tile(u,v,tile):
    row,col=divmod(tile,4)
    return ((col+.01+u*.98)/4,(row+.01+v*.98)/4)

def mesh(name,verts,faces,uvs,parent=root):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o); o.parent=parent; me.materials.append(mat)
    uv=me.uv_layers.new(name='UVMap')
    for p in me.polygons:
        p.use_smooth=True
        for li in p.loop_indices: uv.data[li].uv=uvs[me.loops[li].vertex_index]
    return o

def loft(name,sections,tile=0,parent=root,sides=20):
    # y, centre z, halfwidth, halfheight: one continuous tailored body/bill.
    verts=[]; uvs=[]
    for i,(y,z,rx,rz) in enumerate(sections):
        for j in range(sides):
            a=2*math.pi*j/(sides-1)
            verts.append((math.cos(a)*rx,y,z+math.sin(a)*rz)); uvs.append(uv_tile(j/(sides-1),i/(len(sections)-1),tile))
    faces=[]
    for i in range(len(sections)-1):
        for j in range(sides-1):
            a=i*sides+j; faces.append((a,a+1,a+sides+1,a+sides))
    faces.extend([tuple(range(sides-1,-1,-1)),tuple(range((len(sections)-1)*sides,len(verts)))])
    return mesh(name,verts,faces,uvs,parent)

def sphere(name,loc,scale,tile,parent=root):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=loc)
    o=bpy.context.object; o.name=name; o.scale=scale; o.parent=parent; o.data.materials.append(mat)
    for d in o.data.uv_layers.active.data: d.uv=uv_tile(d.uv.x,d.uv.y,tile)
    for p in o.data.polygons: p.use_smooth=True
    return o

def feather(name,start,end,width,tile,parent=root,camber=.002):
    start,end=Vector(start),Vector(end); axis=end-start
    side=Vector((-axis.y,axis.x,0)).normalized(); verts=[]; uvs=[]
    for i in range(25):
        t=i/24; center=start+axis*t+Vector((0,0,camber*math.sin(math.pi*t)))
        w=width*(.55+.45*math.sin(math.pi*t)) if t<.6 else width*math.sqrt(max(0,1-((t-.6)/.4)**2))
        for j in range(9):
            a=math.pi*2*j/8
            v=center+side*(math.cos(a)*w)+Vector((0,0,math.sin(a)*.0018*math.sin(math.pi*t)))
            verts.append(tuple(v)); uvs.append(uv_tile((math.cos(a)+1)/2,t,tile))
    faces=[]
    for i in range(24):
        for j in range(8):
            a=i*9+j; faces.append((a,a+1,a+10,a+9))
    return mesh(name,verts,faces,uvs,parent)

# 61 cm beak-to-tail; slim neck and gently sloped forehead, not stacked spheres.
body=loft('Body',[
(-.275,.015,.003,.006),(-.23,.024,.042,.042),(-.18,.035,.072,.064),(-.10,.037,.089,.080),
(0,.044,.083,.085),(.075,.059,.070,.074),(.125,.083,.055,.065),(.17,.112,.043,.055),
(.205,.142,.046,.053),(.24,.154,.050,.052),(.27,.149,.045,.044),(.30,.137,.031,.028),(.318,.128,.012,.013)],sides=28)
sub=body.modifiers.new('Smooth contour','SUBSURF'); sub.levels=2
loft('Bill',[(.287,.129,.021,.020),(.314,.127,.021,.018),(.355,.125,.016,.014),(.389,.124,.009,.012),(.407,.115,.001,.002)],5)
# Thin mouth seam and red gonys patch, flush to the bill.
for s in (-1,1):
    sphere('EyeIris',(s*.046,.259,.160),(.004,.009,.009),7)
    sphere('Pupil',(s*.049,.261,.160),(.002,.0045,.0055),8)
    sphere('GonysSpot',(s*.0125,.375,.114),(.0017,.010,.005),9)
    sphere('Nostril',(s*.020,.324,.132),(.001,.007,.002),8)
for i in range(12):
    x=(i-5.5)*.010
    feather('Tail%02d'%i,(x*.7,-.17,.035),(x*1.35,-.34+abs(x)*.12,.01),.012,4)

wings=[]
for s,label in ((-1,'Left'),(1,'Right')):
    p=bpy.data.objects.new(label+'Wing',None);bpy.context.collection.objects.link(p);p.parent=root;p.location=(s*.062,.025,.092); wings.append(p)
    tip=bpy.data.objects.new(label+'WingTip',None);bpy.context.collection.objects.link(tip);tip.parent=p;tip.location=(s*.29,.016,0)
    # Curved aerofoil upper arm; thin rounded leading edge.
    sections=[(0,.04,-.10,.019),(.09,.022,-.145,.016),(.18,.016,-.14,.012),(.29,.061,-.105,.008)]
    verts=[];uvs=[]
    for i,(x,leading,trailing,thick) in enumerate(sections):
        for j in range(17):
            a=j/16*math.pi*2
            y=(leading+trailing)/2+math.cos(a)*(leading-trailing)/2
            z=math.sin(a)*thick+.015*math.sin(x*6)
            verts.append((s*x,y,z));uvs.append(uv_tile((math.cos(a)+1)/2,i/3,1))
    faces=[(i*17+j,i*17+j+1,(i+1)*17+j+1,(i+1)*17+j) for i in range(3) for j in range(16)]
    wing=mesh(label+'Arm',verts,faces,uvs,p)
    sub=wing.modifiers.new('Wing contours','SUBSURF');sub.levels=2
    for i in range(12):
        x=.016+i*.024
        feather(label+'Secondary%02d'%i,(s*x,-.025,.002),(s*(x+.025),-.187+x*.13,-.002),.019,2,p)
    # Primary fan sweeps aft progressively, producing the distinctive long pointed hand.
    for i in range(10):
        t=i/9
        start=(s*(.008+t*.11),.015-t*.012,.003+i*.0004)
        end=(s*(.10+.27*t),-.175-.04*t,-.007)
        feather(label+'Primary%02d'%i,start,end,.030 if i<7 else .025,3 if i>=4 else 2,tip)
    feather(label+'WristCover',(s*(-.025),.013,.019),(s*.25,-.115,.012),.067,1,tip)
    for i in range(8):
        t=i/7
        feather(label+'HandCovert%02d'%i,(s*(t*.11),.031,.014),(s*(.06+t*.18),-.107-t*.04,.009),.023,1,tip)

# Folded plumage is an alternate silhouette, not flight wings rotated through the chest.
fold=bpy.data.objects.new('FoldedWings',None);bpy.context.collection.objects.link(fold);fold.parent=root
for s,label in ((-1,'L'),(1,'R')):
    for i in range(10):
        t=i/9
        feather(label+'Fold%02d'%i,(s*(.064+.018*math.sin(t*math.pi)),.08-t*.10,.077-t*.015),
                (s*(.025+t*.035),-.30-t*.025,.032-t*.017),.022,3 if i>6 else 1,fold,camber=.009)
# Separate leg pivot allows the same feet to tuck in flight / extend when perched.
legs=bpy.data.objects.new('Legs',None);bpy.context.collection.objects.link(legs);legs.parent=root;legs.location=(0,-.07,-.015)
for s in (-1,1):
    sphere('Shank',(s*.033,-.005,-.085),(.007,.007,.065),6,legs)
    mesh('WebbedFoot',[(s*.033,-.015,-.144),(s*.033-.028,.056,-.144),(s*.033,.040,-.142),(s*.033+.028,.056,-.144)],[(0,1,2),(0,2,3)], [uv_tile(0,0,6),uv_tile(0,1,6),uv_tile(.5,1,6),uv_tile(1,1,6)],legs)

# Apply and batch geometry by articulation group: six shared-material draw surfaces.
for parent in [root,*wings,*[next(c for c in w.children if c.type=='EMPTY') for w in wings],fold,legs]:
    parts=[o for o in list(parent.children) if o.type=='MESH']
    if not parts: continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
    bpy.context.object.name=parent.name+'Mesh'
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)

add_head_morphs(bpy.data.objects['CoastalGullMesh'])

# Export rest pose and drive animation procedurally in Godot so age/size/boids share it.
def pose(time,mode='flap'):
    for s,w in zip((-1,1),wings):
        angle=(.18+.65*math.sin(time*math.tau)) if mode=='flap' else .10
        w.rotation_euler=(.03*math.cos(time*math.tau),-s*angle,0)
        tip=next(c for c in w.children if c.type=='EMPTY')
        tip.rotation_euler=(0,-s*.30*math.sin(time*math.tau-.65),-s*.10*(1+math.cos(time*math.tau))) if mode=='flap' else (0,0,0)
    legs.rotation_euler.x=-1.2

def visibility(mode):
    for w in wings:
        for c in w.children_recursive: c.hide_render=mode=='folded'
    for c in fold.children_recursive:c.hide_render=mode!='folded'
    legs.rotation_euler.x=0 if mode=='folded' else -1.2

bpy.ops.object.select_all(action='DESELECT')
for o in [root,*root.children_recursive]:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS/'coastal_gull.glb'),use_selection=True,export_format='GLB',export_animations=False,export_apply=False,export_morph=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=28;scene.cycles.use_denoising=True
scene.render.image_settings.file_format='PNG';scene.render.resolution_percentage=100
scene.render.resolution_x=1200;scene.render.resolution_y=850
scene.world.color=(.12,.12,.12);scene.view_settings.view_transform='AgX'
for name,pos,power,size in [('Key',(1,2,3),160,3),('Fill',(-2,0,1),60,3),('Rim',(0,-2,2),200,2)]:
    bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.size=size;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.09,.12,1)
bpy.ops.object.camera_add(location=(1.0,1.7,.85));cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=1.65
cam.rotation_euler=(Vector((0,0,.02))-cam.location).to_track_quat('-Z','Y').to_euler()
pose(0,'glide');visibility('flight')
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'coastal_gull.blend'))
def render(name):scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
render('01-adult-flight')
cam.location=(1.6,.5,.45);cam.rotation_euler=(Vector((0,0,.015))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.83
visibility('folded');render('02-adult-folded')
tex.image=juvenile;render('03-juvenile-folded');tex.image=adult
cam.location=(0,-.10,3);cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=1.7
visibility('flight');render('04-wing-planform')
cam.location=(1,1.7,.85);cam.rotation_euler=(Vector((0,0,.02))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=1.65
scene.render.resolution_x=800;scene.render.resolution_y=560;scene.cycles.samples=16
for i in range(24):pose(i/24);render('flap-%02d'%i)
(ROOT/'.codex/gull-review-path.txt').write_text(str(OUT),encoding='utf-8')
# Editable flight cycle in the saved Blender source as well as runtime controls.
visibility('flight'); tex.image=adult
scene.frame_start=1; scene.frame_end=24; scene.render.fps=24
for frame in range(1,26):
    pose((frame-1)/24)
    for wing in wings:
        wing.keyframe_insert('rotation_euler',frame=frame,group='Flight')
        tip=next(c for c in wing.children if c.type=='EMPTY')
        tip.keyframe_insert('rotation_euler',frame=frame,group='Flight')
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'coastal_gull.blend'))
print('GULL_REVIEW',OUT)
