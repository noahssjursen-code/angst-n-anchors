"""Original 32 m hull stern kit: 1.8 m screw, 2.1 m spade rudder and fixed gear.
Metres, +Y bow, +Z up. Each part is authored about its real shaft/stock pivot.
"""
import bmesh
from pathlib import Path
exec((Path(__file__).resolve().parent/'build_stern_gear.py').read_text(encoding='utf-8').split('\nclear()\nbronze=')[0])

def normals():
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH':continue
        bm=bmesh.new();bm.from_mesh(ob.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(ob.data);bm.free()
        for face in ob.data.polygons:
            if len(face.vertices)>4:face.use_smooth=False

clear()
bronze=material('Fixed_PropellerBronze',(.48,.29,.105),.82,.3)
steel=material('Fixed_ShaftStainless',(.40,.47,.50),.85,.3)
paint=material('Paint_HullLower',(.29,.07,.045),.26,.57)
seal=material('Fixed_BearingSeal',(.02,.025,.025),.1,.67)
zinc=material('Fixed_SacrificialZinc',(.54,.57,.55),.65,.72)

# Hub sections taper to a fairing cap; blade skins have camber and pitch twist.
vs=[];fs=[];sections=[(.25,.13),(.17,.165),(-.13,.165),(-.24,.135),(-.36,.025)]
for y,r in sections:
    for j in range(48):
        a=j*math.tau/48;vs.append((r*math.cos(a),y,r*math.sin(a)))
for i in range(len(sections)-1):
    for j in range(48):
        a=i*48+j;b=i*48+(j+1)%48;fs.append((a,b,b+48,a+48))
fs.extend([tuple(reversed(range(48))),tuple(range(192,240))])
mesh('Tapered bronze hub and fairing cap',vs,fs,bronze)
for blade in range(4):
    vs=[];fs=[];nr,nc=30,24
    for side in [-1,1]:
        for i in range(nr+1):
            t=i/nr;r=.145+.755*t
            chord=.17*(1-t)+.45*math.sin(math.pi*t)**.7+.008
            pitch=.84-.46*t;angle=blade*math.pi/2+.42*t*t
            for j in range(nc+1):
                u=j/nc;along=(u-.5)*chord
                thickness=.025*math.sin(math.pi*u)*math.sin(math.pi*(.07+.88*t))
                vs.append((r*math.cos(angle)-along*math.cos(pitch)*math.sin(angle),
                    along*math.sin(pitch)+.029*math.sin(math.pi*u)+side*thickness,
                    r*math.sin(angle)+along*math.cos(pitch)*math.cos(angle)))
    n=(nr+1)*(nc+1)
    for side in range(2):
        for i in range(nr):
            for j in range(nc):
                a=side*n+i*(nc+1)+j;face=(a,a+1,a+nc+2,a+nc+1)
                fs.append(face if side else tuple(reversed(face)))
    ring=list(range(nc+1))+[i*(nc+1)+nc for i in range(1,nr+1)]+[nr*(nc+1)+j for j in range(nc-1,-1,-1)]+[i*(nc+1) for i in range(nr-1,0,-1)]
    for a,b in zip(ring,ring[1:]+ring[:1]):fs.append((a,b,b+n,a+n))
    mesh('Skewed cast blade '+str(blade+1),vs,fs,bronze)
normals();export('propeller_1800','ShaftAxis')

clear()
# Balanced symmetric spade with rounded leading edge and finite trailing edge.
vs=[];fs=[];count=64
levels=[(-2.10,1.1),(-2.04,1.14),(-.08,1.35),(0,1.33)]
for z,chord in levels:
    for j in range(count):
        u=(1-math.cos(j/count*math.tau))/2
        half=5*.16*chord*(.2969*math.sqrt(u)-.126*u-.3516*u*u+.2843*u**3-.1015*u**4)
        vs.append((half*(1 if j<count/2 else -1),.27-chord*u,z))
for i in range(len(levels)-1):
    for j in range(count):
        a=i*count+j;b=i*count+(j+1)%count;fs.append((a,b,b+count,a+count))
fs.extend([tuple(reversed(range(count))),tuple(range(count*3,count*4))])
ob=mesh('Tapered balanced spade',vs,fs,paint)
for face in ob.data.polygons:
    if len(face.vertices)>4:face.use_smooth=False
cylinder('Rudder stock',(0,0,-1.9),(0,0,1.75),.078,steel)
cylinder('Stock shoulder',(0,0,.025),(0,0,.12),.11,steel)
for x in [-.105,.105]:
    box('Sacrificial anode',(x,-.11,-1.6),(.035,.23,.36),zinc)
    for z in [-1.70,-1.50]:
        cylinder('Anode fixing',(x*.97,-.11,z),(x*1.21,-.11,z),.012,steel)
normals();export('rudder_2100','StockAxis')

clear()
# Origin is the aft shaft bearing, world (0,1.4,14.15). The fore tube enters
# the raised hull; the strut and upper rudder trunk terminate inside real shell.
cylinder('Stern tube',(0,2.5,0),(0,.16,0),.145,paint)
cylinder('Aft bearing casing',(0,.25,0),(0,-.23,0),.18,paint)
cylinder('Bearing face seal',(0,-.23,0),(0,-.265,0),.15,seal)
cylinder('Propeller shaft',(0,-.25,0),(0,-.58,0),.075,steel)
for a in range(8):
    theta=math.tau*a/8;x=.145*math.cos(theta);z=.145*math.sin(theta)
    cylinder('Bearing flange bolt',(x,-.24,z),(x,-.27,z),.013,steel)
# Streamlined strut cross-section; no broad plate left in the screw disc.
sv=[];sf=[]
for z in [.12,2.10]:
    sv += [(-.075,.26,z),(0,.48,z),(.075,.26,z),(.025,-.14,z),(-.025,-.14,z)]
for j in range(5):sf.append((j,(j+1)%5,(j+1)%5+5,j+5))
sf.extend([tuple(reversed(range(5))),tuple(range(5,10))])
mesh('Faired shaft hanger',sv,sf,paint)
box('Hanger hull pad',(0,.14,2.08),(.45,.82,.13),paint)
# Rudder stock is aft 1.70 m, blade top at 2.65 m above keel.
cylinder('Rudder trunk',(0,-1.70,1.32),(0,-1.70,3.10),.155,paint)
cylinder('Lower neck bearing',(0,-1.70,1.29),(0,-1.70,1.49),.19,paint)
cylinder('Neck seal',(0,-1.70,1.27),(0,-1.70,1.31),.13,seal)
for a in range(8):
    theta=math.tau*a/8;x=.155*math.cos(theta);y=-1.70+.155*math.sin(theta)
    cylinder('Neck retaining bolt',(x,y,1.285),(x,y,1.265),.012,steel)
normals();export('coaster_shaft_support','SternBearing')
(OUT/'mounts_32m.json').write_text(json.dumps({
    'version':1,'hull':'hull_32x10','units':'metres',
    'assets':{'support':'coaster_shaft_support','propeller':'propeller_1800','rudder':'rudder_2100'},
    'support':[0,1.4,14.15],'propeller':[0,1.4,14.9],'rudder':[0,2.65,15.85],
    'max_rudder_degrees':28,'visual_max_rpm':180,
    'note':'Raised-counter shaft line, 1.8 m screw, 2.1 m spade. Original game geometry; hydrodynamic sizing provisional. Force points unchanged.'
},indent=2),encoding='utf-8')
print('COASTER_STERN_EXPORTED: independently authored screw, spade and fixed supports')
