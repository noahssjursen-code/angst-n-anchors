class_name CoastalSettlementPlan
extends RefCounted

## Decorative occupied plots, not a new world generator or saved port layout.
## Small roadside settlements follow the existing coast and leave wild gaps.
const SPACING := 26.0
const REACH := 850.0
const FOOTPRINTS := {"cottage": Vector2(8.6,7.4), "house": Vector2(8,10.2), "boathouse": Vector2(5.8,9.6)}

static func build(layout: WorldLayout, definitions: Array, zones: Array) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := {"buildings": [], "roads": [], "exclusions": [], "build_ms": 0.0}
	var height_cache := {}
	var local_zones := {}
	var occupied := {}
	for definition: PortDefinition in definitions:
		var anchor := Vector2(definition.world_position.x, definition.world_position.z)
		var rng := RandomNumberGenerator.new(); rng.seed = definition.site_seed ^ 0x56494c4c
		var previous := Vector3(INF,INF,INF)
		var made := 0
		for contour: PackedVector2Array in layout.coastline_contours:
			previous = Vector3(INF,INF,INF)
			var carried := 0.0
			for index in range(contour.size()-1):
				var a := contour[index]; var b := contour[index+1]
				var span := a.distance_to(b)
				var offset := carried
				while offset < span:
					var coast := a.lerp(b,offset/maxf(span,.01)); offset += SPACING
					if coast.distance_to(anchor)>REACH or made>=64:
						previous=Vector3(INF,INF,INF); continue
					# One nearby town owns each location; adjacent ports never double it.
					var nearest := true
					for other: PortDefinition in definitions:
						if other==definition: continue
						var point := Vector2(other.world_position.x,other.world_position.z)
						if coast.distance_squared_to(point)<coast.distance_squared_to(anchor): nearest=false;break
					if not nearest: previous=Vector3(INF,INF,INF);continue
					var sea := gradient(layout,coast)
					var road_xz := inset(layout,coast,sea,145.0)
					var ground := height(layout,road_xz,zones,local_zones,height_cache)
					if ground<1.4:
						road_xz=inset(layout,coast,sea,195.0)
						ground=height(layout,road_xz,zones,local_zones,height_cache)
					if ground<1.3 or ground>90 or excluded(road_xz,zones,local_zones):
						previous=Vector3(INF,INF,INF);continue
					var road := Vector3(road_xz.x,ground+.04,road_xz.y)
					if previous.is_finite() and previous.distance_to(road)<55 and absf(previous.y-road.y)<5:
						result.roads.append(PackedVector3Array([previous,road]))
						var center := (Vector2(previous.x,previous.z)+road_xz)*.5
						var direction := road_xz-Vector2(previous.x,previous.z)
						result.exclusions.append({"forest_clear_only":true,"center":center,
							"half_size":Vector2(4,direction.length()*.5+2),"yaw":-atan2(direction.x,direction.y),"falloff":0.0})
					previous=road
					# Occupied clusters separated by open pasture/woodland; no grid of
					# isolated houses at a uniform density across every piece of coast.
					if sin(coast.x*.008+coast.y*.011+float(definition.site_seed%31))<-.25: continue
					for side: float in [-1.0,1.0]:
						if side>0 and rng.randf()<.22: continue
						var tangent := Vector2(sea.y,-sea.x)
						var at := road_xz+sea*side*rng.randf_range(14,20)+tangent*rng.randf_range(-3,3)
						var kind := "house" if rng.randf()<.32 else "cottage"
						var facing := -sea*side
						var yaw := atan2(facing.x,facing.y)+rng.randf_range(-.08,.08)
						var placement := place(layout,at,yaw,kind,zones,local_zones,height_cache,occupied)
						# Walk the plot back from the lane to find an existing level
						# foundation, rather than grading the landscape into a pad.
						if placement.is_empty():
							at += sea*side*8.0
							placement=place(layout,at,yaw,kind,zones,local_zones,height_cache,occupied)
						if placement.is_empty(): continue
						placement["kind"]=kind;placement["paint"]=rng.randi_range(0,5);placement["port_id"]=definition.port_id
						result.buildings.append(placement); result.exclusions.append(placement.exclusion);made+=1
						# A narrow gravel drive actually reaches each occupied entrance.
						var entry: Vector2 = at+facing*(FOOTPRINTS[kind].y*.5+1.3)
						result.get_or_add("drives",[]).append(PackedVector3Array([Vector3(entry.x,0,entry.y),road]))
						var drive := road_xz-entry
						result.exclusions.append({"forest_clear_only":true,"center":(entry+road_xz)*.5,
							"half_size":Vector2(2,drive.length()*.5+1),"yaw":-atan2(drive.x,drive.y),"falloff":0.0})
					# Compact waterside boatshed groups, where the actual ground lets
					# them sit near water. No floating houses or artificial land pads.
					if rng.randf()<.25:
						var at := inset(layout,coast,sea,60.0)
						for depth in [60.0,85.0,110.0]:
							at=inset(layout,coast,sea,depth)
							if height(layout,at,zones,local_zones,height_cache)>.55: break
						var shed := place(layout,at,atan2(sea.x,sea.y),"boathouse",zones,local_zones,height_cache,occupied)
						if not shed.is_empty():
							shed["kind"]="boathouse";shed["paint"]=1 if rng.randf()<.7 else 5;shed["port_id"]=definition.port_id
							result.buildings.append(shed);result.exclusions.append(shed.exclusion);made+=1
				carried=offset-span
	result.build_ms=(Time.get_ticks_usec()-started)/1000.0
	return result

