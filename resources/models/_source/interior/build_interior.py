import bpy, math, json
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent;OUT=SRC.parent.parent/'parts'/'interior';OUT.mkdir(parents=True,exist_ok=True)
def mat(name,c,metal=0,rough=.45):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;return m
paint=mat('Warm white painted steel',(.54,.61,.61),.3)
top=mat('Paint_Surface',(.055,.075,.085),.15)
seat=mat('Paint_Upholstery',(.065,.11,.14))
metal=mat('Fixed brushed metal',(.38,.43,.46),.8,.25)
rubber=mat('Fixed black grip',(.025,.032,.038))
glass=mat('Fixed screen',(.04,.32,.39),.25,.2)
assets=[]
def scene(aid):
 sc=bpy.data.scenes.new(aid);bpy.context.window.scene=sc;sc.unit_settings.system='METRIC';return sc
def box(name,pos,size,m,bevel=.015):
 bpy.ops.mesh.primitive_cube_add(size=1,location=pos);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
 if bevel:
  mod=o.modifiers.new('Manufactured radius','BEVEL');mod.width=bevel;mod.segments=3;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o
def cyl(name,pos,r,depth,m):
 bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=depth,location=pos);o=bpy.context.object;o.name=name;o.data.materials.append(m)
 for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
 return o
def empty(name,pos):
 o=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(o);o.location=pos;return o
def export(sc,aid,style,kind='furniture',dx=0,run=0,height=1,**extra):
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',use_active_scene=True)
 bpy.data.libraries.write(str(SRC/(aid+'.blend')),{sc},fake_user=True)
 assets.append(dict(id=aid,style=style,kind=kind,model='res://resources/models/parts/interior/'+aid+'.glb',start_xz=[0,0],end_xz=[dx,-run],height_start_m=height,height_end_m=height,paintable=True,**extra))
for side in [1,-1]:
 for code,dx,run in [('straight',0,1),('short',0,.5),('26p',.5,1),('26s',-.5,1),('45p',.5,.5),('45s',-.5,.5)]:
  aid='cabin_console_'+code+('_left' if side<0 else '');sc=scene(aid);length=math.hypot(dx,run)
  # Rear datum is the window wall centreline; cabinet starts at its inner face.
  box('Cabinet', (side*.30,length/2,.40),(.48,length,.78),paint,0)
  box('Continuous worktop',(side*.325,length/2,.825),(.55,length,.05),top,0)
  for o in list(sc.objects):
   basis=o.shape_key_add(name='Basis',from_mix=False)
   for name,end in [('MiterStart',0),('MiterEnd',length)]:
    key=o.shape_key_add(name=name,from_mix=False)
    for i,v in enumerate(basis.data):
     p=o.matrix_world@v.co
     if abs(p.y-end)<1e-5:key.data[i].co.y+=4*p.x
  root=empty('ConsoleModule',(0,0,0))
  for o in list(sc.objects):
   if o!=root:o.parent=root
  root.rotation_euler.z=-math.atan2(dx,run)
  export(sc,aid,'console','console',dx,run,.85,side=side)
def rail_cushion(name,cx,cz,width,height,length,side,radius=.025):
 # Rounded cross-section extruded without rounding its mating end faces.
 profile=[]
 for xc,zc,start in [(cx+width/2-radius,cz+height/2-radius,0),(cx-width/2+radius,cz+height/2-radius,90),(cx-width/2+radius,cz-height/2+radius,180),(cx+width/2-radius,cz-height/2+radius,270)]:
  for step in range(4):
   angle=math.radians(start+step*30)
   profile.append((side*(xc+radius*math.cos(angle)),zc+radius*math.sin(angle)))
 n=len(profile);verts=[(x,y,z) for y in (0,length) for x,z in profile]
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
 o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o);mesh.materials.append(seat)
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT');o.select_set(False)
 return o
