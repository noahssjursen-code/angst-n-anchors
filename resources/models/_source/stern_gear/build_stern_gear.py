"""Independent metre-scale stern gear. Blender +Y bow, +Z up.
Run Blender --background --python this_file. No runtime geometry generation.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector

SOURCE = Path(__file__).resolve().parent
OUT = SOURCE.parents[1] / 'parts' / 'stern_gear'
OUT.mkdir(parents=True, exist_ok=True)

def material(name, color, metal, rough):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    return m

def mesh(name, vertices, faces, mat):
    data=bpy.data.meshes.new(name); data.from_pydata(vertices,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    for p in data.polygons:p.use_smooth=True
    return ob

def cylinder(name, a, b, radius, mat):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=radius,depth=(b-a).length,location=(a+b)/2)
    ob=bpy.context.object;ob.name=name;ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:p.use_smooth=True
    return ob

def box(name, location, dimensions, mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location)
    ob=bpy.context.object;ob.name=name;ob.dimensions=dimensions
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(mat)
    bevel=ob.modifiers.new('Small machined edge','BEVEL');bevel.width=.009;bevel.segments=3
    ob.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return ob

def clear():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def export(asset, socket):
    empty=bpy.data.objects.new(socket,None);bpy.context.collection.objects.link(empty)
    bpy.ops.object.select_all(action='SELECT')
    for ob in bpy.context.selected_objects:
        if ob.type=='MESH':
            bpy.context.view_layer.objects.active=ob
            bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(asset+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(asset+'.glb')),export_format='GLB',use_selection=True,export_apply=True)

clear()
bronze=material('Fixed_PropellerBronze',(.52,.30,.095),.82,.28)
steel=material('Fixed_ShaftStainless',(.44,.50,.53),.85,.25)
paint=material('Paint_HullLower',(.36,.075,.043),0.0,.72)
rubber=material('Fixed_Bearing',(.024,.027,.03),.25,.62)

# Shaft axis through local origin; four cambered, twisted blades, not flat paddles.
cylinder('Propeller hub',(0,-.14,0),(0,.14,0),.105,bronze)
for blade in range(4):
    verts=[];faces=[]; nr,nc=20,16
    for side in [-1,1]:
        for i in range(nr+1):
            t=i/nr;r=.095+.425*t
            chord=.10+.22*math.sin(math.pi*t)**.7
            pitch=.8-.43*t;skew=.36*t*t
            for j in range(nc+1):
                u=j/nc; tang=(u-.5)*chord
                thickness=.014*math.sin(math.pi*u)*math.sin(math.pi*(.08+.84*t))
                angle=blade*math.pi/2+skew
                x=r*math.cos(angle)-tang*math.cos(pitch)*math.sin(angle)
                z=r*math.sin(angle)+tang*math.cos(pitch)*math.cos(angle)
                y=tang*math.sin(pitch)+.022*math.sin(math.pi*u)+side*thickness
                verts.append((x,y,z))
    n=(nr+1)*(nc+1)
    for side in range(2):
        for i in range(nr):
            for j in range(nc):
                a=side*n+i*(nc+1)+j
                face=(a,a+1,a+nc+2,a+nc+1)
                faces.append(face if side else tuple(reversed(face)))
    perimeter=list(range(nc+1))+[i*(nc+1)+nc for i in range(1,nr+1)]+[nr*(nc+1)+j for j in range(nc-1,-1,-1)]+[i*(nc+1) for i in range(nr-1,0,-1)]
    for a,b in zip(perimeter,perimeter[1:]+perimeter[:1]):faces.append((a,b,b+n,a+n))
    mesh('Swept bronze blade %d'%blade,verts,faces,bronze)
cylinder('Shaft nut',(0,-.18,0),(0,-.14,0),.075,steel)
export('propeller_1040','ShaftAxis')

clear()
# Stock pivot is top of blade; balanced foil has 20% chord ahead of stock.
cylinder('Rudder stock',(0,0,-.95),(0,0,.45),.045,steel)
verts=[];faces=[]; count=40
for height in [-.95,0]:
    for j in range(count):
        u=(1-math.cos(j/count*2*math.pi))/2
        half=.075*(.2969*math.sqrt(u)-.126*u-.3516*u*u+.2843*u**3-.1036*u**4)/.1
        x=half*(1 if j<count/2 else -1)
        # +Y forward; most chord extends aft.
        verts.append((x,.15-.75*u,height))
for j in range(count):faces.append((j,(j+1)%count,(j+1)%count+count,j+count))
faces.extend([tuple(reversed(range(count))),tuple(range(count,count*2))])
mesh('Balanced foil',verts,faces,paint)
export('rudder_0950','StockAxis')

clear()
# Fixed bracket local origin at transom/shaft intersection. Assembly is outside
# the closed transom. Tubes/support stay clear of the propeller swept disc.
cylinder('Stern tube',(0,.12,0),(0,-.28,0),.09,paint)
cylinder('Exposed shaft',(0,-.25,0),(0,-.43,0),.043,steel)
box('Transom mounting plate',(0,.015,.42),(.42,.10,1.1),paint)
for x in [-.15,.15]:
    for z in [.08,.75]:cylinder('Mounting bolt',(x,-.052,z),(x,-.075,z),.024,steel)
box('Upper stock support',(0,-.50,1.0),(.18,1.05,.14),paint)
cylinder('Stock bearing',(0,-1.03,.75),(0,-1.03,1.15),.079,paint)
cylinder('Bearing seal',(0,-1.03,.73),(0,-1.03,.78),.084,rubber)
export('transom_shaft_support','TransomMount')

(OUT/'mounts_14m.json').write_text(json.dumps({
    'version':1,'hull':'trawler_hull_14m','units':'metres',
    'support':[0,.9,7.0], 'propeller':[0,.9,7.48], 'rudder':[0,1.55,8.03],
    'max_rudder_degrees':28,'visual_max_rpm':240,
    'note':'Prototype external transom installation; does not relocate physics force points.'
},indent=2))
print('STERN_GEAR_EXPORTED')
