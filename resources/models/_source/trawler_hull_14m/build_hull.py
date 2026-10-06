"""Blender-authored standalone fishing hull. Metres; +Y bow, +Z up.
UV textures are generated and packed into both the .blend and exported GLB.
"""
import bpy, bmesh, math, os, json
import numpy as np
from mathutils import Vector

ROOT = r'C:\Users\noahs\Documents\angst-n-anchors\resources\models'
OUT = os.path.join(ROOT, 'vessels', 'trawler_hull_14m')
SOURCE = os.path.dirname(os.path.abspath(__file__))
RENDER = r'C:\Users\noahs\Documents\Codex\2026-10-05\referenced-chatgpt-conversation-this-is-an\outputs\trawler-hull'
os.makedirs(OUT, exist_ok=True)
os.makedirs(RENDER, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
# Straight deck-edge runs. Angles measured from the longitudinal axis.
# Square transom; parallel sides; 3.5 m bow with exact 1:2 and 1:1 slopes.
STATIONS = [(-7,2.5),(3.5,2.5),(5.5,1.5),(7,0)]
DECK = 2.92

def width(y):
    for (a,x),(b,z) in zip(STATIONS,STATIONS[1:]):
        if y <= b:
            t = max(0,min(1,(y-a)/(b-a)))
            return x+(z-x)*t
    return STATIONS[-1][1]

def texture(name, kind):
    n=1024
    rng=np.random.default_rng(48 if kind=='hull' else 91)
    u,v=np.meshgrid(np.linspace(0,1,n),np.linspace(0,1,n))
    grain=rng.normal(0,.013,(n,n))
    rgba=np.ones((n,n,4),dtype=np.float32)
    if kind=='hull':
        color=np.zeros((n,n,3),dtype=np.float32)
        color[:]=(.8,.8,.8) # Neutral paint texture; material slots supply colour.
    else:
        color=np.full((n,n,3),(.29,.33,.33),dtype=np.float32)
        grain += .012*np.sin(u*1600)*np.sin(v*1600)
    rgba[:,:,:3]=np.clip(color+grain[:,:,None],0,1)
    image=bpy.data.images.new(name,n,n,alpha=True)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw=os.path.join(OUT,name+'.png')
    image.file_format='PNG'
    image.save()
    image.pack()
    mat=bpy.data.materials.new(name)
    mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Metallic'].default_value=.35 if kind=='hull' else .12
    bsdf.inputs['Roughness'].default_value=.46 if kind=='hull' else .88
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=image
    mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    return mat

paint=texture('trawler_painted_steel_basecolor','hull')
deckmat=texture('trawler_nonslip_basecolor','deck')
paint.name='Paint_HullUpper'
paint.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.075,.25,.29,1)
# Multiply the neutral texture by a separately exposed paint colour on export.
for link in list(paint.node_tree.links):
    if link.to_socket.name=='Base Color':paint.node_tree.links.remove(link)
paint.diffuse_color=(.075,.25,.29,1)
lower=paint.copy();lower.name='Paint_HullLower';lower.diffuse_color=(.36,.075,.043,1)
lower.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=0.0
lower.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.72
lower.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.36,.075,.043,1)
stripe=paint.copy();stripe.name='Fixed_BootStripe';stripe.diffuse_color=(.035,.045,.045,1)
stripe.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.035,.045,.045,1)
deckmat.name='Paint_Deck'
for material,color in [(paint,(.075,.25,.29,1)),(lower,(.36,.075,.043,1))]:
    nodes=material.node_tree.nodes
    multiply=nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY'
    multiply.inputs[0].default_value=1
    multiply.inputs[2].default_value=color
    material.node_tree.links.new(next(n for n in nodes if n.type=='TEX_IMAGE').outputs['Color'],multiply.inputs[1])
    material.node_tree.links.new(multiply.outputs[0],nodes['Principled BSDF'].inputs['Base Color'])
rubber=bpy.data.materials.new('Rubber rubbing strake')
rubber.diffuse_color=(.025,.03,.03,1)
rubber.use_nodes=True
rubber.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.025,.03,.03,1)
rubber.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.8

def mesh(name,verts,faces,material,uv_kind='hull',smooth=True):
    data=bpy.data.meshes.new(name)
    data.from_pydata(verts,[],faces)
    data.update()
    bm=bmesh.new();bm.from_mesh(data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.00001)
    if name.startswith('Trawler hull'):
        for z in [1.435,1.5785]:
            bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,z),plane_no=(0,0,1),dist=.000001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    uv=data.uv_layers.new(name='UVMap')
    for poly in data.polygons:
        poly.use_smooth=smooth
        for li in poly.loop_indices:
            x,y,z=data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv=((y+7)/14,z/4.1) if uv_kind=='hull' else ((x+2.5)/5,(y+7)/14)
    return obj

