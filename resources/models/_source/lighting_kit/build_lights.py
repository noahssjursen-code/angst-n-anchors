"""Reusable marine light fixtures; no illumination baked into GLB materials.
Godot ShipLight owns on/off, lens emission, weather scaling and actual light.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix
SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[1]
OUT=ROOT/'parts/lighting_kit';OUT.mkdir(parents=True,exist_ok=True)

def mat(n,c,metal=.3,rough=.5):
    m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
    bs=m.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(*c,1)
    bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    return m
paint=mat('Warm white painted steel',(.7,.73,.70))
dark=mat('Fixed_BlackHousing',(.03,.045,.05),.35)
steel=mat('Fixed_Stainless',(.44,.50,.53),.8,.28)
glass=mat('Fixed_Lens',(.3,.33,.3),0,.2)

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(n,p,s,m=paint):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    b=o.modifiers.new('Edge radius','BEVEL');b.width=min(.014,min(s)*.18);b.segments=3
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o
def rod(n,a,b,r,m=steel):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    return o
def socket(p,angle=0):
    o=bpy.data.objects.new('LightAim',None);bpy.context.collection.objects.link(o);o.location=p;o.rotation_euler.x=angle
def base(height):
    box('Welded mounting pad',(0,0,.025),(.24,.24,.05))
    for x in [-.085,.085]:
        for y in [-.085,.085]:rod('Mount bolt',(x,y,.05),(x,y,.065),.014)
    rod('Tubular standard',(0,0,.05),(0,0,height),.047,paint)
    rod('Base collar',(0,0,.05),(0,0,.22),.063,dark)
def export(name,light_type,height):
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    assets.append({'id':name,'kind':'furniture','style':'light','light_type':light_type,'model':'res://resources/models/parts/lighting_kit/'+name+'.glb','start_xz':[0,0],'end_xz':[.4,.35],'height_start_m':height,'height_end_m':height,'paintable':True})

assets=[]
clear();base(2.3)
# U-yoke and pivot bolts, with finned lamp tilted toward the deck.
box('Yoke bridge',(0,0,2.29),(.39,.09,.055),steel)
for x in [-.185,.185]:
    box('Yoke ear',(x,0,2.40),(.035,.09,.26),steel)
    rod('Tilt pivot',(x-.02,0,2.49),(x+.02,0,2.49),.035,dark)
before=set(bpy.context.scene.objects)
box('Flood housing',(0,0,0),(.33,.14,.17),dark)
for x in [-.135+i*.027 for i in range(11)]:box('Cooling fin',(x,-.093,0),(.011,.057,.15),dark)
box('Lens gasket',(0,.074,0),(.31,.017,.15),steel)
box('Lens',(0,.085,0),(.286,.012,.126),glass)
for x in [-.144,.144]:
    for z in [-.062,.062]:rod('Bezel fastener',(x,.081,z),(x,.087,z),.008,steel)
transform=Matrix.Translation((0,0,2.49))@Matrix.Rotation(math.radians(-35),4,'X')
bpy.context.view_layer.update()
for ob in set(bpy.context.scene.objects)-before:ob.matrix_world=transform@ob.matrix_world
rod('Cable gland',(0,-.05,2.24),(0,-.05,2.39),.018,dark)
socket(transform@Vector((0,.10,0)),math.radians(-35))
export('deck_floodlight',4,2.64)

# Port/starboard/stern lamps with swept lenses, screening plates and actual screws.
for name,kind,lo,hi,col in [('nav_port',0,-112.5,0,(.25,.015,.01)),('nav_starboard',1,0,112.5,(.015,.23,.035)),('nav_stern',3,112.5,247.5,(.25,.25,.23))]:
    clear();base(.8)
    rod('Lantern lower rim',(0,0,.80),(0,0,.84),.13,dark)
    rod('Lantern cap',(0,0,1.02),(0,0,1.08),.145,dark)
    vs=[];fs=[]
    for z in [.84,1.02]:
        for i in range(33):
            angle=math.radians(lo+(hi-lo)*i/32);vs.append((.124*math.sin(angle),.124*math.cos(angle),z))
    for i in range(32):fs.append((i+33,i+34,i+1,i))
    data=bpy.data.meshes.new('Lens');data.from_pydata(vs,[],fs);data.update()
    obj=bpy.data.objects.new('Lens',data);bpy.context.collection.objects.link(obj);data.materials.append(mat('Fixed_Lens_'+name,col,0,.2))
    for p in data.polygons:p.use_smooth=True
    for a in [lo,hi]:
        angle=math.radians(a)
        ob=box('Screen',(0,0,.94),(.018,.29,.29),dark)
        ob.location.x=.115*math.sin(angle);ob.location.y=.115*math.cos(angle);ob.rotation_euler.z=-angle
    rod('Rear housing',(0,0,.84),(0,0,1.03),.073,dark)
    for x in [-.08,.08]:rod('Lid screw',(x,0,1.08),(x,0,1.091),.009,steel)
    socket((0,0,.94));export(name,kind,1.1)

clear();base(2.7)
rod('Mast lamp base',(0,0,2.68),(0,0,2.74),.13,dark)
rod('Lens',(0,0,2.74),(0,0,2.96),.11,glass)
rod('Weather cap',(0,0,2.96),(0,0,3.01),.15,dark)
for a in [0,math.pi/2,math.pi,math.pi*1.5]:
    x=.14*math.cos(a);y=.14*math.sin(a)
    rod('Lamp guard',(x,y,2.7),(x,y,2.99),.008,steel)
socket((0,0,2.85));export('mast_lantern',2,3.02)
(OUT/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2))
print('LIGHTING_EXPORTED: five reusable fixtures, separate lens and authored aim')
