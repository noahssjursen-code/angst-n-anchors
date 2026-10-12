"""Species-specific fish meshes and authored skin textures, built in Blender.
Reference anatomy: IMR species photographs. Original geometry and texture pixels;
reference photographs are not distributed or projected onto the models.
1 metre from tail to snout. 3-bone swimming rig. Blender Z up, head +X.
"""
import bpy, math, random
import numpy as np
from pathlib import Path
from mathutils import Vector
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'fishing_items'
OUT.mkdir(parents=True,exist_ok=True)

def mat(name,c,rough=.52,metal=.0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 return m

def obj(name,v,f,m):
 me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(m)
 for face in me.polygons:face.use_smooth=True
 return o

def path(name,pts,r,m):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=2
 s=c.splines.new('POLY');s.points.add(len(pts)-1)
 for p,co in zip(s.points,pts):p.co=(*co,1)
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.data.materials.append(m);return o

def sphere(name,p,r,scale,m):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=r,location=p)
 o=bpy.context.object;o.name=name;o.scale=scale;o.data.materials.append(m)
 for face in o.data.polygons:face.use_smooth=True
 return o

def smooth(p,t):
 # Cubic interpolated anatomical profiles; no conical tube / stretched sphere.
 k=min(len(p)-2,int(t));f=t-k
 a=np.array(p[max(0,k-1)]);b=np.array(p[k]);c=np.array(p[k+1]);d=np.array(p[min(len(p)-1,k+2)])
 return .5*((2*b)+(-a+c)*f+(2*a-5*b+4*c-d)*f*f+(-a+3*b-3*c+d)*f*f*f)

profiles={
'cod':[(-.39,.018,.026,.0),(-.29,.037,.047,.0),(-.15,.060,.080,.0),(.0,.079,.108,.003),(.15,.087,.123,.008),(.25,.074,.105,.014),(.33,.057,.079,.009),(.405,.035,.047,-.006),(.45,.024,.025,-.01)],
'pollack':[(-.40,.018,.026,0),(-.29,.030,.052,0),(-.13,.049,.083,0),(.03,.065,.102,.005),(.17,.065,.107,.009),(.28,.058,.089,.005),(.36,.040,.058,-.007),(.425,.022,.026,-.020),(.45,.016,.012,-.022)],
'saithe':[(-.40,.018,.032,0),(-.29,.029,.053,0),(-.14,.05,.083,0),(.03,.071,.105,0),(.17,.071,.103,.003),(.28,.059,.085,0),(.36,.038,.054,-.008),(.43,.022,.027,-.014),(.45,.015,.015,-.017)],
'haddock':[(-.40,.018,.025,0),(-.29,.032,.045,0),(-.15,.052,.075,0),(.0,.073,.105,0),(.15,.080,.123,.0),(.25,.066,.116,-.001),(.33,.047,.084,-.013),(.405,.027,.045,-.028),(.45,.014,.020,-.035)],
'mackerel':[(-.40,.012,.018,0),(-.32,.020,.031,0),(-.18,.036,.059,0),(-.02,.054,.080,0),(.13,.060,.087,0),(.25,.053,.079,0),(.34,.038,.06,-.002),(.425,.018,.03,-.005),(.45,.007,.013,-.005)],
'halibut':[(-.40,.023,.012,0),(-.29,.085,.022,0),(-.15,.170,.036,0),(.0,.205,.043,0),(.15,.174,.043,0),(.25,.127,.037,0),(.33,.082,.027,0),(.40,.048,.02,-.005),(.45,.018,.012,-.007)]}
colors={
'cod':[(.145,.12,.055),(.46,.37,.18),(.72,.68,.52)],
'pollack':[(.085,.13,.105),(.41,.40,.22),(.75,.74,.62)],
'saithe':[(.035,.066,.075),(.19,.28,.29),(.72,.75,.72)],
'haddock':[(.10,.12,.145),(.43,.45,.44),(.74,.74,.68)],
'mackerel':[(.02,.16,.18),(.18,.39,.39),(.76,.8,.77)],
'halibut':[(.17,.15,.105),(.20,.18,.13),(.76,.74,.66)]}

