"""Blender geometry for the reference-style maritime character.
Angular silhouette; rounded edges and deformation rings, not a primitive mannequin.
"""
import bpy, math, json
from mathutils import Vector, Quaternion
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'resources/models/characters'; SOURCE=ROOT/'resources/models/_source/characters'
OUT.mkdir(parents=True,exist_ok=True); SOURCE.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
objects=[]
def mat(name,color,rough=.8,metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    return m
skin=mat('Skin',(.7,.49,.32)); shirt=mat('Top',(.86,.87,.81)); pants=mat('Trousers',(.15,.23,.28))
boot=mat('Footwear',(.055,.075,.085)); hair=mat('Hair',(.07,.04,.025)); trim=mat('Trim',(.065,.12,.15))
hat=mat('Headwear',(.09,.17,.21)); vest=mat('Outerwear',(.92,.68,.035)); metal=mat('Hardware',(.6,.65,.65),.35,.55)
eye=mat('Eyes',(.024,.029,.025),.5); lip=mat('Lips',(.3,.14,.09)); sole=mat('Sole',(.022,.028,.028))
glass=mat('Glasses',(.67,.73,.71),.35); pipe_mat=mat('Pipe',(.16,.073,.029)); nails=mat('Nails',(.64,.47,.36))

# A seamless tile containing small knitted V stitches. All actual colour regions
# are separate materials, so tinting does not recolour the dark trim.
image=bpy.data.images.new('Mariner knit',width=256,height=256)
pixels=[]
for y in range(256):
    for x in range(256):
        row=y//32; u=(x+(16 if row%2 else 0))%32-16; v=y%32-16
        stitch=abs(v-(abs(u)*.65-5))<2 and abs(u)<8
        weave=.96+.035*math.sin(x*math.pi/2)*math.sin(y*math.pi/2)
        c=(.095,.15,.17) if stitch else (weave,weave,weave)
        pixels.extend((*c,1))
image.pixels.foreach_set(pixels); image.filepath_raw=str(OUT/'mariner_knit.png'); image.file_format='PNG'; image.save(); image.pack()
tex=shirt.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=image
shirt.node_tree.links.new(tex.outputs['Color'],shirt.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])

def mesh(name,verts,faces,material):
    data=bpy.data.meshes.new(name); data.from_pydata(verts,[],faces); data.update()
    o=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(o); data.materials.append(material)
    for p in data.polygons:p.use_smooth=True
    objects.append(o); return o

def loft(name,rings,material,steps=3,bevel=.22,segments=6):
    # Rounded rectangle cross-section: planar broad faces, explicitly modelled corners.
    rr=[]
    for j in range(len(rings)-1):
        for k in range(steps): rr.append(tuple(a+(b-a)*k/steps for a,b in zip(rings[j],rings[j+1])))
    rr.append(rings[-1]); verts=[]; faces=[]
    for x,y,z,rx,ry in rr:
        for corner in range(4):
            angle=corner*math.pi/2
            cx=(rx-rx*bevel)*(1 if corner in [0,3] else -1)
            cy=(ry-ry*bevel)*(1 if corner in [0,1] else -1)
            for i in range(segments+1):
                a=angle+i/segments*math.pi/2
                verts.append((x+cx+rx*bevel*math.cos(a),y+cy+ry*bevel*math.sin(a),z))
    n=4*(segments+1)
    for j in range(len(rr)-1):
        for i in range(n):
            a=j*n+i; b=j*n+(i+1)%n; faces.append((a,b,b+n,a+n))
    faces.extend([tuple(reversed(range(n))),tuple((len(rr)-1)*n+i for i in range(n))])
    return mesh(name,verts,faces,material)

