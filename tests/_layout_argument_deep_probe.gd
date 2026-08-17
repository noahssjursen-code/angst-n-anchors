extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## `tests/_layout_argument_probe.gd` concluded that dropping `world_layout`
## moves `basin.max_arm_m` at 70/70 and NOTHING ELSE THAT MATTERS. Two of its
## comparators are lossy and could hide exactly the thing the question is about:
##
##   "coast_polyline_points": (...).get("coast_polyline", []).size()   ← a COUNT
##   "quay_length_m": sum of every station's length_m                  ← a SUM
##
## A synthetic coast with the same number of vertices in different places, or
## two quays that trade length, are both invisible to those. So this probe
## compares the WHOLE serialized result — `PortData.to_dict()` and
## `PortLayoutGraph.to_dict()` — path by path, and reports every path that moves
## with how many ports it moves at.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817]


func _initialize() -> void:
	var total := 0
	var moved: Dictionary = {}
	var ports_with_any_move := 0
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		for port in ports:
			total += 1
			var with_layout := _fingerprint(port, int(world_seed), layout)
			var without := _fingerprint(port, int(world_seed), null)
			var diffs: Dictionary = {}
			_diff(with_layout, without, "", diffs)
			if not diffs.is_empty():
				ports_with_any_move += 1
			for path in diffs:
				if not moved.has(path):
					moved[path] = [0, port.port_id, diffs[path][0], diffs[path][1]]
				var row: Array = moved[path]
				row[0] = int(row[0]) + 1

	print("=== %d ports expanded twice (with layout / without), seeds %s" % [total, str(SEEDS)])
	print("=== %d of %d ports differ somewhere" % [ports_with_any_move, total])
	var paths := moved.keys()
	paths.sort_custom(func(a, b) -> bool:
		return int((moved[a] as Array)[0]) > int((moved[b] as Array)[0]))
	print("=== %d distinct paths move" % paths.size())
	for path in paths:
		var row: Array = moved[path]
		print("  %3d/%d  %s\n           with=%s\n           without=%s" % [
			int(row[0]), total, str(path),
			_clip(str(row[2])), _clip(str(row[3])),
		])
	quit(0)


func _clip(s: String) -> String:
	return s if s.length() <= 150 else s.substr(0, 147) + "..."


## Bucket array indices out of the path so 60 coast vertices report as one path.
func _diff(a, b, path: String, out: Dictionary) -> void:
	if typeof(a) != typeof(b):
		out[path + " <type>"] = [str(typeof(a)), str(typeof(b))]
		return
	if a is Dictionary:
		var keys := {}
		for k in (a as Dictionary):
			keys[k] = true
		for k in (b as Dictionary):
			keys[k] = true
		for k in keys:
			if not (a as Dictionary).has(k) or not (b as Dictionary).has(k):
				out[path + "." + str(k) + " <present>"] = [
					str((a as Dictionary).has(k)), str((b as Dictionary).has(k))]
				continue
			_diff((a as Dictionary)[k], (b as Dictionary)[k], path + "." + str(k), out)
		return
	if a is Array or a is PackedVector2Array or a is PackedVector3Array \
			or a is PackedFloat32Array or a is PackedStringArray:
		if a.size() != b.size():
			out[path + " <size>"] = [str(a.size()), str(b.size())]
			return
		for i in a.size():
			_diff(a[i], b[i], path + "[]", out)
		return
	if a is float:
		## Anything under a tenth of a millimetre is not a geometry change.
		if absf(float(a) - float(b)) > 0.0001 or is_finite(float(a)) != is_finite(float(b)):
			if not out.has(path):
				out[path] = ["%.4f" % float(a), "%.4f" % float(b)]
		return
	if a is Vector2 or a is Vector3:
		if (a - b).length() > 0.0001:
			if not out.has(path):
				out[path] = [str(a), str(b)]
		return
	if str(a) != str(b):
		if not out.has(path):
			out[path] = [str(a), str(b)]


func _fingerprint(definition: PortDefinition, world_seed: int, layout: WorldLayout) -> Dictionary:
	PortDataCache.clear()
	var data := PortExpander.expand_uncached(
		PortDefinition.from_dict(definition.to_dict()), world_seed, layout)
	var out: Dictionary = data.to_chart_dict()
	out["__graph"] = data.layout_graph.to_dict() if data.layout_graph != null else {}
	## `world_layout` is erased from initial_attributes by the generator, but be
	## explicit: an object reference is not a comparable value.
	((out["__graph"] as Dictionary).get("initial_attributes", {}) as Dictionary) \
		.erase("world_layout")
	out["__dock_length"] = data.dock_length
	out["__island_width"] = data.island_width
	out["__plot_depth"] = data.plot_depth
	return out
