"""Author finger poses against the physical handle cross-section in Blender.

The exported bone-local quaternions are consumed by the equipment modifier;
the matching actions remain editable in the original mariner .blend.
"""
import bpy, math, json
from mathutils import Vector, Quaternion, Matrix

def author_grips(rig,contacts,out):
    poses={}
    for side in ['L','R']:
        hand=rig.data.bones['hand.'+side]
        inverse=hand.matrix_local.inverted()
        center=Vector(contacts[side]['palm_contact'])-Vector((0,0,.012))
        rotations={}
        for digit in ['index','middle','ring','little']:
            chain=[rig.data.bones[digit+'_'+j+'.'+side] for j in ['01','02','03']]
            rests=[inverse@chain[0].matrix_local]+[chain[i-1].matrix_local.inverted()@chain[i].matrix_local for i in [1,2]]
            def score(angles):
                matrix=Matrix.Identity(4);cost=0;tip=None
                for i,bone in enumerate(chain):
                    matrix=matrix@rests[i]@Quaternion((1,0,0),-angles[i]).to_matrix().to_4x4()
                    for t in [.25,.5,.75,1.0]:
                        point=matrix@Vector((0,bone.length*t,0))
                        radius=math.hypot(point.y-center.y,point.z-center.z)
                        # Include the palmar flesh around each phalanx. The
                        # proximal mesh is 11 mm thick, not a 9 mm bone tube.
                        target=.012+[.011,.008,.0065][i]
                        error=radius-target
                        cost+=error*error*(25 if error<0 else 1)
                    tip=point
                # Close around the underside; do not merely point into the cylinder.
                cost+=max(0,tip.y-center.y)**2*2
                return cost
            best=[1.05,1.2,1.0]
            for step in [.35,.16,.07,.025,.008]:
                for repeat in range(8):
                    improved=False
                    for i in range(3):
                        for direction in [-1,1]:
                            test=best[:];test[i]=max(.25,min(1.85,test[i]+direction*step))
                            if score(test)<score(best):best=test;improved=True
                    if not improved:break
            print('GRIP',side,digit,best,score(best))
            for bone,angle in zip(chain,best):rotations[bone.name]=Quaternion((1,0,0),-angle)
        # Oppose the thumb to the fingers, across the cylinder, using its authored
        # CMC/IP joints rather than rolling the entire wrist to fake contact.
        for joint,angle in [('01',.65),('02',.70)]:
            rotations['thumb_'+joint+'.'+side]=Quaternion((1,0,0),-angle)
        poses[side]={name:list(q) for name,q in rotations.items()}
        action=bpy.data.actions.new('Fishing_RodGrip' if side=='L' else 'Fishing_CrankGrip')
        action.use_fake_user=True;rig.animation_data.action=action
        for name,q in rotations.items():
            pb=rig.pose.bones[name];pb.rotation_mode='QUATERNION';pb.rotation_quaternion=q
            pb.keyframe_insert('rotation_quaternion',frame=0,group=name)
        rig.animation_data.action=None
        for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    (out/'hand_grips.json').write_text(json.dumps(poses,indent=2),encoding='utf-8')
