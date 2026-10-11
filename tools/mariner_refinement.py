"""Refine the original authored mariner, retaining all part/rig/save identifiers.

No external character or garment models. This replaces the old closed trouser
waist union with a continuous crotch and joins the existing hand skin pieces.
"""
import bpy
import bmesh
import math


def refine(objects):
    _trousers(bpy.data.objects['Trousers_Work'])
    _hands(bpy.data.objects['Hands'])
    _sweater(bpy.data.objects['Top_Sweater'])
    obj=bpy.data.objects['Base_Shorts']
    bpy.context.view_layer.objects.active=obj
    dec=obj.modifiers.new('Covered base layer budget','DECIMATE');dec.ratio=.18
    bpy.ops.object.modifier_apply(modifier=dec.name)
    # The cap retains its original crown/band, with a curved, tapered peak.
    cap = bpy.data.objects['Headwear_Cap']
    for v in cap.data.vertices:
        x, y, z = v.co
        if y > .09 and z < 1.766:
            v.co.z -= .010 * (abs(x) / .117) ** 2
            v.co.y -= .018 * (abs(x) / .117) ** 2


def _trousers(obj):
    verts, faces = [], []
    n = 32
    # Ankle / calf / close knee loops / thigh. The original joint centres stay put.
    rings = [(.156,.110,.000,.059,.060), (.28,.110,.000,.065,.067),
             (.36,.110,.000,.072,.073), (.46,.110,.015,.068,.071),
             (.50,.110,.020,.069,.076), (.53,.110,.020,.072,.077),
             (.57,.108,.018,.077,.083), (.72,.102,.004,.090,.092),
             (.84,.098,.000,.095,.105)]
    ends = {}
    for side in [1,-1]:
        start = len(verts)
        for z,cx,cy,rx,ry in rings:
            for i in range(n):
                a = math.tau*i/n
                # Soft rectangular sections retain the old workwear silhouette.
                x = math.copysign(abs(math.cos(a))**.65, math.cos(a))*rx
                y = math.copysign(abs(math.sin(a))**.65, math.sin(a))*ry
                # Lift the front/back hip connection while the inner leg stays
                # down at the actual crotch. No horizontal skirt edge.
                height=z
                if z==.84: height+=.062*abs(math.sin(a))+.035*max(0,side*math.cos(a))
                verts.append((side*cx+x,cy+y,height))
        for j in range(len(rings)-1):
            for i in range(n):
                a=start+j*n+i; b=start+j*n+(i+1)%n
                faces.append((a,b,b+n,a+n))
        faces.append(tuple(reversed(range(start,start+n))))
        ends[side] = start+(len(rings)-1)*n
    # A saddle between the two inside leg arcs, rather than a flat box hem.
    for k in range(n//2):
        la=ends[1]+(8+k)%n; lb=ends[1]+(9+k)%n
        ra=ends[-1]+(8-k)%n; rb=ends[-1]+(7-k)%n
        faces.append((la,ra,rb,lb))
    outline=[ends[1]+i%n for i in range(24,41)]
    outline += [ends[-1]+i for i in range(8,25)]
    count=len(outline)
    previous=outline
    for z,rx,ry in [(.947,.184,.118),(.98,.177,.116),(1.026,.171,.115)]:
        current=[]
        for source in outline:
            x,y,_ = verts[source]
            a=math.atan2(y/.105,x/.193)
            px=rx*math.copysign(abs(math.cos(a))**.67,math.cos(a))
            py=ry*math.copysign(abs(math.sin(a))**.67,math.sin(a))
            current.append(len(verts)); verts.append((px,py,z))
        for i in range(count):
            j=(i+1)%count;faces.append((previous[i],previous[j],current[j],current[i]))
        previous=current
    # Open waist sits beneath sweater, with a turned-in edge rather than a cap.
    inner=[]
    for index in previous:
        x,y,z=verts[index];inner.append(len(verts));verts.append((x*.95,y*.95,z-.006))
    for i in range(count):
        j=(i+1)%count;faces.append((previous[i],previous[j],inner[j],inner[i]))
    data=bpy.data.meshes.new('Mariner work trousers - continuous crotch')
    data.from_pydata(verts,[],faces);data.update()
    data.materials.append(obj.data.materials[0]);obj.data=data
    bpy.context.view_layer.objects.active=obj
    sub=obj.modifiers.new('Tailored hip and knee loops','SUBSURF');sub.levels=1
    bpy.ops.object.modifier_apply(modifier=sub.name)
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
    for p in obj.data.polygons:p.use_smooth=True


def _hands(obj):
    # Keep the original hands and digit locations. Join flesh only; nails remain
    # independent surfaces and retain their original material and finger weights.
    for v in obj.data.vertices:
        if v.co.z>.931:v.co.z+=.024*min(1,(v.co.z-.931)/.016)
    bm=bmesh.new();bm.from_mesh(obj.data)
    nails=[f for f in bm.faces if obj.data.materials[f.material_index].name=='Nails']
    nail_mesh=bpy.data.meshes.new('Retained mariner nails');bm.to_mesh(nail_mesh)
    nb=bmesh.new();nb.from_mesh(nail_mesh)
    bmesh.ops.delete(nb,geom=[f for f in nb.faces if obj.data.materials[f.material_index].name!='Nails'],context='FACES')
    nb.to_mesh(nail_mesh);nb.free()
    bmesh.ops.delete(bm,geom=nails,context='FACES');bm.to_mesh(obj.data);bm.free()
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Continuous original hand skin','REMESH')
    mod.mode='VOXEL';mod.voxel_size=.0016;mod.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    sm=obj.modifiers.new('Palm and knuckle continuity','SMOOTH');sm.factor=.45;sm.iterations=3
    bpy.ops.object.modifier_apply(modifier=sm.name)
    dec=obj.modifiers.new('Hand surface budget','DECIMATE');dec.ratio=.14
    bpy.ops.object.modifier_apply(modifier=dec.name)
    nail_obj=bpy.data.objects.new('Original nails',nail_mesh);bpy.context.collection.objects.link(nail_obj)
    for mat in obj.data.materials:nail_mesh.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);nail_obj.select_set(True)
    bpy.context.view_layer.objects.active=obj;bpy.ops.object.join()


