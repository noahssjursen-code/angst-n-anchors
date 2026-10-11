"""Structural wheelhouse kit. Individual Blender sources; metres, +Y forward.
Continuous 100 mm skins with Blender-authored end shear shape keys.
Godot sets the two key weights from adjacent wall directions for matching miters.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
OUT=SRC.parent.parent/'parts'/'wheelhouse'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def mat(name,color,metal=0,rough=.4):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 return m
paint=mat('Warm white painted steel',(.74,.78,.75),.25)
frame=mat('Fixed anodized window frame',(.18,.23,.25),.7,.3)
rubber=mat('Fixed glazing gasket',(.025,.035,.035),0,.75)
glass=mat('Fixed wheelhouse glass',(.28,.48,.52),.1,.15)
p=glass.node_tree.nodes.get('Principled BSDF');p.inputs['Alpha'].default_value=.32
glass.diffuse_color=(.28,.48,.52,.32);glass.surface_render_method='DITHERED'
steel=mat('Fixed door hardware',(.48,.53,.55),.8,.3)
assets=[]
def box(name,x,y,z,sx,sy,sz,material,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=(x,y,z));o=bpy.context.object;o.name=name;o.dimensions=(sx,sy,sz)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
 if bevel:
  mod=o.modifiers.new('Manufactured edge radius','BEVEL');mod.width=bevel;mod.segments=3;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o

def socket(name,pos):
 o=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(o);o.location=pos;return o

def build(style,code,dx,run):
 aid=f'cabin_{style}_{code}';scene=bpy.data.scenes.new(aid);bpy.context.window.scene=scene;scene.unit_settings.system='METRIC'
 length=math.hypot(dx,run);lo=0;hi=length
 if style=='wall':box('Steel wall panel',0,length/2,1.1,.10,hi-lo,2.2,paint)
 else:
  width=.82 if style=='door' else max(.26,length-.22)
  sill=0 if style=='door' else .95
  head=2.0 if style=='door' else 2.05
  left=(length-width)/2;right=(length+width)/2
  box('Wall left jamb',0,(lo+left)/2,1.1,.10,left-lo,2.2,paint)
  box('Wall right jamb',0,(right+hi)/2,1.1,.10,hi-right,2.2,paint)
  box('Wall header',0,length/2,(head+2.2)/2,.10,width,2.2-head,paint)
  if sill:box('Wall below window',0,length/2,sill/2,.10,width,sill,paint)
  if style=='window':
   for y in [left+.022,right-.022]:box('Window frame upright',0,y,(sill+head)/2,.13,.044,head-sill,frame,.006)
   for z in [sill+.022,head-.022]:box('Window frame horizontal',0,length/2,z,.13,width,.044,frame,.006)
   for y in [left+.05,right-.05]:box('Rubber gasket upright',0,y,(sill+head)/2,.075,.018,head-sill-.08,rubber,.003)
   for z in [sill+.05,head-.05]:box('Rubber gasket horizontal',0,length/2,z,.075,width-.08,.018,rubber,.003)
   box('Transparent glazing',0,length/2,(sill+head)/2,.018,width-.11,head-sill-.11,glass)
  else:
   # Leaf is separate from its real opening, with a hinge pivot for inspection.
   pivot=socket('DoorLeafPivot',(0,left+.015,0));before=set(scene.objects)
   box('Door leaf',0,length/2,1.0,.055,width-.03,1.97,paint,.012)
   for side in [-1,1]:
    box('Lever handle mount',side*.04,right-.11,1.03,.026,.035,.17,steel,.008)
    box('Lever handle',side*.068,right-.16,1.07,.025,.14,.025,steel,.008)
   for z in [.25,1,1.75]:box('Door hinge',.06,left+.025,z,.04,.045,.10,steel,.008)
   for o in set(scene.objects)-before:
    o.parent=pivot;o.location-=pivot.location
 # Author end-only deformation in Blender; never stretch windows or door hardware.
 for o in list(scene.objects):
  if o.type!='MESH' or not (o.name.startswith('Wall ') or o.name.startswith('Steel wall')):continue
  basis=o.shape_key_add(name='Basis',from_mix=False)
  base_coords=[v.co.copy() for v in basis.data]
  for name,endpoint in [('MiterStart',0),('MiterEnd',length)]:
   key=o.shape_key_add(name=name,from_mix=False)
   for index,co in enumerate(base_coords):
    key.data[index].co=co
    p=o.matrix_world @ co
    if abs(p.y-endpoint)<1e-5:key.data[index].co.y += 4*p.x
 root=socket('Module',(0,0,0));angle=-math.atan2(dx,run)
 for o in list(scene.objects):
  if o!=root and o.parent is None:o.parent=root
 root.rotation_euler.z=angle
 socket('SocketStart',(0,0,0));socket('SocketEnd',(dx,run,0))
 export(scene,aid,style,dx,run)

def export(scene,aid,style,dx,run):
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,export_apply=True)
 bpy.data.libraries.write(str(SRC/(aid+'.blend')),{scene},fake_user=True)
 assets.append(dict(id=aid,style=style,kind='structure',model='res://resources/models/parts/wheelhouse/'+aid+'.glb',start_xz=[0,0],end_xz=[dx,-run],height_start_m=2.2,height_end_m=2.2,angle_deg=math.degrees(math.atan2(abs(dx),run)),paintable=True))

for style in ['wall','window','door']:
 variants=[('straight',0,1),('26_port',.5,1),('26_starboard',-.5,1)]
 if style!='door':variants += [('short',0,.5),('45_port',.5,.5),('45_starboard',-.5,.5)]
 else:variants += [('45_port',1,1),('45_starboard',-1,1)]
 for code,dx,run in variants:build(style,code,dx,run)
json.dump({'units':'metres','wall_height_m':2.2,'thickness_m':.1,'end_shear_key_amplitude':4,'joint_style':'matching_miter','door_clear_width_m':.82,'door_clear_height_m':2,'window_sill_m':.95,'assets':assets},open(OUT/'manifest.json','w'),indent=2)
print('PASS: exported',len(assets),'individual structural Blender models')
