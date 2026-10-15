extends Node
## Differential check against the original general polygon-union path. The
## optimized shared-seam path must preserve exact edge topology and stable keys.

const Berths = preload("res://scripts/port/state/custom_port_berths.gd")
const EPS := Berths.EPS
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := CustomPortCatalog.definitions()
	var fixture := CustomPortExample.build(Vector3.ZERO, [], {})
	_compare(Berths._platforms(fixture, catalog), "complete harbour")
	var square := PackedVector2Array([Vector2(-2,-2), Vector2(2,-2), Vector2(2,2), Vector2(-2,2)])
	var triangle := PackedVector2Array([Vector2(-2,-2), Vector2(2,2), Vector2(-2,2)])
	var chamfer := PackedVector2Array([Vector2(-2,-2), Vector2(1,-2), Vector2(2,-1), Vector2(2,2), Vector2(-2,2)])
	var concave := PackedVector2Array([Vector2(-2,-2), Vector2(2,-2), Vector2(2,-1), Vector2(-1,-1), Vector2(-1,2), Vector2(-2,2)])
	var shapes: Array[PackedVector2Array] = [square, triangle, chamfer, concave]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7340531
	for trial in range(96):
		var platforms: Array[Dictionary] = []
		for i in range(24):
			var polygon: PackedVector2Array = shapes[rng.randi_range(0, shapes.size()-1)].duplicate()
			var shift := Vector2(rng.randi_range(-3,3)*4, rng.randi_range(-3,3)*4)
			if trial % 3 == 0: shift += Vector2(rng.randf_range(-2,2), rng.randf_range(-2,2))
			var angle := rng.randi_range(0,3) * PI * 0.5
			for j in polygon.size(): polygon[j] = polygon[j].rotated(angle) + shift
			if i % 4 == 0: polygon.reverse()
			platforms.append(_platform(polygon))
			if i % 7 == 0: platforms.append(_platform(polygon.duplicate()))
		_compare(platforms, "mixed tiles %d" % trial)
	# A shared segment is only a candidate. Near-coincident, wafer-thin and
	# duplicate pieces must still use actual outward polygon coverage.
	for width in [0.0005, 0.001, 0.0015, 0.002, 0.01, 1.0, 4.0]:
		var narrow := PackedVector2Array([Vector2(2,-2), Vector2(2+width,-2), Vector2(2+width,2), Vector2(2,2)])
		_compare([_platform(square), _platform(narrow)], "thin neighbour %s" % width)
		for gap in [-0.002, -0.001, 0.0005, 0.001, 0.002]:
			var shifted := narrow.duplicate()
			for j in shifted.size(): shifted[j].x += gap
			_compare([_platform(square), _platform(shifted)], "near seam %s/%s" % [width,gap])
	for failure in failures: push_error(failure)
	print("CUSTOM PORT EDGE EQUIVALENCE %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _platform(polygon: PackedVector2Array) -> Dictionary:
	return {"polygon": polygon, "bounds": Berths._polygon_bounds(polygon)}


func _compare(platforms: Array[Dictionary], label: String) -> void:
	checks += 1
	var expected := _reference_edges(platforms)
	var actual := Berths._exposed_edges(platforms)
	if expected != actual: failures.append("Exposed edges differ for " + label + ": expected " + str(expected) + ", actual " + str(actual))


func _reference_edges(platforms: Array[Dictionary]) -> Array[Dictionary]:
	# Frozen pre-optimization union. Keep the order and tolerances independent
	# of the optimized candidate shortcut so regressions cannot mirror it.
	var exposed: Array[Dictionary] = []
	var spatial: Dictionary = {}
	for index in range(platforms.size()):
		for cell in Berths._cells(platforms[index].bounds.grow(EPS * 2.0)):
			if not spatial.has(cell): spatial[cell] = []
			spatial[cell].append(index)
	for platform in platforms:
		var polygon: PackedVector2Array = platform.polygon
		var winding := 1.0 if Berths._signed_area(polygon) > 0.0 else -1.0
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			if a.distance_to(b) <= EPS: continue
			var direction := (b-a).normalized()
			var normal := Vector2(direction.y, -direction.x) * winding
			var tangent := direction
			if tangent.x < -EPS or (absf(tangent.x) <= EPS and tangent.y < 0.0): tangent = -tangent
			var origin := normal * normal.dot(a)
			var start := minf(tangent.dot(a), tangent.dot(b))
			var end := maxf(tangent.dot(a), tangent.dot(b))
			var edge := {"origin": origin, "normal": normal, "tangent": tangent, "start": start, "end": end,
				"key": "%d:%d:%d" % [roundi(normal.x * 1000000.0), roundi(normal.y * 1000000.0), roundi(normal.dot(a) / EPS)]}
			var intervals: Array[Vector2] = [Vector2(start, end)]
			var nearby: Dictionary = {}
			var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(EPS * 2.0)
			for cell in Berths._cells(bounds):
				for other_index in spatial.get(cell, []): nearby[other_index] = true
			for other_index in nearby:
				var other: Dictionary = platforms[other_index]
				if not bounds.intersects(other.bounds.grow(EPS * 2.0)): continue
				for cut in Berths._inside_line_intervals(origin + normal * EPS, tangent, start, end, other.polygon):
					intervals = Berths._subtract(intervals, cut)
			for interval in intervals:
				var part: Dictionary = edge.duplicate()
				part.start = interval.x
				part.end = interval.y
				exposed.append(part)
	exposed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.key != b.key: return str(a.key) < str(b.key)
		return float(a.start) < float(b.start))
	var merged: Array[Dictionary] = []
	for edge in exposed:
		if not merged.is_empty():
			var last: Dictionary = merged.back()
			if last.key == edge.key and float(edge.start) <= float(last.end) + EPS:
				last.end = maxf(float(last.end), float(edge.end))
				continue
		merged.append(edge)
	return merged
