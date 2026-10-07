"""Reusable operator cab, machinery, slewing platform, foundation and ballast rack. Metres, Blender +Y outreach/+Z up.
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "crane_kit"))
from paint_bake import author_paint, bake_paint, wear_space
OUT=HERE.parents[1]/'parts/provision_station';OUT.mkdir(parents=True,exist_ok=True)
bpy.context.scene.unit_settings.system='METRIC'
def mat(n,c,metal=.3):
    m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48
    return m
paint=mat('Ochre painted steel',(.66,.42,.075));steel=mat('Fixed_DarkSteel',(.065,.085,.10),.65)
author_paint(paint)
glass=mat('Fixed_CabinGlass',(.12,.26,.31),.35);silver=mat('Fixed_PinSteel',(.38,.43,.46),.8)
glass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.28
glass.diffuse_color=(.12,.26,.31,.28);glass.surface_render_method='DITHERED'
def purge_authoring_orphans():
    # Every source blend is standalone; do not carry previous parts' packed maps.
    for mesh in list(bpy.data.meshes):
        if mesh.users==0:bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        if material.users==0 and material not in (paint,steel,glass,silver):bpy.data.materials.remove(material)
    for image in list(bpy.data.images):
        if image.users==0:bpy.data.images.remove(image)

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    purge_authoring_orphans()
def box(n,p,s,m=None):
    if m is None: m=paint
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    if min(s)>.06:
        mod=o.modifiers.new('Fabricated edge radius','BEVEL');mod.width=min(.025,min(s)*.15);mod.segments=1
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o
def rod(n,a,b,r,m=None,verts=32):
    if m is None: m=paint
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.name=n;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
    for poly in o.data.polygons:poly.use_smooth=len(poly.vertices)==4
    return o
def plate(n,outline,thickness,m=None):
    if m is None: m=paint
    normal=(Vector(outline[1])-Vector(outline[0])).cross(Vector(outline[2])-Vector(outline[0])).normalized()
    vs=[tuple(Vector(p)+normal*offset) for offset in [-thickness/2,thickness/2] for p in outline];k=len(outline)
    fs=[tuple(reversed(range(k))),tuple(range(k,2*k))]+[(i,(i+1)%k,(i+1)%k+k,i+k) for i in range(k)]
    data=bpy.data.meshes.new(n);data.from_pydata(vs,[],fs);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    ob=bpy.data.objects.new(n,data);bpy.context.collection.objects.link(ob);data.materials.append(m);return ob
def socket(n,p):
    o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=p;return o
def export(n):
    # One origin-centred mesh per GLB; preserve the existing role-node datums.
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    for o in meshes:
        if paint.node_tree.nodes.get('AuthoredWear'): wear_space(o, paint, o.data.name.startswith('Cylinder'))
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join()
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.context.object.name=n
    bake_paint(bpy.context.object, paint, n, HERE/'textures')
    for material in bpy.context.object.data.materials:
        if material.name.startswith('Paint_Ochre_'):
            if n in ('tower_foundation','counterweight_rack'): material.name='Fixed_Concrete_'+n
            elif n=='operator_cab': material.name='Paint_Enamel_'+n
    purge_authoring_orphans()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/(n+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(n+'.glb')),export_format='GLB',use_selection=True,export_apply=True)

# White enamel shares the worn-paint baker, with an original neutral palette.
for node in paint.node_tree.nodes:
    if node.type=='VALTORGB':
        for e in node.color_ramp.elements:
            c=tuple(e.color[:3])
            if abs(c[0]-.50)<.001 and abs(c[1]-.32)<.001: e.color=(.66,.69,.67,1)
            if abs(c[0]-.63)<.001 and abs(c[1]-.43)<.001: e.color=(.82,.84,.79,1)
clear()
# Cabin bottom and back stay opaque; glazed front extends below the seated eye.
box('Floor',(0,0,.42),(2.15,2.30,.14),steel)
box('Rear bulkhead',(0,-1.10,1.46),(2.10,.10,2.0))
box('Roof overhang',(0,.04,2.55),(2.36,2.64,.14))
for x in [-1.03,1.03]:
    box('Lower side panel',(x,0,.70),(.10,2.25,.42))
    for y in [-1.09,1.09]:box('Corner frame',(x,y,1.52),(.10,.10,2.04))
    box('Window lower frame',(x,0,.97),(.11,2.14,.07),steel)
    box('Window upper frame',(x,0,2.39),(.11,2.14,.07),steel)
    box('Side glazing',(x,0,1.68),(.018,2.08,1.35),glass)
    box('Door vertical seal',(x,.32,1.68),(.12,.026,1.43),steel)
    rod('Door pull',(x*1.075,.45,1.02),(x*1.075,.45,1.30),.018,steel,8)
    for z in [1.08,2.25]:rod('Door hinge',(x*1.07,1.00,z-.055),(x*1.07,1.00,z+.055),.023,steel,8)
box('Front sill',(0,1.09,.64),(2.06,.12,.16))
box('Front gasket',(0,1.10,.78),(2.02,.06,.05),steel)
box('Front upper gasket',(0,1.10,2.39),(2.02,.06,.05),steel)
box('Front glazing',(0,1.10,1.58),(1.96,.018,1.57),glass)
rod('Wiper blade',(-.60,1.14,.96),(.34,1.14,1.55),.013,steel,8)
rod('Wiper arm',(.40,1.15,.80),(-.05,1.15,1.30),.011,steel,8)
# Visible operator furniture; visual equipment only, no added interaction targets.
rod('Seat pedestal',(0,-.25,.5),(0,-.25,.92),.095,steel,12)
box('Seat cushion',(0,-.25,.98),(.57,.61,.13),steel)
back=box('Seat back',(0,-.52,1.33),(.55,.12,.63),steel);back.rotation_euler.x=-.10
for x in [-.42,.42]:
    box('Console side',(x,-.13,.90),(.22,.66,.73),steel)
    box('Arm rest',(x,-.23,1.31),(.20,.45,.07),steel)
    rod('Control lever',(x,.12,1.28),(x,.16,1.42),.018,steel,8)
    box('Control grip',(x,.16,1.44),(.065,.065,.055),steel)
box('Screen bezel',(.68,.61,1.30),(.39,.06,.27),steel)
box('Screen glass',(.68,.575,1.30),(.33,.014,.21),glass)
socket('CabinFloor',(0,0,.49));socket('OperatorEye',(0,-.15,1.9))
export('operator_cab')
# Restore ochre surface recipe for the machinery and platform.
paint=mat('Ochre station paint',(.66,.42,.075));author_paint(paint)
clear()
box('Left machinery cabinet',(-1.77,0,1.18),(1.20,2.22,1.65))
box('Rear electrical cabinet',(-.16,-2.04,1.18),(3.82,1.62,1.65))
# Raised seams, service covers and actual blade depth give the cabinets scale.
for z in [.44,1.92]:box('Rear drip seam',(-.16,-2.89,z),(3.87,.065,.06),steel)
for x in [-1.15,.40]:
    box('Service door',(x,-2.875,1.17),(1.40,.035,1.32))
    box('Door handle',(x+.48,-2.92,1.18),(.045,.04,.22),steel)
    for zz in [.65,1.70]:box('Door hinge',(x-.63,-2.92,zz),(.055,.045,.13),steel)
box('Louvre recess',(-2.385,0,1.22),(.035,1.65,1.12),steel)
for i in range(8):
    o=box('Rain louvre',(-2.42,0,.76+i*.13),(.09,1.57,.055));o.rotation_euler.y=.25
# Twin bearing cheeks visibly connect the unchanged boom pivot to its support.
for x in [-2.26,-1.24]:
    plate('Jib support cheek',[(x,-.7,2.0),(x,.78,2.0),(x,.5,3.88),(x,0,3.88)],.13)
    rod('Pivot bearing boss',(x-.10,.25,3.7),(x+.10,.25,3.7),.22,paint,24)
rod('Jib pivot pin',(-2.43,.25,3.7),(-1.07,.25,3.7),.105,steel,16)
# Fixed conduit follows the cabinet to the support, never floats through space.
for x in [-2.30,-2.20]:
    rod('Conduit riser',(x,-.88,.52),(x,-.88,2.32),.026,steel,8)
    rod('Conduit header',(x,-.88,2.32),(x,.0,2.32),.026,steel,8)
socket('JibPivot',(-1.75,.25,3.7))
export('machinery_station')
clear()
# Slewing ring rests on the tower head. Distinct race bands avoid a solid box.
for z,r,h,m in [(.07,1.36,.14,steel),(.19,1.32,.10,paint),(.28,1.36,.08,steel)]:
    rod('Slew bearing',(0,0,z-h/2),(0,0,z+h/2),r,m,48)
for i in range(24):
    a=i*math.tau/24;x=1.22*math.cos(a);y=1.22*math.sin(a)
    rod('Race bolt',(x,y,.32),(x,y,.37),.026,steel,6)
box('Service deck',(-.55,-1.105,.35),(5.20,5.19,.10),steel)
for y in [-2.8,0.9]:box('Deck cross beam',(-.55,y,.21),(5.2,.12,.20),steel)
# Open rails at the rear and sides; the cab front remains unobstructed.
for x in [-3.12,2.02]:
    for y in [-3.67,-2.38,-1.09,.2,1.49]:rod('Handrail post',(x,y,.40),(x,y,1.48),.025,steel,10)
    for z in [.94,1.48]:rod('Side rail',(x,-3.67,z),(x,1.49,z),.025,steel,10)
    box('Toe board',(x,-1.09,.48),(.035,5.16,.16))
for z in [.94,1.48]:rod('Rear rail',(-3.12,-3.67,z),(2.02,-3.67,z),.025,steel,10)
box('Rear toe board',(-.55,-3.67,.48),(5.14,.035,.16))
socket('TowerHead',(0,0,0))
export('slew_platform')


# Concrete is baked as its own dielectric aggregate finish, not rusty paint.
paint=mat('Cast concrete',(.36,.37,.35),0)
paint['crane_paint']=True
nodes=paint.node_tree.nodes;links=paint.node_tree.links;p=nodes.get('Principled BSDF')
coord=nodes.new('ShaderNodeTexCoord');grain=nodes.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=85
links.new(coord.outputs['Object'],grain.inputs['Vector'])
large=nodes.new('ShaderNodeTexNoise');large.inputs['Scale'].default_value=2.7
links.new(coord.outputs['Object'],large.inputs['Vector'])
ramp=nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.23,.25,.24,1);ramp.color_ramp.elements[1].color=(.49,.49,.43,1)
links.new(large.outputs['Fac'],ramp.inputs[0]);links.new(ramp.outputs[0],p.inputs['Base Color'])
p.inputs['Roughness'].default_value=.91
bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.23;bump.inputs['Distance'].default_value=.008
links.new(grain.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],p.inputs['Normal'])
# The generic export helper only installs edge wear when the recipe has it.
clear()
box('Foundation slab',(0,0,.30),(7,7,.60))
box('Raised tower seat',(0,0,.775),(3.20,3.20,.35))
box('Steel bearing cap',(0,0,.975),(2.72,2.72,.05),steel)
for x in [-1,1]:
    for y in [-1,1]:
        box('Anchor plate',(x,y,.99),(.46,.46,.02),steel)
        for dx in [-.17,.17]:
            for dy in [-.17,.17]:
                rod('Anchor stud',(x+dx,y+dy,.9),(x+dx,y+dy,1.10),.025,steel,8)
                rod('Anchor nut',(x+dx,y+dy,1.01),(x+dx,y+dy,1.065),.045,steel,6)
# Flush shuttering joints and lifting sockets, away from the tower mounting face.
for x in [-2.7,2.7]:
    for y in [-2.7,2.7]:rod('Recess plug',(x,y,.597),(x,y,.602),.065,steel,12)
socket('MastSeat',(0,0,1))
export('tower_foundation')
clear()
box('Ballast cradle',(0,0,.10),(2.48,3.90,.20),steel)
for i in range(6):
    box('Concrete ballast slab',(0,-1.625+i*.65,1.15),(2.32,.625,1.90))
for x in [-1.20,1.20]:
    for y in [-1.7,1.7]:box('Retaining strap',(x,y,1.19),(.09,.14,2.18),steel)
for y in [-1.7,1.7]:
    box('Jib saddle beam',(0,y,2.30),(2.58,.18,.10),steel)
    for x in [-.60,.60]:
        box('Chord clamp',(x,y,2.39),(.27,.25,.08),steel)
        for dx in [-.10,.10]:rod('Clamp bolt',(x+dx,y,2.25),(x+dx,y,2.48),.023,steel,6)
socket('CradleBase',(0,0,0));socket('LowerChord',(0,0,2.35))
export('counterweight_rack')
