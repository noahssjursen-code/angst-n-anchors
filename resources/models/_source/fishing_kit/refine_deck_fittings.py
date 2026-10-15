"""Fishing deck refinement. Original metre-scale Blender assets, same runtime sockets.
Run after the original kit generators to regenerate this finish pass.
"""
import bpy, math
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]

def material(name, color, metal=0):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color, 1); m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal; p.inputs['Roughness'].default_value = .43
    return m

def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def box(name, at, size, mat, bevel=.008):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    o = bpy.context.object; o.name = name; o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    mod = o.modifiers.new('Manufactured radius', 'BEVEL'); mod.width = bevel; mod.segments = 3
    o.modifiers.new('Face normals', 'WEIGHTED_NORMAL')
    return o

def rod(name, a, b, radius, mat, vertices=32):
    a,b = Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object; o.name=name; o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    o.data.materials.append(mat)
    for f in o.data.polygons: f.use_smooth = len(f.vertices)==4 and vertices>8
    mod=o.modifiers.new('Rounded rim','BEVEL'); mod.width=.003;mod.segments=2
    o.modifiers.new('Face normals','WEIGHTED_NORMAL')
    return o

def socket(name, at):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=at

def ring_points(w,d,r,z):
    pts=[]
    for cx,cy,start in [(w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)]:
        for i in range(9):
            t=math.radians(start+i*90/8);pts.append((cx+r*math.cos(t),cy+r*math.sin(t),z))
    return pts

def shell(name, rings, mat):
    verts=[]; faces=[]
    for w,d,r,z in rings: verts.extend(ring_points(w,d,r,z))
    n=36
    for j in range(len(rings)-1):
        for i in range(n): faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
    for f in mesh.polygons:f.use_smooth=True
    o.modifiers.new('Face normals','WEIGHTED_NORMAL')
    return o

