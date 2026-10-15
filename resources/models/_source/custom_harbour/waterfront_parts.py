"""Reusable waterfront parts. Executed by build_custom_harbour.py in its context.
8m gabled spans extend in 4m bays; wall datum remains deck +3m everywhere.
All fittings are visual assets. Stock, utilities and services are separate data.
"""
def beam(name,a,b,width,depth,mat):
    a,b=Vector(a),Vector(b)
    o=box(name,(a+b)*.5,(width,depth,(b-a).length),mat,.003)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return o

clear()
pitch=math.atan(.6)
cols=[]
for side in [-1,1]:
    panel=box('Standing seam pitched roof',(side*2.13,0,4.172),(4.26/math.cos(pitch),4,.10),roof,.002)
    panel.rotation_euler.y=side*pitch
    # Ribs run down the pitch, not along the ridge. Continuous between bays.
    for y in [-1.75,-1.25,-.75,-.25,.25,.75,1.25,1.75]:
        beam('Raised standing seam',(0,y,5.49),(side*4.30,y,2.91),.024,.025,roof)
    for y in [-1.85,0,1.85]:
        beam('Exposed timber rafter',(0,y,5.29),(side*4.25,y,2.74),.14,.16,timber)
    box('Painted eaves fascia',(side*4.22,0,2.83),(.12,4,.22),white,.003)
    box('Gutter channel',(side*4.36,0,2.77),(.21,4,.035),steel,.003)
    for x in [side*4.26,side*4.46]:box('Gutter lip',(x,0,2.82),(.025,4,.10),steel,.002)
    cols.append(collider((side*2.0,0,4.20),(4/math.cos(pitch),4,.12),rotation_degrees=[0,0,-side*math.degrees(pitch)]))
box('Ridge cap',(0,0,5.46),(.18,4,.09),roof,.025)
box('Ridge timber',(0,0,5.27),(.18,4,.20),timber,.003)
for y in [-2,2]:socket('Ridge'+str(y),(0,y,5.4))
export('warehouse_roof_8x4','Pitched roof · 8 × 4 m',[8,4],5.51,'Waterfront buildings','building',4,cols,
       '8m clear building width; repeat 4m along the ridge. Eaves at +3m, ridge +5.4m.',layer='roof')
for o in bpy.context.scene.objects:
    if not o.parent:o.location.z+=3
tall_cols=json.loads(json.dumps(cols))
for c in tall_cols:c['position_m'][1]+=3
export('office_roof_8x4','Upper-storey roof · 8 × 4 m',[8,4],8.51,'Waterfront buildings','building',4,tall_cols,
       'For the decorative office upper facade. Fixed eaves +6m and ridge +8.4m.',layer='roof')

clear()
for i in range(50):
    x=-3.92+i*.16
    h=max(.04,2.4-abs(x)*.6)
    box('Painted gable board',(x,.11,3+h/2),(.155,.05,h),cladding,.002)
    box('Gable backing',(x,0,3+h/2),(.16,.16,h),white,0)
for side in [-1,1]:
    beam('Ivory bargeboard',(0,.17,5.48),(side*4.28,.17,2.91),.15,.12,white)
    beam('Metal verge flashing',(0,.08,5.53),(side*4.30,.08,2.95),.045,.32,roof)
box('Gable sill',(0,.13,3.02),(8,.12,.13),white,.003)
box('Loft vent recess',(0,.15,4.30),(.62,.04,.62),dark,.006)
for x in [-.35,.35]:box('Vent frame',(x,.19,4.30),(.06,.08,.72),white,.002)
for z in [3.94,4.66]:box('Vent frame',(0,.19,z),(.76,.08,.06),white,.002)
for z in [4.04,4.16,4.28,4.40,4.52]:box('Angled vent louvre',(0,.20,z),(.62,.12,.05),white,.002).rotation_euler.x=.35
export('warehouse_gable_8m','Timber gable · 8 m',[8,.38],5.55,'Waterfront buildings','building',4,[],
       'Closes the end above two standard 4m walls. Shares the +3m wall datum.',layer='roof_trim',paint_regions=['Office cladding','Ivory trim'])
for o in bpy.context.scene.objects:
    if not o.parent:o.location.z+=3
export('office_gable_8m','Upper-storey gable · 8 m',[8,.38],8.55,'Waterfront buildings','building',4,[],
       'Gable for the decorative office upper facade; fixed base +6m.',layer='roof_trim',paint_regions=['Office cladding','Ivory trim'])

