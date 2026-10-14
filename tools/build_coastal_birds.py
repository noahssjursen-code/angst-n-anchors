"""Original Blender-authored sea eagle and arctic tern. Metres, +Y forward."""
import ast, bpy, math, sys
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'resources/models/wildlife'
SOURCE=ROOT/'resources/models/_source/wildlife'
bpy.context.preferences.filepaths.save_version=0
# Reuse the existing authored loft/feather construction helpers, not gull geometry.
tree=ast.parse((ROOT/'tools/build_coastal_gull.py').read_text(encoding='utf-8'))
helpers=ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ('uv_tile','mesh','loft','sphere','feather')],type_ignores=[])

def atlas(species):
    n=512; t=n//4; rgba=np.ones((n,n,4),dtype=np.float32)
    rng=np.random.default_rng(943); y,x=np.mgrid[0:t,0:t]/t
    eagle=species=='white_tailed_eagle'
    colors=[(.24,.18,.12),(.19,.14,.09),(.15,.11,.075),(.075,.06,.045),(.90,.90,.82),(.78,.62,.19),(.72,.56,.20),(.72,.65,.34),(.01,.008,.006),(.42,.35,.24)] if eagle else [(.87,.89,.87),(.60,.64,.67),(.68,.71,.73),(.26,.29,.31),(.88,.91,.90),(.72,.09,.035),(.62,.08,.04),(.05,.045,.04),(.012,.015,.017),(.015,.018,.021)]
    for k in range(16):
        c=np.broadcast_to(np.array(colors[min(k,9)]),(t,t,3)).copy()
        if k<5:
            grain=rng.normal(0,.01,(t,t))+.018*np.sin(y*170+abs(x-.5)*90)
            c+=grain[:,:,None]
            if eagle and k in (0,1,2): c+=(.025*np.cos(x*75+y*30))[:,:,None]
        row,col=divmod(k,4);rgba[row*t:(row+1)*t,col*t:(col+1)*t,:3]=np.clip(c,0,1)
    im=bpy.data.images.new(species+'_adult',width=n,height=n,alpha=True)
    im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(ASSETS/(species+'_adult.png'));im.file_format='PNG';im.save()
    return im

def batch():
    for parent in [root,*[o for o in root.children_recursive if o.type=='EMPTY']]:
        parts=[o for o in parent.children if o.type=='MESH']
        if not parts:continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
        bpy.context.object.name='CoastalGullMesh' if parent==root else parent.name+'Mesh'
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)

def far_export(name, folded=False):
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    for o in list(root.children_recursive):
        if o.type!='MESH':continue
        if folded and o.parent!=root and o.parent.name!='FoldedWings':continue
        if not folded and o.parent.name in ('FoldedWings','Legs'):continue
        c=o.copy();c.data=o.data.copy();bpy.context.collection.objects.link(c)
        c.matrix_world=o.matrix_world.copy();c.parent=None
        rest=[v.co.copy() for v in c.data.shape_keys.key_blocks['WaterRest'].data] if folded and c.data.shape_keys and 'WaterRest' in c.data.shape_keys.key_blocks else None
        c.shape_key_clear()
        if rest:
            for vertex,co in zip(c.data.vertices,rest):vertex.co=co
        c.select_set(True);copies.append(c)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();c=bpy.context.object
    d=c.modifiers.new('Distance simplification','DECIMATE');d.ratio=.035
    bpy.ops.object.modifier_apply(modifier=d.name)
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/(name+'_far.glb')),use_selection=True,export_format='GLB',export_animations=False)
    bpy.data.objects.remove(c,do_unlink=True)

