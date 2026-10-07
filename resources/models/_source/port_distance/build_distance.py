"""Offline lightweight 3D proxies from the project's assembled crane poses.
Run export_crane_sources.tscn isolated first; imports contain no gameplay scripts.
"""
import bpy
from mathutils import Vector
from pathlib import Path
SRC=Path(__file__).resolve().parent
OUT=SRC.parents[1]/'scenery/port_distance';OUT.mkdir(parents=True,exist_ok=True)
for kind in ['provision','bulk']:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SRC/(kind+'_source.glb')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    # Shared low-frequency material palette, no baked sunlight or tiny texture
    # glints. Keep the equipment silhouette and cabin/counterweight massing.
    palette=[]
    for name,color in [('Paint',(.46,.31,.08)),('Steel',(.09,.11,.12)),('Glass',(.15,.24,.27))]:
        mat=bpy.data.materials.new(name);mat.use_nodes=True
        p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.86;p.inputs['Specular IOR Level'].default_value=.1
        palette.append(mat)
    for ob in meshes:
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
        ob.data=ob.data.copy()
        bpy.context.view_layer.objects.active=ob
        # Preserve complete world pose when dropping the animated node hierarchy.
        xf=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=xf
        original=list(ob.data.materials)
        mapping=[]
        for mat in original:
            n=mat.name.lower() if mat else ''
            mapping.append(2 if 'glass' in n else 0 if any(k in n for k in ['paint','ochre','yellow']) else 1)
        indices=[mapping[p.material_index] if p.material_index<len(mapping) else 1 for p in ob.data.polygons]
        ob.data.materials.clear()
        for mat in palette:ob.data.materials.append(mat)
        for p,i in zip(ob.data.polygons,indices):p.material_index=i
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        # Reduce each independently so small major structural components survive.
        if len(ob.data.polygons)>60:
            dec=ob.modifiers.new('Distance simplification','DECIMATE');dec.decimate_type='DISSOLVE';dec.angle_limit=.6
            bpy.ops.object.modifier_apply(modifier=dec.name)
            dec=ob.modifiers.new('Silhouette reduction','DECIMATE');dec.ratio=.25
            bpy.ops.object.modifier_apply(modifier=dec.name)
    if kind == 'bulk':
        # Runtime-generated hoist lines are not part of the imported GLTF.
        # Retain their silhouette between the authored boom and grab seats.
        boom=next(o for o in meshes if o.name=='crane_boom_30m')
        grab=next(o for o in meshes if o.name=='grab_head')
        top=max((boom.matrix_world@v.co).z for v in boom.data.vertices)
        bottom=max((grab.matrix_world@v.co).z for v in grab.data.vertices)
        a=Vector((grab.matrix_world.translation.x,grab.matrix_world.translation.y,top))
        b=Vector((a.x,a.y,bottom))
        bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=.055,depth=(a-b).length,location=(a+b)*.5)
        rope=bpy.context.object;rope.name='DistanceHoistLine'
        for mat in palette:rope.data.materials.append(mat)
        for polygon in rope.data.polygons:polygon.material_index=1
        meshes.append(rope)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();ob=bpy.context.object
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    ids=[p.material_index%3 for p in ob.data.polygons]
    ob.data.materials.clear()
    for mat in palette:ob.data.materials.append(mat)
    for p,i in zip(ob.data.polygons,ids):p.material_index=i
    for other in list(bpy.context.scene.objects):
        if other!=ob:bpy.data.objects.remove(other,do_unlink=True)
    ob.name=kind+'_distance';ob.data.calc_loop_triangles();print('PROXY BUDGET',kind,len(ob.data.loop_triangles))
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(kind+'_distance.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'_distance.glb')),export_format='GLB',use_selection=True,export_apply=True)
