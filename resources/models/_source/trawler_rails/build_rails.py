"""Individual Blender railing panels, bulwarks and joints with explicit end sockets.
Metres, +Y forward in Blender. Exported models use Godot -Z forward.
"""
import bpy, math, os, json
from mathutils import Vector

ROOT=r'C:\Users\noahs\Documents\angst-n-anchors\resources\models'
OUT=os.path.join(ROOT,'parts','trawler_rails')
SRC=os.path.dirname(os.path.abspath(__file__))
RENDER=r'C:\Users\noahs\Documents\Codex\2026-10-05\referenced-chatgpt-conversation-this-is-an\outputs\trawler-rails'
os.makedirs(RENDER,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
master=bpy.context.scene
master.name='Railing kit review'
assets={}; manifest=[]

def material(name,col,metal,rough):
    m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m

steel=material('Galvanized marine rail',(.58,.64,.65),.72,.34)
paint=material('Warm white painted steel',(.74,.78,.75),.30,.42)
capmat=material('Dark gunwale cap',(.075,.13,.15),.5,.4)

def rod(name,a,b,r,mat):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=r,depth=(b-a).length,location=(a+b)*.5)
    o=bpy.context.object;o.name=name;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();o.data.materials.append(mat)
    for f in o.data.polygons:f.use_smooth=True
    return o

def panel_mesh(name,dx,run,h0,h1,thickness,mat):
    normal=Vector((run,-dx,0)).normalized()*thickness/2
    pts=[Vector((0,0,0)),Vector((dx,run,0)),Vector((dx,run,h1)),Vector((0,0,h0))]
    verts=[tuple(p+normal*s) for s in [-1,1] for p in pts]
    faces=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o);o.data.materials.append(mat)
    bevel=o.modifiers.new('Rounded manufactured edges','BEVEL');bevel.width=.003;bevel.segments=2
    return o

def socket(name,pos):
    o=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(o);o.location=pos;o.empty_display_size=.08

def seamless_wall(dx,run,h0,h1,m0=None,m1=None):
    normal=Vector((run,-dx,0)).normalized()
    m0=Vector(m0) if m0 is not None else normal
    m1=Vector(m1) if m1 is not None else normal
    for name,profile,mat in [
        ('Seamless solid halfwall',[(-.04,0),(.04,0),(.04,1),(-.04,1)],paint),
        ('Seamless top cap',[(-.05,-.015),(.05,-.015),(.05,.015),(.04,.025),(-.04,.025),(-.05,.015)],capmat)]:
        verts=[]
        for origin,m,height in [(Vector((0,0,0)),m0,h0),(Vector((dx,run,0)),m1,h1)]:
            for offset,z in profile:
                p=origin+m*offset
                p.z=z*height if mat==paint else height+z
                verts.append(tuple(p))
        n=len(profile)
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj);mesh.materials.append(mat)
        # No end-edge bevel: adjoining panels share identical end profiles.

def asset(id,style,dx=0,run=1,h0=1,h1=1,joint=False,m0=None,m1=None):
    scene=bpy.data.scenes.new(id);scene.unit_settings.system='METRIC';bpy.context.window.scene=scene
    if joint:
        rod('Joint post',(0,0,0),(0,0,h0),.028 if style=='rail' else .06,steel if style=='rail' else paint)
        if style=='rail':
            bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=.07,depth=.012,location=(0,0,.006))
            bpy.context.object.name='Mounting foot';bpy.context.object.data.materials.append(steel)
    elif style=='rail':
        rod('Top rail',(0,0,h0),(dx,run,h1),.024,steel)
        rod('Mid rail',(0,0,h0*.52),(dx,run,h1*.52),.019,steel)
        panel_mesh('Toe plate',dx,run,.10,.10,.012,paint)
    else:
        seamless_wall(dx,run,h0,h1,m0,m1)
    socket('SocketStart',(0,0,0))
    if not joint:socket('SocketEnd',(dx,run,0))
    bpy.ops.object.select_all(action='SELECT')
    for o in scene.objects:
        if o.type=='MESH':
            bpy.context.view_layer.objects.active=o
            for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,id+'.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_apply=True)
    bpy.data.libraries.write(os.path.join(SRC,id+'.blend'),{scene},fake_user=True)
    assets[id]=scene
    manifest.append({'id':id,'style':style,'kind':'joint' if joint else 'panel','model':'res://resources/models/parts/trawler_rails/'+id+'.glb','start_xz':[0,0],'end_xz':[dx,-run] if not joint else [0,0],'height_start_m':h0,'height_end_m':h1 if not joint else h0,'angle_deg':math.degrees(math.atan2(abs(dx),run)) if not joint else 0})

