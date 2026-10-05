"""Author contact-based loops in Blender and bake to quaternion bone tracks.
No runtime procedural limb waving. +Y forward, Z up, metres, 60 Hz authoring.
"""
import bpy, math, json
from mathutils import Vector, Quaternion, Matrix

FPS=60
CLIPS={'idle':240,'walk':60,'run':42,'seated':240}
WALK_STRIDE=1.0 # metres travelled per complete loop; .6 m / .6 s stance
RUN_STRIDE=2.625 # .84 m / (.32 * .7 s) = 3.75 m/s

def solve_joint(a,b,l1,l2,pole):
    assert (b-a).length <= l1+l2+.001, f'IK target would stretch limb: {(b-a).length:.6f} > {l1+l2:.6f}, {tuple(a)} -> {tuple(b)}'
    axis=b-a;length=min(axis.length,l1+l2-.0005);axis.normalize()
    along=(l1*l1-l2*l2+length*length)/(2*length)
    bend=(Vector(pole)-axis*Vector(pole).dot(axis)).normalized()
    return a+axis*along+bend*math.sqrt(max(0,l1*l1-along*along))

def author(rig,bones,out):
    skin_modifiers=[m for o in bpy.data.objects if o.type=='MESH' for m in o.modifiers if m.type=='ARMATURE']
    for modifier in skin_modifiers:modifier.show_viewport=False
    rig.animation_data_create()
    bpy.context.scene.render.fps=FPS
    diagnostics={}
    def put(name,head,tail,twist=0):
        rest=rig.data.bones[name]
        orient=(rest.tail_local-rest.head_local).rotation_difference(Vector(tail)-Vector(head)) @ rest.matrix_local.to_quaternion()
        orient=orient @ Quaternion((0,1,0),twist)
        matrix=orient.to_matrix().to_4x4();matrix.translation=head
        rig.pose.bones[name].matrix=matrix
        bpy.context.view_layer.update()
    def length(name):return (bones[name][1]-bones[name][0]).length
    for clip,frames in CLIPS.items():
        for track in rig.animation_data.nla_tracks:track.mute=True
        action=bpy.data.actions.new(clip);rig.animation_data.action=action
        for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
        contacts=[]
        for frame in range(frames+1):
            u=frame/frames;t=math.tau*u
            # Start from a clean local pose, never from the previous clip or NLA mix.
            for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
            bpy.context.view_layer.update()
            moving=clip in ('walk','run');running=clip=='run'
            if moving:
                half=u% .5
                flight=max(0,min(1,(half-.32)/.18))
                hip_z=(.788+.07*math.sin(math.pi*flight)**2) if running else (.842+.008*math.cos(2*t))
                hip_x=.012*math.sin(t)
                yaw=.04*math.sin(t);lean=-.11 if running else -.025
            else:
                hip_z=.91;hip_x=.003*math.sin(t);yaw=.006*math.sin(t);lean=0
            offset=Vector((hip_x,0,hip_z-.91))
            turn=Quaternion((0,0,1),yaw) @ Quaternion((1,0,0),lean)
            def torso(p):
                return Vector((hip_x,0,hip_z))+turn@(Vector(p)-Vector((0,0,.91)))
            put('hips',torso((0,0,.91)),torso((0,0,1.06)))
            put('spine',torso((0,0,1.06)),torso((0,0,1.25)))
            put('chest',torso((0,0,1.25)),torso((0,.003*math.sin(t),1.45)))
            put('neck',torso((0,0,1.45)),torso((0,0,1.55)))
            # Keep the gaze stable instead of nodding the head with every step.
            head=torso((0,0,1.55));put('head',head,head+Vector((0,0,.23)))
            for side,s,phase in [('L',1,0),('R',-1,.5)]:
                p=(u+phase)%1.0
                hip=torso((s*.105,0,.93))
                if moving:
                    stance=.32 if running else .60;reach=.42 if running else .30
                    if p<stance:
                        y=reach-2*reach*p/stance;z=.12
                        contacts.append({'side':side,'frame':frame,'ankle':[s*.11,y,z]})
                    else:
                        swing=(p-stance)/(1-stance)
                        y=-reach+2*reach*(.5-.5*math.cos(math.pi*swing))
                        z=.12+(.22 if running else .10)*math.sin(math.pi*swing)**1.4
                    ankle=Vector((s*.11,y,z))
                    if p>=stance:
                        reach_limit=length('thigh.'+side)+length('shin.'+side)-.002
                        horizontal=(ankle.x-hip.x)**2+(ankle.y-hip.y)**2
                        ankle.z=max(ankle.z,hip.z-math.sqrt(max(.001,reach_limit*reach_limit-horizontal)))
                elif clip=='seated':
                    # Seated clip retains the existing visual root; seat gameplay owns its offset.
                    ankle=Vector((s*.11,.40,.52))
                else:ankle=Vector((s*.11,0,.12))
                knee=solve_joint(hip,ankle,length('thigh.'+side),length('shin.'+side),(0,1,0))
                put('thigh.'+side,hip,knee);put('shin.'+side,knee,ankle)
                # Flat stance soles; swing toe is slightly raised for ground clearance.
                foot_dir=Vector((0,.13,-.07))
                if moving and p>=stance:foot_dir=Quaternion((1,0,0),.12*math.sin(math.pi*(p-stance)/(1-stance)))@foot_dir
                put('foot.'+side,ankle,ankle+foot_dir)
                shoulder=torso((s*.21,0,1.415));clav=torso((0,0,1.43))
                arm_wave=math.cos(t+phase*math.tau)
                if moving:
                    wrist=shoulder+Vector((s*.045,-(.19 if running else .115)*arm_wave, -.37 if running else -.49))
                elif clip=='seated':wrist=shoulder+Vector((s*.015,.25,-.35))
                else:wrist=shoulder+Vector((s*.045,.018,-.49))
                elbow=solve_joint(shoulder,wrist,length('upper_arm.'+side),length('forearm.'+side),(0,-1,0))
                put('clavicle.'+side,clav,shoulder)
                put('upper_arm.'+side,shoulder,elbow)
                put('forearm.'+side,elbow,wrist)
                twist_head=elbow.lerp(wrist,.68)
                put('forearm_twist.'+side,twist_head,wrist)
                # Nails face out, palms face thighs, thumbs point forward.
                hand_direction=(wrist-elbow).normalized()*.115
                put('hand.'+side,wrist,wrist+hand_direction)
                for k,digit in enumerate(['index','middle','ring','little']):
                    curl=(.14+.06*k)+(.18 if running else 0)
                    for joint,mult in [('01',1),('02',1.3)]:
                        pb=rig.pose.bones[digit+'_'+joint+'.'+side]
                        bind_axis=(bones['forearm.'+side][1]-bones['forearm.'+side][0]).normalized()
                        curl_axis=Quaternion(bind_axis,s*math.pi/2)@Vector((1,0,0))
                        axis=pb.bone.matrix_local.to_3x3().inverted()@curl_axis
                        pb.rotation_quaternion=Quaternion(axis,-curl*mult)
                for joint in ['01','02']:
                    pb=rig.pose.bones['thumb_'+joint+'.'+side]
                    pb.rotation_quaternion=Quaternion((1,0,0),-.12)
            bpy.context.view_layer.update()
            for pb in rig.pose.bones:
                pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name)
                pb.keyframe_insert('location',frame=frame,group=pb.name)
        track=rig.animation_data.nla_tracks.new();track.name=clip
        strip=track.strips.new(clip,0,action);strip.blend_type='REPLACE';strip.extrapolation='NOTHING'
        track.mute=True
        diagnostics[clip]={'frames':frames,'fps':FPS,'seconds':frames/FPS,'contacts':contacts}
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.scene.frame_set(0)
    for modifier in skin_modifiers:modifier.show_viewport=True
    (out/'animation_contract.json').write_text(json.dumps({'walk_stride_m':WALK_STRIDE,'run_stride_m':RUN_STRIDE,'clips':diagnostics},indent=2),encoding='utf-8')
