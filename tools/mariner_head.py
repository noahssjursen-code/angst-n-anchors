"""Authored adult mariner head, preserving the shared character bind and IDs.

The face is a continuous quad surface with sculpted anatomical planes. Eye
apertures are part of that surface, with concentric lid topology, rather than
eyes/nose stuck to a primitive skull. All dimensions are metres, Z up, +Y front.
"""
import math
import bpy
import bmesh
from mathutils import Vector


def rebuild_head(g):
    objects = g['objects']
    skin, hair, lips = g['skin'], g['hair'], g['lip']
    for name in ['Head', 'Face', 'Neck', 'Hair_Crop', 'FacialHair_Moustache']:
        old = bpy.data.objects.get(name)
        if old:
            if old in objects:
                objects.remove(old)
            bpy.data.objects.remove(old, do_unlink=True)

    def material(name, rgb, roughness=.65):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        m.diffuse_color = (*rgb, 1)
        p = m.node_tree.nodes.get('Principled BSDF')
        p.inputs['Base Color'].default_value = (*rgb, 1)
        p.inputs['Roughness'].default_value = roughness
        return m

    sclera = material('EyeWhite', (.66, .69, .65), .38)
    iris = material('Iris', (.14, .23, .23), .43)
    iris_rim = material('IrisRim', (.035, .065, .064), .44)
    pupil = material('Pupil', (.009, .012, .012), .26)
    cavity = material('FaceCrease', (.16, .085, .060), .9)
    hair.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .82
    skin.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .71

    def create(name, verts, faces, materials, face_mats=None):
        data = bpy.data.meshes.new(name)
        data.from_pydata(verts, [], faces)
        data.update()
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        for m in materials:
            data.materials.append(m)
        for i, p in enumerate(data.polygons):
            p.use_smooth = True
            if face_mats:
                p.material_index = face_mats[i]
        bm = bmesh.new()
        bm.from_mesh(data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(data)
        bm.free()
        objects.append(obj)
        return obj

    def gauss(v, centre, radius):
        return math.exp(-((v-centre)/radius)**2)

    # Chin, jaw angle, malar width, temples and cranial vault are independent
    # sections; the occiput is deeper than the facial plane, as on a real head.
    profile = [
        (1.559, .025, .032, -.022), (1.566, .047, .065, -.033),
        (1.577, .061, .079, -.047), (1.588, .075, .080, -.066),
        (1.601, .082, .077, -.080), (1.628, .086, .076, -.089),
        (1.651, .090, .075, -.096), (1.676, .091, .074, -.100),
        (1.700, .089, .077, -.104), (1.724, .089, .080, -.104),
        (1.749, .084, .075, -.100), (1.770, .073, .061, -.088),
        (1.788, .054, .037, -.066), (1.799, .028, .009, -.039),
        (1.804, .001, -.015, -.017),
    ]

    def section(z):
        z = max(profile[0][0], min(profile[-1][0], z))
        for i in range(len(profile)-1):
            p, q = profile[i], profile[i+1]
            if p[0] <= z <= q[0]:
                t = (z-p[0])/(q[0]-p[0])
                # Slope-continuous monotone Hermite sections. A smoothstep on
                # each interval makes a visibly stacked, corrugated skull.
                def tangent(k, component):
                    if k == 0:
                        return (profile[1][component]-profile[0][component])/(profile[1][0]-profile[0][0])
                    if k == len(profile)-1:
                        return (profile[-1][component]-profile[-2][component])/(profile[-1][0]-profile[-2][0])
                    a,b,c=profile[k-1],profile[k],profile[k+1]
                    h0,h1=b[0]-a[0],c[0]-b[0]
                    d0,d1=(b[component]-a[component])/h0,(c[component]-b[component])/h1
                    if d0*d1 <= 0:return 0.
                    w0,w1=2*h1+h0,h1+2*h0
                    return (w0+w1)/(w0/d0+w1/d1)
                h=q[0]-p[0]
                return tuple((2*t**3-3*t*t+1)*p[j]+(t**3-2*t*t+t)*h*tangent(i,j)
                             +(-2*t**3+3*t*t)*q[j]+(t**3-t*t)*h*tangent(i+1,j) for j in range(1,4))
        return profile[-1][1:]

    def surface(u, z):
        w, front, back = section(z)
        x = u*w
        side = -.013
        y = side+(front-side)*math.sqrt(max(0, 1-abs(u)**2.7))
        central = max(0, 1-abs(u)**8)
        # Integrated bridge/glabella, nasal tip, alar wings and columella.
        y += .017*gauss(x, 0, .010)*gauss(z, 1.678, .030)
        y += .023*gauss(x, 0, .016)*gauss(z, 1.651, .012)
        y += .010*gauss(abs(x), .014, .008)*gauss(z, 1.645, .007)
        y += .007*gauss(x, 0, .0045)*gauss(z, 1.640, .005)
        # Orbital recess, brow ridge and zygomatic/cheek masses.
        y -= .011*gauss(abs(x), .038, .024)*gauss(z, 1.684, .018)
        y += .007*gauss(abs(x), .037, .030)*gauss(z, 1.709, .011)
        y += .009*gauss(abs(x), .059, .025)*gauss(z, 1.658, .017)
        y -= .008*gauss(abs(x), .066, .022)*gauss(z, 1.618, .020)
        # Oral mound, philtrum columns, lower lip and labiomental groove.
        y += .006*gauss(x, 0, .035)*gauss(z, 1.616, .016)
        y += .0015*gauss(abs(x), .004, .002)*gauss(z, 1.632, .008)
        lip_height = 1.619 + .0014*gauss(abs(x), .006, .005)
        y += .003*gauss(x, 0, .024)*gauss(z, lip_height, .0035)
        y += .0032*gauss(x, 0, .020)*gauss(z, 1.612, .0032)
        y -= .003*gauss(x, 0, .025)*gauss(z, 1.600, .005)
        y += .003*gauss(x, 0, .030)*gauss(z, 1.579, .012)
        return (x, y*central + side*(1-central), z)

    # Shared outer grid and orbital patches. The patch boundaries use exactly
    # the surrounding grid vertices, and are welded before export.
    vs, fs = [], []
    u_breaks = [-1., -.72, -.16, 0., .16, .72, 1.]
    z_breaks = [1.559, 1.577, 1.588, 1.601, 1.620, 1.640,
                1.663, 1.709, 1.729, 1.750, 1.770, 1.788, 1.804]
    subdiv = 10
    for ix in range(len(u_breaks)-1):
        for iz in range(len(z_breaks)-1):
            if ix in (1, 4) and iz == 6:
                continue
            start = len(vs)
            for j in range(subdiv+1):
                z = z_breaks[iz]+(z_breaks[iz+1]-z_breaks[iz])*j/subdiv
                for i in range(subdiv+1):
                    u = u_breaks[ix]+(u_breaks[ix+1]-u_breaks[ix])*i/subdiv
                    vs.append(surface(u, z))
            for j in range(subdiv):
                for i in range(subdiv):
                    a = start+j*(subdiv+1)+i
                    fs.append((a, a+1, a+subdiv+2, a+subdiv+1))

    eye_cz, eye_rx, eye_ry, eye_rz = 1.685, .020, .014, .0145
    eye_cy = .062
    for s in [-1, 1]:
        lo, hi = (.16, .72) if s > 0 else (-.72, -.16)
        bottom, top_z = 1.663, 1.709
        # Counterclockwise rectangle starts lower left; each side is subdivided
        # identically to its neighbour in the facial grid.
        border = []
        for i in range(subdiv): border.append((lo+(hi-lo)*i/subdiv, bottom))
        for i in range(subdiv): border.append((hi, bottom+(top_z-bottom)*i/subdiv))
        for i in range(subdiv): border.append((hi-(hi-lo)*i/subdiv, top_z))
        for i in range(subdiv): border.append((lo, top_z-(top_z-bottom)*i/subdiv))
        centre_x = s*.038
        start = len(vs)
        layers = 6
        for layer in range(layers):
            t = layer/(layers-1)
            for u, z in border:
                outer = Vector(surface(u, z))
                a = math.atan2((z-eye_cz)/.023, (outer.x-centre_x)/.025)
                # Narrow almond: restrained upper lid covers the top of iris.
                dx = .0177*math.cos(a)
                dz = (.0058 if math.sin(a) > 0 else .0049)*math.sin(a)
                dz += .0013*(s*dx/.0177)
                inner_x, inner_z = centre_x+dx, eye_cz+dz
                root = max(.03, 1-(dx/eye_rx)**2-(dz/eye_rz)**2)
                inner_y = eye_cy+eye_ry*math.sqrt(root)+.00035
                x = outer.x+(inner_x-outer.x)*t
                zz = outer.z+(inner_z-outer.z)*t
                base_y = surface(x/section(zz)[0],zz)[1]
                blend=t*t*(3-2*t)
                y = base_y+(inner_y-base_y)*blend
                # Both upper and lower lids have volume rather than a tube rim.
                y += .0012*math.sin(math.pi*t)**2*(1 if math.sin(a)>0 else .7)
                if math.sin(a)>0:
                    y += .0012*gauss(t,.82,.14)*math.sin(a)
                    y -= .0007*gauss(t,.54,.07)*math.sin(a)
                vs.append((x,y,zz))
        n = len(border)
        for j in range(layers-1):
            for i in range(n):
                a = start+j*n+i; b = start+j*n+(i+1)%n
                fs.append((a,b,b+n,a+n))

    # Back half of the skull shares the front's left/right seam exactly.
    all_z = []
    for i in range(len(z_breaks)-1):
        all_z += [z_breaks[i]+(z_breaks[i+1]-z_breaks[i])*j/subdiv for j in range(subdiv)]
    all_z.append(z_breaks[-1])
    nback, start = 32, len(vs)
    for z in all_z:
        w, front, back = section(z)
        for i in range(nback+1):
            a = math.pi*i/nback
            vs.append((w*math.cos(a), -.013+(back+.013)*math.sin(a), z))
    for j in range(len(all_z)-1):
        for i in range(nback):
            a = start+j*(nback+1)+i
            fs.append((a,a+1,a+nback+2,a+nback+1))
    create('Head', vs, fs, [skin])

    # Neck has a sloping nape and subtle sternomastoid mass, disappearing inside
    # both the jaw and garment collar rather than ending at a straight seam.
    vs, fs = [], []
    rings = [(1.426,.052,.044,-.006),(1.456,.047,.040,-.006),
             (1.492,.043,.039,-.009),(1.525,.045,.043,-.014),
             (1.581,.052,.047,-.020)]
    for z, rx, ry, cy in rings:
        for i in range(48):
            a=math.tau*i/48
            x=rx*math.sin(a);y=cy+ry*math.cos(a)
            y+=.002*gauss(x,0,.015)*gauss(z,1.503,.017)*max(0,math.cos(a))
            vs.append((x,y,z))
    for j in range(len(rings)-1):
        for i in range(48):
            a=j*48+i;b=j*48+(i+1)%48;fs.append((a,b,b+48,a+48))
    create('Neck',vs,fs,[skin])

    # Eyes, brows, attached ear anatomy and small facial recesses share Face.
    vs, fs, fm = [], [], []
    mats=[skin,sclera,iris,iris_rim,pupil,hair,lips,cavity]
    def add_surface(rows, mat_index, wrap=True):
        start=len(vs);n=len(rows[0]);vs.extend(p for row in rows for p in row)
        for j in range(len(rows)-1):
            for i in range(n if wrap else n-1):
                a=start+j*n+i;b=start+j*n+(i+1)%n
                fs.append((a,b,b+n,a+n));fm.append(mat_index)

    for s in [-1,1]:
        cx=s*.038
        rows=[]
        for j in range(25):
            a=math.pi*j/24
            rows.append([(cx+eye_rx*math.sin(a)*math.cos(math.tau*i/48),
                          eye_cy+eye_ry*math.cos(a),
                          eye_cz+eye_rz*math.sin(a)*math.sin(math.tau*i/48)) for i in range(48)])
        add_surface(rows,1)
        # Curved concentric iris patches hug the eyeball instead of flat decals.
        for r0,r1,idx in [(0,.0025,4),(.0025,.0057,2),(.0057,.00615,3)]:
            rows=[]
            for j in range(3):
                r=r0+(r1-r0)*j/2
                row=[]
                for i in range(48):
                    a=math.tau*i/48;dx=r*math.cos(a);dz=r*math.sin(a)
                    y=eye_cy+eye_ry*math.sqrt(max(0,1-(dx/eye_rx)**2-(dz/eye_rz)**2))+.00016
                    row.append((cx+dx,y,eye_cz+dz))
                rows.append(row)
            add_surface(rows,idx)
        # A tapered brow patch follows the brow ridge, no cylindrical eyebrow.
        rows=[]
        for j in range(4):
            row=[]
            for i in range(25):
                t=i/24;x=s*(.018+.046*t)
                centre_z=1.709+.0037*math.sin(math.pi*t)-.0015*t
                width=.0011+.0013*math.sin(math.pi*t)
                z=centre_z+(j/3-.5)*2*width
                y=surface(x/section(z)[0],z)[1]+.0006
                row.append((x,y,z))
            rows.append(row)
        add_surface(rows,5,False)

        # Ear is one continuous cupped surface with helix, antihelix and lobe.
        # Its inner boundary embeds in the skull; never a detached tubular ring.
        n=48;rows=[]
        for j in range(9):
            r=j/8
            row=[]
            for i in range(n):
                a=math.tau*i/n
                z=1.669+.027*math.sin(a)*r
                yy=-.006+.015*math.cos(a)*r+.003*math.sin(a)
                helix=.009*gauss(r,.82,.13)
                anti=.004*gauss(r,.42,.12)*(1+.25*math.sin(a))
                # Lobe is fleshy and the upper pinna tapers into the head.
                xx=.088+.011*r*math.sqrt(max(.05,1-.82*math.sin(a)**2))+helix+anti
                xx+=.001*max(0,-math.sin(a))*r
                row.append((s*xx,yy,z))
            rows.append(row)
        add_surface(rows,0)
        # Reverse side closes the leaf onto an embedded attachment line.
        outer=rows[-1];inner=[]
        for i,p in enumerate(outer):
            a=math.tau*i/n
            inner.append((s*.086,-.010+.008*math.cos(a),1.668+.023*math.sin(a)))
        add_surface([outer,inner],0)
        # Small shadow recess in the concha, skin-coloured by the Lips contract.
        rows=[]
        for j in range(3):
            r=.2+.8*j/2
            rows.append([(s*(.0915+.0012*r),-.001+.005*r*math.cos(math.tau*i/24),1.666+.009*r*math.sin(math.tau*i/24)) for i in range(24)])
        add_surface(rows,6)

        # Nostrils are tucked under the integrated alar wing rather than dots.
        rows=[]
        for j in range(3):
            r=j/2
            rows.append([(s*(.0105+.0034*r*math.cos(math.tau*i/24)),
                          .1033+.0023*r*math.sin(math.tau*i/24),
                          1.6420+.0014*r*math.sin(math.tau*i/24)) for i in range(24)])
        add_surface(rows,7)

    # Upper/lower lip surfaces grow directly out of the sculpted oral mound.
    for upper in [True,False]:
        rows=[]
        for j in range(4):
            row=[]
            for i in range(33):
                x=-.026+.052*i/32
                fade=max(0,1-(abs(x)/.026)**2)
                mid=1.616+.0007*gauss(abs(x),.006,.005)
                edge=(1.619+.0010*gauss(abs(x),.006,.005)) if upper else 1.6125
                z=mid+(edge-mid)*j/3*fade
                y=surface(x/section(z)[0],z)[1]+.00023
                row.append((x,y,z))
            rows.append(row)
        add_surface(rows,6,False)
    rows=[]
    for j in range(2):
        row=[]
        for i in range(41):
            x=-.026+.052*i/40;fade=max(0,1-(abs(x)/.026)**2)
            z=1.616+.0007*gauss(abs(x),.006,.005)+(j-.5)*.0007*fade
            y=surface(x/section(z)[0],z)[1]+.00055
            row.append((x,y,z))
        rows.append(row)
    add_surface(rows,7,False)
    create('Face',vs,fs,mats,fm)

    # Fitted short side-part: temples, sideburns and nape follow the scalp;
    # volume is reserved for the swept crown. No cap-like horizontal hair hem.
    def hairline(a):
        aa=abs((a+math.pi) % math.tau-math.pi)
        anchors=[(0,1.742),(.35,1.741),(.65,1.750),(.95,1.737),
                 (1.23,1.694),(1.5,1.705),(1.85,1.677),(2.3,1.657),(math.pi,1.652)]
        for (a0,z0),(a1,z1) in zip(anchors,anchors[1:]):
            if a0<=aa<=a1:
                t=(aa-a0)/(a1-a0);t=t*t*(3-2*t)
                return z0+(z1-z0)*t+.003*math.sin(a*2)
        return 1.744
    vs,fs=[],[];n=96;nr=38
    for j in range(nr):
        t=j/(nr-1)
        for i in range(n):
            a=math.tau*i/n;z=hairline(a)+(1.8035-hairline(a))*t
            w,front,back=section(z)
            x=w*math.sin(a)
            y=(-.013+(front+.013)*math.cos(a)) if math.cos(a)>=0 else (-.013+(-back-.013)*math.cos(a))
            if math.cos(a)>0:
                y=surface(x/max(w,.0001),z)[1]
            lift=.0010+.006*(t**1.2)
            sweep=.007*gauss(a,math.pi*.23,.6)*gauss(t,.65,.35)
            strand=.0012*math.sin(a*29+t*10)*math.sin(math.pi*t)
            # A restrained asymmetric part, shallow sculpted flowing locks.
            groove=.0015*gauss((a+.5*t)-.57,0,.045)*math.sin(math.pi*t)
            x+=(lift+strand-groove)*math.sin(a)
            y+=(lift+strand-groove)*math.cos(a)
            z+=lift*.60+sweep+.002*math.sin(a)*math.sin(math.pi*t)
            vs.append((x,y,z))
    for j in range(nr-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;fs.append((a,b,b+n,a+n))
    fs.append(tuple((nr-1)*n+i for i in range(n)))
    create('Hair_Crop',vs,fs,[hair])

    # Optional compact moustache follows the upper lip rather than floating.
    vs,fs=[],[]
    for s in [-1,1]:
        start=len(vs);nx,ny=24,5
        for j in range(ny):
            for i in range(nx):
                t=i/(nx-1);x=s*(.002+.026*t)
                lower=1.622-.004*t;upper=1.638-.011*t
                z=lower+(upper-lower)*j/(ny-1)
                y=surface(x/section(z)[0],z)[1]+.0008+.0015*math.sin(math.pi*j/(ny-1))
                vs.append((x,y,z))
        for j in range(ny-1):
            for i in range(nx-1):
                a=start+j*nx+i;fs.append((a,a+1,a+nx+1,a+nx))
    create('FacialHair_Moustache',vs,fs,[hair])

    # Original accessory IDs and rig are retained. Existing wearable models are
    # sized to the new skull, and the glasses sit just clear of the nose bridge.
    for name in ['Headwear_Cap','Headwear_Hardhat']:
        obj=bpy.data.objects.get(name)
        if obj:
            for v in obj.data.vertices:
                v.co.x*=.93;v.co.y=-.013+(v.co.y+.013)*.98
    glasses=bpy.data.objects.get('Eyewear_Glasses')
    if glasses:
        for v in glasses.data.vertices:
            v.co.z-=.008
            v.co.x*=.97
            v.co.y-=.010
    pipe=bpy.data.objects.get('Accessory_Pipe')
    if pipe:
        for v in pipe.data.vertices:
            v.co.y-=.009;v.co.z+=.001