def skin(kind):
 W,H=1024,512
 u,v=np.meshgrid(np.linspace(0,1,W),np.linspace(0,1,H));z=np.sin(v*math.tau)
 top,side,belly=[np.array(c) for c in colors[kind]]
 if kind=='halibut':
  upper=np.clip(z*12+.5,0,1)[...,None];rgb=belly[None,None,:]*(1-upper)+top[None,None,:]*upper
 else:
  upper=np.clip((z-.08)/.92,0,1)[...,None];lower=np.clip((-z-.30)/.7,0,1)[...,None]
  rgb=side[None,None,:]*(1-upper)+top[None,None,:]*upper
  rgb=rgb*(1-lower)+belly[None,None,:]*lower
 rng=np.random.default_rng(107+len(kind))
 noise=np.zeros((H,W))
 # Smooth, irregular mottling at several spatial scales.
 for _ in range(18):
  fx,fy=rng.uniform(8,90),rng.uniform(8,55);phase=rng.uniform(0,6.28)
  noise+=np.sin(u*fx+np.sin(v*fy)*1.7+phase)/18
 if kind in ['cod','halibut']:
  patches=np.clip((noise+.08)*4,0,1)
  rgb*=1-(patches*(.19 if kind=='cod' else .42))[...,None]
  # Cod is peppered with irregular dark spots, rather than broad tiger bands.
  spots=np.zeros((H,W))
  for _ in range(240 if kind=='cod' else 75):
   cx,cy=rng.uniform(.04,.96),rng.uniform(0,1)
   rx,ry=rng.uniform(.002,.009),rng.uniform(.005,.016)
   spots=np.maximum(spots,np.exp(-(((u-cx)/rx)**2+((v-cy)/ry)**2)*2))
  spots*=np.clip((z+.65)*4,0,1)
  rgb*=1-spots[...,None]*.65
 else:rgb*=1+(noise*.2)[...,None]
 if kind=='mackerel':
  bars=np.sin(u*185+np.sin(v*26)*1.6+np.sin(u*44)*.8)
  stripe=np.clip((bars-.12)*2.2,0,1)*np.clip((z+.03)*5,0,1)
  rgb*=1-stripe[...,None]*.78
 if kind=='haddock':
  spot=np.exp(-(((u-.66)/.035)**2+((np.abs(z)-.22)/.22)**2))
  rgb*=1-spot[...,None]*.92
 # Minute overlapping scales, subdued on the head and belly.
 scallop=np.sin(u*math.tau*90+np.floor(v*70)%2*math.pi)*np.sin(v*math.tau*70)
 scale_detail=np.clip(scallop,0,1)*.055*(u<.79)
 rgb*=1-scale_detail[...,None]
 # Distinct lateral lines painted into skin, not a floating bright wire.
 line_z=.14+(.37*np.exp(-((u-.64)/.15)**2) if kind=='pollack' else 0)
 if kind!='mackerel' and kind!='halibut':
  line=np.exp(-((z-line_z)/.020)**2)*(u>.04)*(u<.78)
  target=np.array((.74,.71,.55)) if kind!='haddock' else np.array((.045,.05,.055))
  rgb=rgb*(1-line[...,None]*.8)+target*line[...,None]*.8
 # Light stippling breaks up smooth plastic reflections.
 rgb*=rng.uniform(.965,1.035,(H,W,1));rgba=np.concatenate([np.clip(rgb,0,1),np.ones((H,W,1))],2).astype(np.float32)
 im=bpy.data.images.new(kind+'_skin',width=W,height=H);im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(OUT/(kind+'_skin.png'));im.file_format='PNG';im.save();im.pack()
 m=mat(kind+' skin',(1,1,1),.53,.04);nodes=m.node_tree.nodes;tex=nodes.new('ShaderNodeTexImage');tex.image=im
 m.node_tree.links.new(tex.outputs['Color'],nodes.get('Principled BSDF').inputs['Base Color'])
 return m

