"""Individual reusable floor/roof triangular infill and perimeter profiles.
All source meshes authored in Blender; game only selects/places imported assets.
"""
import bpy, json, itertools, math
from pathlib import Path
SRC=Path(__file__).resolve().parent
OUT=SRC.parent.parent/'parts'/'surface_tiles'; OUT.mkdir(parents=True,exist_ok=True)
points=[(0,0),(.25,0),(.5,0),(.5,.25),(.5,.5),(.25,.5),(0,.5),(0,.25)]
def mat(name,c):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=.25;p.inputs['Roughness'].default_value=.48
 return m
mats=[mat('Paint_Surface',(.48,.55,.55)),mat('Paint_Fascia',(.74,.78,.75)),mat('Paint_Underside',(.74,.78,.75))]
assets=[]
def uv_map(mesh):
 uv=mesh.uv_layers.new(name='UVMap')
 for face in mesh.polygons:
  axis=max(range(3),key=lambda i:abs(face.normal[i]))
  dims=[i for i in range(3) if i!=axis]
  for loop_id in face.loop_indices:
   co=mesh.vertices[mesh.loops[loop_id].vertex_index].co
   uv.data[loop_id].uv=(co[dims[0]],co[dims[1]])

def export(aid,style,poly,low,high):
 scene=bpy.data.scenes.new(aid);bpy.context.window.scene=scene;scene.unit_settings.system='METRIC'
 # Input coordinates are Godot XZ; Blender Y=-Z.
 n=len(poly); verts=[(x,-z,y) for y in (low,high) for x,z in poly]
 faces=[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 mesh=bpy.data.meshes.new(aid);mesh.from_pydata(verts,[],faces);mesh.update()
 o=bpy.data.objects.new(aid,mesh);scene.collection.objects.link(o)
 for m in mats:mesh.materials.append(m)
 mesh.polygons[0].material_index=2;mesh.polygons[1].material_index=0
 for f in list(mesh.polygons)[2:]:f.material_index=1
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 if style=='roof':
  bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.subdivide(number_cuts=7);bpy.ops.object.mode_set(mode='OBJECT')
  for face in mesh.polygons:
   if face.normal.z>.99:face.use_smooth=True
  basis=o.shape_key_add(name='Basis',from_mix=False)
  for name,power in [('Crown0',0),('CrownX',1),('CrownXX',2)]:
   key=o.shape_key_add(name=name,from_mix=False)
   for i,v in enumerate(basis.data):
    key.data[i].co.z+=(v.co.x**power)*max(0,v.co.z/high)
 uv_map(mesh)
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',use_active_scene=True)
 bpy.data.libraries.write(str(SRC/(aid+'.blend')),{scene},fake_user=True)
 assets.append(dict(id=aid,style=style,kind='surface',model='res://resources/models/parts/surface_tiles/'+aid+'.glb',start_xz=[0,0],end_xz=[.5,.5],height_start_m=.1,height_end_m=.1,paintable=True))
for style in ['floor','roof']:
 low,high=(-.1,0) if style=='floor' else (0,.1)
 export(style+'_tile',style,[(0,0),(.5,0),(.5,.5),(0,.5)],low,high)
 for ids in itertools.combinations(range(8),3):
  a,b,c=[points[i] for i in ids]
  area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
  if abs(area)<1e-8:continue
  export(style+'_tri_'+'_'.join(map(str,ids)),style,[a,b,c],low,high)
# Authored eave profiles, with end-only miter keys, like the wall kit.
for code,length in [('straight',.5),('45',math.sqrt(.5)),('26',math.sqrt(1.25))]:
 aid='roof_edge_'+code;scene=bpy.data.scenes.new(aid);bpy.context.window.scene=scene
 # X outward; Godot +Z along edge; fascia bevel only on exposed outer rim.
 profile=[(0,0),(.15,0),(.15,.085),(.135,.1),(0,.1)]
 verts=[(x,-z,y) for z in (0,length) for x,y in profile];n=len(profile)
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n)]
 mesh=bpy.data.meshes.new(aid);mesh.from_pydata(verts,[],faces);mesh.update()
 o=bpy.data.objects.new(aid,mesh);scene.collection.objects.link(o)
 for m in mats:mesh.materials.append(m)
 for f in mesh.polygons:f.material_index=1
 mesh.polygons[2].material_index=2;mesh.polygons[5].material_index=0
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.subdivide(number_cuts=7);bpy.ops.object.mode_set(mode='OBJECT')
 for face in mesh.polygons:
  if face.normal.z>.99:face.use_smooth=True
 basis=o.shape_key_add(name='Basis',from_mix=False)
 for name,end in [('MiterStart',0),('MiterEnd',-length)]:
  key=o.shape_key_add(name=name,from_mix=False)
  for i,v in enumerate(basis.data):
   key.data[i].co.y-=4*v.co.x*((1+v.co.y/length) if name=='MiterStart' else -v.co.y/length)
 for xp in range(3):
  for zp in range(3):
   key=o.shape_key_add(name=f'Crown{xp}{zp}',from_mix=False)
   for i,v in enumerate(basis.data):key.data[i].co.z+=(v.co.x**xp)*((-v.co.y)**zp)*max(0,v.co.z/.1)
 uv_map(mesh)
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',use_active_scene=True)
 bpy.data.libraries.write(str(SRC/(aid+'.blend')),{scene},fake_user=True)
 assets.append(dict(id=aid,style='roof',kind='surface_edge',model='res://resources/models/parts/surface_tiles/'+aid+'.glb',start_xz=[0,0],end_xz=[0,length],height_start_m=.1,height_end_m=.1,paintable=True))
json.dump({'cell_m':.5,'thickness_m':.1,'points_xz':points,'assets':assets},open(OUT/'manifest.json','w'),indent=2)
print('PASS exported',len(assets),'Blender floor/roof modules')
