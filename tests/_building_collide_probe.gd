extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Measures what
## PhysicsServer3D actually holds for a stamped warehouse, and marches a
## player-sized capsule at it. Lane B: BuildingCache preloads brick_door.gd,
## which names WorldGateway.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_building_collide_probe.tscn

const CAPSULE_R := 0.35
const STAND_H := 1.8
const KNEE_H := 0.8
const MARCH_STEP := 0.04

var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		printerr("[probe] warehouse did not load")
		get_tree().quit(1)
		return
	printerr("[probe] blueprint id=%s grid=%s primary=%d"
		% [layout.blueprint_id, str(layout.grid_size), layout.iter_primary_cells().size()])
	_space = (self as Node).get_viewport().world_3d.direct_space_state

	BuildingCache.clear()
	var cached := BuildingCache.instance(layout, true)
	add_child(cached)
	await get_tree().physics_frame
	await get_tree().physics_frame
	printerr("\n=== A. PRODUCTION PATH: BuildingCache.instance(layout, true) ===")
	_dump_bodies(cached)
	printerr("  DRAWN mesh union: %s" % str(_drawn_bounds(cached)))
	printerr("--- marches against A ---")
	await _marches()
	remove_child(cached)
	cached.free()
	await get_tree().physics_frame

	printerr("\n=== A2. STRIP TEST: the same path on a blueprint with cells emptied ===")
	var bare := BuildingBlueprintCatalog.by_id("warehouse")
	bare.cells.clear()
	BuildingCache.clear()
	var stripped := BuildingCache.instance(bare, true)
	add_child(stripped)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_dump_bodies(stripped)
	remove_child(stripped)
	stripped.free()
	await get_tree().physics_frame

	printerr("\n=== B. THE OTHER PATH: BuildingFitout.build(layout, true) ===")
	var fitout := BuildingFitout.build(layout, true)
	add_child(fitout)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_dump_bodies(fitout)
	printerr("  DRAWN mesh union: %s" % str(_drawn_bounds(fitout)))
	printerr("--- marches against B (per-brick colliders) ---")
	await _marches()
	await _between_bricks()
	remove_child(fitout)
	fitout.free()
	await get_tree().physics_frame

	printerr("\n=== D. DRAWN GEOMETRY of the two doors ===")
	_door_geometry(layout)

	get_tree().quit(0)


func _bodies(node: Node, out: Array) -> void:
	if node is CollisionObject3D:
		out.append(node)
	for child in node.get_children():
		_bodies(child, out)


func _dump_bodies(root: Node) -> void:
	var found: Array = []
	_bodies(root, found)
	printerr("[probe] %d CollisionObject3D under %s" % [found.size(), root.name])
	var total := 0
	var bodies_only := 0
	for body_variant in found:
		var body := body_variant as CollisionObject3D
		var rid := body.get_rid()
		var is_body := body is PhysicsBody3D
		var count := PhysicsServer3D.body_get_shape_count(rid) if is_body \
			else PhysicsServer3D.area_get_shape_count(rid)
		total += count
		if is_body:
			bodies_only += count
		printerr("  body %s (%s): PhysicsServer3D holds %d shapes"
			% [body.name, body.get_class(), count])
		if not is_body:
			continue
		var union := AABB()
		for i in count:
			var shape_rid: RID = PhysicsServer3D.body_get_shape(rid, i)
			var xf: Transform3D = body.global_transform * PhysicsServer3D.body_get_shape_transform(rid, i)
			var data: Variant = PhysicsServer3D.shape_get_data(shape_rid)
			var extent := Vector3.ONE
			if data is Vector3:
				extent = (data as Vector3) * 2.0
			var box := AABB(xf.origin - extent * 0.5, extent)
			union = box if i == 0 else union.merge(box)
			if count <= 8:
				printerr("    shape %d type=%d size=%s centre=%s -> y %.3f..%.3f"
					% [i, PhysicsServer3D.shape_get_type(shape_rid), str(extent), str(xf.origin),
						xf.origin.y - extent.y * 0.5, xf.origin.y + extent.y * 0.5])
		if count > 0:
			printerr("    union of shapes: pos %s size %s" % [str(union.position), str(union.size)])
	printerr("[probe] TOTAL SHAPES = %d (on PhysicsBody3D: %d)" % [total, bodies_only])


func _drawn_bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		out = aabb if first else out.merge(aabb)
		first = false
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _figure(height: float) -> PhysicsShapeQueryParameters3D:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	return query


func _hit(centre: Vector3, query: PhysicsShapeQueryParameters3D) -> String:
	query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(query, 8):
		var hit := hit_variant as Dictionary
		var body := hit.get("collider") as CollisionObject3D
		if body == null:
			continue
		var owner: Node = body.shape_owner_get_owner(
			body.shape_find_owner(int(hit.get("shape", -1)))
		) as Node
		return "%s/%s" % [body.name, "?" if owner == null else str(owner.name)]
	return ""


func _march(label: String, from: Vector3, motion: Vector3, height: float) -> void:
	var query := _figure(height)
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	for i in steps + 1:
		var at := from + motion * (float(i) / float(steps))
		var name := _hit(at, query)
		if name.is_empty():
			continue
		if i == 0:
			printerr("  %s: BEGAN INSIDE %s at %s (VACUOUS)" % [label, name, str(at)])
			return
		printerr("  %s: stopped at %.3f m by %s (capsule centre %s)"
			% [label, (float(i) / float(steps)) * length, name, str(at)])
		return
	printerr("  %s: WALKED THROUGH the full %.2f m" % [label, length])


