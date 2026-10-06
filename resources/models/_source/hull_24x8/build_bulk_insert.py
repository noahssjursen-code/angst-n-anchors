"""Individual bulk compartment divider for the 5 x 8 m cargo opening."""
import bpy, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1];OUT=ROOT/'parts/bulk_kit';OUT.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mat(name,c):
    m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
    p.inputs['Metallic'].default_value=.35;p.inputs['Roughness'].default_value=.6
    return m
paint=mat('Warm white painted steel',(.34,.40,.38));steel=mat('Fixed_BulkEdge',(.09,.14,.16))
def box(name,p,s,m):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
# Origin on deck, bottom -2 m, coaming top +.74; no coincident floor/side sheets.
box('Transverse bulkhead',(0,0,-.65),(5,.20,2.7),paint)
box('Hatch meeting seat',(0,0,.72),(5,.24,.04),steel)
for x in [-2,-1,0,1,2]:
    for y in [-.15,.15]:box('Bulkhead stiffener',(x,y,-.65),(.09,.10,2.7),paint)
for name,y in [('HoldForward',2.05),('HoldAft',-2.05)]:
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=(0,y,.70)
bpy.context.scene.unit_settings.system='METRIC'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'bulk_divider_5m.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'bulk_divider_5m.glb'),export_format='GLB',use_selection=True,export_apply=True)
entry={'id':'bulk_divider_5m','style':'bulk_divider','kind':'furniture','model':'res://resources/models/parts/bulk_kit/bulk_divider_5m.glb','start_xz':[0,0],'end_xz':[5,.3],'height_start_m':.74,'height_end_m':.74,'paintable':True}
(OUT/'manifest.json').write_text(json.dumps({'assets':[entry]},indent=2))
draft=json.loads((ROOT/'examples/coastal_cargo_draft.json').read_text())
draft['parts']=[p for p in draft['parts'] if not(p['asset_id']=='hatch_cover_5x4' and p['position'][2]<0)]
draft['parts'].append({'asset_id':'bulk_divider_5m','position':[0,3.6,0],'yaw_degrees':0.0,'colors':{'wall':[.34,.40,.38]}})
draft['hull_colors']['upper']=[.14,.26,.19]
(ROOT/'examples/coastal_bulk_draft.json').write_text(json.dumps(draft,indent=2))
print('BULK_INSERT_EXPORTED',len(draft['parts']))