clear()
from mathutils import Matrix
for angle,axis in [(0,(0,4)),(math.pi,(0,-4)),(math.pi/2,(-4,0)),(-math.pi/2,(4,0))]:
    for lane in [-2,2]:
        before=set(bpy.context.scene.objects)
        wall_sections((-1.18,1.18,.95,2.35))
        for x in [-1.23,1.23]:box('Upper window jamb',(x,.15,1.65),(.10,.10,1.50),white,.002)
        for z in [.90,2.40]:box('Upper window head',(0,.15,z),(2.56,.10,.10),white,.002)
        box('Upper window sill',(0,.21,.96),(2.65,.24,.075),white,.003)
        for x in [-.60,.60]:box('Upper glazing',(x,.025,1.65),(1.12,.018,1.29),glass,.001)
        for x in [-1.16,0,1.16]:box('Upper window mullion',(x,.07,1.65),(.055,.11,1.4),white,.002)
        box('Upper window crossbar',(0,.07,1.65),(2.36,.11,.045),white,.002)
        matrix=Matrix.Translation((axis[0],axis[1],3)) @ Matrix.Rotation(angle,4,'Z') @ Matrix.Translation((lane,0,0))
        for o in set(bpy.context.scene.objects)-before:o.matrix_world=matrix@o.matrix_world
cols=[]
for x in [-4,4]:cols.append(collider((x,0,4.5),(.28,8,3)))
for y in [-4,4]:cols.append(collider((0,y,4.5),(8,.28,3)))
export('harbour_office_upper_floor','Office upper facade · 8 m',[8.38,8.38],6,'Waterfront buildings','building',4,cols,
       'Decorative exterior only: no stairs, floors or interior. Assemble over an 8 × 8m shell; finish with upper-storey roof. Asset ID retained for saved ports.',
       layer='upper_floor',paint_regions=['Office cladding','Ivory trim'])

clear()
# A continuous downpipe clips to the eaves without intersecting the wall.
rod('Rainwater pipe',(0,0,.12),(0,0,2.62),.045,steel,12)
rod('Offset neck',(0,0,2.62),(0,.16,2.78),.045,steel,12)
rod('Shoe outlet',(0,0,.12),(0,.19,.06),.045,steel,12)
for z in [.45,1.5,2.4]:
    torus('Pipe strap',(0,0,z),.047,.008,dark,(0,0,0),16,4)
    box('Wall bracket',(0,-.075,z),(.14,.11,.035),steel,.003)
export('warehouse_downpipe','Gutter downpipe',[.3,.4],2.85,'Waterfront buildings','building',.5,[],layer='wall_trim')

clear()
rod('Tall rainwater pipe',(0,0,.12),(0,0,5.62),.045,steel,12)
rod('Offset eaves neck',(0,0,5.62),(0,.16,5.78),.045,steel,12)
rod('Shoe outlet',(0,0,.12),(0,.19,.06),.045,steel,12)
for z in [.45,1.5,2.4,3.5,4.6,5.4]:
    torus('Pipe strap',(0,0,z),.047,.008,dark,(0,0,0),16,4)
    box('Wall bracket',(0,-.075,z),(.14,.11,.035),steel,.003)
export('office_downpipe','Upper-storey gutter downpipe',[.3,.4],5.85,'Waterfront buildings','building',.5,[],layer='wall_trim')

clear()
for x in [-1.85,1.85]:
    box('Post shoe',(x,.85,.10),(.20,.20,.20),steel,.01)
    box('Canopy timber post',(x,.85,1.32),(.14,.14,2.44),white,.003)
    beam('Knee brace',(x,.85,1.9),(x,.15,2.63),.09,.09,white)
box('Front canopy beam',(0,.85,2.58),(4,.18,.18),white,.003)
box('Rear wall ledger',(0,-.90,2.88),(4,.15,.18),white,.003)
o=box('Canopy roof',(0,0,2.82),(4.15,2.15,.08),roof,.003);o.rotation_euler.x=-.17
for x in [-1.75,-1.25,-.75,-.25,.25,.75,1.25,1.75]:
    beam('Canopy roof seam',(x,-1.07,3.04),(x,1.07,2.68),.022,.024,roof)