func _marches() -> void:
	## The building stands at world origin: x -10..10, z -6..6.
	## Front wall is cell z 16 (centre -5.5). Doors centred x -5.0 and +5.0.
	printerr("-- standing figure, 1.8 m, foot on y=0 (centre y 0.9) --")
	_march("wall @x=0.5 marching +z from z=-10", Vector3(0.5, 0.9, -10.0), Vector3(0, 0, 6.0), STAND_H)
	_march("wall @x=-8.5 marching +z from z=-10", Vector3(-8.5, 0.9, -10.0), Vector3(0, 0, 6.0), STAND_H)
	_march("side wall @z=0.5 marching +x from x=-14", Vector3(-14.0, 0.9, 0.5), Vector3(6.0, 0, 0), STAND_H)
	_march("back wall @x=0.5 marching -z from z=+10", Vector3(0.5, 0.9, 10.0), Vector3(0, 0, -6.0), STAND_H)
	_march("door A @x=-5.0 marching +z from z=-10", Vector3(-5.0, 0.9, -10.0), Vector3(0, 0, 8.0), STAND_H)
	_march("door B @x=+5.0 marching +z from z=-10", Vector3(5.0, 0.9, -10.0), Vector3(0, 0, 8.0), STAND_H)
	printerr("-- kneeling figure, 0.8 m --")
	_march("wall @x=0.5 kneeling", Vector3(0.5, 0.4, -10.0), Vector3(0, 0, 6.0), KNEE_H)
	printerr("-- drop inside: from y=2.6 straight down at 4 stations --")
	for station in [Vector2(0.5, 0.5), Vector2(-6.5, 0.5), Vector2(6.5, 3.5), Vector2(0.5, -3.5)]:
		_march("drop at (%.1f, %.1f)" % [station.x, station.y],
			Vector3(station.x, 2.6 + KNEE_H * 0.5, station.y), Vector3.DOWN * 3.0, KNEE_H)
	printerr("-- stand test: 1.8 m capsule planted with foot at y=0.03 inside --")
	var stand := _figure(STAND_H)
	for station in [Vector2(0.5, 0.5), Vector2(-6.5, 0.5), Vector2(6.5, 3.5), Vector2(0.5, -3.5)]:
		var name := _hit(Vector3(station.x, 0.03 + STAND_H * 0.5, station.y), stand)
		printerr("  stand at (%.1f, %.1f): %s" % [station.x, station.y,
			"CLEAR" if name.is_empty() else "inside " + name])
	printerr("-- control: open air 40 m up --")
	_march("open air", Vector3(0.0, 40.0, -10.0), Vector3(0, 0, 20.0), STAND_H)


## DOES A PLAYER FIT BETWEEN THE BRICKS? Brick centres sit on integer+0.5 and a
## 1x1x1 brick DRAWS 0.5 m, so it spans +-0.25 of its centre: solid on
## [n+0.25, n+0.75], daylight on [n+0.75, n+1.25]. The joins are on the integers.
func _between_bricks() -> void:
	printerr("-- BETWEEN-BRICK marches at the front wall (joins on integer x) --")
	for x in [0.0, -1.0, -8.0, 1.0]:
		_march("standing at vertical join x=%.2f" % x, Vector3(x, 0.9, -10.0),
			Vector3(0, 0, 6.0), STAND_H)
	printerr("-- point scan across the front wall at y=0.5 (brick mid-height), x -9.9..-7.1 --")
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	var line := ""
	var x := -9.9
	while x <= -7.1:
		query.position = Vector3(x, 0.5, -5.5)
		line += "#" if not _space.intersect_point(query, 1).is_empty() else "."
		x += 0.05
	printerr("  x -9.90 -> -7.10 step 0.05 : %s" % line)
	printerr("-- point scan UP the front wall at x=-8.5 (brick centre), y 0.0..3.0 --")
	line = ""
	var y := 0.0
	while y <= 3.0:
		query.position = Vector3(-8.5, y, -5.5)
		line += "#" if not _space.intersect_point(query, 1).is_empty() else "."
		y += 0.05
	printerr("  y 0.00 -> 3.00 step 0.05 : %s" % line)


func _door_geometry(layout: BuildingLayout) -> void:
	var grid := layout.grid()
	for item in layout.iter_primary_cells():
		var brick_id := str(item.get("brick_id", ""))
		if brick_id != "block_door_double":
			continue
		var cell := item["cell"] as Vector3i
		var yaw := int(item.get("yaw", 0))
		var centre := BuildingFitout.footprint_center_local(grid, cell, brick_id, yaw)
		var drawn := BrickCatalog.size_m(brick_id)
		var fp := BrickCatalog.footprint_of(brick_id)
		var pitch := Vector3(float(fp.x), float(fp.y), float(fp.z)) * BuildingGrid.CELL_M
		printerr("  door cell %s yaw %d: footprint %s cells" % [str(cell), yaw, str(fp)])
		printerr("    pitch reserves %s m, brick DRAWS %s m (factor %.3f)"
			% [str(pitch), str(drawn), pitch.x / maxf(drawn.x, 0.0001)])
		printerr("    drawn box centred %s -> x %.3f..%.3f, y %.3f..%.3f, z %.3f..%.3f"
			% [str(centre), centre.x - drawn.x * 0.5, centre.x + drawn.x * 0.5,
				centre.y - drawn.y * 0.5, centre.y + drawn.y * 0.5,
				centre.z - drawn.z * 0.5, centre.z + drawn.z * 0.5])
		printerr("    a 1.8 m player needs 1.800 m of head; the leaf opening draws %.3f m"
			% drawn.y)
