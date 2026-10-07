"""Fresh fixed-length mariner animation. Only the pelvis translates."""
import bpy, math, json
from mathutils import Vector, Quaternion, Matrix
FPS=60
CLIPS={'idle':240,'walk':60,'run':42,'seated':240}
WALK_STRIDE=1.0
RUN_STRIDE=2*.30/.38
def ease(t):
    t=max(0,min(1,t));return t*t*(3-2*t)
def author(rig,bones,out):
    skin=[m for o in bpy.data.objects if o.type=='MESH' for m in o.modifiers if m.type=='ARMATURE']
    for m in skin:m.show_viewport=False
    rig.animation_data_create()
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action=None
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    bpy.context.scene.render.fps=FPS
    for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
    def axis_rotation(name,axis,angle):
        rest=rig.data.bones[name].matrix_local.to_quaternion()
        return rest.inverted() @ Quaternion(Vector(axis),angle) @ rest
    def point(name):return rig.pose.bones[name].head.copy()
    def length(name):return rig.data.bones[name].length
    def aim(name,direction):
        bone=rig.data.bones[name];pb=rig.pose.bones[name]
        desired=(bone.tail_local-bone.head_local).rotation_difference(direction.normalized()) @ bone.matrix_local.to_quaternion()
        parent=pb.parent
        base=(parent.matrix @ parent.bone.matrix_local.inverted() @ bone.matrix_local) if parent else bone.matrix_local
        pb.rotation_quaternion=base.to_quaternion().inverted() @ desired
        bpy.context.view_layer.update()
    def leg(side,target):
        thigh='thigh.'+side;shin='shin.'+side
        hip=point(thigh);axis=target-hip;distance=axis.length
        upper=length(thigh);lower=length(shin)
        assert distance<upper+lower, ('Unreachable leg target',side,distance,upper+lower)
        axis.normalize();along=(upper*upper-lower*lower+distance*distance)/(2*distance)
        pole=Vector((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized()
        knee=hip+axis*along+pole*math.sqrt(max(0,upper*upper-along*along))
        aim(thigh,knee-hip);aim(shin,target-knee)
        assert (point('foot.'+side)-target).length<.0001
    diagnostics={}
    for clip,frames in CLIPS.items():
        for track in rig.animation_data.nla_tracks:track.mute=True
        action=bpy.data.actions.new(clip);rig.animation_data.action=action
        samples=[]
        for frame in range(frames+1):
            u=frame/frames;t=math.tau*u
            for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
            moving=clip in ['walk','run'];running=clip=='run'
            pelvis=rig.pose.bones['hips']
            offset=Vector((.008*math.sin(t) if moving else .002*math.sin(t),0,
                (-.085+.025*math.cos(2*t)) if running else (-.047+.008*math.cos(2*t) if moving else -.014)))
            pelvis.location=pelvis.bone.matrix_local.to_3x3().inverted()@offset
            pelvis.rotation_quaternion=axis_rotation('hips',(0,0,1),.025*math.sin(t) if moving else .003*math.sin(t))
            rig.pose.bones['spine'].rotation_quaternion=axis_rotation('spine',(1,0,0),-.065 if running else -.012)
            rig.pose.bones['chest'].rotation_quaternion=axis_rotation('chest',(0,0,1),-.05*math.sin(t) if moving else .005*math.sin(t))
            bpy.context.view_layer.update()
            for side,sign,phase in [('L',1,0),('R',-1,.5)]:
                p=(u+phase)%1;tarm=t+phase*math.tau
                upper='upper_arm.'+side;fore='forearm.'+side
                # Constant adduction plus a continuous shoulder swing. No wrist
                # targets, elbow pole flips, per-bone translation or axial twist.
                adduct=axis_rotation(upper,(0,1,0),sign*.30)
                swing=-(.58 if running else .24)*math.cos(tarm) if moving else .009*math.sin(t)
                elbow=(.96+.10*math.cos(tarm+.4)) if running else (.16+.06*(.5+.5*math.cos(tarm)) if moving else .14)
                if clip=='seated':swing=.48;elbow=.78
                rig.pose.bones[upper].rotation_quaternion=adduct @ axis_rotation(upper,(1,0,0),swing)
                rig.pose.bones[fore].rotation_quaternion=axis_rotation(fore,(1,0,0),elbow)
                for k,digit in enumerate(['index','middle','ring','little']):
                    for joint,mult in [('01',1),('02',1.25)]:
                        name=digit+'_'+joint+'.'+side
                        bind_axis=(bones['forearm.'+side][1]-bones['forearm.'+side][0]).normalized()
                        curl_axis=Quaternion(bind_axis,sign*math.pi/2)@Vector((1,0,0))
                        rig.pose.bones[name].rotation_quaternion=axis_rotation(name,curl_axis,-(.13+k*.045+(.10 if running else 0))*mult)
                bpy.context.view_layer.update()
                hip=point('thigh.'+side);pitch=0.0
                if moving:
                    stance=.38 if running else .60
                    reach=.30
                    if p<stance:
                        q=p/stance;y=reach*(1-2*q)
                        pitch=.25*(1-ease(q/.22))-.40*ease((q-.72)/.28)
                        lift=0.0
                    else:
                        q=(p-stance)/(1-stance)
                        # Match the planted foot's velocity at lift-off and
                        # landing. Smoothstep alone abruptly stops it there.
                        tangent=-2*reach*(1-stance)/stance
                        y=-reach+2*reach*ease(q)+tangent*(2*q*q*q-3*q*q+q)
                        lift=(.21 if running else .13)*math.sin(math.pi*q)**2
                        pitch=-.40*(1-ease(q/.35))+.25*ease((q-.55)/.45)
                    ankle_z=.005+.115*math.cos(pitch)+(.095 if pitch>=0 else .175)*abs(math.sin(pitch))+lift
                    target=Vector((sign*.11,y,ankle_z))
                    reach_limit=length('thigh.'+side)+length('shin.'+side)-.002
                    horizontal=(target.x-hip.x)**2+(target.y-hip.y)**2
                    target.z=max(target.z,hip.z-math.sqrt(max(.001,reach_limit**2-horizontal)))
                elif clip=='seated':target=Vector((sign*.11,.4,.52))
                else:target=Vector((sign*.11,0,.12))
                leg(side,target)
                aim('foot.'+side,Quaternion((1,0,0),pitch)@Vector((0,.13,-.07)))
                samples.append({'side':side,'frame':frame,'ankle':list(target)})
            bpy.context.view_layer.update()
            for pb in rig.pose.bones:
                pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name)
                if pb.name=='hips':pb.keyframe_insert('location',frame=frame,group=pb.name)
                else:assert pb.location.length<.00001, ('Bone translated',pb.name)
        track=rig.animation_data.nla_tracks.new();track.name=clip
        strip=track.strips.new(clip,0,action);strip.blend_type='REPLACE';strip.extrapolation='NOTHING';track.mute=True
        diagnostics[clip]={'frames':frames,'fps':FPS,'seconds':frames/FPS,'contacts':samples}
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.scene.frame_set(0)
    for m in skin:m.show_viewport=True
    (out/'animation_contract.json').write_text(json.dumps({'version':2,'arm_method':'fixed-length local FK; no wrist targets','walk_stride_m':WALK_STRIDE,'run_stride_m':RUN_STRIDE,'clips':diagnostics},indent=2),encoding='utf-8')
