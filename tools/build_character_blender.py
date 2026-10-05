"""Build the rigged Blender mariner; geometry follows the approved angular references."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mariner_geometry import *

# One rig, shared bind transforms. Weighted continuous body and modular clothing.
arm_data=bpy.data.armatures.new('MarinerSkeleton'); rig=bpy.data.objects.new('MarinerRig',arm_data)
bpy.context.collection.objects.link(rig); bpy.context.view_layer.objects.active=rig
rig.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
bones={}
def bone(name,head,tail,parent=None):
    b=arm_data.edit_bones.new(name); b.head=head; b.tail=tail
    if parent: b.parent=arm_data.edit_bones[parent]
    bones[name]=(Vector(head),Vector(tail))
bone('root',(0,0,0),(0,0,.15))
bone('hips',(0,0,.91),(0,0,1.06),'root')
bone('spine',(0,0,1.06),(0,0,1.25),'hips')
bone('chest',(0,0,1.25),(0,0,1.45),'spine')
bone('neck',(0,0,1.45),(0,0,1.55),'chest')
bone('head',(0,0,1.55),(0,0,1.78),'neck')
for s,side in [(-1,'R'),(1,'L')]:
    bone('clavicle.'+side,(0,0,1.43),(s*.21,0,1.415),'chest')
    bone('upper_arm.'+side,(s*.21,0,1.415),(s*.32,.005,1.15),'clavicle.'+side)
    bone('forearm.'+side,(s*.32,.005,1.15),(s*.39,.025,.935),'upper_arm.'+side)
    twist_head=Vector((s*.32,.005,1.15)).lerp(Vector((s*.39,.025,.935)),.68)
    bone('forearm_twist.'+side,twist_head,(s*.39,.025,.935),'forearm.'+side)
    bone('hand.'+side,(s*.39,.025,.935),(s*.41,.03,.82),'forearm_twist.'+side)
    for k,digit in enumerate(['index','middle','ring','little']):
        x=s*(.382+k*.021);tip=.793+[.012,0,.004,.02][k]
        bone(digit+'_01.'+side,(x,.03,.86),(x,.036,.829),'hand.'+side)
        bone(digit+'_02.'+side,(x,.036,.829),(x,.043,tip),digit+'_01.'+side)
    bone('thumb_01.'+side,(s*.375,.04,.913),(s*.353,.05,.889),'hand.'+side)
    bone('thumb_02.'+side,(s*.353,.05,.889),(s*.347,.061,.862),'thumb_01.'+side)
    bone('thigh.'+side,(s*.105,0,.93),(s*.11,.02,.51),'hips')
    bone('shin.'+side,(s*.11,.02,.51),(s*.11,0,.12),'thigh.'+side)
    bone('foot.'+side,(s*.11,0,.12),(s*.11,.13,.05),'shin.'+side)
bpy.ops.object.mode_set(mode='OBJECT')

def distance(p,a,b):
    t=max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared))
    return (p-(a+t*(b-a))).length

def morph(p,kind):
    x,y,z=p; q=Vector(p)
    if kind=='Build':
        q.x*=1.0+.17*max(0,min(1,(1.53-z)/.3))
        q.y*=1.0+.22*max(0,min(1,(1.52-z)/.25))
    if kind=='Belly':
        f=math.exp(-((z-1.13)/.22)**2)
        q.y+=max(0,y)*.68*f; q.x*=1+.16*f
    if kind=='Frame':
        q.x*=1+.17*math.exp(-((z-.97)/.2)**2)-.12*math.exp(-((z-1.4)/.16)**2)
        q.y+=max(0,y)*.12*math.exp(-((z-1.32)/.12)**2)
    if kind=='Age':
        if z>1.53:
            q.x*=1+.06*math.exp(-((z-1.59)/.055)**2)
            q.z-=.008*math.exp(-((z-1.59)/.06)**2)
        # Small posture change; no extreme hunch that invalidates the shared rig.
        q.y+=.015*max(0,min(1,(z-1.25)/.3))
    return q

for o in objects:
    # UVs are mandatory even for tintable materials; this also permits later texture work.
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); bpy.context.view_layer.objects.active=o
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
    if o.name == 'Top_Sweater':
        for poly in o.data.polygons:
            axis=max(range(3),key=lambda i:abs(poly.normal[i]))
            for index in poly.loop_indices:
                p=o.data.vertices[o.data.loops[index].vertex_index].co
                uv=(p.y,p.z) if axis==0 else ((p.x,p.z) if axis==1 else (p.x,p.y))
                o.data.uv_layers.active.data[index].uv=(uv[0]*3.7,uv[1]*3.7)
    basis_coords=[v.co.copy() for v in o.data.vertices]
    o.shape_key_add(name='Basis',from_mix=False)
    for key in ['Build','Belly','Frame','Age']:
        sk=o.shape_key_add(name=key,from_mix=False)
        for index,v in enumerate(sk.data): v.co=morph(basis_coords[index],key)
    for name in bones: o.vertex_groups.new(name=name)
    for vert in o.data.vertices:
        p=vert.co; x,y,z=p; side='L' if x>=0 else 'R'
        if o.name == 'Hands':
            if abs(x)<.369 and z<.917:
                candidates=['hand.'+side,'thumb_01.'+side,'thumb_02.'+side]
            elif z<.854:
                digit=min(range(4),key=lambda k:abs(abs(x)-(.382+k*.021)))
                digit=['index','middle','ring','little'][digit]
                candidates=['hand.'+side,digit+'_01.'+side,digit+'_02.'+side]
            else: candidates=['hand.'+side]
            ds=sorted([(distance(p,*bones[n]),n) for n in candidates])[:2]
            weights=[math.exp(-d*140) for d,n in ds];total=sum(weights)
            for (d,n),w in zip(ds,weights):o.vertex_groups[n].add([vert.index],w/total,'REPLACE')
            continue
        if .9 <= z <= 1.52:
            # Continuous shoulder blend. Do not let nearest hand/forearm bones
            # steal waist vertices when the arm is close to the torso.
            edge=.18+(1.42-z)*.20
            influence=max(0,min(1,(abs(x)-edge)/.065))
            influence=influence*influence*(3-2*influence)
            for group,factor in [(['hips','spine','chest','neck'],1-influence),(['clavicle.'+side,'upper_arm.'+side,'forearm.'+side,'forearm_twist.'+side],influence)]:
                if factor<.00001: continue
                if group[0].startswith('clavicle'):
                    # Narrow elbow articulation; shafts stay attached to one bone.
                    t=max(0,min(1,(1.177-z)/.054));t=t*t*(3-2*t)
                    o.vertex_groups['upper_arm.'+side].add([vert.index],factor*(1-t),'REPLACE')
                    o.vertex_groups['forearm.'+side].add([vert.index],factor*t,'REPLACE')
                    continue
                ds=sorted([(distance(p,*bones[n]),n) for n in group])[:2]
                weights=[math.exp(-d*35) for d,n in ds]; total=sum(weights)
                for (d,n),w in zip(ds,weights): o.vertex_groups[n].add([vert.index],factor*w/total,'REPLACE')
            continue
        if o.name in ['Head','Face','Hair_Crop','FacialHair_Moustache','Headwear_Cap','Headwear_Hardhat','Eyewear_Glasses','Accessory_Pipe']: candidates=['head']
        elif z>1.52: candidates=['head','neck'] if z<1.57 else ['head']
        elif abs(x)>.22 and z<1.05 and z>.77: candidates=['forearm.'+side,'hand.'+side]
        elif z<.9:
            if z>.145:
                t=max(0,min(1,(.535-z)/.05));t=t*t*(3-2*t)
                o.vertex_groups['thigh.'+side].add([vert.index],1-t,'REPLACE')
                o.vertex_groups['shin.'+side].add([vert.index],t,'REPLACE')
            else:
                t=max(0,min(1,(.145-z)/.04));t=t*t*(3-2*t)
                o.vertex_groups['shin.'+side].add([vert.index],1-t,'REPLACE')
                o.vertex_groups['foot.'+side].add([vert.index],t,'REPLACE')
            continue
        else: candidates=['hips','spine','chest','neck','clavicle.'+side,'upper_arm.'+side,'forearm.'+side,'hand.'+side]
        ds=sorted([(distance(p,*bones[n]),n) for n in candidates])[:2]
        weights=[math.exp(-d*35) for d,n in ds]; total=sum(weights)
        for (d,n),w in zip(ds,weights): o.vertex_groups[n].add([vert.index],w/total,'REPLACE')
    mod=o.modifiers.new('Mariner skin','ARMATURE'); mod.object=rig
    o.parent=rig

# Correct the hand mesh AND its rest bones together. The neutral hand orientation
# belongs in the bind pose, not in a 90-degree animation twist through a sleeve.
hand_bind={}
for side,s in [('L',1),('R',-1)]:
    wrist=Vector((s*.39,.025,.935))
    axis=(wrist-Vector((s*.32,.005,1.15))).normalized()
    hand_bind[side]=(wrist,Quaternion(axis,s*math.pi/2))
hands=bpy.data.objects['Hands']
for key in hands.data.shape_keys.key_blocks:
    for v in key.data:
        wrist,rotation=hand_bind['L' if v.co.x>=0 else 'R']
        v.co=wrist+rotation@(v.co-wrist)
for i,v in enumerate(hands.data.vertices):v.co=hands.data.shape_keys.key_blocks['Basis'].data[i].co
bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
for b in arm_data.edit_bones:
    if b.name.split('.')[0] in ['hand','index_01','index_02','middle_01','middle_02','ring_01','ring_02','little_01','little_02','thumb_01','thumb_02']:
        wrist,rotation=hand_bind[b.name.split('.')[-1]]
        from mathutils import Matrix
        b.transform(Matrix.Translation(wrist)@rotation.to_matrix().to_4x4()@Matrix.Translation(-wrist))
        bones[b.name]=(b.head.copy(),b.tail.copy())
bpy.ops.object.mode_set(mode='OBJECT')
# Bake constrained foot contact and anatomical hand poses into standard clips.
from mariner_animation import author
author(rig,bones,OUT)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'mariner.blend'))
for tr in rig.animation_data.nla_tracks: tr.mute=False
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for o in objects: o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'mariner.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_morph=True,export_skins=True,export_yup=True)
print('MARINER EXPORTED',len(objects),'modular meshes',len(bones),'bones')
stats={o.name:{'vertices':len(o.data.vertices),'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)} for o in objects}
(OUT/'mesh_stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
print('GEOMETRY',sum(v['vertices'] for v in stats.values()),'vertices',sum(v['triangles'] for v in stats.values()),'triangles across all optional parts')
