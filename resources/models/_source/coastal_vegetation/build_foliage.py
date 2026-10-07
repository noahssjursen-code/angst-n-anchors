"""Blender-authored foliage sprays, card trees and matching distant silhouettes.
All texture pixels originate from rendering authored leaf/needle geometry.
Run with Blender --background --python this_file.py. Metres, Blender Z up.
"""
import bpy, math, random
from pathlib import Path
from mathutils import Vector
S=Path(__file__).resolve().parent
O=S.parents[1]/'scenery/coastal_vegetation';O.mkdir(parents=True,exist_ok=True)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=8
scene.render.film_transparent=True
scene.view_settings.view_transform='Standard'
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
random.seed(2801)

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def plain(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=.95
    return m
def geometry(name,v,f,material,uv=None):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.materials.append(material)
    ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob)
    if uv:
        layer=me.uv_layers.new()
        for poly in me.polygons:
            for j,li in enumerate(poly.loop_indices):layer.data[li].uv=uv[j%4]
    return ob
def tube(a,b,r,mat):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=5,radius1=r,radius2=r*.5,depth=d.length,location=(a+b)*.5)
    ob=bpy.context.object;ob.rotation_euler=d.to_track_quat('Z','Y').to_euler();ob.data.materials.append(mat)
    return ob
def bake(path,center,size,angle=0,res=512):
    cam_data=bpy.data.cameras.new('BakeCamera');cam=bpy.data.objects.new('BakeCamera',cam_data);scene.collection.objects.link(cam)
    cam.location=Vector(center)+Vector((math.sin(angle)*25,-math.cos(angle)*25,0))
    cam.rotation_euler=(Vector(center)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.type='ORTHO';cam_data.ortho_scale=size;scene.camera=cam
    world=bpy.data.worlds.new('DiffuseBakeWorld');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.8,.8,.8,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=1.0;scene.world=world
    scene.render.resolution_x=res;scene.render.resolution_y=res;scene.render.resolution_percentage=100
    scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)
def textured(name,path):
    m=plain(name,(1,1,1));p=m.node_tree.nodes.get('Principled BSDF')
    t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(path),check_existing=True)
    m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']);m.node_tree.links.new(t.outputs['Alpha'],p.inputs['Alpha'])
    m.surface_render_method='DITHERED';m.use_backface_culling=False
    return m
def join_save(name):
    bpy.ops.object.select_all(action='DESELECT')
    obs=[o for o in scene.objects if o.type=='MESH']
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();ob=bpy.context.object
    scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    ob.name=name
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(S/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(O/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    ob.data.calc_loop_triangles();print('FOLIAGE_BUDGET',name,len(ob.data.loop_triangles),flush=True)
    return ob

# Render branch sprays with hundreds of individually shaped leaves/needles.
for broad in [False,True]:
    clear();name='birch_spray' if broad else 'needle_spray'
    twig=plain('Twig',(.13,.085,.04));leafmats=[plain('Leaf'+str(i),((.12+i*.014),(.22+i*.016),(.065+i*.009))) for i in range(5)]
    tube((0,0,-.9),(0,0,.85),.015,twig)
    verts=[[] for _ in range(5)];faces=[[] for _ in range(5)]
    for k in range(14):
        z=-.75+k*.11;side=-1 if k%2 else 1
        tip=Vector((side*(.65-.2*(z+.7)),0,z+.28));base=Vector((0,0,z))
        tube(base,tip,.008,twig)
        for j in range(18 if broad else 110):
            t=random.uniform(.1,1);c=base.lerp(tip,t)+Vector((random.uniform(-.08,.08),random.uniform(-.09,.09),random.uniform(-.05,.05)))
            length=random.uniform(.09,.15) if broad else random.uniform(.08,.14)
            width=length*(.48 if broad else .16)
            a=random.uniform(-math.pi,math.pi);u=Vector((math.cos(a),0,math.sin(a)))*length
            v=Vector((-math.sin(a),0,math.cos(a)))*width
            ix=random.randrange(5);n=len(verts[ix]);verts[ix].extend([c-u,c-v+Vector((0,-.025,0)),c+u,c+v]);faces[ix].append((n,n+1,n+2,n+3))
    for i in range(5):geometry(name,verts[i],faces[i],leafmats[i])
    bake(O/(name+'.png'),(0,0,0),2.1,res=512)

for species in ['pine','birch','spruce','juniper']:
    clear();random.seed(400+['pine','birch','spruce','juniper'].index(species))
    leaf=textured(species+' Foliage',O/('birch_spray.png' if species=='birch' else 'needle_spray.png'))
    bark=plain(species+' Bark',(.48,.46,.39) if species=='birch' else (.16,.095,.045))
    height={'pine':11,'birch':10,'spruce':14,'juniper':2.6}[species]
    tube((0,0,0),(.18,0,height*.86),.17 if species!='juniper' else .055,bark)
    v=[];f=[]
    for level in range(15 if species=='spruce' else 10):
        z=(.15+level*.054)*height if species=='spruce' else (.40+level*.05)*height
        if species=='pine':z=(.62+level*.03)*height
        if species=='juniper':z=.3+level*.17
        radius=(1-level/16)*3.4 if species=='spruce' else 2.9*(1-abs(level-5)/9)
        if species=='pine':radius=3.7*(1-abs(level-4)/9)
        if species=='juniper':radius*=.65
        for arm in range(5):
            angle=arm*math.tau/5+level*2.4+random.uniform(-.2,.2)
            radius_j=radius*random.uniform(.7,1.2)
            end=Vector((math.cos(angle)*radius_j,math.sin(angle)*radius_j,z+random.uniform(-.3,.6)))
            start=Vector((0,0,z-.25));tube(start,end,.035 if species!='juniper' else .015,bark)
            for j in range(5):
                c=start.lerp(end,(.65+j*.085) if species=='pine' else (.28+j*.18))
                c.z+=random.uniform(-.22,.35)
                a=angle+random.uniform(-1,1)
                width=(.8 if species=='spruce' else 1.05)*random.uniform(.8,1.15)
                if species=='juniper':width*=.55
                u=Vector((math.cos(a),math.sin(a),0))*width*.5
                tilt=random.uniform(.55,1.4) if species in ['pine','spruce'] else random.uniform(.1,1.4)
                up=Vector((-math.sin(tilt)*math.sin(a),math.sin(tilt)*math.cos(a),math.cos(tilt)))*width*.65
                n=len(v);v.extend([c-u-up,c+u-up,c+u+up,c-u+up]);f.append((n,n+1,n+2,n+3))
    geometry(species+' Sprays',v,f,leaf,[(0,0),(1,0),(1,1),(0,1)])
    tree=join_save(species+'_near')
    # Matching whole-tree texture; texture is re-lit in Godot, never emissive.
    size=height*1.12
    bake(O/(species+'_silhouette.png'),(0,0,height*.5),size,res=1024)
    clear();m=textured(species+' Silhouette',O/(species+'_silhouette.png'))
    vv=[];ff=[]
    # One upright view-facing card at distance. Crossed planes create dark
    # vertical bands through the same baked crown and triple alpha overdraw.
    for angle in [0]:
        u=Vector((math.cos(angle),math.sin(angle),0))*size*.5
        c=Vector((0,0,height*.5));up=Vector((0,0,size*.5));n=len(vv)
        vv.extend([c-u-up,c+u-up,c+u+up,c-u+up]);ff.append((n,n+1,n+2,n+3))
    geometry(species,vv,ff,m,[(0,0),(1,0),(1,1),(0,1)])
    join_save(species+'_mid')