for style,base in [('rail',1.0),('halfwall',.75)]:
    for run in [.5,1.0]:asset(f'{style}_straight_{int(run*100)}cm',style,run=run,h0=base,h1=base)
    for hand,sign in [('port',1),('starboard',-1)]:
        for angle,run in [('26',1),('45',.5)]:asset(f'{style}_{angle}_{hand}',style,dx=sign*.5,run=run,h0=base,h1=base)
        for step in range(5):
            angle='26' if step<2 else '45';run=1 if step<2 else .5
            asset(f'{style}_{angle}_{hand}_rise_{step+1}',style,dx=sign*.5,run=run,h0=base+step*.15,h1=base+(step+1)*.15)
    if style=='rail':
        for level in range(6):asset(f'{style}_joint_{level}',style,h0=base+level*.15,joint=True)

json.dump({'units':'metres','origin':'start socket at deck level','rise_step_m':.15,'assets':manifest},open(os.path.join(OUT,'manifest.json'),'w'),indent=2)

def instance(id,position,yaw=0):
    root=bpy.data.objects.new(id,None);bpy.context.scene.collection.objects.link(root)
    root.location=position;root.rotation_euler.z=yaw
    for original in assets[id].objects:
        if original.type!='MESH':continue
        o=original.copy();o.data=original.data;bpy.context.scene.collection.objects.link(o);o.parent=root
    return root

def assembly(style,rising):
    scene=bpy.data.scenes.new(style+('_rising' if rising else '_flat'));bpy.context.window.scene=scene
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'vessels','trawler_hull_14m','trawler_hull_14m.glb'))
    placements=[];joints={};endpoints=[];segments=[]
    base=1 if style=='rail' else .75
    def place(id,x,y,dx,dy,h0,h1,yaw=0):
        segments.append((id,x,y,dx,dy,h0,h1,yaw))
        for px,py,h in [(x,y,h0),(x+dx,y+dy,h1)]:
            key=(round(px,6),round(py,6))
            if key in joints:assert abs(joints[key]-h)<1e-6,('height mismatch',key)
            joints[key]=h;endpoints.append(key)
    for hand,sign in [('port',1),('starboard',-1)]:
        x=-2.5 if hand=='port' else 2.5;y=-7
        for i in range(10):place(style+'_straight_100cm',x,y,0,1,base,base);y+=1
        place(style+'_straight_50cm',x,y,0,.5,base,base);y+=.5
        for step in range(5):
            angle='26' if step<2 else '45';run=1 if step<2 else .5
            h0=base+(.15*step if rising else 0);h1=base+(.15*(step+1) if rising else 0)
            id=f'{style}_{angle}_{hand}'+(f'_rise_{step+1}' if rising else '')
            place(id,x,y,sign*.5,run,h0,h1);x+=sign*.5;y+=run
        assert abs(x)<1e-6 and abs(y-7)<1e-6
    for i in range(5):place(style+'_straight_100cm',-2.5+i,-7,1,0,base,base,-math.pi/2)
    # Every panel endpoint is paired with exactly one neighbour.
    assert len(endpoints)==74 and all(endpoints.count(p)==2 for p in joints)
    seams={}
    for segment_index,(id,x,y,dx,dy,h0,h1,yaw) in enumerate(segments):
        if style=='halfwall':
            direction=Vector((dx,dy,0)).normalized()
            normal=Vector((direction.y,-direction.x,0))
            miters=[]
            for endpoint,at_start in [(Vector((x,y,0)),True),(Vector((x+dx,y+dy,0)),False)]:
                for j,other in enumerate(segments):
                    if j==segment_index:continue
                    _,ox,oy,odx,ody,*_=other
                    a=Vector((ox,oy,0));b=Vector((ox+odx,oy+ody,0))
                    if (a-endpoint).length<1e-6:away=(b-a).normalized();break
                    if (b-endpoint).length<1e-6:away=(a-b).normalized();break
                neighbour=-away if at_start else away
                nn=Vector((neighbour.y,-neighbour.x,0))
                m=(normal+nn)/(1+normal.dot(nn))
                # Transform the world miter into this panel's local coordinates.
                miters.append((m.x*math.cos(yaw)+m.y*math.sin(yaw),-m.x*math.sin(yaw)+m.y*math.cos(yaw),0))
            signature='_'.join(str(round(v*10000)) for m in miters for v in m[:2])
            variant=id+'_miter_'+signature
            if variant not in assets:
                local_dx=dx*math.cos(yaw)+dy*math.sin(yaw)
                local_run=-dx*math.sin(yaw)+dy*math.cos(yaw)
                asset(variant,style,dx=local_dx,run=local_run,h0=h0,h1=h1,m0=miters[0],m1=miters[1])
            id=variant;bpy.context.window.scene=scene
        root=instance(id,(x,y,2.92),yaw)
        placements.append({'asset_id':id,'position':[x,2.92,-y],'yaw_degrees':math.degrees(yaw)})
        if style=='halfwall':
            bpy.context.view_layer.update()
            for end,key in [(0,(round(x,6),round(y,6))),(1,(round(x+dx,6),round(y+dy,6)))]:
                ring=set()
                for obj in root.children:
                    n=len(obj.data.vertices)//2
                    for vertex in list(obj.data.vertices)[end*n:(end+1)*n]:
                        ring.add(tuple(round(v,6) for v in (obj.matrix_world@vertex.co)))
                if key in seams:assert seams[key]==ring,('Miter geometry mismatch',key,seams[key],ring)
                seams[key]=ring
    for (x,y),height in (joints.items() if style=='rail' else []):
        level=round((height-base)/.15)
        id=f'{style}_joint_{level}';instance(id,(x,y,2.92))
        placements.append({'asset_id':id,'position':[x,2.92,-y],'yaw_degrees':0})
    json.dump({'style':style,'rising':rising,'panel_count':37,'joint_count':37 if style=='rail' else 0,'max_endpoint_gap_m':0,'verified_matching_miter_profiles':len(seams),'placements':placements},open(os.path.join(OUT,scene.name+'_assembly.json'),'w'),indent=2)
    return scene

