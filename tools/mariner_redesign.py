"""Tailored second-generation mariner body, using connected authored garment loops.
No voxel union or height-threshold material boundaries. Shared skeleton is unchanged.
Head/face authoring is owned by mariner_head.py.
"""
import bpy, bmesh, math
from mathutils import Vector

def rebuild(g):
    objects=g['objects']; skin=g['skin']; top=g['shirt']; pants=g['pants']; boot=g['boot']; sole=g['sole']
    def remove(name):
        obj=bpy.data.objects.get(name)
        if obj:
            if obj in objects:objects.remove(obj)
            bpy.data.objects.remove(obj,do_unlink=True)
    rib=g['mat']('TopRib',(.70,.72,.70),1.0)
    seam=g['mat']('TrouserSeam',(.12,.18,.22),1.0)
    rubber_edge=g['mat']('BootEdge',(.038,.044,.045),.94)
    # Sweater topology: the torso's two real side armholes are stitched into
    # sleeve rings. Neck, hem and cuffs have continuous turned-over edge loops.
    remove('Top_Sweater');remove('Top_Trim')
    vs=[];fs=[];materials=[]
    def vertex(p):vs.append(tuple(p));return len(vs)-1
    def face(indices,mat=0):fs.append(tuple(indices));materials.append(mat)
    def connect(a,b,mat=0):
        for i in range(len(a)):face((a[i],a[(i+1)%len(a)],b[(i+1)%len(b)],b[i]),mat)
    n=32;torso=[]
    for z,rx,ry in [(1.006,.178,.121),(1.016,.180,.122),(1.055,.180,.121),(1.082,.180,.117),(1.18,.178,.110),(1.27,.188,.112),(1.355,.206,.113),(1.405,.207,.101),(1.448,.095,.067),(1.465,.064,.054)]:
        ring=[]
        for i in range(n):
            a=math.tau*i/n;x=rx*math.cos(a);y=ry*math.sin(a)
            # Actual shoulder slope follows toward the upper-arm insertion.
            zz=z
            if z==1.405:zz-=.022*abs(math.cos(a))**2
            if z in (1.082,1.18):y+=.0014*math.cos(a*5+z*21)
            ring.append(vertex((x,y-.003,zz)))
        torso.append(ring)
    omitted=set()
    for j in range(len(torso)-1):
        for i in range(n):
            # Both sockets span three torso bands, with top at sloping shoulder.
            side_sector=i in [29,30,31,0,1,2,13,14,15,16,17,18]
            if 4<=j<=6 and side_sector:
                omitted.add((j,i));continue
            face((torso[j][i],torso[j][(i+1)%n],torso[j+1][(i+1)%n],torso[j+1][i]),1 if j<2 else 0)
    # Enumerate the two boundary loops left by the omitted side panels.
    edges={}
    for f in fs:
        for a,b in zip(f,f[1:]+f[:1]):
            key=tuple(sorted((a,b)));edges[key]=edges.get(key,0)+1
    boundary={}
    excluded=set(torso[0]+torso[-1])
    for (a,b),count in edges.items():
        if count==1 and a not in excluded and b not in excluded:
            boundary.setdefault(a,[]).append(b);boundary.setdefault(b,[]).append(a)
    while boundary:
        start=next(iter(boundary));loop=[start];previous=-1;current=start
        while True:
            nxt=next((v for v in boundary[current] if v!=previous),start)
            if nxt==start:break
            loop.append(nxt);previous,current=current,nxt
        for i in loop:boundary.pop(i,None)
        s=1 if sum(vs[i][0] for i in loop)>0 else -1
        axis=Vector((s*.11,.005,-.265)).normalized();u=Vector((0,1,0));v=axis.cross(u).normalized()
        # Broad upper sleeve, clear elbow loops, forearm ease, fitted wrist cuff.
        specs=[(s*.243,0,1.332,.065,.065),(s*.274,.002,1.265,.060,.061),(s*.306,.005,1.19,.051,.054),(s*.321,.007,1.151,.049,.052),(s*.334,.011,1.113,.050,.052),(s*.352,.018,1.055,.049,.048),(s*.371,.024,.999,.040,.039),(s*.377,.025,.982,.035,.034),(s*.384,.026,.958,.033,.032)]
        count=len(loop)
        # Pick the orientation/phase that joins neighbouring points without twist.
        centre=Vector(specs[0][:3]);rx,ry=specs[0][3:]
        candidates=[]
        for direction in [-1,1]:
            for offset in range(count):
                coords=[centre+u*(rx*math.cos(math.tau*(offset+direction*i)/count))+v*(ry*math.sin(math.tau*(offset+direction*i)/count)) for i in range(count)]
                candidates.append((sum((Vector(vs[loop[i]])-coords[i]).length_squared for i in range(count)),direction,offset))
        _,direction,offset=min(candidates)
        previous=loop
        for k,spec in enumerate(specs):
            centre=Vector(spec[:3]);rx,ry=spec[3:];ring=[]
            for i in range(count):
                a=math.tau*(offset+direction*i)/count
                p=centre+u*(rx*math.cos(a))+v*(ry*math.sin(a))
                if 2<=k<=5:p+=u*(.0012*math.sin(a*3+k))
                ring.append(vertex(p))
            connect(previous,ring,1 if k>=7 else 0);previous=ring
        inner=[]
        for index in previous:inner.append(vertex(centre+(Vector(vs[index])-centre)*.88-axis*.005))
        connect(previous,inner,1)
    # Turned hem underside, with no broad cap across the waist.
    inner=[vertex((vs[i][0]*.96,vs[i][1]*.96,vs[i][2]+.006)) for i in torso[0]]
    connect(inner,torso[0],1)
    sweater=g['mesh']('Top_Sweater',vs,fs,top);sweater.data.materials.append(rib)
    for poly,idx in zip(sweater.data.polygons,materials):poly.material_index=idx
    bpy.context.view_layer.objects.active=sweater
    sub=sweater.modifiers.new('Tailored connected garment','SUBSURF');sub.levels=1
    bpy.ops.object.modifier_apply(modifier=sub.name)
    # Separate visible rib collar has explicit open inner surface; neck remains anatomical.
    def oval(name,rings,material,n=32,power=1.0):
        verts=[];faces=[]
        for x,y,z,rx,ry in rings:
            for i in range(n):
                a=math.tau*i/n
                verts.append((x+rx*math.copysign(abs(math.cos(a))**power,math.cos(a)),y+ry*math.copysign(abs(math.sin(a))**power,math.sin(a)),z))
        for j in range(len(rings)-1):
            for i in range(n):
                a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
        return g['mesh'](name,verts,faces,material)
    collar=oval('Top_Trim',[(0,-.003,1.451,.069,.057),(0,-.003,1.456,.069,.057),(0,-.003,1.483,.061,.052),(0,-.003,1.486,.057,.048),(0,-.003,1.478,.055,.046),(0,-.003,1.451,.058,.048)],rib,40)
    # Small tonal knit only. Yarn varies by a few percent; it must not dominate at distance.
    image=bpy.data.images.new('Mariner fine wool',width=512,height=512);pixels=[]
    for y in range(512):
        for x in range(512):
            u=(x%8-4)/4;v=(y%12)/12
            c=.96+.014*math.cos((v-abs(u)*.3)*math.tau)+.006*math.cos(x*math.pi)
            pixels.extend((c,c,c,1))
    image.pixels.foreach_set(pixels);image.filepath_raw=str(g['OUT']/'mariner_wool.png');image.file_format='PNG';image.save();image.pack()
    for node in top.node_tree.nodes:
        if node.type=='TEX_IMAGE':node.image=image
    # Use the continuous crotch authored by mariner_refinement, tailoring the leg fall.
    trousers=bpy.data.objects['Trousers_Work']
    for vert in trousers.data.vertices:
        x,y,z=vert.co;s=1 if x>=0 else -1
        if z<.82:
            taper=.88+.12*max(0,min(1,(z-.35)/.47))
            centre=s*.11
            vert.co.x=centre+(x-centre)*taper;vert.co.y*=.95
            # Very restrained folds at bent knee; no floating painted knee-pad mesh.
            vert.co.y+=.0018*math.sin(z*48)*math.exp(-((z-.5)/.12)**2)
    bm=bmesh.new();bm.from_mesh(trousers.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,plane_co=(0,0,.277),plane_no=(0,0,1),clear_inner=True)
    bm.to_mesh(trousers.data);bm.free()
    # Pocket opening welts follow the cloth, rather than detached strips/cargo boxes.
    parts=[trousers]
    for s in [-1,1]:
        parts.append(g['tube']('Pocket seam',[(s*.086,.107,.975),(s*.120,.106,.953),(s*.146,.095,.929)],.0011,seam))
    g['join'](parts,'Trousers_Work')
    # Compact work boots with a turned shaft, shaped instep and tread, matte rubber.
    remove('Footwear_Boots');boots=[]
    for s in [-1,1]:
        boots.append(oval('Deck boot',[(s*.11,.034,.025,.056,.121),(s*.11,.034,.038,.057,.122),(s*.11,.038,.062,.057,.119),(s*.11,.032,.082,.056,.109),(s*.11,.020,.105,.052,.083),(s*.11,.002,.137,.047,.055),(s*.11,-.003,.18,.050,.052),(s*.11,-.003,.25,.059,.059),(s*.11,-.003,.296,.062,.062),(s*.11,-.003,.302,.062,.062),(s*.11,-.003,.306,.057,.057),(s*.11,-.003,.281,.055,.055)],boot,36,.9))
        boots.append(oval('Sole',[(s*.11,.035,.010,.057,.121),(s*.11,.035,.018,.060,.124),(s*.11,.035,.033,.060,.124),(s*.11,.035,.039,.057,.121)],sole,36,.85))
        boots.append(oval('Sole welt',[(s*.11,.035,.034,.060,.124),(s*.11,.035,.041,.060,.124)],rubber_edge,36,.85))
        for j in range(5):boots.append(g['box']('Tread',(s*.11,-.052+j*.039,.010),(.092,.018,.012),sole,.002))
    g['join'](boots,'Footwear_Boots')
    # Skin boots are deliberately matte even before the shared rubber material treatment.
    p=boot.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.94;p.inputs['Specular IOR Level'].default_value=.16
    p=sole.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=1;p.inputs['Specular IOR Level'].default_value=.12
    # A softly tailored flotation/work vest, with clean mesh panels and actual strap loops.
    remove('Outerwear_Vest');vest=g['vest'];trim=g['trim'];vest_parts=[]
    for s in [-1,1]:
        panel=oval('Vest front',[(s*.094,.091,1.061,.075,.040),(s*.094,.102,1.083,.078,.040),(s*.095,.108,1.19,.078,.043),(s*.098,.102,1.30,.073,.039),(s*.124,.073,1.381,.044,.035),(s*.136,.028,1.416,.035,.028)],vest,24,.9)
        vest_parts.append(panel)
        vest_parts.append(g['tube']('Vest binding',[(s*.020,.126,1.075),(s*.018,.149,1.17),(s*.027,.141,1.29),(s*.080,.105,1.38)],.0035,trim))
        vest_parts.append(g['box']('Webbing strap',(s*.092,.150,1.14),(.138,.009,.018),trim,.003))
    vest_parts.append(oval('Vest back',[(0,-.114,1.067,.160,.025),(0,-.124,1.16,.178,.027),(0,-.125,1.30,.184,.025),(0,-.094,1.382,.168,.020),(0,-.047,1.417,.155,.015)],vest,32,.78))
    g['join'](vest_parts,'Outerwear_Vest')
    for obj in objects:
        bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