def join(parts,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join(); o=parts[0]; o.name=name
    for p in parts[1:]:objects.remove(p)
    return o

def box(name,loc,size,material,bevel=.006):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=o.modifiers.new('Authored edge bevel','BEVEL'); mod.width=bevel; mod.segments=4
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Apply location so all clothing has the same bind-space origin and morph functions.
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    o.data.materials.append(material); objects.append(o)
    return o

def tube(name,points,radius,material):
    verts=[]; faces=[]; n=12
    for j,p in enumerate(points):
        tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(0,j-1)])
        tangent.normalize(); u=tangent.cross(Vector((0,1,0))).normalized()
        if u.length<.1:u=Vector((1,0,0))
        v=tangent.cross(u).normalized()
        for i in range(n): verts.append(Vector(p)+radius*(u*math.cos(i*2*math.pi/n)+v*math.sin(i*2*math.pi/n)))
    for j in range(len(points)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
    return mesh(name,verts,faces,material)

def fuse(o,size=.004):
    bpy.context.view_layer.objects.active=o
    mod=o.modifiers.new('Weld tailored seams','REMESH'); mod.mode='VOXEL';mod.voxel_size=size;mod.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Relax seams','SMOOTH');mod.factor=.35;mod.iterations=2;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Production surface','DECIMATE');mod.ratio=.8;bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

# Body regions are separate and explicitly hidden under their covering garments.
# Region boundaries are away from cuffs/collars; coverage does not rely on coplanar shells.
torso=[(0,0,.88,.135,.085),(0,0,1.04,.155,.09),(0,0,1.17,.156,.092),(0,0,1.33,.198,.10),(0,0,1.43,.205,.095),(0,0,1.46,.08,.06)]
loft('Body_Torso',torso,skin,4)
loft('Neck',[(0,0,1.425,.052,.048),(0,0,1.54,.052,.05)],skin,6,.6)
arms=[]; legs=[]; hands=[]; feet=[]
for s in [-1,1]:
    arms.append(loft('Arm',[(s*.205,0,1.425,.063,.063),(s*.25,0,1.33,.06,.056),(s*.312,.005,1.17,.044,.044),(s*.323,.006,1.13,.042,.042),(s*.355,.017,1.03,.044,.04),(s*.39,.025,.935,.029,.03)],skin,5,.4))
    legs.append(loft('Leg',[(s*.10,0,.935,.078,.088),(s*.10,0,.82,.082,.082),(s*.11,.02,.55,.057,.061),(s*.11,.02,.50,.055,.057),(s*.11,0,.34,.06,.055),(s*.11,0,.10,.037,.04)],skin,6,.4))
    feet.append(loft('Foot',[(s*.11,.04,.012,.047,.102),(s*.11,.04,.045,.052,.115),(s*.11,.015,.10,.041,.05),(s*.11,0,.12,.038,.043)],skin,4,.45))
    hands.append(loft('Palm',[(s*.398,.027,.947,.029,.025),(s*.408,.027,.905,.044,.025),(s*.412,.03,.859,.043,.024),(s*.414,.031,.847,.034,.021)],skin,5,.4))
    for k in range(4):
        x=s*(.382+k*.021); tip=.793+[.012,0,.004,.02][k]
        hands.append(loft('Finger',[(x,.03,.86,.009,.014),(x,.032,.832,.009,.012),(x,.04,tip+.014,.008,.010),(x,.043,tip,.004,.006)],skin,4,.65,5))
        hands.append(box('Nail',(x,.054,tip+.009),(.011,.002,.013),nails,.002))
    hands.append(loft('Thumb',[(s*.375,.04,.913,.017,.017),(s*.353,.05,.889,.014,.014),(s*.347,.061,.862,.009,.01)],skin,5,.5))
join(arms,'Body_Arms');join(legs,'Body_Legs');join(feet,'Body_Feet');join(hands,'Hands')