export('door_canopy_4m','Covered loading porch · 4 × 2 m',[4,2],3.09,'Waterfront buildings','building',1,
       [collider((x,.85,1.32),(.18,.18,2.64)) for x in [-1.85,1.85]],layer='surface')

for aid,title,text in [('sign_harbour','Harbour office sign','HAVNEKONTOR'),('sign_workshop','Workshop sign','VERKSTED'),('sign_warehouse','Warehouse sign','NORDVIK  LAGER'),('sign_fish','Fish receiving sign','FISKEMOTTAK')]:
    clear()
    box('Enamel sign panel',(0,.16,2.66),(3.1,.07,.44),roof,.018)
    for x in [-1.42,1.42]:bolt((x,.205,2.66),(0,1,0),.016)
    # Blender text normally faces -Y; rotate to face the exterior (+Y).
    o=label(text,(0,.204,2.66),.25,white);o.rotation_euler.z=math.pi
    export(aid,title,[3.2,.46],2.9,'Waterfront buildings','building',.5,[],layer='wall_trim')

clear()
for x in [-.78,.78]:
    for y in [-.24,.24]:box('Bench cast leg',(x,y,.23),(.085,.085,.46),dark,.015)
    box('Bench seat bearer',(x,0,.44),(.07,.62,.07),dark,.008)
    beam('Back support',(x,-.22,.36),(x,-.33,.92),.07,.07,dark)
for y in [-.22,-.075,.075,.22]:box('Oiled timber seat',(0,y,.49),(2,.13,.065),timber,.012)
for z in [.70,.85]:box('Oiled backrest',(0,-.29,z),(2,.06,.12),timber,.009)
export('quay_bench','Timber quay bench',[2,.75],.94,'Quay fittings',snap=.5,colliders=[collider((0,0,.46),(2,.65,.92))])

clear()
box('Service plinth',(0,0,.045),(.58,.55,.09),concrete,.025)
box('Marine supply cabinet',(0,0,.65),(.42,.32,1.16),roof,.035)
box('Angled rain hood',(0,0,1.26),(.53,.44,.10),white,.025)
box('Service face',(0,.17,.77),(.35,.035,.70),white,.015)
blue=material('Fixed_ServiceCaps',(.10,.28,.43),0,.45)
for x in [-.10,.10]:
    rod('Socket housing',(x,.18,.84),(x,.23,.84),.065,dark,16)
    rod('Closed socket cover',(x,.23,.84),(x,.245,.84),.055,blue,16)
rod('Water tap',(0,.19,.52),(0,.29,.52),.025,steel,12)
rod('Tap spout',(0,.29,.52),(0,.29,.45),.025,steel,12)
rod('Tap lever',(-.065,.22,.58),(.065,.22,.58),.015,steel,10)
export('dock_service_pedestal','Shore power and water pedestal',[.6,.6],1.32,'Quay fittings',snap=.5,
       colliders=[collider((0,0,.65),(.5,.45,1.3))],notes='Visible sockets and tap; utility supply is not simulated yet.')

clear()
points=[]
for i in range(481):
    t=i/480;angle=t*math.tau*6;r=.10+.40*t
    points.append((r*math.cos(angle),r*math.sin(angle),.037+.004*math.sin(angle*3)))
for i in range(len(points)-1):rod('Coiled mooring warp',points[i],points[i+1],.027,rope,6)
for i in range(18):
    t=i/17;u=(i+1)/17
    rod('Loose rope end',(.5+t*.36,.18*math.sin(t*2.2),.03),(.5+u*.36,.18*math.sin(u*2.2),.03),.027,rope,6)
export('mooring_warp_coil','Coiled mooring rope',[1.8,1.2],.08,'Cargo details',snap=.5,notes='Loose deck dressing, not a second mooring constraint.')

clear();pallet(0)
green=material('Fixed_NetTwine',(.12,.25,.21),0,.8)
for x in [-.55,.55]:
    for y in [-.35,.35]:rod('Cage upright',(x,y,.18),(x,y,1.35),.025,steel,10)
for z in [.20,.65,1.32]:
    for y in [-.35,.35]:rod('Cage rail',(-.55,y,z),(.55,y,z),.018,steel,8)
    for x in [-.55,.55]:rod('Cage rail',(x,-.35,z),(x,.35,z),.018,steel,8)
for x in [-.40,-.20,0,.20,.40]:
    for y in [-.35,.35]:rod('Cage wire',(x,y,.2),(x,y,1.32),.007,steel,6)
