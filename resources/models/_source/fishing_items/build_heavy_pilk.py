"""Original heavy chrome pilk from Noah's supplied reference. Metres."""
from pathlib import Path
import bpy,math
source=Path(__file__).with_name('build_fishing_items.py')
exec(compile(source.read_text(encoding='utf-8').split('clear();make_rod();')[0],str(source),'exec'))
clear()
root=empty('HeavyPilk')
# Tapered, asymmetric spoon-like metal body, thick enough to read as a heavy jig.
verts=[];faces=[]
for z,w in [(0,.004),(-.02,.009),(-.07,.016),(-.13,.019),(-.18,.014),(-.20,.004)]:
    for i in range(16):
        t=math.tau*i/16;verts.append((math.cos(t)*w,math.sin(t)*.005+.006*math.sin(-z*math.pi/.20),z))
for j in range(5):
    for i in range(16):a=j*16+i;b=j*16+(i+1)%16;faces.append((a,b,b+16,a+16))
faces.extend([tuple(range(15,-1,-1)),tuple(range(80,96))])
m=bpy.data.meshes.new('Forged tapered chrome body');m.from_pydata(verts,[],faces);m.update();o=bpy.data.objects.new('Chrome pilk',m);bpy.context.collection.objects.link(o);o.parent=root;o.data.materials.append(silver)
for p in m.polygons:p.use_smooth=True
for z in [.006,-.207]:curve('Split ring',[(.007*math.cos(i*math.tau/32),0,z+.007*math.sin(i*math.tau/32)) for i in range(33)],.0014,silver,root)
red=material('Red hook sleeve',(.65,.015,.012),0,.45)
rodbar('Sleeved treble shank',(0,0,-.216),(0,0,-.251),.004,red,root)
for j in range(3):
    t=j*math.tau/3;pts=[]
    for r,z in [(0,-.228),(0,-.263),(.006,-.271),(.014,-.268),(.018,-.258),(.014,-.252)]:pts.append((r*math.cos(t),r*math.sin(t),z))
    curve('Treble hook %d'%j,pts,.0012,silver,root)
empty('LineEye',root,(0,0,.013));save('heavy_pilk')