ys=[-7+i*14/112 for i in range(113)]
cross=[(-1,1),(-.99,.78),(-.91,.5),(-.70,.25),(-.40,.08),(0,0),(.40,.08),(.70,.25),(.91,.5),(.99,.78),(1,1)]
verts=[]
for y in ys:
    rise=.12+.8*max(0,(y-3)/4)**2+.16*max(0,(-y-4)/3)**2
    for x,h in cross:
        verts.append((x*width(y),y,rise+(DECK-rise)*h))
faces=[]
k=len(cross)
for i in range(len(ys)-1):
    for j in range(k-1):
        a=i*k+j;faces.append((a,a+1,a+1+k,a+k))
faces += [tuple(range(k-1,-1,-1)),tuple((len(ys)-1)*k+j for j in range(k))]
shell=mesh('Trawler hull - formed steel shell',verts,faces,paint)
shell.data.materials.append(lower);shell.data.materials.append(stripe)
for face in shell.data.polygons:
    z=sum(shell.data.vertices[i].co.z for i in face.vertices)/len(face.vertices)
    face.material_index=1 if z<1.435 else (2 if z<1.5785 else 0)
# Keep only real construction corners, not arbitrary samples of a curve.
outline=[(-x,y) for y,x in STATIONS]+[(x,y) for y,x in reversed(STATIONS[:-1])]
deck=mesh('Working deck',[(x,y,DECK) for x,y in outline],[tuple(range(len(outline)))],deckmat,'deck',False)
bpy.ops.object.select_all(action='DESELECT')
for obj in [shell,deck]:obj.select_set(True)
bpy.context.view_layer.objects.active=shell
bpy.ops.object.convert(target='MESH')
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'trawler_hull_14m.glb'),export_format='GLB',use_selection=True,export_apply=True)
with open(os.path.join(OUT,'deck_outline.json'),'w') as f:
    json.dump({'length_m':14,'beam_m':5,'deck_y':DECK,'grid_m':1,'snap_m':.1,'outline_xz':[[x,-y] for x,y in outline]},f,indent=2)
edges=[]
for a,b in zip(outline,outline[1:]+outline[:1]):
    dx,dy=b[0]-a[0],b[1]-a[1]
    angle=math.degrees(math.atan2(abs(dx),abs(dy)))
    allowed=[0,math.degrees(math.atan(1/3)),math.degrees(math.atan(1/2)),45,90]
    assert min(abs(angle-v) for v in allowed)<1e-7
    assert all(abs(v*10-round(v*10))<1e-7 for v in a+b)
    edges.append({'start_xz':[a[0],-a[1]],'end_xz':[b[0],-b[1]],'angle_from_longitudinal_deg':angle,'length_m':math.hypot(dx,dy)})
with open(os.path.join(OUT,'construction_edges.json'),'w') as f:
    json.dump({'modules':[{'run_m':1,'inset_m':.5,'angle_deg':math.degrees(math.atan(1/2))},{'run_m':.5,'inset_m':.5,'angle_deg':45}],'edges':edges},f,indent=2)

world=scene.world or bpy.data.worlds.new('Studio');scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.11,.14,.18,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.55
for name,pos,power,size in [('Key',(3,3,12),2200,9),('Fill',(-6,-3,6),1600,8),('Rim',(0,8,7),1700,6)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=pos
    obj.rotation_euler=(Vector((0,0,1.5))-obj.location).to_track_quat('-Z','Y').to_euler()
camera_data=bpy.data.cameras.new('Review camera');camera=bpy.data.objects.new('Review camera',camera_data)
scene.collection.objects.link(camera);scene.camera=camera
camera.location=(12,17,13);camera.rotation_euler=(Vector((0,0,1.7))-camera.location).to_track_quat('-Z','Y').to_euler()
camera_data.type='ORTHO';camera_data.ortho_scale=18
scene.render.engine='CYCLES';scene.cycles.samples=32
scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,'trawler_hull_14m.blend'))
scene.render.filepath=os.path.join(RENDER,'blender-hull.png');bpy.ops.render.render(write_still=True)
camera.location=(0,0,25);camera.rotation_euler=(0,0,0)
scene.render.resolution_x=900;scene.render.resolution_y=1500
camera_data.ortho_scale=16
scene.render.filepath=os.path.join(RENDER,'angled-hull-top.png');bpy.ops.render.render(write_still=True)
print('TRAWLER_HULL_COMPLETE',flush=True)
