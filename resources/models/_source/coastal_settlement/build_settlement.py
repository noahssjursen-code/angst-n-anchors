"""Original reusable Norwegian coastal scenery kit, metres, Blender Z up.
Runtime finishes reuse the approved SurfaceMaterialLibrary. Buildings are closed
scenery shells, not enterable interiors. Near/far geometry share footprint/roof.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parent.parent
OUT = ROOT / 'scenery/coastal_settlement'
OUT.mkdir(parents=True, exist_ok=True)

def material(name, color, rough=.8):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    return m

wall = material('Coastal painted timber', (.70,.70,.64))
trim = material('Coastal window trim', (.83,.82,.72))
roof = material('Coastal standing seam roof', (.10,.12,.12), .65)
base = material('Coastal stone plinth', (.37,.36,.32))
glass = material('Coastal window glass', (.10,.16,.17), .23)
door = material('Coastal timber door', (.16,.22,.21))

def box(name, p, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p)
    o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    return o

def mesh(name, verts, faces, mat):
    data=bpy.data.meshes.new(name); data.from_pydata(verts, [], faces); data.update()
    o=bpy.data.objects.new(name, data); bpy.context.collection.objects.link(o)
    o.data.materials.append(mat); return o

def beam(a, b, width, mat):
    a,b=Vector(a),Vector(b)
    o=box('Joinery', (a+b)/2, (width,width,(b-a).length),mat)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler(); return o

def window(x,y,z,w=1.1,h=1.35, side=False, detailed=True):
    # All panes are slightly proud of the closed wall, with four separate casings.
    def p(a,b,c): return (b,a,c) if side else (a,b,c)
    def s(a,b,c): return (b,a,c) if side else (a,b,c)
    box('Recessed glazing',p(x,y,z),s(w,.045,h),glass)
    if not detailed: return
    for dx in [-w/2-.055,w/2+.055]: box('Window jamb',p(x+dx,y,z),s(.11,.16,h+.20),trim)
    for dz in [-h/2-.045,h/2+.045]: box('Window casing',p(x,y,z+dz),s(w+.22,.17,.11),trim)
    box('Window mullion',p(x,y-.025,z),s(.055,.10,h),trim)
    box('Window transom',p(x,y-.025,z+.10),s(w,.10,.05),trim)
    box('Weather sill',p(x,y-.05,z-h/2-.08),s(w+.26,.25,.06),trim)

def build(kind, detailed):
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    w,d,h,r = {'cottage':(8.6,7.4,3.3,2.8),'house':(8.0,10.2,5.6,2.9),'boathouse':(5.8,9.6,3.4,2.0)}[kind]
    box('Masonry foundation', (0,0,-.35),(w+.08,d+.08,1.4),base)
    box('Timber walls',(0,0,h/2+.30),(w,d,h),wall)
    e=h+.30
    # Full gables under a pitched roof; ridge along the building depth.
    mesh('Gable walls',[(-w/2,-d/2,e),(w/2,-d/2,e),(0,-d/2,e+r),
                       (-w/2,d/2,e),(w/2,d/2,e),(0,d/2,e+r)],
         [(0,2,1),(3,4,5),(0,3,5,2),(2,5,4,1)],wall)
    x=w/2+.35; y=d/2+.42
    mesh('Pitched metal roof',[(-x,-y,e-.12),(0,-y,e+r+.06),(x,-y,e-.12),
                              (-x,y,e-.12),(0,y,e+r+.06),(x,y,e-.12)],
         [(0,1,4,3),(1,2,5,4)],roof)
    for side in [-1,1]:
        beam((side*x,-y,e-.13),(side*x,y,e-.13),.16,trim)
        for edge in [-1,1]: beam((side*x,edge*y,e-.10),(0,edge*y,e+r+.07),.17,trim)
    if detailed:
        # Real board relief at close range; far shell drops the battens entirely.
        for side in [-1,1]:
            for i in range(int(w/.24)+1):
                px=-w/2+.08+i*.24
                top=e+r*(1-abs(px)/(w/2))
                box('Vertical board batten',(px,side*(d/2+.025),(.30+top)/2),(.032,.045,top-.30),wall)
            for i in range(int(d/.24)+1):
                py=-d/2+.08+i*.24
                box('Vertical board batten',(side*(w/2+.025),py,e/2),(.045,.032,e-.30),wall)
        for sx in [-1,1]:
            for sy in [-1,1]:box('Corner casing',(sx*(w/2),sy*(d/2),e/2),(.14,.14,e),trim)
        for sx in [-1,1]:
            box('Rain downpipe',(sx*(w/2+.10),d/2-.16,e/2),(.09,.09,e),roof)
        # Standing roof seams, along roof fall, not oversized corrugated ribs.
        for py in [(-y+.1)+i*.66 for i in range(int(2*y/.66))]:
            for sx in [-1,1]: beam((sx*x,py,e-.1),(0,py,e+r+.075),.025,roof)
    if kind=='boathouse':
        box('Boat doors',(0,-d/2-.06,1.68),(3.65,.09,2.75),door)
        if detailed:
            for px in [-1.88,0,1.88]: box('Boat door post',(px,-d/2-.12,1.7),(.12,.14,2.9),trim)
            box('Door lintel',(0,-d/2-.12,3.13),(3.9,.14,.16),trim)
            for sign in [-1,1]: beam((.06*sign,-d/2-.13,.43),(1.76*sign,-d/2-.13,2.99),.095,trim)
        window(0,-d/2-.08,e+.65,.7,.7,detailed=detailed)
        for py in [-1.6,1.6]: window(py,w/2+.08,2.1,.72,.9,True,detailed)
    else:
        box('Entrance door',(0,-d/2-.07,1.36),(1.02,.10,2.12),door)
        for px in [-2.55,2.55]: window(px,-d/2-.08,1.98,detailed=detailed)
        for py in [-2.25,1.55]:
            for sx in [-1,1]: window(py,sx*(w/2+.08),2.0,side=True,detailed=detailed)
        for px in [-2.25,2.25]: window(px,d/2+.08,2.0,detailed=detailed)
        if kind=='house':
            for px in [-2.45,0,2.45]: window(px,-d/2-.08,4.55,detailed=detailed)
            for py in [-2.25,1.55]:
                for sx in [-1,1]: window(py,sx*(w/2+.08),4.55,side=True,detailed=detailed)
        window(0,-d/2-.09,e+.7,.8,1.0,detailed=detailed)
        box('Chimney',(w*.22,d*.16,e+r-.2),(.70,.72,2.3),base)
        if detailed:
            box('Chimney cap',(w*.22,d*.16,e+r+.99),(.9,.92,.16),roof)
            for i in range(3): box('Entry steps',(0,-d/2-.33-i*.26,.27-i*.09),(1.65,.30,.15+i*.18),base)
            for px in [-.70,.70]:box('Porch post',(px,-d/2-.8,1.38),(.10,.1,2.2),trim)
            o=box('Door canopy',(0,-d/2-.44,2.58),(1.9,1.35,.10),roof);o.rotation_euler.x=math.radians(-8)
    aid=kind+('_near' if detailed else '_far')
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active=bpy.context.selected_objects[0]
    bpy.ops.object.join(); o=bpy.context.object; o.name=aid
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(aid+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',
        use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT')
    return {'id':aid,'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)}

manifest=[build(kind,near) for kind in ['cottage','house','boathouse'] for near in [True,False]]
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('COASTAL BUILDING KIT',manifest)