for side in [1,-1]:
 variants=[('straight' if i==2 else f'length_{i*50}cm',0,i*.5) for i in range(1,13)]
 variants += [('26p',.5,1),('26s',-.5,1),('45p',.5,.5),('45s',-.5,.5)]
 for code,dx,run in variants:
  aid='cabin_bench_'+code+('_left' if side<0 else '');sc=scene(aid);length=math.hypot(dx,run)
  rail_cushion('Bench seat cushion',.335,.56,.55,.13,length,side)
  rail_cushion('Bench upright back',.11,.92,.12,.65,length,side)
  box('Bench support beam',(side*.33,length/2,.44),(.38,length,.07),metal,0)
  for o in list(sc.objects):
   basis=o.shape_key_add(name='Basis',from_mix=False)
   for name,end in [('MiterStart',0),('MiterEnd',length)]:
    key=o.shape_key_add(name=name,from_mix=False)
    for i,v in enumerate(basis.data):
     pos=o.matrix_world@v.co
     if abs(pos.y-end)<1e-5:key.data[i].co.y+=4*pos.x
  # Feet are set back from joints and never distorted by end miters.
  for j in range(max(1,round(length))):
   y=(j+.5)*length/max(1,round(length))
   cyl('Bench pedestal',(side*.33,y,.23),.04,.40,metal)
   box('Bench foot',(side*.33,y,.035),(.36,.20,.07),metal,.02)
   empty('SeatSocket_'+str(j),(side*.36,y,.625))
  root=empty('BenchModule',(0,0,0))
  for o in list(sc.objects):
   if o!=root and o.parent is None:o.parent=root
  root.rotation_euler.z=-math.atan2(dx,run)
  export(sc,aid,'bench','bench',dx,run,1.245,side=side)

for style in ['helm_chair','passenger_seat']:
 sc=scene(style)
 cyl('Deck foot',(0,0,.035),.22,.07,metal);cyl('Pedestal',(0,0,.28),.055,.49,metal)
 box('Seat cushion',(0,0,.56),(.49,.48,.13),seat,.055)
 box('Back cushion',(0,-.20,.92),(.47,.12,.65),seat,.035)
 if style=='helm_chair':
  for x in [-.29,.29]:
   cyl('Arm support',(x,-.1,.67),.02,.25,metal)
   box('Arm rest',(x,0,.80),(.07,.4,.065),rubber,.028)
  cyl('Footrest hub',(0,0,.2),.09,.06,metal)
  box('Footrest',(0,.20,.20),(.40,.10,.035),metal)
 empty('SeatSocket',(0,0,.61));empty('ExitSocket',(.65,0,0))
 export(sc,style,style,height=1.25)
sc=scene('helm_wheel_base');box('Mount',(0,0,.045),(.22,.22,.09),paint);box('Column support',(0,0,.13),(.08,.10,.20),paint);column=cyl('Column',(0,0,.19),.045,.3,metal);column.rotation_euler.x=math.pi/2
export(sc,'helm_wheel_base','wheel_base',height=.4)
sc=scene('helm_wheel_rotor')
bpy.ops.mesh.primitive_torus_add(major_radius=.20,minor_radius=.017,major_segments=48,minor_segments=10);o=bpy.context.object;o.name='Wheel rim';o.rotation_euler.x=math.pi/2;o.data.materials.append(rubber)
for angle in [0,2*math.pi/3,4*math.pi/3]:
 o=box('Wheel spoke',(math.sin(angle)*.095,0,math.cos(angle)*.095),(.025,.025,.19),metal,.008);o.rotation_euler.y=angle
hub=cyl('Wheel hub',(0,0,0),.045,.055,metal);hub.rotation_euler.x=math.pi/2
export(sc,'helm_wheel_rotor','wheel_rotor',height=.42)
sc=scene('helm_wheel');empty('WheelPivot',(0,-.12,.24));export(sc,'helm_wheel','wheel',height=.48,components=[{'id':'helm_wheel_base','position':[0,0,0]},{'id':'helm_wheel_rotor','pivot':'WheelPivot'}])
sc=scene('helm_throttle_base');box('Throttle housing',(0,0,.05),(.14,.23,.10),paint,.035);export(sc,'helm_throttle_base','throttle_base',height=.1)
sc=scene('helm_throttle_lever');cyl('Lever',(0,0,.08),.013,.16,metal);box('Throttle grip',(0,0,.17),(.09,.045,.045),rubber,.02);export(sc,'helm_throttle_lever','throttle_lever',height=.2)
sc=scene('helm_throttle');empty('ThrottlePivot',(0,0,.10));export(sc,'helm_throttle','throttle',height=.3,components=[{'id':'helm_throttle_base','position':[0,0,0]},{'id':'helm_throttle_lever','pivot':'ThrottlePivot'}])
sc=scene('helm_display');box('Screen stand',(0,0,.035),(.18,.13,.07),metal);box('Display enclosure',(0,.025,.16),(.34,.075,.24),rubber,.018);box('Display glass',(0,-.016,.16),(.30,.006,.20),glass,.008);export(sc,'helm_display','display',height=.28)
json.dump({'units':'metres','console_top_m':.85,'assets':assets},open(OUT/'manifest.json','w'),indent=2)
print('PASS interior Blender exports',len(assets))