for kind in profiles:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 sk=skin(kind);finmat=mat(kind+' fin membrane',tuple(np.array(colors[kind][1])*.65),.68)
 finray=mat(kind+' fin rays',tuple(np.array(colors[kind][1])*.92),.58)
 lip=mat(kind+' lips',tuple(np.array(colors[kind][1])*.78),.52)
 dark=mat('Mouth and gill recess',(.021,.018,.015),.78)
 pupil=mat('Gloss black pupil',(.004,.006,.006),.12)
 iris=mat('Iris',(.49,.36,.13) if kind=='cod' else (.56,.58,.48),.31,.12)
 verts=[];faces=[];N=73;S=48;profile=profiles[kind]
 rings=[]
 for i in range(N):
  x,w,h,zc=smooth(profile,i*(len(profile)-1)/(N-1));rings.append((x,w,h,zc))
  for j in range(S+1):
   a=j*math.tau/S
   # Flatten head cheeks; round muscle section behind the operculum.
   y=w*math.cos(a);z=h*math.sin(a)+zc
   verts.append((x,y,z))
 for i in range(N-1):
  for j in range(S):faces.append((i*(S+1)+j,i*(S+1)+j+1,(i+1)*(S+1)+j+1,(i+1)*(S+1)+j))
 faces.extend([tuple(reversed(range(S))),tuple((N-1)*(S+1)+j for j in range(S))])
 body=obj('Anatomical body',verts,faces,sk);uv=body.data.uv_layers.new(name='SkinUV')
 for poly in body.data.polygons:
  for li in poly.loop_indices:
   index=body.data.loops[li].vertex_index;uv.data[li].uv=(index//(S+1)/(N-1),index%(S+1)/S)
 def body_dims(x):
  rr=min(rings,key=lambda r:abs(r[0]-x));return rr[1],rr[2],rr[3]
 def ribbon(name,start,end,height,sign=1,flat=False):
  # A fin is a curved, ribbed membrane with an anatomical base and scalloped edge.
  vs=[];fs=[];rays=25
  for j in range(rays):
   t=j/(rays-1);x=start+(end-start)*t;w,h,zc=body_dims(x)
   envelope=math.sin(math.pi*t)**.65*(1-.46*t)
   extension=height*envelope
   base=Vector((x,sign*w*.96,zc)) if flat else Vector((x,0,zc+sign*h*.96))
   tip=base+Vector((-.019*envelope,sign*extension,-.003)) if flat else base+Vector((-.026*envelope,.007*math.sin(t*math.pi),sign*extension))
   vs.extend([base,base.lerp(tip,.52)+Vector((0,.004,0)),tip])
   if j>0:
    for k in range(2):fs.append(((j-1)*3+k,(j-1)*3+k+1,j*3+k+1,j*3+k))
   if j%2==0:path(name+' ray',[base,base.lerp(tip,.52),tip],.0008,finray)
  o=obj(name,vs,fs,finmat);sol=o.modifiers.new('Fin thickness','SOLIDIFY');sol.thickness=.0012
 if kind=='halibut':
  for side in [-1,1]:ribbon('Dorsal fringe' if side>0 else 'Anal fringe',.35,-.33,.06,side,True)
 else:
  dorsals=[(.25,.045,.076),(.03,-.17,.056),(-.20,-.34,.036)]
  if kind=='haddock':dorsals=[(.24,.045,.12),(.015,-.17,.052),(-.21,-.34,.03)]
  if kind=='mackerel':dorsals=[(.23,.045,.07),(-.13,-.23,.032)]
  for a,b,h in dorsals:ribbon('Dorsal fin',a,b,h)
  for a,b,h in ([(-.13,-.23,.025)] if kind=='mackerel' else [(.005,-.16,.044),(-.19,-.34,.028)]):ribbon('Anal fin',a,b,h,-1)
 # Caudal fan with realistic rounded rays, species fork depth.
 fork=.06 if kind in ['saithe','pollack','mackerel'] else (.024 if kind=='cod' else .04)
 vs=[];fs=[]
 for j in range(33):
  t=j/32;z=(t*2-1)*(.115 if kind!='mackerel' else .105)
  x=-.55+fork*(1-abs(t*2-1))**1.8
  base=Vector((-.385,0,(t*2-1)*.022));tip=Vector((x,0,z))
  if kind=='halibut':base=Vector((-.385,(t*2-1)*.022,0));tip=Vector((x,z,0))
  vs.extend([base,base.lerp(tip,.55),tip])
  if j:
   for k in range(2):fs.append(((j-1)*3+k,(j-1)*3+k+1,j*3+k+1,j*3+k))
  if j%2==0:path('Caudal ray',[base,tip],.0009,finray)
 o=obj('Caudal fin',vs,fs,finmat);sol=o.modifiers.new('Caudal membrane','SOLIDIFY');sol.thickness=.002
 if kind!='halibut':
  for side in [-1,1]:
   # Swept pectoral fin, narrow point and fan of supporting rays.
   root=Vector((.20,side*body_dims(.20)[0]*.99,-.016));vs=[];fs=[]
   for j in range(18):
    t=j/17;tip=root+Vector((-.155*math.sin(math.pi*t)**.6,side*.067*math.sin(math.pi*t),-.06*t))
    vs.extend([root,root.lerp(tip,.5)+Vector((0,side*.012,0)),tip])
    if j:
     for k in range(2):fs.append(((j-1)*3+k,(j-1)*3+k+1,j*3+k+1,j*3+k))
    if j%2==0:path('Pectoral ray',[root,tip],.0007,finray)
   o=obj('Pectoral fin',vs,fs,finmat);sol=o.modifiers.new('Thickness','SOLIDIFY');sol.thickness=.001
   if kind!='mackerel':
    path('Pelvic fin',[(.18,side*.027,-.092),(.10,side*.051,-.14),(.125,side*.033,-.10)],.003,finmat)
   # Eye socket rims, domed amber iris, pupil; situated on head cheeks.
   ex=.334 if kind!='haddock' else .319;w,h,zc=body_dims(ex)
   ep=(ex,side*w*.88,zc+h*.40);radius=.021 if kind=='cod' else (.018 if kind!='mackerel' else .016)
   sphere('Eye socket',ep,radius*1.15,(1,.42,1),lip)
   sphere('Iris',(ep[0],ep[1]+side*.006,ep[2]),radius,(1,.40,1),iris)
   sphere('Pupil',(ep[0]+.001,ep[1]+side*.012,ep[2]),radius*.62,(1,.36,1),pupil)
   # Operculum curves follow the actual surface, never float through the cheek.
   g=[]
   for j in range(22):
    a=.9-j*1.8/21;x=.25-.040*math.cos(a);w,h,zc=body_dims(x);g.append((x,side*w*math.cos(a)*1.004,zc+h*math.sin(a)))
   path('Gill slit',g,.0020,dark);path('Operculum rim',[(x+.003,y*1.005,z) for x,y,z in g],.0012,lip)
   # Mouth seam with separately sculpted lower jaw, not a pointed cone.
   w,h,zc=body_dims(.41)
   mouth=[(.449,side*.021,zc-.005),(.424,side*w*.88,zc-.010),(.384,side*.040,zc-.022)]
   path('Mouth opening',mouth,.004 if kind=='cod' else .0025,dark)
   path('Lower lip',[(x-.003,y,z-.0035) for x,y,z in mouth],.003,lip)
  if kind in ['cod','haddock']:
   path('Chin barbel',[(.402,0,-.052),(.395,0,-.077),(.371,0,-.087)],.0028 if kind=='cod' else .0015,lip)
  if kind=='mackerel':
   for i in range(5):
    x=-.25-i*.025
    for sign in [-1,1]:ribbon('Finlet',x+.012,x-.008,.018,sign)
 else:
  # Both eyes on the pigmented side, asymmetrical flatfish head.
  for x,y in [(.332,-.016),(.287,.027)]:
   h=body_dims(x)[1]
   sphere('Raised eye socket',(x,y,h*.95),.019,(1,1,.7),lip)
   sphere('Upper iris',(x,y,h+.008),.014,(1,1,.4),iris)
   sphere('Upper pupil',(x,y,h+.013),.0085,(1,1,.4),pupil)
  path('Flatfish mouth',[(.446,-.01,.004),(.399,-.031,.019),(.376,-.041,.017)],.003,dark)
  path('Flatfish gill',[(.266,-.065,.03),(.225,-.098,.026),(.255,-.13,.018)],.002,dark)
 # Convert curves, combine by material into one rigged fish (shared mesh surfaces).
 bpy.ops.object.select_all(action='SELECT')
 for o in list(bpy.context.selected_objects):
  bpy.context.view_layer.objects.active=o
  if o.type=='CURVE':bpy.ops.object.convert(target='MESH')
  for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
  bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=body;bpy.ops.object.join();body=bpy.context.object;body.name=kind.capitalize()+'_Mesh'
 # Articulate the rear half; the head/eyes stay rigid.
 arm=bpy.data.armatures.new('FishSkeleton');rig=bpy.data.objects.new('FishRig',arm);bpy.context.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 prev=None
 for name,start,end in [('Body',.25,-.12),('Tail',-.12,-.34),('Caudal',-.34,-.55)]:
  b=arm.edit_bones.new(name);b.head=(start,0,0);b.tail=(end,0,0)
  if prev:b.parent=prev;b.use_connect=True
  prev=b
 bpy.ops.object.mode_set(mode='OBJECT')
 groups=[body.vertex_groups.new(name=n) for n in ['Body','Tail','Caudal']]
 for v in body.data.vertices:
  x=v.co.x;t=max(0,min(1,(-x-.04)/.22));q=max(0,min(1,(-x-.29)/.17))
  weights=[1-t,t*(1-q),t*q]
  for g,w in zip(groups,weights):
   if w>0:g.add([v.index],w,'REPLACE')
 mod=body.modifiers.new('Swim deformation','ARMATURE');mod.object=rig;body.parent=rig
 for frame in range(1,50,3):
  time=(frame-1)/48*math.tau
  for name,amp,phase in [('Tail',.12,0),('Caudal',.22,-.8)]:
   bone=rig.pose.bones[name];bone.rotation_mode='XYZ';bone.rotation_euler=(0,math.sin(time+phase)*amp,0);bone.keyframe_insert('rotation_euler',frame=frame)
 bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=49;bpy.context.scene.render.fps=24
 if rig.animation_data and rig.animation_data.action:rig.animation_data.action.name='Swim'
 bpy.context.scene.frame_set(1)
 # Author the actual lip attachment, independent of the tail animation. Godot
 # uses this socket as the line endpoint, never the mesh's centre of mass.
 hook=bpy.data.objects.new('MouthHook',None);bpy.context.collection.objects.link(hook)
 hook.empty_display_type='PLAIN_AXES';hook.empty_display_size=.025
 hook.location=(.446,-.01,.004) if kind=='halibut' else (.449,0,body_dims(.41)[2]-.005)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(kind+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'.glb')),export_format='GLB',export_apply=True,export_animations=True)
 print('AUTHORED',kind,len(body.data.vertices),'vertices')
print('DETAILED FISH COMPLETE')