for species in ('white_tailed_eagle','arctic_tern'):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    root=bpy.data.objects.new(species,None);bpy.context.collection.objects.link(root)
    mat=bpy.data.materials.new(species+'Plumage');mat.use_nodes=True
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas(species)
    bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.8
    mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    exec(compile(helpers,'bird_helpers','exec'),globals())
    eagle=species=='white_tailed_eagle'
    if eagle:
        loft('Body',[(-.33,.01,.02,.03),(-.23,.05,.10,.09),(-.04,.06,.145,.13),(.15,.08,.12,.13),(.28,.12,.09,.095),(.38,.14,.076,.078),(.45,.13,.048,.05)],0,sides=28)
        # Heavy yellow hooked bill, pale head/neck, small eyes beneath brow.
        loft('Head',[(.20,.12,.075,.075),(.31,.155,.085,.085),(.42,.152,.070,.070),(.47,.128,.044,.044)],9,sides=24)
        loft('Bill',[(.435,.13,.044,.045),(.49,.13,.039,.040),(.535,.112,.025,.035),(.55,.065,.008,.018),(.535,.052,.002,.002)],5)
        for s in (-1,1):
            sphere('Iris',(s*.073,.385,.165),(.005,.013,.012),7)
            sphere('Pupil',(s*.077,.388,.165),(.003,.006,.007),8)
            feather('Brow',(s*.065,.345,.18),(s*.069,.422,.178),.016,9)
        for i in range(12):
            x=(i-5.5)*.018
            feather('WhiteTail',(x*.6,-.24,.035),(x*1.35,-.49+abs(x)*.7,.01),.023,4)
        span,arm,width=.98,.50,.28
    else:
        loft('Body',[(-.16,.0,.002,.004),(-.09,.025,.035,.034),(0,.035,.045,.045),(.075,.059,.030,.036),(.115,.075,.028,.032),(.15,.076,.027,.025),(.165,.066,.017,.014)],0,sides=24)
        # Black breeding cap, slender straight red bill and deep forked tail.
        sphere('BlackCap',(0,.124,.087),(.029,.043,.026),9)
        loft('Bill',[(.15,.068,.010,.008),(.19,.068,.008,.006),(.23,.063,.001,.001)],5)
        for s in (-1,1):
            sphere('Eye',(s*.027,.141,.075),(.002,.005,.005),8)
            for i in range(6):
                t=i/5
                feather('ForkTail',(s*.015,-.10,.018),(s*(.022+.036*t),-.20-.13*t*t,.009),.012,4)
        span,arm,width=.36,.17,.09
    for s,label in ((-1,'Left'),(1,'Right')):
        wing=bpy.data.objects.new(label+'Wing',None);bpy.context.collection.objects.link(wing);wing.parent=root;wing.location=(s*(.11 if eagle else .037),.035,.08 if eagle else .045)
        tip=bpy.data.objects.new(label+'WingTip',None);bpy.context.collection.objects.link(tip);tip.parent=wing;tip.location=(s*arm,0,0)
        sections=[(0,.03,-width*.65,.01),(arm*.35,.055,-width,.015),(arm*.75,.03,-width,.012),(arm,.015,-width*.8,.006)]
        verts=[];uvs=[]
        for i,(x,front,back,thick) in enumerate(sections):
            for j in range(17):
                a=j/16*math.tau
                verts.append((s*x,(front+back)/2+math.cos(a)*(front-back)/2,math.sin(a)*thick));uvs.append(uv_tile(j/16,i/3,1))
        mesh(label+'Arm',verts,[(i*17+j,i*17+j+1,(i+1)*17+j+1,(i+1)*17+j) for i in range(3) for j in range(16)],uvs,wing)
        for i in range(12):
            t=i/11
            feather('Secondary',(s*arm*t,-.02,0),(s*(arm*t+.025),-width*(1.10-.12*t),-.007),width*.105,2,wing)
        for i in range(10):
            t=i/9
            # Eagle primaries spread into clearly separated fingers. Tern ends in a point.
            end=(s*(.20+.30*t),-.28+.32*t,-.003) if eagle else (s*(.065+.14*t),-.065-.055*t,-.004)
            feather('Primary',(s*t*(.15 if eagle else .06),-.015,0),end,.033 if eagle else .014,3,tip)
        feather('WristCover',(0,.01,.018),(s*(.32 if eagle else .15),-.065,.007),.095 if eagle else .035,1,tip)
    fold=bpy.data.objects.new('FoldedWings',None);bpy.context.collection.objects.link(fold);fold.parent=root
    legs=bpy.data.objects.new('Legs',None);bpy.context.collection.objects.link(legs);legs.parent=root
    for s in (-1,1):
        for i in range(8):
            t=i/7
            feather('Fold',(s*(.10 if eagle else .035),.09-t*.09,.09 if eagle else .05),(s*(.04+t*.05 if eagle else .02+t*.01),-.30 if eagle else -.16,.01),.04 if eagle else .015,1,fold)
        sphere('TuckedFoot',(s*(.065 if eagle else .015),-.08,-.07 if eagle else -.024),(.018,.045,.016) if eagle else (.005,.018,.005),6,legs)
    batch()
    # Preview morph API: flight-only species currently have no water-rest states.
    body=bpy.data.objects['CoastalGullMesh'];body.shape_key_add(name='Basis')
    for name in ('WaterRest','NeckLift','LookLeft','LookRight'):body.shape_key_add(name=name)
    bpy.context.view_layer.update()
    far_export(species)
    bpy.ops.object.select_all(action='DESELECT')
    for o in [root,*root.children_recursive]:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/(species+'.glb')),use_selection=True,export_format='GLB',export_animations=False,export_apply=False,export_morph=True)
    # Save an editable wing cycle in the source only.
    scene=bpy.context.scene;scene.frame_start=1;scene.frame_end=48;scene.render.fps=24
    for frame in range(1,50):
        phase=(frame-1)/48*math.tau
        for s,label in ((-1,'Left'),(1,'Right')):
            o=bpy.data.objects[label+'Wing'];o.rotation_euler.y=-s*(.10+.38*math.sin(phase));o.keyframe_insert('rotation_euler',frame=frame)
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(species+'.blend')))
    print('BIRD_ASSET',species,flush=True)
# Bake the existing gull's far representation too.
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'coastal_gull.blend'))
root=bpy.data.objects['CoastalGull']
for o in root.children_recursive:
    o.animation_data_clear()
    if o.type=='EMPTY':o.rotation_euler=(0,0,0)
bpy.context.view_layer.update();far_export('herring_gull')

far_export('herring_gull_rest',folded=True)
