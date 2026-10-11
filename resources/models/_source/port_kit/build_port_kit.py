"""Reusable mooring and unloading hardware; metres, Blender +Z up/+Y forward."""
import bpy, math
from mathutils import Vector
from pathlib import Path
HERE=Path(__file__).resolve().parent;OUT=HERE.parents[1]/'parts/port_kit';OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
def mat(n,c,metal=.6):
    m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48;return m
paint=mat('Warm white painted steel',(.14,.22,.23));steel=mat('Fixed_Galvanized',(.47,.53,.55))
dark=mat('Fixed_DarkMetal',(.06,.085,.095));yellow=mat('Paint_Bollard',(.75,.46,.07),.25)
rubber=mat('Fixed_Rubber',(.025,.033,.04),0)
def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def box(n,p,s,m=steel):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    mod=o.modifiers.new('Manufactured edge','BEVEL');mod.width=.012;mod.segments=2
    bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name);return o
def rod(n,a,b,r,m=steel,v=24,r2=None):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=v,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
    for face in o.data.polygons:face.use_smooth=len(face.vertices)==4 and v>=24
    return o
def socket(n,p):
    o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=p
def export(n):
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.object.name=n
    bpy.ops.object.select_all(action='SELECT');bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(n+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(n+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
def mesh_object(n,vertices,faces,m=steel,smooth=False):
    mesh=bpy.data.meshes.new(n);mesh.from_pydata(vertices,[],faces);mesh.update()
    o=bpy.data.objects.new(n,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(m)
    for p in mesh.polygons:p.use_smooth=smooth
    return o
def pipe(n,points,r=.16,m=steel):
    # Round bends as a continuous swept tube, never intersecting capped cylinders.
    src=[Vector(p) for p in points];path=[src[0]]
    for i in range(1,len(src)-1):
        corner=src[i];incoming=corner-src[i-1];outgoing=src[i+1]-corner
        cut=min(.30,incoming.length*.38,outgoing.length*.38)
        a=corner-incoming.normalized()*cut;b=corner+outgoing.normalized()*cut
        path.append(a)
        for j in range(1,9):
            t=j/8;path.append(a*(1-t)**2+corner*(2*t*(1-t))+b*t*t)
    path.append(src[-1]);verts=[];faces=[]
    for i,p in enumerate(path):
        tangent=path[min(i+1,len(path)-1)]-path[max(i-1,0)]
        tangent.normalize();u=tangent.cross(Vector((0,0,1)))
        if u.length<.01:u=tangent.cross(Vector((0,1,0)))
        u.normalize();v=tangent.cross(u)
        for j in range(24):
            a=j*math.tau/24;verts.append(p+r*(math.cos(a)*u+math.sin(a)*v))
    for i in range(len(path)-1):
        for j in range(24):k=i*24+j;l=i*24+(j+1)%24;faces.append((k,l,l+24,k+24))
    mesh_object(n,verts,faces,m,True)
def flange(n,p,axis,r=.25):
    p=Vector(p);d=Vector(axis).normalized();u=d.cross(Vector((0,0,1)))
    if u.length<.01:u=d.cross(Vector((0,1,0)))
    u.normalize();v=d.cross(u)
    rod(n,p-d*.035,p+d*.035,r,steel,48)
    rod('Flange gasket',p-d*.008,p+d*.008,r+.006,dark,48)
    for j in range(8):
        a=j*math.tau/8;q=p+(u*math.cos(a)+v*math.sin(a))*(r-.043)
        rod('Flange bolt',q-d*.055,q+d*.055,.017,steel,6)
def tank_shell():
    # Domed pressure-vessel heads around a horizontal X axis.
    rings=[(-2.3,0.0),(-2.28,.25),(-2.20,.47),(-2.06,.65),(-1.87,.77),(-1.65,.82),
           (1.65,.82),(1.87,.77),(2.06,.65),(2.20,.47),(2.28,.25),(2.3,0.0)]
    verts=[];faces=[]
    for x,r in rings:
        for j in range(64):
            t=j*math.tau/64;verts.append((x-.15,r*math.cos(t),2.05+r*math.sin(t)))
    for i in range(len(rings)-1):
        for j in range(64):k=i*64+j;l=i*64+(j+1)%64;faces.append((k,l,l+64,k+64))
    mesh_object('Dished pressure tank',verts,faces,steel,True)
clear()
box('Bitt foundation',(0,0,.045),(.8,.42,.09),dark)
for x in [-.24,.24]:
    rod('Bitt',(x,0,.09),(x,0,.61),.092,steel)
    rod('Cap',(x,0,.61),(x,0,.65),.13,steel)
rod('Cross horn',(-.45,0,.51),(.45,0,.51),.046,steel)
for x in [-.33,.33]:
    for y in [-.15,.15]:rod('Stud',(x,y,.09),(x,y,.12),.027,steel,6)
socket('RopeAnchor',(0,0,.52));export('deck_double_bitt')
clear()
box('Quay anchor flange',(0,0,.05),(.60,.58,.10),yellow)
rod('Tee neck',(0,0,.10),(0,0,.55),.16,yellow,r2=.12)
box('Tee crown',(0,0,.64),(.60,.29,.20),yellow)
for x in [-.23,.23]:
    for y in [-.21,.21]:
        rod('Anchor washer',(x,y,.102),(x,y,.116),.048,dark)
        rod('Anchor nut',(x,y,.116),(x,y,.155),.032,steel,6)
socket('RopeAnchor',(0,0,.52));export('quay_tee_bollard')
clear()
# Deck-mounted high roller guide, clear of the flat 0.75m wall / 1m railing.
box('Fairlead sole',(0,0,.035),(.25,.66,.07),dark)
for y in [-.25,.25]:
    box('Roller cheek',(0,y,.59),(.105,.08,1.11),steel)
    rod('Bearing',(0,y-.065,1.0),(0,y+.065,1.0),.105,paint,32)
    for x in [-.085,.085]:rod('Deck fastener',(x,y,.07),(x,y,.10),.018,steel,6)
rod('Roller',(0,-.2,1.0),(0,.2,1.0),.075,dark,48)
rod('Upper keeper',(0,-.25,1.24),(0,.25,1.24),.025,steel)
for y in [-.25,.25]:rod('Keeper support',(0,y,1.12),(0,y,1.24),.025,steel)
socket('RopeLead',(0,0,1.12));export('deck_roller_fairlead')
# Four independently reusable assemblies. Retain the existing hose/fill datums.
clear()
for y in [-1.62,1.62]:box('Longitudinal channel',(-.05,y,.62),(7.25,.16,.24),paint)
for x in [-3.6,-1.35,1.05,3.5]:box('Crossmember',(x,0,.62),(.16,3.4,.24),paint)
for x in [-3.1,3.05]:
    rod('Axle',(x,-1.86,.49),(x,1.86,.49),.085,dark)
    for y in [-1.72,1.72]:
        rod('Tyre',(x,y-.15,.49),(x,y+.15,.49),.49,rubber,48)
        rod('Pressed rim',(x,y-.16,.49),(x,y+.16,.49),.28,steel,48)
        for j in range(6):
            t=j*math.tau/6
            rod('Wheel stud',(x+.17*math.cos(t),y-.18,.49+.17*math.sin(t)),(x+.17*math.cos(t),y+.18,.49+.17*math.sin(t)),.022,dark,6)
for x in [-1.35,1.05]:
    box('Saddle foot',(x,0,.79),(.5,2.03,.10),dark)
    # Concave saddle follows the exact tank radius, with a 15mm isolating strip.
    profile=[(-.93,.84),(.93,.84),(.93,1.74)]
    profile += [(y,2.05-math.sqrt(max(0,.835**2-y*y))) for y in [.80-i*.05 for i in range(33)]]
    profile += [(-.93,1.74)]
    n=len(profile);verts=[(xx,y,z) for xx in [x-.16,x+.16] for y,z in profile]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    for i in range(n):j=(i+1)%n;faces.append((i,j,j+n,i+n))
    mesh_object('Profiled saddle',verts,faces,paint)
    for y in [-.88,.88]:
        for xx in [x-.18,x+.18]:rod('Saddle anchor',(xx,y,.84),(xx,y,.90),.03,steel,6)
# Side service grating, with connected supports rather than floating uprights.
for x in [-1.9,-.6,.7,2.0]:box('Walkway bearer',(x,-1.18,.82),(.09,.85,.09),dark)
for i in range(30):box('Grating',( -1.95+i*.14,-1.18,.91),(.045,.7,.035))
for y in [-1.55,-.82]:box('Walkway edge',(.08,y,.9),(4.3,.055,.065))
for x in [-3.45,3.3]:
    for y in [-1.52,1.52]:
        box('Stabilizer pad',(x,y,.035),(.30,.3,.07),dark)
        rod('Adjustable support',(x,y,.07),(x,y,.68),.045,steel)
        rod('Jack collar',(x,y,.35),(x,y,.63),.07,paint)
        rod('Jack handle',(x-.14,y,.7),(x+.14,y,.7),.02,dark)
socket('SeparatorMount',(-.15,0,2.05));export('landing_skid')
clear();tank_shell()
# Circumferential support straps, pressure sensor, access hatch, discharge valve.
for x in [-1.35,1.05]:
    rod('Isolation band',(x-.105,0,2.05),(x+.105,0,2.05),.827,rubber,64)
    rod('Steel retaining strap',(x-.055,0,2.05),(x+.055,0,2.05),.842,steel,64)
rod('Inspection neck',(-.4,.76,2.05),(-.4,.89,2.05),.26)
flange('Inspection flange',(-.4,.91,2.05),(0,1,0),.31)
rod('Inspection cover',(-.4,.94,2.05),(-.4,.975,2.05),.26,paint,48)
rod('Hatch handle',(-.52,1.035,2.05),(-.28,1.035,2.05),.018,dark)
for x in [-.52,-.28]:rod('Handle foot',(x,.975,2.05),(x,1.035,2.05),.018,dark)
pipe('Discharge',[(-2.45,0,2.05),(-3.28,0,2.05),(-3.28,0,1.72)],.18)
flange('Outlet union',(-2.60,0,2.05),(1,0,0),.27)
rod('Valve actuator',(-2.78,0,2.12),(-2.78,0,2.50),.085,paint)
box('Actuator junction',(-2.78,0,2.48),(.20,.18,.14),dark)
rod('Sensor stem',(.35,0,2.83),(.35,0,2.99),.032)
rod('Gauge body',(.35,-.055,3.03),(.35,.055,3.03),.13,dark,48)
rod('Gauge face',(.35,.055,3.03),(.35,.063,3.03),.108,steel,48)
rod('Gauge needle',(.35,.065,3.03),(.29,.065,3.09),.005,dark)
socket('AirPort',(.9,.58,2.63));socket('Inlet',(2.15,0,2.05));export('landing_separator')
clear()
# Main fish path goes directly into the PV tank, not through an electric motor.
pipe('Full bore fish inlet',[(3.72,.82,1.35),(2.85,.82,1.35),(2.85,0,1.35),(2.85,0,2.05),(2.15,0,2.05)],.16)
flange('Hose coupling',(3.67,.82,1.35),(1,0,0),.24)
flange('Inlet union',(2.35,0,2.05),(1,0,0),.24)
rod('Inlet valve actuator',(2.6,0,2.18),(2.6,0,2.55),.075,paint)
box('Motor bed',(1.05,1.25,.84),(1.9,.68,.12),dark)
rod('Electric motor',(.2,1.25,1.16),(1.18,1.25,1.16),.27,paint,48)
for i in range(12):rod('Motor cooling fin',(.24+i*.071,1.25,1.16),(.265+i*.071,1.25,1.16),.30,paint,48)
rod('Ventilated end bell',(.12,1.25,1.16),(.23,1.25,1.16),.29,dark,48)
rod('Guarded coupling',(1.18,1.25,1.16),(1.38,1.25,1.16),.20,dark)
rod('Vacuum unit',(1.38,1.25,1.16),(1.82,1.25,1.16),.32,paint,48)
for x in [.4,1.55]:box('Motor mount',(x,1.25,.98),(.14,.48,.24))
pipe('Vacuum air line',[(1.63,1.25,1.42),(1.63,1.25,2.48),(.9,1.25,2.63),(.9,.58,2.63)],.048,dark)
box('Control cabinet',(1.5,-1.25,1.62),(.82,.44,1.22),paint)
for x in [1.22,1.78]:box('Cabinet support',(x,-1.25,.85),(.065,.065,.35))
box('Cabinet door',(1.5,-1.481,1.62),(.74,.025,1.12))
box('Screen bezel',(1.5,-1.503,1.91),(.49,.02,.30),dark)
box('Screen glass',(1.5,-1.519,1.91),(.43,.012,.24),paint)
for x in [1.27,1.5,1.73]:rod('Control',(x,-1.51,1.54),(x,-1.56,1.54),.032,dark)
rod('Stop collar',(1.5,-1.51,1.32),(1.5,-1.55,1.32),.063,yellow)
red=mat('Fixed_EmergencyStop',(.6,.025,.015),0)
rod('Emergency stop',(1.5,-1.55,1.32),(1.5,-1.60,1.32),.045,red)
pipe('Control conduit',[(1.5,-1.25,1.01),(1.5,-1.25,.78),(1.5,1.25,.78),(1.5,1.25,.9)],.02,dark)
socket('HoseConnection',(3.72,.82,1.35));socket('HoseDeparture',(4.22,.82,1.35));export('landing_pump_drive')
clear()
box('Trough floor',(-3.35,0,1.02),(2.45,2.65,.08),dark)
for y in [-1.32,1.32]:
    box('Folded trough side',(-3.35,y,1.4),(2.55,.05,.78))
    rod('Rolled lip',(-4.63,y,1.8),(-2.07,y,1.8),.03)
box('Trough end',(-4.58,0,1.4),(.05,2.65,.78))
rod('End lip',(-4.58,-1.32,1.8),(-4.58,1.32,1.8),.03)
for x in [-4.35,-2.4]:
    for y in [-1.1,1.1]:
        box('Trough leg',(x,y,.52),(.08,.08,.98))
        box('Trough foot',(x,y,.035),(.2,.2,.07),dark)
    rod('Trough tie',(x,-1.1,.42),(x,1.1,.42),.03)
for i in range(24):box('Dewatering bar',(-4.4+i*.095,0,1.079),(.025,2.42,.025))
socket('FillDatum',(-3.28,0,1.10));export('landing_trough')
print('PORT_KIT_EXPORTED: seven independent Blender/GLB parts, refined PV plant and fairlead')
