extends SceneTree

## SCRATCH PROBE (leading underscore, not gate-scored).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_wave_trim_reach.gd
##
## For every `trim_band` placement in every fixture that carries pieces: how far
## is its drawn plate from anything it could be trim ON — a plate of some other
## piece, or the deck plane itself? The question is whether "trim is trim on
## something" separates the two runs that hang off the bow from the rubbing
## strakes, cap rails and stem-head caps that legitimately stand proud.

const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const DECK_SLAB := 0.15


func _init() -> void:
	var dir := DirAccess.open("res://resources/data/structures")
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".json"):
			continue
		_audit("res://resources/data/structures/%s" % file_name)
	quit()


func _audit(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	var doc := parsed as Dictionary
	var placements: Array = doc.get("pieces", []) as Array
	if placements.is_empty():
		return
	var hull: Dictionary = doc.get("hull", {}) as Dictionary
	var loa := float(hull.get("loa_m", 0.0))
	var beam := float(hull.get("beam_m", 0.0))
	var deck := AABB(Vector3(0.0, -DECK_SLAB, 0.0), Vector3(beam, DECK_SLAB, loa))

	var trim: Array = []
	var solid: Array = []
	for placement_variant in placements:
		var placement := placement_variant as Dictionary
		var raw_box: Variant = _box(placement)
		if raw_box == null:
			continue
		var box := raw_box as AABB
		if str(placement.get("piece", "")) == "trim_band":
			trim.append({"p": placement, "box": box, "corners": _corners(placement)})
		else:
			solid.append(box)
	## Hand-authored plates count as things trim can sit on too.
	for item_variant in doc.get("items", []) as Array:
		var item := item_variant as Dictionary
		var raw: Variant = item.get("at", null)
		if raw is Array and (raw as Array).size() == 3:
			var at_list := raw as Array
			solid.append(AABB(
				Vector3(float(at_list[0]), float(at_list[1]), float(at_list[2])),
				Vector3.ZERO
			))
	if trim.is_empty():
		return

	print("\n=== %s  (%d trim runs, %d other placements)" % [
		path.get_file(), trim.size(), solid.size(),
	])
	for entry_variant in trim:
		var entry := entry_variant as Dictionary
		var box := entry["box"] as AABB
		var best := 0.0
		var against := "deck"
		for corner_variant in entry["corners"] as Array:
			var corner := corner_variant as Vector3
			var near := _reach(corner, deck)
			var what := "deck"
			for other_variant in solid:
				var gap := _reach(corner, other_variant as AABB)
				if gap < near:
					near = gap
					what = "piece"
			if near > best:
				best = near
				against = what
		print("  id=%-3s %-9s gap=%6.3f m to %-5s  z %6.2f..%-6.2f  %s" % [
			str((entry["p"] as Dictionary).get("id", "?")),
			str(((entry["p"] as Dictionary).get("params", {}) as Dictionary).get("profile", "?")),
			best, against,
			box.position.z, box.position.z + box.size.z,
			str((entry["p"] as Dictionary).get("_is", "")),
		])


## Distance from a point to a box; 0.0 inside it.
func _reach(point: Vector3, box: AABB) -> float:
	var d := Vector3.ZERO
	for axis in 3:
		d[axis] = maxf(
			maxf(box.position[axis] - point[axis], point[axis] - (box.position[axis] + box.size[axis])),
			0.0
		)
	return d.length()


func _corners(placement: Dictionary) -> Array:
	var out: Array = []
	var result := PieceKitScript.resolve_placement(placement, 1)
	for item_variant in result["items"] as Array:
		var item := item_variant as Dictionary
		var at_list: Array = item["at"] as Array
		var at := Vector3(float(at_list[0]), float(at_list[1]), float(at_list[2]))
		var basis := Basis(Vector3.UP, deg_to_rad(float(item.get("yaw", 0.0))))
		for corner_variant in (item["props"] as Dictionary)["corners"] as Array:
			var corner_list: Array = corner_variant as Array
			out.append(at + basis * Vector3(
				float(corner_list[0]), float(corner_list[1]), float(corner_list[2])
			))
	return out


## Largest axis gap between two boxes; 0.0 when they touch or overlap.
func _gap(a: AABB, b: AABB) -> float:
	var worst := 0.0
	for axis in 3:
		var lo := b.position[axis] - (a.position[axis] + a.size[axis])
		var hi := a.position[axis] - (b.position[axis] + b.size[axis])
		worst = maxf(worst, maxf(lo, hi))
	return worst


func _box(placement: Dictionary) -> Variant:
	var result := PieceKitScript.resolve_placement(placement, 1)
	var box := AABB()
	var first := true
	for item_variant in result["items"] as Array:
		var item := item_variant as Dictionary
		var at_list: Array = item["at"] as Array
		var at := Vector3(float(at_list[0]), float(at_list[1]), float(at_list[2]))
		var basis := Basis(Vector3.UP, deg_to_rad(float(item.get("yaw", 0.0))))
		for corner_variant in (item["props"] as Dictionary)["corners"] as Array:
			var corner_list: Array = corner_variant as Array
			var world: Vector3 = at + basis * Vector3(
				float(corner_list[0]), float(corner_list[1]), float(corner_list[2])
			)
			if first:
				box = AABB(world, Vector3.ZERO)
				first = false
			else:
				box = box.expand(world)
	if first:
		return null
	return box
