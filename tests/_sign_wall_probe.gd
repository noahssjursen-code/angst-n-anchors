extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Measures, asserts
## nothing. Question: which bricks tagged `wall` draw less wall than a plain
## block does, and what does the warehouse's front elevation actually look like
## column by column, measured off DRAWN geometry.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_sign_wall_probe.tscn


func _ready() -> void:
	_catalogue()
	_warehouse()
	get_tree().quit(0)


func _catalogue() -> void:
	print("== EVERY brick: drawn size / brick size, on x and y ==")
	var all := BrickCatalog.ids()
	all.sort()
	for id_v in all:
		var id := str(id_v)
		var v := BrickCatalog.create_visual(id, {"text": "WAREHOUSE"})
		add_child(v)
		var a := _bounds(v)
		var s := BrickCatalog.size_m(id)
		print("  %-24s fp=%-10s  x %.3f  y %.3f  meshes=%d  tags=%s"
			% [id, str(BrickCatalog.footprint_of(id)),
				a.size.x / maxf(s.x, 0.0001), a.size.y / maxf(s.y, 0.0001),
				_meshes(v).size(), str(BrickCatalog.get_entry(id).get("tags", []))])
		remove_child(v)
		v.free()

	print("")
	print("== every brick tagged `wall`, drawn in isolation ==")
	var ids := BrickCatalog.ids()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		if not BrickCatalog.has_tag(id, "wall") and not BrickCatalog.has_tag(id, "text"):
			continue
		var visual := BrickCatalog.create_visual(id, {"text": "WAREHOUSE"})
		add_child(visual)
		var aabb := _bounds(visual)
		var sz := BrickCatalog.size_m(id)
		var fp := BrickCatalog.footprint_of(id)
		print("  %-18s tags=%s fp=%s size=%s  drawn=%s %s  meshes=%d  visuals=%d"
			% [id, str(BrickCatalog.get_entry(id).get("tags", [])), str(fp),
				str(sz.snappedf(0.001)), str(aabb.position.snappedf(0.001)),
				str(aabb.size.snappedf(0.001)), _meshes(visual).size(),
				_visual_instances(visual).size()])
		remove_child(visual)
		visual.free()


func _warehouse() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		print("warehouse did not load")
		return
	var fitout := BuildingFitout.build(layout, true)
	add_child(fitout)
	var grid := layout.grid()

	## column "x,z" -> y -> {id, lo, hi}
	var columns: Dictionary = {}
	for child in fitout.get_children():
		if not (child is Node3D) or str(child.name) == "Collision":
			continue
		var parsed := _parse(str(child.name))
		if parsed.is_empty() or not BrickCatalog.has(str(parsed["id"])):
			continue
		var brick_id := str(parsed["id"])
		var cell: Vector3i = parsed["cell"]
		var aabb := _bounds(child)
		var yaw := int(round(child.rotation_degrees.y / 90.0)) % 4
		if yaw < 0:
			yaw += 4
		for c in grid.footprint_cells(cell, BrickCatalog.footprint_of(brick_id), yaw):
			var key := "%d,%d" % [c.x, c.z]
			if not columns.has(key):
				columns[key] = {}
			(columns[key] as Dictionary)[c.y] = {
				"id": brick_id,
				"lo": aabb.position.y,
				"hi": aabb.position.y + aabb.size.y,
				"empty": aabb.size == Vector3.ZERO,
			}

	## The front elevation is z = 16 (the quay face the doors and sign are on).
	print("")
	print("== warehouse front elevation, z=16, drawn top of each column ==")
	print("   x    courses drawn (id@y)                              top y")
	for x in range(12, 32):
		var key := "%d,%d" % [x, 16]
		if not columns.has(key):
			continue
		var col := columns[key] as Dictionary
		var ys := col.keys()
		ys.sort()
		var parts := PackedStringArray()
		var top := -INF
		for y_v in ys:
			var e := col[y_v] as Dictionary
			parts.append("%s@%d%s" % [str(e["id"]).substr(0, 12), int(y_v),
				"·NOTHING-DRAWN" if bool(e["empty"]) else ""])
			if not bool(e["empty"]) and str(e["id"]).begins_with("roof"):
				continue
			if not bool(e["empty"]):
				top = maxf(top, float(e["hi"]))
		print("  %3d   %-52s  %6.3f" % [x, " ".join(parts), top])

	remove_child(fitout)
	fitout.free()


func _parse(raw: String) -> Dictionary:
	var cut := raw.rfind("_")
	if cut <= 0:
		return {}
	var parts := raw.substr(cut + 1).split(",")
	if parts.size() != 3:
		return {}
	for p in parts:
		if not p.is_valid_int():
			return {}
	return {
		"id": raw.substr(0, cut),
		"cell": Vector3i(int(parts[0]), int(parts[1]), int(parts[2])),
	}


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _visual_instances(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node as VisualInstance3D)
	for child in node.get_children():
		out.append_array(_visual_instances(child))
	return out
