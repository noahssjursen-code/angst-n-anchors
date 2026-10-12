"""Original modular Norwegian bridge kit. Run with Blender --background --python.
Metres, Blender +Y along bridge; GLB exports Godot -Z along bridge.
Each GLB is an independent reusable construction part, with applied transforms.
"""
import bpy, math, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'resources/models/bridges'
SRC = ROOT / 'resources/models/_source/bridges'
OUT.mkdir(parents=True, exist_ok=True)
SRC.mkdir(parents=True, exist_ok=True)
materials = {}
for name, color in [('Concrete',(.57,.59,.57,1)),('Asphalt',(.12,.13,.14,1)),('Steel',(.34,.39,.42,1)),('Marking',(.85,.8,.56,1))]:
    m=bpy.data.materials.new(name); m.diffuse_color=color; m.use_nodes=True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.8
    materials[name]=m
def box(name, pos, size, mat, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(materials[mat])
    if bevel:
        mod=o.modifiers.new('Cast edge','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
def begin():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def save(name, length):
    # Preserve individual materials but one mesh per reusable part.
    bpy.ops.object.select_all(action='DESELECT')
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]; bpy.ops.object.join()
    o=bpy.context.object; o.name=name
    bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    for label,y in [('SocketStart',0),('SocketEnd',length)]:
        e=bpy.data.objects.new(label,None); bpy.context.collection.objects.link(e); e.location=(0,y,0)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True)
    assert all(abs(s-1)<1e-6 for s in o.scale)
    assert len(o.data.polygons)>0
begin()
box('Slab',(0,10,-.45),(12,20,.9),'Concrete')
box('WearingCourse',(0,10,.025),(9.4,20,.05),'Asphalt')
for x in [-5.25,5.25]:
    box('Footpath',(x,10,.12),(1.1,20,.24),'Concrete')
    for h in [.65,1.25]:box('Rail',(x+math.copysign(.45,x),10,h),(.09,20,.09),'Steel')
    for y in range(1,20,2):box('RailPost',(x+math.copysign(.45,x),y,.75),(.09,.09,1.25),'Steel')
for x in [-4.4,4.4]:box('EdgeLine',(x,10,.056),(.12,20,.012),'Marking')
for y in [2,7,12,17]:box('CentreLine',(0,y,.056),(.14,3,.012),'Marking')
save('deck_20m',20)
begin();box('Pier',(0,0,.5),(1,1,1),'Concrete',.04);save('pier_unit',0)
begin();box('BearingCap',(0,0,-.5),(10,3,1),'Concrete',.08);save('pier_cap',0)
begin();box('Abutment',(0,0,-.5),(13,5,1),'Concrete',.04);save('abutment_unit',0)
begin()
# Trapezoid closed box, top at deck underside. Unit length/depth are fit by generator.
verts=[(x,y,z) for y in [0,1] for x,z in [(-4.7,0),(4.7,0),(3.3,-1),(-3.3,-1)]]
faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
mesh=bpy.data.meshes.new('BoxGirder');mesh.from_pydata(verts,[],faces);mesh.update()
o=bpy.data.objects.new('BoxGirder',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(materials['Concrete']);save('girder_unit',1)
begin();box('ArchRib',(0,.5,0),(1,1,1),'Concrete',.025);save('arch_rib_unit',1)
begin();box('TowerLeg',(0,0,.5),(1,1,1),'Concrete',.03);save('tower_leg_unit',0)
begin();box('Crossbeam',(0,0,0),(1,1,1),'Concrete',.025);save('tower_crossbeam_unit',0)
begin()
bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=.5,depth=1,location=(0,.5,0),rotation=(math.pi/2,0,0))
o=bpy.context.object;o.data.materials.append(materials['Steel']);save('cable_unit',1)
begin();box('Anchor',(0,0,0),(7,9,5),'Concrete',.3);save('anchor_block',0)
(OUT/'kit.json').write_text(json.dumps({'version':1,'units':'metres','axis':'Godot -Z','deck_length':20,'deck_width':12,'families':['girder','arch','cantilever','suspension'],'source':'Original Blender-authored geometry; finishes use existing SurfaceMaterialLibrary CC0 sources.'},indent=2))
print('BRIDGE KIT PASS: 10 independent Blender/GLB modules')
