"""Rig the new CC0 anatomical mesh to the game's existing animation contract.
Source rig weights are remapped, then the skin is put in a lower A bind pose.
No legacy character geometry is used.
"""
import bpy,json,math,bmesh
from mathutils import Vector,Matrix
from crew_base_skinning import mapped_weights

def build(ref, out, verts, transform, body, objects):
 groups=json.loads((ref/'basemesh_vertex_groups.json').read_text())
 source=json.loads((ref/'rig.default_no_toes.json').read_text())
 def joint(spec):
  if isinstance(spec,str):spec={'strategy':'CUBE','cube_name':spec}
  if spec['strategy']=='CUBE':
   ids=[i for a,b in groups[spec['cube_name']] for i in range(a,b+1)]
  elif spec['strategy']=='VERTEX':ids=[spec['vertex_index']]
  elif spec['strategy']=='MEAN':ids=spec['vertex_indices']
  else:raise ValueError(spec)
  return sum((transform(verts[i]) for i in ids),Vector())/len(ids)
 def src(n,end='head'):return joint(source[n][end])
 def frame(a,b,z):
  y=(b-a).normalized();z=(Vector(z)-y*Vector(z).dot(y)).normalized()
  if z.length<.1:z=y.cross(Vector((1,0,0))).normalized()
  x=y.cross(z).normalized();m=Matrix((x,y,z)).transposed().to_4x4();m.translation=a;return m
 s={};t={};parents={};sz={};tz={}
 def add(n,a,b,parent,ta=None,tb=None,z=(0,1,0),targetz=None):
  s[n]=(Vector(a),Vector(b));t[n]=(Vector(ta) if ta is not None else Vector(a),Vector(tb) if tb is not None else Vector(b));parents[n]=parent;sz[n]=Vector(z);tz[n]=Vector(targetz) if targetz is not None else Vector(z)
 add('root',(0,0,0),(0,0,.15),None)
 add('hips',joint('joint-pelvis'),joint('joint-spine-3'),'root')
 add('spine',joint('joint-spine-3'),joint('joint-spine-1'),'hips')
 add('chest',joint('joint-spine-1'),joint('joint-neck'),'spine')
 add('neck',joint('joint-neck'),joint('joint-head'),'chest')
 add('head',joint('joint-head'),joint('joint-head-2'),'neck')
 for side,sign in [('L',1),('R',-1)]:
  suffix='.'+side
  shoulder=src('upperarm01'+suffix);elbow=src('lowerarm01'+suffix);wrist=src('wrist'+suffix)
  middle=src('finger3-1'+suffix)
  index=src('finger2-1'+suffix);little=src('finger5-1'+suffix)
  dorsal=(index-wrist).cross(little-wrist).normalized()
  if dorsal.z<0:dorsal=-dorsal
  ts=Vector((sign*.21,0,1.415));te=Vector((sign*.32,.005,1.15));tw=Vector((sign*.39,.025,.935));th=tw+Vector((sign*.02,.005,-.115)).normalized()*(middle-wrist).length
  add('clavicle'+suffix,src('clavicle'+suffix),shoulder,'chest',tb=ts)
  add('upper_arm'+suffix,shoulder,elbow,'clavicle'+suffix,ts,te,z=(0,1,0))
  add('forearm'+suffix,elbow,wrist,'upper_arm'+suffix,te,tw,z=(0,1,0))
  add('forearm_twist'+suffix,elbow.lerp(wrist,.68),wrist,'forearm'+suffix,te.lerp(tw,.68),tw,z=(0,1,0))
  add('hand'+suffix,wrist,middle,'forearm_twist'+suffix,tw,th,z=dorsal,targetz=(sign,0,0))
  hm=frame(tw,th,(sign,0,0))@frame(wrist,middle,dorsal).inverted()
  # Preserve new anatomical digit lengths and their natural spread.
  for k,digit in [(2,'index'),(3,'middle'),(4,'ring'),(5,'little')]:
   for j in range(1,4):
    name=f'{digit}_{j:02d}{suffix}';old=f'finger{k}-{j}{suffix}';a=src(old);b=src(old,'tail')
    add(name,a,b,'hand'+suffix if j==1 else f'{digit}_{j-1:02d}{suffix}',hm@a,hm@b,z=dorsal,targetz=(sign,0,0))
  a=src('finger1-1'+suffix);b=src('finger1-2'+suffix,'tail')
  add('thumb_01'+suffix,a,b,'hand'+suffix,hm@a,hm@b,z=dorsal,targetz=(sign,0,0))
  a=src('finger1-3'+suffix);b=src('finger1-3'+suffix,'tail')
  add('thumb_02'+suffix,a,b,'thumb_01'+suffix,hm@a,hm@b,z=dorsal,targetz=(sign,0,0))
  hip=src('upperleg01'+suffix);knee=src('lowerleg01'+suffix);ankle=src('foot'+suffix);toe=src('foot'+suffix,'tail')
  tk=Vector((sign*.11,.02,.51));ta=Vector((sign*.11,0,.12));tt=Vector((sign*.11,.13,.05))
  add('thigh'+suffix,hip,knee,'hips',hip,tk)
  add('shin'+suffix,knee,ankle,'thigh'+suffix,tk,ta)
  add('foot'+suffix,ankle,toe,'shin'+suffix,ta,tt)
 weights=mapped_weights(ref)
 delta={}
 for name,(a,b) in s.items():
  aa,bb=t[name];ratio=(bb-aa).length/(b-a).length
  delta[name]=frame(aa,bb,tz[name])@Matrix.Diagonal((1,ratio,1,1))@frame(a,b,sz[name]).inverted()
 for v in body.data.vertices:
  original=transform(verts[v.index]);p=sum(((delta[n]@original)*w for n,w in weights[v.index].items()),Vector())
  # Ankle contract is 12cm. Keep the newly articulated soles at ground level.
  for side in ['L','R']:
   w=weights[v.index].get('foot.'+side,0)
   if w:p.z+=w*((p.z-.12)*(.12/s['foot.'+side][0].z-1))
  v.co=p
 # Share pronation through the anatomical distal forearm, rather than forcing
 # the complete palm roll through a single narrow wrist ring.
 for v in body.data.vertices:
  for side in ['L','R']:
   n='forearm.'+side;w=weights[v.index].get(n,0)
   if not w:continue
   a,b=t[n];axis=b-a;u=max(0,min(1,((v.co-a).dot(axis)/axis.length_squared-.25)/.70));u=u*u*(3-2*u)
   if u>0:
    weights[v.index][n]=w*(1-u);weights[v.index]['forearm_twist.'+side]=w*u
  strongest=sorted(weights[v.index].items(),key=lambda x:-x[1])[:4];total=sum(w for n,w in strongest)
  weights[v.index]={n:w/total for n,w in strongest if w>1e-7}
 # Reflection in MH Y-up -> Blender Z-up needs outward winding recalculation.
 bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(body.data);bm.free();body.data.update()
 arm=bpy.data.armatures.new('CrewSkeleton');rig=bpy.data.objects.new('CrewRig',arm);bpy.context.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for name,(a,b) in t.items():
  bone=arm.edit_bones.new(name);bone.head=a;bone.tail=b;bone.align_roll(tz[name])
  if parents[name]:bone.parent=arm.edit_bones[parents[name]]
 bpy.ops.object.mode_set(mode='OBJECT')
 # Split only for first-person visibility/hand tools; shared boundaries retain
 # identical source positions and source-authored normalized skin influences.
 categories={'Body':[],'Head':[],'Neck':[],'Hands':[]}
 for poly in body.data.polygons:
  avg={}
  for i in poly.vertices:
   for n,w in weights[i].items():avg[n]=avg.get(n,0)+w/len(poly.vertices)
  hand=sum(w for n,w in avg.items() if n.startswith(('hand.','index_','middle_','ring_','little_','thumb_')))
  name='Hands' if hand>.5 else ('Head' if avg.get('head',0)>.5 else ('Neck' if avg.get('neck',0)>.45 else 'Body'))
  categories[name].append(poly)
 objects.remove(body)
 for name,polys in categories.items():
  ids=sorted({i for poly in polys for i in poly.vertices});lookup={i:j for j,i in enumerate(ids)}
  mesh=bpy.data.meshes.new(name);mesh.from_pydata([body.data.vertices[i].co for i in ids],[],[[lookup[i] for i in poly.vertices] for poly in polys]);mesh.update()
  ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);objects.append(ob);mesh.materials.append(body.data.materials[0]);uv=mesh.uv_layers.new(name='UVMap')
  for p,old in zip(mesh.polygons,polys):
   p.use_smooth=True
   for li,oldli in zip(p.loop_indices,old.loop_indices):uv.data[li].uv=body.data.uv_layers.active.data[oldli].uv
  mesh.normals_split_custom_set_from_vertices([body.data.vertices[i].normal for i in ids])
  for n in t:ob.vertex_groups.new(name=n)
  for i,old in enumerate(ids):
   for n,w in weights[old].items():ob.vertex_groups[n].add([i],w,'REPLACE')
  mod=ob.modifiers.new('Crew skin','ARMATURE');mod.object=rig;ob.parent=rig
 for ob in objects:
  if ob.name.startswith('Body.'):ob.name='Body'
 bpy.data.objects.remove(body,do_unlink=True)
 for ob in objects:
  if ob.name.startswith('Body.'):ob.name='Body'
 for ob in objects:
  if ob.name=='Eyes':
   ob.vertex_groups.new(name='head').add(list(range(len(ob.data.vertices))),1,'REPLACE');mod=ob.modifiers.new('Crew skin','ARMATURE');mod.object=rig;ob.parent=rig
 contacts={}
 hands=next(ob for ob in objects if ob.name=='Hands')
 for side in ['L','R']:
  inv=rig.data.bones['hand.'+side].matrix_local.inverted();points=[inv@v.co for v in hands.data.vertices if v.co.x*(1 if side=='L' else -1)>0]
  # Contact on palmar surface beneath index/middle MCP, not mesh bounding-box.
  candidates=[p for p in points if .035<p.y<.095 and abs(p.x)<.025]
  nearest=sorted(candidates,key=lambda p:p.x*p.x+(p.y-.075)**2)[:8]
  p=min(nearest,key=lambda p:p.z) if nearest else Vector((0,.075,-.018))
  contacts[side]={'palm_contact':list(p),'knuckles_axis':[0,0,1],'fingers_axis':[0,1,0],'morph_deltas':{k:[0,0,0] for k in ['Build','Belly','Frame','Age']}}
 (out/'hand_contacts.json').write_text(json.dumps(contacts,indent=2))
 from crew_base_animation import author
 author(rig,t,out)
 from crew_base_hand_grips import author_grips
 author_grips(rig,contacts,out)
 for tr in rig.animation_data.nla_tracks:tr.mute=False
 rig.animation_data.action=None
 for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.scene.frame_set(0)
 return rig,t
