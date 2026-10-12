"""Original Norwegian iron perch with viser. Metres, Blender +Z up.
Origin = mean waterline, pointer = +X (also +X after glTF export).
Reference: Kystverket Norwegian coast markings; no third-party geometry.
"""
import bpy, math
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
OUT=HERE.parents[1]/'navigation'
ROOT=HERE.parents[2]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system='METRIC'
m=bpy.data.materials.new('Black painted iron');m.use_nodes=True
n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF')
p.inputs['Metallic'].default_value=.05;p.inputs['Roughness'].default_value=.72
tex=n.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/'textures/marine/Paint004/Paint004_1K-PNG_Color.png'));tex.image.pack()
# Bake the paint tint into pixels: glTF does not export arbitrary MixRGB graphs.
pixels=list(tex.image.pixels[:])
for i in range(0,len(pixels),4):
 for c,tint in enumerate((.025,.03,.033)): pixels[i+c]*=tint
tex.image.pixels[:]=pixels
tex.image.pack()
l.new(tex.outputs['Color'],p.inputs['Base Color'])

r=n.new('ShaderNodeTexImage');r.image=bpy.data.images.load(str(ROOT/'textures/marine/Paint004/Paint004_1K-PNG_Roughness.png'));r.image.colorspace_settings.name='Non-Color';r.image.pack();l.new(r.outputs['Color'],p.inputs['Roughness'])
normal=n.new('ShaderNodeTexImage');normal.image=bpy.data.images.load(str(ROOT/'textures/marine/Paint004/Paint004_1K-PNG_NormalGL.png'));normal.image.colorspace_settings.name='Non-Color';normal.image.pack()
nm=n.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.25;l.new(normal.outputs['Color'],nm.inputs['Color']);l.new(nm.outputs['Normal'],p.inputs['Normal'])

def rod(name,a,b,radius,verts=16):
 a,b=Vector(a),Vector(b);v=b-a
 bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=radius,depth=v.length,location=(a+b)/2)
 ob=bpy.context.object;ob.name=name;ob.rotation_euler=v.to_track_quat('Z','Y').to_euler();ob.data.materials.append(m)
 for f in ob.data.polygons:f.use_smooth=len(f.vertices)==4
 return ob
rod('Iron shaft',(0,0,-5),(0,0,3.2),.065)
rod('Capped pole head',(0,0,3.17),(0,0,3.23),.073)
# User photo: a short flat rectangular viser, horizontal beside the shaft top.
# Its inboard edge overlaps the pole; no diagonal arm or supporting brace.
bpy.ops.mesh.primitive_cube_add(size=1,location=(.14,0,3.02))
o=bpy.context.object;o.name='Rectangular viser';o.dimensions=(.48,.028,.27);o.data.materials.append(m)
for z in [2.94,3.10]:
 rod('Plate fixing bolt',(0,-.032,z),(0,.032,z),.014,6)
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.select_set(False)
# Consolidate the static fitting for inexpensive instances.
for o in bpy.context.scene.objects:
 if o.type=='MESH':o.select_set(True);bpy.context.view_layer.objects.active=o
bpy.ops.object.join();o=bpy.context.object;o.name='Jernstang'
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
s=bpy.data.objects.new('PointerTip',None);bpy.context.collection.objects.link(s);s.location=(.38,0,3.02)
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'jernstang.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'jernstang.glb'),export_format='GLB',export_yup=True)

