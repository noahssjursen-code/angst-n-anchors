class_name CoastalSkerries
extends RefCounted
## Small-scale exposed bedrock geography, independent of render LOD. Immutable
## after creation; 250 m bins keep physical queries local. Metres, mean sea datum.
const BIN_M := 250.0
## Offshore support for the island foot. The foot meets the deep basin inside
## this distance so the apron does not end as a cliff.
const FOOT_M := 420.0
var features: Array[Dictionary] = []
var bins: Dictionary = {}
var contours: Array[PackedVector2Array] = []

func generate(layout: WorldLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed ^ 0x534b4552
	var until_group := 0.0
	var ways := layout.waterway_centerlines
	for contour in layout.coastline_contours:
		for i in range(1,contour.size()):
			var a: Vector2 = contour[i-1]
			var b: Vector2 = contour[i]
			until_group -= a.distance_to(b)
			if until_group > 0: continue
			until_group = rng.randf_range(650,1300)
			var anchor := (a+b)*.5
			if absf(anchor.x) > layout.half_extent_m-1500 or absf(anchor.y) > layout.half_extent_m-1500: continue
			var tangent := (b-a).normalized()
			var outward := tangent.orthogonal()
			if layout.sample_macro_signed_distance(anchor+outward*100) < 0: outward = -outward
			# Patchy belts, not a continuous wall or evenly scattered ocean islands.
			if rng.randf() < .23: continue
			var count := rng.randi_range(4,10)
			var root := anchor+outward*rng.randf_range(180,600)
			var axis := tangent.rotated(rng.randf_range(-.65,.65))
			for part in count:
				var size_class := rng.randf()
				var length := rng.randf_range(100,240) if part == 0 else (rng.randf_range(40,100) if size_class < .4 else rng.randf_range(12,40))
				var width := length*rng.randf_range(.3,.65)
				# The first rock establishes a ridge. Satellites break off its flanks
				# and ends; some farther fragments continue the same structural line.
				var at := root if part == 0 else root+axis*rng.randf_range(-320,320)+outward*rng.randf_range(-100,200)
				if _blocks_corridor(at,length+80,ways): continue
				var polygon := PackedVector2Array()
				var angle := axis.angle()+rng.randf_range(-.3,.3)
				var notch_angle := rng.randf()*TAU
				var bent := rng.randf_range(-.3,.3)
				var corners := 16 if length > 60 else 10
				for corner in corners:
					var theta := corner*TAU/float(corners)
					var rough := rng.randf_range(.78,1.08)
					# One or two cuts and a bent ridge axis produce embayments and
					# uneven lobes, rather than merely wobbling an elliptical coast.
					var notch := pow(maxf(0,cos(theta-notch_angle)),12)*rng.randf_range(.3,.55)
					var local := Vector2(cos(theta)*length,(sin(theta)+bent*cos(theta*2))*width)
					polygon.append(at+local.rotated(angle)*rough*(1.0-notch))
				var overlap := false
				for vertex in polygon:
					if layout.sample_macro_signed_distance(vertex) < 20:
						overlap = true
						break
				if overlap: continue
				# Use the footprints, not their bounding circles: long narrow rocks
				# can sit alongside one another with an actual intervening channel.
				for existing in in_rect(Rect2(at-Vector2.ONE*(length+25),Vector2.ONE*(length+25)*2)):
					if at.distance_to(existing.position) > length+float(existing.radius)+25: continue
					if _polygons_too_close(polygon,existing.polygon,20):
						overlap = true
						break
				if overlap: continue
				var height := clampf(width*.26,1.2,26.0)*rng.randf_range(.7,1.2)
				var feature := {"position":at,"polygon":polygon,"height":height,
					"radius":length*1.15,"width":width,"group":root,"axis":axis}
				var index := features.size()
				features.append(feature)
				for corner in polygon.size():
					contours.append(PackedVector2Array([polygon[corner],polygon[(corner+1)%polygon.size()]]))
				var extent := length*1.15+FOOT_M+20.0
				for z in range(floori((at.y-extent)/BIN_M),floori((at.y+extent)/BIN_M)+1):
					for x in range(floori((at.x-extent)/BIN_M),floori((at.x+extent)/BIN_M)+1):
						var key := Vector2i(x,z)
						if not bins.has(key): bins[key] = []
						bins[key].append(index)

static func _blocks_corridor(at: Vector2, radius: float, ways: Array[Dictionary]) -> bool:
	for way in ways:
		var points: PackedVector2Array = way.points
		var widths: PackedFloat32Array = way.get("widths_m",PackedFloat32Array())
		for i in range(1,points.size()):
			var width := maxf(widths[i-1],widths[i]) if widths.size() == points.size() else float(way.width_m)
			var clearance := width*.24+radius
			if Geometry2D.get_closest_point_to_segment(at,points[i-1],points[i]).distance_to(at) < clearance: return true
	return false

func nearby(at: Vector2) -> Array:
	return bins.get(Vector2i(floori(at.x/BIN_M),floori(at.y/BIN_M)),[])

static func polygon_distance(at: Vector2, polygon: PackedVector2Array) -> float:
	var distance_sq := INF
	for i in polygon.size():
		var point := Geometry2D.get_closest_point_to_segment(at,polygon[i],polygon[(i+1)%polygon.size()])
		distance_sq = minf(distance_sq,at.distance_squared_to(point))
	return sqrt(distance_sq)*(-1.0 if Geometry2D.is_point_in_polygon(at,polygon) else 1.0)

func signed_distance(at: Vector2, macro_distance: float) -> float:
	var result := macro_distance
	for index in nearby(at):
		var f := features[index]
		if at.distance_to(f.position)-float(f.radius) > minf(result,180): continue
		result = minf(result,polygon_distance(at,f.polygon))
	return result

func elevation(at: Vector2, base_height: float) -> float:
	var result := base_height
	for index in nearby(at):
		var f := features[index]
		var support := float(f.radius)+FOOT_M
		var center_distance := at.distance_to(f.position)
		if center_distance > support: continue
		var distance := polygon_distance(at,f.polygon)
		var height: float
		if distance < 0:
			# Low exposed rock, not miniature mountains. Ridge crest follows the
			# polygon's medial shape; shoreline is exactly the mean-water contour.
			height = float(f.height)*sin(clampf(-distance/(float(f.width)*.8),0,1)*PI*.5)
		else:
			# Crab ground close to the rock, then a slope into the deep basin.
			# The old quadratic was already ~100 m deep within 50 m of shore.
			var width := float(f.width)
			var shelf_run := clampf(width*1.5,48.0,140.0)
			var shelf_depth := clampf(16.0+width*.04,16.0,32.0)
			var basin_depth := maxf(-base_height,shelf_depth)
			var held := minf(shelf_depth+6.0,35.0)
			var depth: float
			if distance <= 40.0:
				depth = smoothstep(0.0,40.0,distance)*shelf_depth
			elif distance <= 40.0+shelf_run:
				depth = lerpf(shelf_depth,held,(distance-40.0)/shelf_run)
			else:
				var span := maxf(FOOT_M-40.0-shelf_run,1.0)
				var t := smoothstep(0.0,1.0,clampf((distance-40.0-shelf_run)/span,0.0,1.0))
				depth = lerpf(held,basin_depth,t)
			height = -depth
			# Fade into the surrounding bottom at the support edge so a long
			# rock does not leave a circular wall where the foot stops.
			var fade := smoothstep(0.0,80.0,support-center_distance)
			height = lerpf(base_height,height,fade)
		result = maxf(result,height)
	return result

func in_rect(rect: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for z in range(floori(rect.position.y/BIN_M),floori(rect.end.y/BIN_M)+1):
		for x in range(floori(rect.position.x/BIN_M),floori(rect.end.x/BIN_M)+1):
			for index in bins.get(Vector2i(x,z),[]):
				if seen.has(index): continue
				seen[index] = true
				var f := features[index]
				if rect.grow(float(f.radius)+FOOT_M).has_point(f.position): result.append(f)
	return result

func segment_clear(a: Vector2, b: Vector2, margin: float) -> bool:
	var rect := Rect2(a,Vector2.ZERO).expand(b).grow(margin)
	for f in in_rect(rect):
		var polygon: PackedVector2Array = f.polygon
		if Geometry2D.is_point_in_polygon(a,polygon) or Geometry2D.is_point_in_polygon(b,polygon): return false
		for i in polygon.size():
			var c := polygon[i]
			var d := polygon[(i+1)%polygon.size()]
			if Geometry2D.segment_intersects_segment(a,b,c,d) != null: return false
			if c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)) < margin: return false
			if a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)) < margin: return false
			if b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d)) < margin: return false
	return true


static func _polygons_too_close(a: PackedVector2Array,b: PackedVector2Array,gap: float) -> bool:
	if not Geometry2D.intersect_polygons(a,b).is_empty(): return true
	for point in a:
		if polygon_distance(point,b) < gap: return true
	for point in b:
		if polygon_distance(point,a) < gap: return true
	return false
