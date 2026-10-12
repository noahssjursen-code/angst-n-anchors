class_name BridgeStructurePlan
extends RefCounted

## Deterministic construction record. No render resources or scene nodes.
const MAX_GRADE := .085
const MAX_FOUNDATION_DEPTH := 90.0
const FOUNDATION_EMBED_M := 5.0

static func _terrain(layout: WorldLayout, at: Vector2, zones: Array = [], cache: Dictionary = {}) -> float:
	return WorldForestStreamer.sample_root_height(layout,at,zones,cache)

## Sample the whole support footprint in its actual orientation. This includes
## both tower legs, not just the water beneath the middle of the road.
static func foundation_base(layout: WorldLayout, at: Vector2, direction: Vector2, width: float, depth: float, zones: Array = [], cache: Dictionary = {}) -> float:
	if layout==null: return -20.0
	var lowest := INF
	var side := direction.orthogonal()
	var across := maxi(2,ceili(width/2.0))
	var along := maxi(2,ceili(depth/2.0))
	for x in across+1:
		for z in along+1:
			var point := at+side*width*(float(x)/across-.5)+direction*depth*(float(z)/along-.5)
			lowest=minf(lowest,_terrain(layout,point,zones,cache))
	# Visible terrain is triangulated on 25–200 m grids. A sharp shoreline can
	# render lower than the continuous field. Bound all LOD cell vertices under
	# the footprint so a change of terrain LOD cannot expose the bottom either.
	var radius := Vector2(width,depth).length()*.5
	for step: float in WorldTerrainStreamer.DEFAULT_LOD_STEPS:
		var low := Vector2i(floori((at.x-radius)/step),floori((at.y-radius)/step))
		var high := Vector2i(ceili((at.x+radius)/step),ceili((at.y+radius)/step))
		for x in range(low.x,high.x+1):
			for z in range(low.y,high.y+1):
				lowest=minf(lowest,_terrain(layout,Vector2(x,z)*step,zones,cache))
	return lowest-FOUNDATION_EMBED_M

static func design(crossing: Dictionary, layout: WorldLayout = null, force_family := "", zones: Array = [], roads: Array = [], cache: Dictionary = {}) -> Dictionary:
	var a: Vector2 = crossing.a_xz
	var b: Vector2 = crossing.b_xz
	var relevant: Array = []
	var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(1700)
	for zone: Dictionary in zones:
		if WorldTerrainStreamer._zone_influence_bounds(zone).intersects(bounds,true): relevant.append(zone)
	zones=relevant
	var length := a.distance_to(b)
	var direction := (b-a).normalized()
	var sea := WaveSurface.WATER_LEVEL
	var channels: Array[float] = []
	if layout != null:
		for waterway: Dictionary in layout.waterway_centerlines:
			var points: PackedVector2Array = waterway.get("points",PackedVector2Array())
			for i in range(points.size()-1):
				var hit = Geometry2D.segment_intersects_segment(a,b,points[i],points[i+1])
				if hit != null: channels.append(a.distance_to(hit))
	# Reserve 55 m beneath even the deepest concrete girder over mapped waterways.
	var bank_a := _terrain(layout,a,zones,cache) if layout != null else float(crossing.a_ground)
	var bank_b := _terrain(layout,b,zones,cache) if layout != null else float(crossing.b_ground)
	var deck := maxf(sea+(64.0 if not channels.is_empty() else 22.0),maxf(bank_a,bank_b)+2.5)
	var family := force_family
	if family.is_empty():
		family="girder" if length<220 else ("arch" if length<420 else ("cantilever" if length<820 else "suspension"))
	var supports: Array[float] = []
	if family=="girder":
		var count := ceili(length/65.0)
		for i in range(1,count): supports.append(length*float(i)/count)
	elif family=="cantilever":
		# A 298 m main span is the Raftsund reference; longer crossings need more piers.
		var count := ceili(length/280.0)
		for i in range(1,count): supports.append(length*float(i)/count)
	elif family=="arch":
		supports.assign([length*.15,length*.85])
	else:
		supports.assign([length*.12,length*.88])
		if layout!=null:
			var fitted:=_suspension_supports(layout,a,direction,length,channels,zones,cache)
			if fitted.is_empty(): return {"accepted":false,"reason":"No suitable suspension tower banks"}
			supports.assign(fitted)
	var invalid := false
	for s in supports:
		if layout!=null and sea-_terrain(layout,a+direction*s,zones,cache)>MAX_FOUNDATION_DEPTH: invalid=true
		for channel in channels:
			if absf(s-channel)<60: invalid=true
	if invalid and family!="suspension" and force_family.is_empty():
		return design(crossing,layout,"suspension",zones,roads,cache)
	if invalid: return {"accepted":false,"reason":"No suitable foundations outside shipping opening"}
	if family=="suspension" and supports[1]-supports[0]>1310:
		return {"accepted":false,"reason":"Main span exceeds suspension kit range"}
	# Arch underside must preserve clearance across the protected shipping opening.
	if family=="arch" and not channels.is_empty():
		return design(crossing,layout,"suspension",zones,roads,cache)
	var approaches: Array[Vector3] = []
	for endpoint in [{"point":a,"out":-direction,"ground":crossing.a_ground},{"point":b,"out":direction,"ground":crossing.b_ground}]:
		var landing := _approach(endpoint.point,endpoint.out,deck,endpoint.ground,layout,zones,cache)
		if landing.is_empty(): return {"accepted":false,"reason":"No dry approach within grade limit"}
		approaches.append(landing.point)
	var bases: Array[float] = []
	for s in supports:
		bases.append(foundation_base(layout,a+direction*s,direction,22.0 if family=="suspension" else 6.0,6.0,zones,cache) if layout!=null else sea-15.0)
	var approach_piers: Array[Dictionary] = []
	for i in 2:
		var start := Vector3(a.x,deck,a.y) if i==0 else Vector3(b.x,deck,b.y)
		var end := approaches[i]
		var count := ceili(start.distance_to(end)/40.0)
		for j in range(1,count):
			var at := start.lerp(end,float(j)/count)
			var base := foundation_base(layout,Vector2(at.x,at.z),direction,4.0,3.0,zones,cache) if layout!=null else -5.0
			approach_piers.append({"at":at,"base":base})
	var road_links: Array = []
	if layout != null:
		for landing in approaches:
			road_links.append(preload("res://scripts/world/bridge_road_connector.gd").connect_road(layout,landing,roads,zones))
	return {"accepted":true,"family":family,"length":length,"deck_y":deck,"a":a,"b":b,
		"road_links":road_links,"supports":supports,"bases":bases,"approaches":approaches,"channels":channels,
		"source":crossing,"navigation_clearance_m":55.0 if not channels.is_empty() else 0.0,
		"approach_piers":approach_piers,"end_bases":[foundation_base(layout,a,direction,22,10,zones,cache),foundation_base(layout,b,direction,22,10,zones,cache)],
        "landing_bases":[foundation_base(layout,Vector2(approaches[0].x,approaches[0].z),direction,13,5,zones,cache),foundation_base(layout,Vector2(approaches[1].x,approaches[1].z),direction,13,5,zones,cache)]}