def setup_render(scene,location=(12,18,14),target=(0,0,2.5),scale=19):
    bpy.context.window.scene=scene
    world=bpy.data.worlds.new(scene.name+' studio');scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.10,.13,.17,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.55
    for name,pos,power,size in [('Key',(4,3,14),2800,9),('Fill',(-7,-2,7),2100,8),('Rim',(0,9,8),1800,6)]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
        o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    camera_data=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',camera_data);scene.collection.objects.link(camera)
    camera.location=location;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.type='ORTHO';camera_data.ortho_scale=scale;scene.camera=camera
    scene.render.engine='CYCLES';scene.cycles.samples=24
    scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'

for style in ['rail','halfwall']:
    for rising in [False,True]:
        scene=assembly(style,rising);setup_render(scene)
        scene.render.filepath=os.path.join(RENDER,scene.name+'.png');bpy.ops.render.render(write_still=True)
        if style=='halfwall' and rising:
            scene.camera.location=(7,12,8);scene.camera.rotation_euler=(Vector((0,5,3.7))-scene.camera.location).to_track_quat('-Z','Y').to_euler();scene.camera.data.ortho_scale=7
            scene.render.filepath=os.path.join(RENDER,'bow-joins.png');bpy.ops.render.render(write_still=True)

json.dump({'units':'metres','origin':'start socket at deck level','rise_step_m':.15,'assets':manifest},open(os.path.join(OUT,'manifest.json'),'w'),indent=2)
bpy.context.window.scene=master
representatives=[a for a in manifest if a['kind']=='panel' and ('starboard' not in a['id']) and '_miter_' not in a['id']]
for i,a in enumerate(representatives):
    x=(i%5)*2.8;y=-(i//5)*3
    instance(a['id'],(x,y,0))
    data=bpy.data.curves.new(a['id'],'FONT');data.body=a['id'].replace('_',' ');data.size=.16
    text=bpy.data.objects.new('Label',data);master.collection.objects.link(text);text.location=(x-.3,y-.5,0);text.data.materials.append(paint)
setup_render(master,(16,-18,22),(5,-4,0),18)
master.render.resolution_x=2000;master.render.resolution_y=1500
master.render.filepath=os.path.join(RENDER,'individual-pieces.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC,'trawler_railing_kit.blend'))
print(f'RAILING_KIT_COMPLETE: {len(manifest)} individual assets; four closed assemblies; halfwall miter profiles verified',flush=True)