def save(folder,name):
    # Keep meaningful separate editable objects in the source; merge by finish for runtime.
    bpy.context.scene.unit_settings.system='METRIC'
    source=ROOT/'_source'/folder;out=ROOT/'parts'/folder
    bpy.ops.wm.save_as_mainfile(filepath=str(source/(name+'.blend')))
    groups={}
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH':continue
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        groups.setdefault(o.data.materials[0].name,[]).append(o)
    for name2,parts in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();bpy.context.object.name=name2
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(out/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    print('REFINED',folder,name)

clear()
poly=material('Fixed_FishBoxPolymer',(.72,.80,.77))
blue=material('Fixed_FishBoxBlue',(.065,.28,.34))
board=material('Fixed_CuttingBoard',(.82,.84,.72))
steel=material('Fixed_Stainless',(.46,.51,.53),.8)
zinc=material('Fixed_Galvanized',(.37,.43,.45),.75)
dark=material('Fixed_DarkMetal',(.075,.10,.105),.65)
rubber=material('Fixed_Rubber',(.022,.028,.027))
paint=material('Warm white painted steel',(.15,.22,.22),.2)

# A hollow rotationally moulded insulated fish box, rounded body and reinforced rim.
shell('Insulated rounded shell',[(1.28,1.08,.09,.12),(1.36,1.16,.10,.23),(1.40,1.20,.11,.76),
    (1.40,1.20,.11,.83),(1.20,1.00,.08,.83),(1.17,.97,.08,.22),(1.12,.92,.08,.17)],poly)
box('Sealed interior floor',(0,0,.145),(1.18,.98,.09),poly,.04)
shell('Reinforced upper collar',[(1.41,1.21,.11,.74),(1.43,1.23,.11,.79),(1.43,1.23,.11,.83),
    (1.40,1.20,.11,.835)],blue)
for x in [-.49,.49]:
    box('Fork runner',(x,0,.07),(.20,1.12,.14),blue,.035)
for side in [-1,1]:
    for y in [-.33,0,.33]:
        o=box('Vertical moulded strengthening rib',(side*.685,y,.44),(.045,.08,.43),poly,.02)
        o.rotation_euler.y=side*.035
    box('Recessed carry grip shadow',(side*.715,0,.69),(.014,.32,.07),rubber,.015)
    box('Integral carrying lip',(side*.733,0,.74),(.045,.38,.045),blue,.016)
for y in [-.59,.59]:
    box('End reinforcement',(0,y,.43),(.93,.045,.12),poly,.018)
    box('Recessed end label',(0,y*1.035,.60),(.34,.012,.13),blue,.013)
    for x in [-.48,.48]:box('Latch catch',(x,y*1.025,.78),(.07,.025,.09),steel)
rod('Capped cleanout',(.69,0,.25),(.745,0,.25),.042,blue)
rod('Drain cap',(.744,0,.25),(.765,0,.25),.045,poly,12)
socket('PumpConnection',(.92,0,.3));socket('HoseDrop',(.92,0,.3));socket('LidMount',(0,0,.84))
save('fishing_kit','insulated_catch_tank')
clear()
box('Lid gasket',(0,0,-.003),(1.39,1.19,.025),rubber,.065)
box('Moulded insulated lid',(0,0,.035),(1.44,1.24,.075),poly,.055)
box('Recessed lid centre',(0,0,.075),(1.20,1.00,.025),poly,.045)
for y in [-.43,.43]:box('Stacking locator',(0,y,.093),(1.05,.048,.026),blue,.012)
for x in [-.46,.46]:
    box('Grip pocket',(x,0,.094),(.17,.30,.012),blue,.025)
    rod('Flush folding handle',(x,-.09,.115),(x,.09,.115),.014,steel)
    for y in [-.095,.095]:rod('Handle hinge',(x-.025,y,.112),(x+.025,y,.112),.021,steel)
for y in [-.605,.605]:
    for x in [-.48,.48]:box('Over-centre lid latch',(x,y,-.005),(.055,.027,.13),steel)
save('fishing_kit','catch_tank_lid')

clear()
# Compact food-preparation bench: welded frame, washable board, open recessed tray.
for x in [-.46,.46]:
    for y in [-.27,.27]:
        box('Square stainless leg',(x,y,.43),(.045,.045,.82),steel)
        rod('Adjustable foot',(x,y,.025),(x,y,.08),.030,rubber)
    box('Side frame',(x,0,.82),(.045,.58,.06),steel)
for y in [-.27,.27]:box('Longitudinal frame',(0,y,.82),(.96,.045,.06),steel)
box('Under-bench shelf',(0,0,.24),(.95,.56,.028),steel)
for y in [-.275,.275]:box('Shelf rolled edge',(0,y,.267),(.96,.018,.055),steel)
box('Board support',(0,0,.87),(1.1,.7,.035),steel,.016)
box('Replaceable HDPE cutting slab',(.18,0,.905),(.71,.66,.045),board,.016)
for y in [-.25,.25]:
    for x in [-.12,.46]:rod('Flush board fastener',(x,y,.927),(x,y,.929),.006,steel,12)
shell('Removable deep bait pan',[(.32,.53,.035,.89),(.32,.53,.035,.985),(.28,.49,.025,.985),(.26,.47,.025,.905)],steel).location.x=-.35
box('Bait pan bottom',(-.35,0,.90),(.27,.48,.02),steel)
box('Rear splashback',(0,.335,.96),(1.10,.025,.16),steel,.008)
rod('Towel rail',(-.49,-.38,.74),(.49,-.38,.74),.012,steel)
for x in [-.49,.49]:rod('Towel rail bracket',(x,-.27,.74),(x,-.38,.74),.012,steel)
save('coastal_fishing','bait_work_table')

clear()
# Proper fabricated twin bitts with foot collars, rounded caps and anchor hardware.
box('Welded mounting plinth',(0,0,.035),(.82,.44,.07),paint,.025)
for x in [-.24,.24]:
    rod('Weld collar',(x,0,.069),(x,0,.092),.12,dark)
    rod('Bitt barrel',(x,0,.09),(x,0,.56),.088,paint)
    rod('Wear collar',(x,0,.40),(x,0,.49),.09,steel)
    rod('Rounded mushroom cap',(x,0,.555),(x,0,.60),.125,paint)
rod('Line retaining crossbar',(-.45,0,.49),(.45,0,.49),.035,steel)
for x in [-.34,.34]:
    for y in [-.15,.15]:
        rod('Anchor washer',(x,y,.071),(x,y,.078),.033,steel)
        rod('Hex anchor nut',(x,y,.078),(x,y,.096),.022,steel,6)
socket('RopeAnchor',(0,0,.52));save('port_kit','deck_double_bitt')

clear()
# Broad welded cheeks replace the spindly uprights, keeping the rope above the bulwark.
box('Fairlead deck sole',(0,0,.035),(.32,.68,.07),paint,.02)
for y in [-.25,.25]:
    box('Fabricated cheek',(0,y,.53),(.12,.09,.98),paint,.025)
    for x in [-.08,.08]:
        o=box('Base gusset',(x,y,.22),(.035,.15,.36),paint,.006);o.rotation_euler.y=-x*1.5
    rod('Sealed bearing',(0,y-.055,1.0),(0,y+.055,1.0),.115,paint)
    rod('Bearing cover',(0,y+(-.065 if y<0 else .065),1.0),(0,y+(-.073 if y<0 else .073),1.0),.075,steel)
rod('Dark polished roller',(0,-.20,1.0),(0,.20,1.0),.085,dark)
for y in [-.19,.19]:rod('Roller flared rim',(0,y-.012,1.0),(0,y+.012,1.0),.105,steel)
rod('Top keeper',(0,-.25,1.22),(0,.25,1.22),.022,steel)
for y in [-.25,.25]:rod('Keeper upright',(0,y,1.08),(0,y,1.22),.022,steel)
for x in [-.115,.115]:
    for y in [-.26,.26]:rod('Sole nut',(x,y,.07),(x,y,.091),.018,steel,6)
socket('RopeLead',(0,0,1.12));save('port_kit','deck_roller_fairlead')
