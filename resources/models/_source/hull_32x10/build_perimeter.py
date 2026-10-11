"""Reuse the accepted rail cross sections and exact miter rule on a larger hull."""
from pathlib import Path
import json, math
import bpy
from mathutils import Vector
HERE=Path(__file__).resolve().parent
MODELS=HERE.parents[1]
# Load authoring primitives only, never execute the trawler's assembly/render job.
source=(MODELS/'_source/trawler_rails/build_rails.py').read_text()
exec(source.split("for style,base in")[0])
OUT=str(MODELS/'parts/coaster_perimeter');Path(OUT).mkdir(exist_ok=True)
SRC=str(HERE)
existing={a['id']:a for a in json.loads((MODELS/'parts/trawler_rails/manifest.json').read_text())['assets']}
existing.update({a['id']:a for a in json.loads((MODELS/'parts/cargo_perimeter/manifest.json').read_text())['assets']})
for style,base in [('rail',1),('halfwall',.75)]:
    segments=[]
    for hand,sign in [('port',1),('starboard',-1)]:
        x=-5*sign;y=-16
        for i in range(24):segments.append((f'{style}_straight_100cm',x,y,0,1,0));y+=1
        for i in range(10):
            run=1 if i<6 else .5;angle='26' if i<6 else '45'
            segments.append((f'{style}_{angle}_{hand}',x,y,sign*.5,run,0));x+=sign*.5;y+=run
        assert abs(x)<1e-6 and y==16
    for i in range(10):segments.append((f'{style}_straight_100cm',-5+i,-16,1,0,-math.pi/2))
    placements=[];seams={}
    for index,(id,x,y,dx,dy,yaw) in enumerate(segments):
        if style=='halfwall':
            direction=Vector((dx,dy,0)).normalized();normal=Vector((direction.y,-direction.x,0));ms=[]
            for p,start in [(Vector((x,y,0)),True),(Vector((x+dx,y+dy,0)),False)]:
                for j,(_,ox,oy,odx,ody,_) in enumerate(segments):
                    if j==index:continue
                    a=Vector((ox,oy,0));b=Vector((ox+odx,oy+ody,0))
                    if (a-p).length<1e-6:away=(b-a).normalized();break
                    if (b-p).length<1e-6:away=(a-b).normalized();break
                neighbour=-away if start else away;nn=Vector((neighbour.y,-neighbour.x,0));m=(normal+nn)/(1+normal.dot(nn))
                # Independent ring positions on both adjacent panels must coincide.
                ring={tuple(round(v,6) for v in p+m*s) for s in [-.05,-.04,.04,.05]}
                key=(round(p.x,6),round(p.y,6))
                if key in seams:assert seams[key]==ring
                seams[key]=ring
                ms.append((m.x*math.cos(yaw)+m.y*math.sin(yaw),-m.x*math.sin(yaw)+m.y*math.cos(yaw),0))
            variant=id+'_miter_'+'_'.join(str(round(v*10000)) for m in ms for v in m[:2])
            if variant not in existing and variant not in assets:
                asset(variant,style,dx=dx*math.cos(yaw)+dy*math.sin(yaw),run=-dx*math.sin(yaw)+dy*math.cos(yaw),h0=base,h1=base,m0=ms[0],m1=ms[1])
            id=variant
        placements.append({'asset_id':id,'position':[x,4.5,-y],'yaw_degrees':math.degrees(yaw)})
    (MODELS/'vessels/hull_32x10'/f'{style}_flat_assembly.json').write_text(json.dumps({'placements':placements},indent=2))
for a in manifest:a['model']=a['model'].replace('/trawler_rails/','/coaster_perimeter/')
Path(OUT,'manifest.json').write_text(json.dumps({'assets':manifest},indent=2))
print('COASTER_PERIMETER_PASS',len(manifest),'new variants; all miter profiles match')
