"""Flat six-hook handline winder, authored from Noah's reference photograph."""
import bpy, math
from pathlib import Path
from mathutils import Vector
source=Path(__file__).with_name('build_fishing_items.py')
exec(compile(source.read_text(encoding='utf-8').split('clear();make_rod();')[0],str(source),'exec'))
clear()
plastic=material('Moulded grey polymer',(.32,.35,.36),0,.32)
green=material('Green hook keeper',(.015,.25,.10),0,.65)
red=material('Red coated lead',(.65,.018,.022),0,.23)
nylon=material('Clear white monofilament',(.77,.82,.84),0,.25)
# Authored fine polymer grain, retained in the exported finish.
for mat in [plastic,green,red]:
    nodes=mat.node_tree.nodes; links=mat.node_tree.links
    noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=360
    bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.0003
    links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],nodes.get('Principled BSDF').inputs['Normal'])
root=empty('Harpe')
# Broad oval upper shell with a true finger opening, extruded as a watertight ring.
n=64;verts=[]
for y in [-.014,.014]:
    for inner in [False,True]:
        for i in range(n):
            t=math.tau*i/n
            x=(.078 if inner else .19)*math.cos(t)
            z=(-.018 if inner else -.039)+(.029 if inner else .079)*math.sin(t)
            verts.append((x,y,z))
faces=[]
for i in range(n):
    j=(i+1)%n
    faces.extend([(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),(i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
mesh=bpy.data.meshes.new('Continuous handle shell');mesh.from_pydata(verts,[],faces);mesh.update()
o=bpy.data.objects.new('Moulded handle with finger opening',mesh);bpy.context.collection.objects.link(o);o.parent=root;o.data.materials.append(plastic)
bevel=o.modifiers.new('Rounded mould edges','BEVEL');bevel.width=.006;bevel.segments=3
o.modifiers.new('Weighted shell normals','WEIGHTED_NORMAL')
def box(name,loc,scale,mat,parent):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.parent=parent;o.data.materials.append(mat)
    b=o.modifiers.new('Soft mould edges','BEVEL');b.width=.005;b.segments=3;o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o
box('Winding waist',(0,0,-.116),(.337,.025,.084),plastic,root)
box('Lower flared lip',(0,0,-.164),(.386,.036,.023),plastic,root)
# Individual tightly wound strands wrap front, ends and back of the waist.
for i in range(64):
    z=-.079-i*.00115
    curve('Wound monofilament %02d'%i,[(-.166,-.019,z),(.166,-.019,z-.0005),(.174,-.010,z-.0005),(.174,.010,z-.0005),(.166,.019,z-.0005),(-.166,.019,z-.00115),(-.174,.010,z-.00115),(-.174,-.010,z-.00115),(-.166,-.019,z-.00115)],.00048,nylon,root)
rodbar('Green hook storage strip',(-.168,-.018,-.180),(.168,-.018,-.180),.008,green,root)
stowed=empty('StoredTackle',root)
def hook(parent,x=0,z=0):
    curve('Stainless J hook',[(x,-.029,z+.029),(x,-.029,z-.012),(x+.004,-.029,z-.020),(x+.010,-.029,z-.021),(x+.015,-.029,z-.014),(x+.013,-.029,z-.002)],.0009,silver,parent)
    rodbar('Red attractor bead',(x,-.029,z+.018),(x,-.029,z+.025),.0032,red,parent)
for i in range(6):
    x=-.125+i*.05
    hook(stowed,x,-.179)
    curve('Stored snood',[(x,-.029,-.153),(x+.003,-.026,-.121)],.0004,nylon,stowed)
def sinker(parent,loc):
    # Revolved teardrop lead weight with a red protective coating.
    v=[];f=[];rings=[(0,.003),(.012,.010),(.037,.020),(.063,.023),(.079,.016),(.087,.002)]
    for z,r in rings:
        for i in range(24):v.append((r*math.cos(i*math.tau/24),r*math.sin(i*math.tau/24),-z))
    for j in range(len(rings)-1):
        for i in range(24):a=j*24+i;b=j*24+(i+1)%24;f.append((a,b,b+24,a+24))
    f.extend([tuple(range(23,-1,-1)),tuple(range(120,144))])
    m=bpy.data.meshes.new('Teardrop lead');m.from_pydata(v,[],f);m.update();o=bpy.data.objects.new('Red teardrop sinker',m);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;o.data.materials.append(red)
    for p in m.polygons:p.use_smooth=True
    return o
s=sinker(stowed,(.035,-.044,-.052));s.rotation_euler.y=-math.pi/2
curve('Sinker snap swivel',[(-.014,-.044,-.052),(.03,-.044,-.052)],.0014,silver,stowed)
# Grip faces and line exit; no crank exists on a flat hand winder.
empty('RightGrip',root,(.025,-.015,.017))
empty('LeftGrip',root,(-.15,-.026,-.115))
empty('LineTip',root,(-.17,-.020,-.09))
save('harpe')
# Source render: independent close camera, no gameplay changes.
bpy.ops.object.camera_add(location=(.30,-.85,.17));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,-.075))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=.49;bpy.context.scene.camera=cam
for loc,power,size in [((-.3,-.4,.5),45,.4),((.4,.1,.2),30,.3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(Vector((0,0,-.07))-light.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=1100;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.world.color=(.15,.15,.15)
import datetime
archive=Path('C:/Users/noahs/Pictures/machinescreenshots');archive.mkdir(exist_ok=True,parents=True)
scene.render.filepath=str(archive/('harpe-flat-winder-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'.png'));bpy.ops.render.render(write_still=True)
clear();hook(None);save('harpe_hook')
clear();sinker(None,(0,0,0));save('harpe_sinker')
