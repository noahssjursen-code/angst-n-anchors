"""Independent 32 x 10 m coastal platform and 6 x 12 m hatch kit.

Deck edge geometry is a construction contract, not an interpolated hull outline.
Underwater sections are authored independently of the existing smaller hulls.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[1]
# Reuse asset export helpers, never execute the smaller hull's modeling job.
exec((ROOT/'_source/hull_24x8/build_cargo.py').read_text().split('clear()\nupper=')[0])
OUT=ROOT/'vessels/hull_32x10';OUT.mkdir(parents=True,exist_ok=True)
PARTS=ROOT/'parts/coaster_kit';PARTS.mkdir(parents=True,exist_ok=True)
DECK=4.5
clear()
upper=material('Paint_HullUpper',(.12,.23,.28))
lower=material('Paint_HullLower',(.28,.075,.047))
stripe=material('Fixed_BootStripe',(.045,.055,.061))
deck=material('Paint_Deck',(.32,.36,.35),.12)
paint=material('Warm white painted steel',(.56,.59,.56))
steel=material('Fixed_Galvanized',(.40,.46,.48),.78)
rubber=material('Fixed_Seal',(.025,.03,.03),0)
deck.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.88
image=bpy.data.images.load(str(ROOT/'vessels/trawler_hull_14m/trawler_nonslip_basecolor.png'));image.pack()
tex=deck.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
deck.node_tree.links.new(tex.outputs['Color'],deck.node_tree.nodes['Principled BSDF'].inputs['Base Color'])

STATIONS=[(-16,5),(8,5),(14,2),(16,0)]
def width(y):
    for (a,w),(b,v) in zip(STATIONS,STATIONS[1:]):
        if y<=b:return w+(v-w)*max(0,(y-a)/(b-a))
    return 0

# Broad tank bottom, rounded bilges, nearly vertical topsides; swept/raked stern.
# Top vertices stay precisely at the straight authored deck edge.
cross=[(-1,1),(-.998,.80),(-.985,.60),(-.95,.40),(-.87,.22),(-.72,.10),(-.46,.025),(0,0),(.46,.025),(.72,.10),(.87,.22),(.95,.40),(.985,.60),(.998,.80),(1,1)]
ys=[-16+i*.25 for i in range(129)]
vertices=[]
for y in ys:
    fore=max(0,(y-6)/10)
    aft=max(0,(-y-10)/6)
    # Raised counter leaves a true shaft/propeller aperture below the aft hull.
    bottom=.16+1.05*fore**2+2.8*aft**2
    for x,h in cross:
        # Lower stern withdraws 2.4 m, making space for shaft and rudder.
        yy=y+2.4*aft**2*(1-h)**1.5
        vertices.append((x*width(y),yy,bottom+(DECK-bottom)*h))
k=len(cross);faces=[]
for i in range(len(ys)-1):
    for j in range(k-1):
        a=i*k+j;faces.append((a,a+1,a+k+1,a+k))
# Close the non-planar raised transom in horizontal strips. One large n-gon
# triangulates diagonally across the curved counter and creates shading creases.
for j in range(k//2):
    face=(j,k-1-j,k-2-j,j+1)
    faces.append(tuple(dict.fromkeys(face)))
shell=mesh('Coastal formed shell',vertices,faces,upper)
bm=bmesh.new();bm.from_mesh(shell.data)
for z in [2.55,2.68]:
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,z),plane_no=(0,0,1),dist=.000001)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(shell.data);bm.free()
shell.data.materials.append(lower);shell.data.materials.append(stripe)
for p in shell.data.polygons:
    z=sum(shell.data.vertices[i].co.z for i in p.vertices)/len(p.vertices)
    p.material_index=1 if z<2.55 else (2 if z<2.68 else 0)
    p.use_smooth=len(p.vertices)<=4

# 2 m side decks, real 6 x 12 opening; actual tank top at 1.4 m.
for x in [-4,4]:box('Side working deck',(x,-4,4.44),(2,24,.12),deck)
box('Aft working deck',(0,-11,4.44),(6,10,.12),deck)
box('Fore working deck',(0,7,4.44),(6,2,.12),deck)
mesh('Straight edged foredeck',[(-5,8,DECK),(-2,14,DECK),(0,16,DECK),(2,14,DECK),(5,8,DECK)],[(0,1,2,3,4)],deck)
box('Hold tank top',(0,0,1.34),(6,12,.12),paint)
for x in [-3.06,3.06]:box('Hold side lining',(x,0,2.89),(.12,12,3.10),paint)
for y in [-6.06,6.06]:box('Hold end lining',(0,y,2.89),(6.24,.12,3.10),paint)
# Internal vertical ribs sit on the hold wall rather than floating across the pit.
for x in [-2.94,2.94]:
    for y in [-5,-3,-1,1,3,5]:box('Hold frame',(x,y,2.9),(.12,.09,3.0),paint,.01)
socket('HoldCentre',(0,0,1.4));socket('DeckDatum',(0,-11,DECK))
save('hull_32x10',OUT)
outline=[[-5,16],[-5,-8],[-2,-14],[0,-16],[2,-14],[5,-8],[5,16]]
data={'length_m':32,'beam_m':10,'deck_y':DECK,'outline_xz':outline,'openings_xz':[[[-3,-6],[3,-6],[3,6],[-3,6]]]}
(OUT/'deck_outline.json').write_text(json.dumps(data,indent=2))
for p in outline:assert all(abs(v*2-round(v*2))<1e-8 for v in p)
for a,b in zip(outline,outline[1:]+outline[:1]):
    dx=abs(b[0]-a[0]);dz=abs(b[1]-a[1]);assert dx==0 or dz==0 or abs(dz/dx-1)<1e-8 or abs(dz/dx-2)<1e-8

clear()
for x in [-3.06,3.06]:
    box('Coaming web',(x,0,.35),(.12,12.24,.7),paint)
    box('Cover bearing',(x,0,.71),(.22,12.24,.04),steel)
    for y in range(-5,6,2):box('Coaming bracket',(x*1.04,y,.30),(.16,.10,.60),paint,.008)
for y in [-6.06,6.06]:
    box('Coaming end',(0,y,.35),(6,.12,.70),paint)
    box('Cover bearing',(0,y,.71),(6,.22,.04),steel)
for i,y in enumerate([-4.5,-1.5,1.5,4.5]):socket('CoverSeat'+str(i),(0,y,.74))
save('hold_coaming_6x12',PARTS)

clear()
# Covers meet on an exact 3 m pitch. Small edge radius doesn't change mating size.
box('Hatch top',(0,0,.10),(6.30,3,.20),paint,.006)
for x in [-2.4,-1.2,0,1.2,2.4]:box('Underdeck stiffener',(x,0,-.035),(.10,2.9,.12),steel)
for x in [-3.0,3.0]:box('Compression gasket',(x,0,-.015),(.07,2.96,.03),rubber)
for x in [-2.72,2.72]:
    for y in [-1.15,1.15]:
        box('Lifting eye pad',(x,y,.215),(.25,.2,.03),steel,.008)
        bpy.ops.mesh.primitive_torus_add(major_radius=.075,minor_radius=.018,major_segments=24,minor_segments=10,location=(x,y,.28),rotation=(math.pi/2,0,0))
        bpy.context.object.name='Lifting eye';bpy.context.object.data.materials.append(steel)
socket('LiftPoint',(0,0,.36));save('hatch_cover_6x3',PARTS)
assets=[]
for name,style,size in [('hold_coaming_6x12','cargo_coaming',[6.6,12.24,.74]),('hatch_cover_6x3','cargo_hatch',[6.3,3,.37])]:
    assets.append({'id':name,'style':style,'kind':'furniture','model':'res://resources/models/parts/coaster_kit/'+name+'.glb','start_xz':[0,0],'end_xz':size[:2],'height_start_m':size[2],'height_end_m':size[2],'paintable':True})
(PARTS/'manifest.json').write_text(json.dumps({'units':'metres','assets':assets},indent=2))
print('COASTER_PLATFORM_PASS: exact 32 x 10 deck, 6 x 12 opening, separate coaming/cover')