# The square head and understated face retain the user's original character language.
loft('Head',[(0,0,1.535,.086,.077),(0,0,1.545,.098,.087),(0,0,1.59,.1,.089),(0,-.003,1.70,.102,.09),(0,-.004,1.767,.098,.087),(0,-.005,1.784,.083,.076)],skin,6,.16,8)
face=[]
for s in [-1,1]:
    face.append(box('Eye',(s*.038,.092,1.692),(.023,.009,.014),eye,.003))
    face.append(box('EyeGlint',(s*.038-.003,.097,1.696),(.003,.002,.003),metal,.0005))
    face.append(box('Eyebrow',(s*.038,.093,1.711),(.03,.008,.005),hair,.002))
    face.append(loft('Ear',[(s*.105,-.005,1.623,.01,.012),(s*.108,-.005,1.635,.016,.017),(s*.108,-.005,1.692,.015,.018),(s*.104,-.005,1.70,.008,.01)],skin,4,.6))
    face.append(box('EarInset',(s*.116,.009,1.665),(.009,.004,.026),lip,.004))
face.append(loft('Nose',[(0,.103,1.642,.011,.012),(0,.112,1.65,.016,.019),(0,.101,1.682,.012,.012)],skin,5,.4))
face.append(box('Mouth',(0,.092,1.609),(.041,.006,.006),lip,.002))
join(face,'Face')
loft('Hair_Crop',[(0,-.004,1.733,.105,.093),(0,-.008,1.77,.105,.095),(0,-.013,1.797,.069,.07),(0,-.013,1.807,.025,.033)],hair,5,.4)
moustache=[]
for s in [-1,1]:
    moustache.append(loft('Moustache',[(s*.024,.097,1.625,.022,.008),(s*.021,.10,1.636,.027,.009),(s*.014,.102,1.643,.016,.008)],hair,3,.3))
join(moustache,'FacialHair_Moustache')

top=[loft('SweaterChest',[(0,0,1.018,.181,.119),(0,0,1.07,.182,.12),(0,0,1.20,.181,.116),(0,0,1.37,.219,.127),(0,0,1.435,.222,.125),(0,0,1.46,.09,.075)],shirt,5)]
for s in [-1,1]:
    top.append(loft('Sleeve',[(s*.202,0,1.423,.076,.08),(s*.247,0,1.34,.073,.07),(s*.312,.005,1.17,.059,.057),(s*.323,.006,1.13,.057,.056),(s*.358,.017,1.025,.056,.054),(s*.38,.025,.957,.046,.045)],shirt,5))
top_mesh=fuse(join(top,'Top_Sweater'))
top_mesh.data.materials.append(trim)
for poly in top_mesh.data.polygons:
    if poly.center.z < 1.059 or (abs(poly.center.x) > .31 and poly.center.z < 1.005):
        poly.material_index=1
collar=loft('Top_Collar',[(0,0,1.445,.08,.073),(0,0,1.46,.074,.068),(0,0,1.489,.067,.061)],trim,3,.35)
collar.name='Top_Trim'
tr=[loft('TrouserWaist',[(0,0,.866,.187,.117),(0,0,.93,.188,.118),(0,0,1.033,.17,.115)],pants,5)]
for s in [-1,1]:tr.append(loft('TrouserLeg',[(s*.10,0,.924,.09,.111),(s*.10,0,.81,.097,.102),(s*.11,.02,.55,.075,.082),(s*.11,.02,.50,.074,.079),(s*.11,0,.34,.075,.077),(s*.11,0,.155,.064,.066)],pants,6))
fuse(join(tr,'Trousers_Work'))
base=[loft('BaseWaist',[(0,0,.875,.167,.108),(0,0,1.035,.165,.104)],trim,4)]
for s in [-1,1]:base.append(loft('ShortLeg',[(s*.1,0,.795,.088,.095),(s*.1,0,.91,.089,.104)],trim,4))
fuse(join(base,'Base_Shorts'))
boots=[]
for s in [-1,1]:
    boots.append(loft('Boot',[(s*.11,.04,.025,.064,.132),(s*.11,.04,.069,.066,.135),(s*.11,.025,.108,.061,.091),(s*.11,0,.15,.057,.06),(s*.11,0,.30,.071,.072)],boot,5))
    boots.append(loft('Sole',[(s*.11,.04,.005,.066,.135),(s*.11,.04,.029,.067,.136)],sole,3))
    boots.append(loft('BootLip',[(s*.11,0,.281,.073,.074),(s*.11,0,.306,.073,.074)],trim,3))
