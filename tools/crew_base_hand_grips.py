"""Fit finger poses to actual weighted anatomical skin around a 24 mm handle."""
import bpy,json,math
import numpy as np
from mathutils import Vector,Quaternion,Matrix

def author_grips(rig,contacts,out):
 hands=next(o for o in bpy.data.objects if o.type=='MESH' and o.name=='Hands')
 poses={}
 for side,sign in [('L',1),('R',-1)]:
  hand=rig.data.bones['hand.'+side];inverse=hand.matrix_local.inverted()
  vertices=[v for v in hands.data.vertices if v.co.x*sign>0]
  points=np.array([list(inverse@v.co)+[1.] for v in vertices])
  names=[d+'_'+j+'.'+side for d in ['index','middle','ring','little'] for j in ['01','02','03']]+['thumb_01.'+side,'thumb_02.'+side]
  weights={n:np.zeros(len(vertices)) for n in names}
  for i,v in enumerate(vertices):
   for g in v.groups:
    n=hands.vertex_groups[g.group].name
    if n in weights:weights[n][i]=g.weight
  fixed=1-sum(weights.values())
  rests={};binds={};parents={}
  for n in names:
   b=rig.data.bones[n];parents[n]=b.parent.name if b.parent.name in names else None
   parent=rig.data.bones[parents[n]].matrix_local if parents[n] else hand.matrix_local
   rests[n]=np.array(parent.inverted()@b.matrix_local)
   binds[n]=np.array((inverse@b.matrix_local).inverted())
  # Find the supporting cylinder tangent to the actual uncurled palm surface.
  # A fingertip/knuckle proxy is not an adequate test of an anatomical mesh.
  y=.075;radius=.012
  palm=points[fixed>.65]
  support=[p[2]-math.sqrt(max(0,radius*radius-(p[1]-y)**2)) for p in palm if abs(p[1]-y)<radius]
  centerz=min(support)-.0005 if support else -.045
  contacts[side]['palm_contact']=[0.,y,centerz+radius]
  center=np.array([y,centerz])
  def deform(angles):
   posed={};result=points*fixed[:,None]
   for j,n in enumerate(names):
    q=Quaternion((1,0,0),-angles[j]);rotation=np.array(q.to_matrix().to_4x4())
    posed[n]=(posed[parents[n]] if parents[n] else np.eye(4))@rests[n]@rotation
    result+=((posed[n]@binds[n])@points.T).T*weights[n][:,None]
   return result
  def loss(a):
   p=deform(a);r=np.linalg.norm(p[:,1:3]-center,axis=1)
   penetration=np.maximum(.0108-r,0)
   # Strong clearance penalty, then make the distal fingers approach the grip.
   fingerweight=sum(weights[n] for n in names if not n.startswith('thumb'))
   approach=np.maximum(r-.014,0)
   return float(2500*np.sum(penetration**2)+np.sum(approach**2*fingerweight)+.00001*np.sum(a*a))
  best=np.array([.8,1.1,.8]*4+[.4,.5]);bestloss=loss(best)
  for step in [.4,.2,.1,.05,.02,.008]:
   for repeat in range(10):
    changed=False
    for j in range(len(best)):
     for direction in [-1,1]:
      trial=best.copy();trial[j]=max(-.4,min(2.1,trial[j]+step*direction));value=loss(trial)
      if value<bestloss:best=trial;bestloss=value;changed=True
    if not changed:break
  p=deform(best);r=np.linalg.norm(p[:,1:3]-center,axis=1)
  print('SKIN_GRIP',side,'min_mm',float(r.min()*1000),'near',int(((r>=.010)&(r<.016)).sum()),'contact',contacts[side]['palm_contact'],flush=True)
  rotations={n:Quaternion((1,0,0),-float(a)) for n,a in zip(names,best)}
  poses[side]={n:list(q) for n,q in rotations.items()}
  action_name='Fishing_RodGrip' if side=='L' else 'Fishing_CrankGrip'
  old=bpy.data.actions.get(action_name)
  if old:bpy.data.actions.remove(old)
  action=bpy.data.actions.new(action_name);action.use_fake_user=True;rig.animation_data.action=action
  for n,q in rotations.items():
   pb=rig.pose.bones[n];pb.rotation_mode='QUATERNION';pb.rotation_quaternion=q;pb.keyframe_insert('rotation_quaternion',frame=0,group=n)
  rig.animation_data.action=None
  for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 (out/'hand_contacts.json').write_text(json.dumps(contacts,indent=2),encoding='utf-8')
 (out/'hand_grips.json').write_text(json.dumps(poses,indent=2),encoding='utf-8')