static func place(layout: WorldLayout, at: Vector2, yaw: float, kind: String, zones: Array, local_zones: Dictionary, cache: Dictionary, occupied: Dictionary) -> Dictionary:
	var grid := Vector2i(floori(at.x/18),floori(at.y/18))
	for dz in range(-1,2):
		for dx in range(-1,2):
			if occupied.has(grid+Vector2i(dx,dz)) and at.distance_to(occupied[grid+Vector2i(dx,dz)])<19: return {}
	var half: Vector2 = FOOTPRINTS[kind]*.5
	var low := INF; var high := -INF
	for corner in [Vector2.ZERO, -half, half,Vector2(-half.x,half.y),Vector2(half.x,-half.y)]:
		var point: Vector2 = at+corner.rotated(-yaw)
		if layout.sample_signed_distance(point)>-12 or excluded(point,zones,local_zones): return {}
		var h := height(layout,point,zones,local_zones,cache)
		low=minf(low,h);high=maxf(high,h)
	if low<.4 or high-low>.8: return {}
	occupied[grid]=at
	return {"position":Vector3(at.x,high-.15,at.y),"yaw":yaw,"relief":high-low,
		"exclusion":{"forest_clear_only":true,"center":at,"half_size":half+Vector2(4,4),"yaw":-yaw,"falloff":0.0}}

static func gradient(layout: WorldLayout, at: Vector2) -> Vector2:
	return Vector2(layout.sample_signed_distance(at+Vector2(2,0))-layout.sample_signed_distance(at-Vector2(2,0)),
		layout.sample_signed_distance(at+Vector2(0,2))-layout.sample_signed_distance(at-Vector2(0,2))).normalized()

static func inset(layout: WorldLayout, coast: Vector2, sea: Vector2, amount: float) -> Vector2:
	var at := coast-sea*amount
	for i in 2: at-=gradient(layout,at)*(layout.sample_signed_distance(at)+amount)
	return at

static func local_mask(point: Vector2, zones: Array, local_zones: Dictionary) -> Array:
	var chunk := Vector2i(floori(point.x/1000),floori(point.y/1000))
	if not local_zones.has(chunk): local_zones[chunk]=WorldTerrainStreamer.zones_intersecting_chunk(zones,chunk)
	return local_zones[chunk]

static func excluded(point: Vector2, zones: Array, local_zones: Dictionary) -> bool:
	return ForestField.inside_flatten_zones(point,local_mask(point,zones,local_zones))

static func height(layout: WorldLayout, point: Vector2, zones: Array, local_zones: Dictionary, cache: Dictionary) -> float:
	return WorldForestStreamer.sample_root_height(layout,point,local_mask(point,zones,local_zones),cache)