static func _approach(at: Vector2, outward: Vector2, deck: float, ground: float, layout: WorldLayout, zones: Array = [], cache: Dictionary = {}) -> Dictionary:
	if layout==null:
		var p := at+outward*maxf(30,(deck-ground)/.065)
		return {"point":Vector3(p.x,ground,p.y)}
	# Search dry directions rather than abandoning an island when the original
	# bridge axis happens to point back into another inlet.
	var best := {}
	var cost := INF
	for angle in [0.0,-15.0,15.0,-30.0,30.0,-45.0,45.0]:
		var heading := outward.rotated(deg_to_rad(angle))
		var profile: Array[float] = []
		for i in range(1,81):
			var distance := i*20.0
			if distance>=cost: break
			var p := at+heading*distance
			var h := _terrain(layout,p,zones,cache)
			if h<=WaveSurface.WATER_LEVEL+.5: break
			profile.append(h)
			if absf(deck-h)/distance>MAX_GRADE: continue
			var clear := true
			for j in profile.size()-1:
				if profile[j]>lerpf(deck,h,float(j+1)/i)+.4: clear=false;break
			if clear:
				best={"point":Vector3(p.x,h+.08,p.y)}
				cost=distance;break
	return best


static func _suspension_supports(layout: WorldLayout, a: Vector2, direction: Vector2,
		length: float, channels: Array, zones: Array, cache: Dictionary = {}) -> Array[float]:
	var banks: Array = [[],[]]
	for side in 2:
		for i in range(1,19):
			var fraction:=float(i)*.02
			var s:=length*(fraction if side==0 else 1.0-fraction)
			if WaveSurface.WATER_LEVEL-_terrain(layout,a+direction*s,zones,cache)>MAX_FOUNDATION_DEPTH: continue
			var clear:=true
			for channel: float in channels:
				if absf(s-channel)<60: clear=false;break
			if clear: banks[side].append(s)
	var result: Array[float]=[]
	var best:=INF
	for left: float in banks[0]:
		for right: float in banks[1]:
			if right-left>1310 or right-left<length*.28: continue
			var score:=absf(left-length*.12)+absf(right-length*.88)
			if score<best: best=score;result.assign([left,right])
	return result