def _sweater(obj):
    # Broaden the forearm and gather the existing cloth gently at cuff/hem.
    for v in obj.data.vertices:
        x,y,z=v.co;ax=abs(x)
        if ax>.15 and z>1.37:
            v.co.z-=.013*min(1,(ax-.15)/.055)*min(1,(z-1.37)/.045)
        if ax>.28 and z<1.19:
            centre=.312+(1.17-z)*.30
            bulge=.011*math.exp(-((z-1.075)/.085)**2)
            v.co.x += math.copysign(bulge*min(1,abs(ax-centre)/.04),x)*(1 if ax>centre else -1)
            v.co.y *= 1+.10*math.exp(-((z-1.075)/.085)**2)
        if ax<.225 and z<1.16:
            # Slight hanging fullness above a fitted ribbed hem.
            factor=1+.027*math.exp(-((z-1.085)/.031)**2)
            v.co.x*=factor;v.co.y*=factor
    # Remove surplus tessellation from the old voxel union without a silhouette
    # reduction at elbows and shoulder. This is still the original garment.
    bpy.context.view_layer.objects.active=obj
    dec=obj.modifiers.new('Garment surface budget','DECIMATE');dec.ratio=.28
    bpy.ops.object.modifier_apply(modifier=dec.name)


def refine_weights(objects):
    def ease(t):
        t=max(0,min(1,t));return t*t*(3-2*t)
    for obj in objects:
        for vertex in obj.data.vertices:
            x,y,z=vertex.co;side='L' if x>=0 else 'R';weights=None
            if obj.name in ['Trousers_Work','Base_Shorts','Body_Legs'] and z>.81:
                hip=ease((z-.82)/.15)
                # Centre seam remains with pelvis during a stride. The outer
                # leg can follow the femur without dragging the opposite thigh.
                centre=1-ease(abs(x)/.075)
                hip=max(hip,centre*ease((z-.81)/.05))
                weights={'hips':hip,'thigh.'+side:1-hip}
            if obj.name in ['Top_Sweater','Body_Arms'] and z>1.30 and abs(x)>.16:
                arm=ease((abs(x)-.17)/.13)
                weights={'chest':(1-arm)*.55,'clavicle.'+side:(1-arm)*.45,'upper_arm.'+side:arm}
            if weights is None:continue
            for group in list(vertex.groups):obj.vertex_groups[group.group].remove([vertex.index])
            for name,weight in weights.items():
                if weight>0:obj.vertex_groups[name].add([vertex.index],weight,'REPLACE')