join(boots,'Footwear_Boots')

# Clothing additions occupy distinct spaces; no duplicate front/back surface layers.
cap=[loft('CapCrown',[(0,-.005,1.763,.11,.1),(0,-.005,1.806,.101,.095),(0,-.01,1.835,.07,.07),(0,-.01,1.842,.03,.035)],hat,4,.35)]
cap.append(loft('CapBand',[(0,-.005,1.745,.113,.104),(0,-.005,1.774,.113,.104)],trim,3,.25))
cap.append(box('CapPeak',(0,.089,1.752),(.233,.107,.015),hat,.009))
join(cap,'Headwear_Cap')
helmet=[loft('Hardhat',[(0,-.005,1.765,.112,.102),(0,-.005,1.81,.107,.1),(0,-.009,1.86,.069,.067),(0,-.01,1.872,.025,.03)],vest,5,.45)]
helmet.append(box('Brim',(0,.018,1.767),(.27,.26,.012),metal,.013))
join(helmet,'Headwear_Hardhat')
glasses=[]
for s in [-1,1]:
    points=[]
    for i in range(65):
        a=2*math.pi*i/64
        points.append((s*.039+.03*math.copysign(abs(math.cos(a))**.45,math.cos(a)),.108,1.693+.021*math.copysign(abs(math.sin(a))**.45,math.sin(a))))
    glasses.append(tube('Rim',points,.0028,glass))
    glasses.append(tube('Temple',[(s*.069,.108,1.704),(s*.104,.09,1.706),(s*.107,-.01,1.70)],.0028,glass))
glasses.append(tube('Bridge',[(-.01,.11,1.698),(0,.112,1.701),(.01,.11,1.698)],.0026,glass))
join(glasses,'Eyewear_Glasses')
vest_parts=[]
for s in [-1,1]:
    vest_parts.append(loft('VestPanel',[(s*.095,.097,1.045,.086,.052),(s*.095,.102,1.2,.085,.055),(s*.1,.106,1.32,.078,.054),(s*.137,.09,1.421,.041,.039)],vest,5,.32))
    vest_parts.append(box('VestStrap',(s*.095,.159,1.14),(.16,.016,.021),trim,.004))
    vest_parts.append(box('VestStrap',(s*.098,.159,1.30),(.15,.016,.021),trim,.004))
vest_parts.append(loft('VestBack',[(0,-.128,1.05,.18,.034),(0,-.14,1.34,.205,.034),(0,-.12,1.425,.18,.034)],vest,5))
vest_parts.append(box('Zip',(0,.152,1.204),(.014,.019,.321),metal,.003))
join(vest_parts,'Outerwear_Vest')
belt=loft('Utility_Belt',[(0,0,1.008,.186,.126),(0,0,1.037,.187,.126)],trim,3)
pouch=box('Pouch',(.183,.05,.98),(.057,.088,.12),pipe_mat,.008)
join([belt,pouch],'Utility_Belt')
pipe=[tube('Stem',[(-.013,.096,1.615),(-.057,.139,1.602),(-.098,.17,1.576)],.004,pipe_mat)]
pipe.append(loft('Bowl',[(-.105,.176,1.536,.016,.016),(-.105,.176,1.577,.021,.021)],pipe_mat,4,.65))
pipe.append(loft('BowlInset',[(-.105,.176,1.578,.013,.013),(-.105,.176,1.579,.013,.013)],sole,1,.65))
join(pipe,'Accessory_Pipe')