for y in [-.20,0,.20]:
    for x in [-.55,.55]:rod('Cage wire',(x,y,.2),(x,y,1.32),.007,steel,6)
rng=random.Random(714)
for layer in range(8):
    for lane in range(9):
        y=-.29+lane*.072
        a=(-.47,y,.25+layer*.115+rng.uniform(-.035,.035));b=(.47,y,.25+layer*.115+rng.uniform(-.035,.035))
        rod('Folded rope net',a,b,.033,green,8)
for x in [-.33,0,.33]:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=.09,location=(x,.09,1.18));bpy.context.object.data.materials.append(orange)
export('net_storage_cage','Net and float storage cage',[1.2,.8],1.38,'Cargo details',snap=.5,colliders=[collider((0,0,.69),(1.2,.8,1.38))])

clear()
box('Precast bulk wall',(0,0,.95),(4,.55,1.9),concrete,.035)
box('Footing',(0,0,.10),(4,.85,.2),concrete,.025)
box('Steel edge protector',(0,.29,1.83),(4,.035,.16),steel,.005)
for x in [-1.5,-.5,.5,1.5]:
    rod('Recessed lifting eye',(x,.28,1.5),(x,.29,1.5),.055,dark,16)
    rod('Lifting insert',(x,.29,1.5),(x,.295,1.5),.026,steel,12)
export('bulk_retaining_wall_4m','Bulk retaining wall · 4 m',[4,.86],1.94,'Cargo details','building',4,
       [collider((0,0,.95),(4,.55,1.9))],notes='Freestanding precast stock bay wall; inventory remains in the connected store.')

clear()
for x in [-2,0,2]:
    box('Rail base plate',(x,0,.015),(.18,.18,.03),steel,.003)
    rod('Rail upright',(x,0,.03),(x,0,1.12),.033,steel,12)
for z in [.55,1.1]:rod('Continuous rail',(-2,0,z),(2,0,z),.028,steel,12)
export('quay_guardrail_4m','Open quay railing · 4 m',[4,.22],1.14,'Quay fittings','building',4,
       [collider((0,0,.56),(4,.14,1.12))],notes='For pedestrian edges; keep ship mooring faces clear.')

clear()
# Larger true 45-degree cut gives the harbour outline a readable angle at sea.
polygon=[[-4,-4],[4,4],[-4,4]]
polygon_prism('Authored deck cap',polygon,-.004,-.24,concrete)
datum=empty('SupportDatum',(0,0,-.24));support=polygon_prism('Extendable foundation skirt',polygon,0,-.76,concrete);support.parent=datum
export('quay_triangle_8m','Diagonal quay · 8 m',[8,8],1,'Foundations','foundation',8,[],
       'Full 8m diagonal edge. Shares exact footprint and extending collision with the 4m kit.',
       footprint_polygon_m=polygon,water_edge_indices=[0],foundation={'support_node':'SupportDatum','cap_thickness_m':.24,'authored_support_depth_m':.76,'default_depth_m':1.0},layer='foundation',surface='quay')

def coping(aid,name,length,left,right):
    clear()
    def outline(depth):return [[-length/2,0],[length/2,0],[length/2-right*depth,depth],[-length/2+left*depth,depth]]
    polygon_prism('Mitred precast coping',outline(.68),.012,-.44,concrete)
    polygon_prism('Mitred steel cap',outline(.14),.024,.014,steel)
    box('Vertical steel lip',(0,.016,-.036),(length,.032,.12),steel,.002)
    for i in range(round(length)):
        x=(i+.5)*length/round(length)-length/2
        bolt((x,.032,-.07),(0,1,0),.013)
    export(aid,name,[length,.7],.45,'Quay fittings','edge',.5,
           [collider((0,-.34,-.22),(length,.68,.44))],layer='coping',footprint_polygon_m=outline(.68),
           notes='Authored 22.5 degree mitre for a 45 degree change of quay direction. Deck remains flush.')
for size in [4,8]:coping('quay_diagonal_coping_'+str(size)+'m','Diagonal coping · '+str(size)+' m tile',size*math.sqrt(2),math.tan(math.pi/8),math.tan(math.pi/8))
for side in ['left','right','both']:
    coping('quay_edge_mitre_'+side,'Quay coping · '+side+' angled joint',4,
           math.tan(math.pi/8) if side in ['left','both'] else 0,math.tan(math.pi/8) if side in ['right','both'] else 0)
