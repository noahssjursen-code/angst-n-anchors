"""24 x 8 m platform and separate lift-away hatch components. Blender metres.
Design reference: Damen Combi Freighter arrangement / MacGregor lift-away covers.
This is a compact game platform, not a scaled or certified copy of either vessel.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[1]
OUT=ROOT/'vessels'/'hull_24x8';OUT.mkdir(parents=True,exist_ok=True)
PARTS=ROOT/'parts'/'cargo_kit';PARTS.mkdir(parents=True,exist_ok=True)

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def material(name,c,metal=.35):
    m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.55
    return m
def mesh(name,vs,fs,mat):
    d=bpy.data.meshes.new(name);d.from_pydata(vs,[],fs);d.update()
    bm=bmesh.new();bm.from_mesh(d);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(d);bm.free()
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(mat)
    uv=d.uv_layers.new(name='UVMap')
    for p in d.polygons:
        for li in p.loop_indices:
            v=d.vertices[d.loops[li].vertex_index].co;uv.data[li].uv=(v.y/24,v.z/4)
    return o
def box(name,p,s,m,bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    if bevel:
        b=o.modifiers.new('Edge radius','BEVEL');b.width=bevel;b.segments=2
        o.modifiers.new('Normals','WEIGHTED_NORMAL')
    return o
def socket(name,p):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=p
def save(name,folder):
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(folder/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
clear()
upper=material('Paint_HullUpper',(.16,.26,.30));lower=material('Paint_HullLower',(.33,.09,.06))
deck=material('Paint_Deck',(.29,.34,.35));paint=material('Warm white painted steel',(.40,.46,.44))
steel=material('Fixed_Galvanized',(.40,.46,.48),.8);rubber=material('Fixed_Seal',(.025,.03,.03),0)
# Share the accepted neutral nonslip texture; deck paint stays an independent tint.
texture=bpy.data.images.load(str(ROOT/'vessels/trawler_hull_14m/trawler_nonslip_basecolor.png'))
texture.pack()
node=deck.node_tree.nodes.new('ShaderNodeTexImage');node.image=texture
deck.node_tree.links.new(node.outputs['Color'],deck.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
# Fixed straight deck corners, 2:1 then 1:1 bow. Subdivision only below deck.
stations=[(-12,4),(6,4),(10,2),(12,0)]
def width(y):
    for (a,w),(b,v) in zip(stations,stations[1:]):
        if y<=b:return w+(v-w)*max(0,(y-a)/(b-a))
    return 0
ys=sorted(set([-12+i*.25 for i in range(97)]+[6,10,12]))
cross=[(-1,1),(-.99,.73),(-.94,.48),(-.8,.20),(-.5,.04),(0,0),(.5,.04),(.8,.20),(.94,.48),(.99,.73),(1,1)]
vs=[]
for y in ys:
    rise=.14+.65*max(0,(y-5)/7)**2+.18*max(0,(-y-8)/4)**2
    vs.extend([(x*width(y),y,rise+(3.6-rise)*h) for x,h in cross])
k=len(cross);fs=[]
for i in range(len(ys)-1):
    for j in range(k-1):
        a=i*k+j;fs.append((a,a+1,a+k+1,a+k))
fs += [tuple(range(k-1,-1,-1)),tuple((len(ys)-1)*k+j for j in range(k))]
shell=mesh('Formed steel hull',vs,fs,upper)
bm=bmesh.new();bm.from_mesh(shell.data)
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,2),plane_no=(0,0,1),dist=.000001)
bm.to_mesh(shell.data);bm.free();shell.data.materials.append(lower)
for p in shell.data.polygons:
    p.material_index=int(sum(shell.data.vertices[i].co.z for i in p.vertices)/len(p.vertices)<2)
    p.use_smooth=True
# REAL 5 x 8 m opening; no invisible deck under the lift-away covers.
for name,x,y,sx,sy in [('Port deck',-3.25,0,1.5,24),('Starboard deck',3.25,0,1.5,24)]:
    # Rectangles end at the bow shoulder; bow is a separate polygon below.
    box(name,(x,-3,3.55),(sx,18,.1),deck)
box('Aft deck',(0,-8,3.55),(5,8,.1),deck)
box('Fore deck',(0,5,3.55),(5,2,.1),deck)
mesh('Bow deck',[(-4,6,3.6),(-2,10,3.6),(0,12,3.6),(2,10,3.6),(4,6,3.6)],[(0,1,2,3,4)],deck)
box('Hold tank top',(0,0,1.55),(5,8,.1),paint)
for x in [-2.55,2.55]:box('Hold side lining',(x,0,2.55),(.1,8,2),paint)
for y in [-4.05,4.05]:box('Hold end lining',(0,y,2.55),(5.2,.1,2),paint)
socket('HoldCentre',(0,0,1.6));save('hull_24x8',OUT)
outline=[[-4,12],[-4,-6],[-2,-10],[0,-12],[2,-10],[4,-6],[4,12]]
(OUT/'deck_outline.json').write_text(json.dumps({'length_m':24,'beam_m':8,'deck_y':3.6,'outline_xz':outline,'openings_xz':[[[-2.5,-4],[2.5,-4],[2.5,4],[-2.5,4]]]},indent=2))
clear()
for x in [-2.56,2.56]:
    box('Coaming side',(x,0,.35),(.12,8.24,.7),paint)
    box('Seal seat',(x,0,.71),(.20,8.24,.04),steel)
for y in [-4.06,4.06]:
    box('Coaming end',(0,y,.35),(5,.12,.7),paint)
    box('Seal seat',(0,y,.71),(5,.20,.04),steel)
for x in [-2.65,2.65]:
    for y in [-3,-1,1,3]:box('External stiffener',(x,y,.29),(.12,.10,.58),paint)
socket('CoverForward',(0,2,.74));socket('CoverAft',(0,-2,.74));save('hold_coaming_5x8',PARTS)
clear();box('Lift away cover',(0,0,.10),(5.28,4,.2),paint,.006)
for x in [-1.8,0,1.8]:box('Underside beam',(x,0,-.035),(.10,3.9,.12),steel)
for x in [-2.35,2.35]:
    for y in [-1.65,1.65]:
        # Recess-free robust lifting eyes with actual openings.
        bpy.ops.mesh.primitive_torus_add(major_radius=.075,minor_radius=.017,major_segments=24,minor_segments=10,location=(x,y,.24),rotation=(math.pi/2,0,0))
        bpy.context.object.name='Lifting eye';bpy.context.object.data.materials.append(steel)
socket('LiftPoint',(0,0,.32));save('hatch_cover_5x4',PARTS)
assets=[]
for name,style,size in [('hold_coaming_5x8','cargo_coaming',[5.44,8.24,.74]),('hatch_cover_5x4','cargo_hatch',[5.28,4,.32])]:
    assets.append({'id':name,'style':style,'kind':'furniture','model':'res://resources/models/parts/cargo_kit/'+name+'.glb','start_xz':[0,0],'end_xz':size[:2],'height_start_m':size[2],'height_end_m':size[2],'paintable':True})
(PARTS/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2))
print('CARGO_PLATFORM_EXPORTED')
