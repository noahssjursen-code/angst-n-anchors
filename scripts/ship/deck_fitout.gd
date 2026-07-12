class_name DeckFitout
extends RefCounted

## Rebuilds brick visuals + gameplay nodes on a BoatBody from a BrickLayout.

const FITOUT_ROOT := "DeckFitout"
const AUTO_UTILS := "AutoUtilities"


static func apply(boat: BoatBody, layout: BrickLayout, grid: DeckGrid = null) -> Dictionary:
	## Returns capabilities dict from BrickRules.
	if boat == null:
		return {}
	clear(boat)
	if layout == null or layout.is_empty():
		return {}
	var g := grid
	if g == null:
		g = grid_for_boat(boat)
	var root := Node3D.new()
	root.name = FITOUT_ROOT
	boat.add_child(root)

	# WalkDeck must exist before brick colliders are attached (player layer).
	# CollisionShape3D must be *direct* children of WalkDeck — nested shapes are ignored.
	boat.ensure_walk_deck()
	boat.clear_walk_brick_colliders()

	var cargo_cells: Array[Vector3i] = []
	var has_door := false
	var wall_cells: Array[Vector3i] = []
	var crane_origins: Array[Vector3i] = []
	var ladder_n := 0
	var brick_i := 0

	for item in layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		var yaw := int(item.get("yaw", 0))
		if not BrickCatalog.has(brick_id):
			continue
		# Cargo cells only define the zone AABB — one CargoDeckComponent draws the border.
		if BrickCatalog.has_tag(brick_id, "cargo"):
			cargo_cells.append(cell)
			continue
		var visual := BrickCatalog.create_visual(brick_id)
		visual.name = "%s_%d_%d_%d" % [brick_id, cell.x, cell.y, cell.z]
		var boat_local := footprint_center_local(g, cell, brick_id, yaw)
		visual.position = boat_local
		visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
		root.add_child(visual)
		_add_brick_collider(boat, brick_id, boat_local, yaw, brick_i)
		brick_i += 1

		if BrickCatalog.has_tag(brick_id, "door"):
			has_door = true
		if BrickCatalog.has_tag(brick_id, "wall") or BrickCatalog.has_tag(brick_id, "solid"):
			wall_cells.append(cell)
		if BrickCatalog.has_tag(brick_id, "window"):
			_maybe_window_light(visual)
		if BrickCatalog.has_tag(brick_id, "crane"):
			crane_origins.append(cell)
		if BrickCatalog.has_tag(brick_id, "ladder"):
			_add_hull_ladder(visual)
			ladder_n += 1
		if BrickCatalog.has_tag(brick_id, "mooring"):
			_add_deck_bollard(visual)

	if not cargo_cells.is_empty():
		_add_cargo_deck(boat, root, g, cargo_cells)
	if has_door or wall_cells.size() >= 8:
		_add_helm(boat, root, g, wall_cells if not wall_cells.is_empty() else [Vector3i(g.width / 2, 0, g.length / 2)])

	var report := BrickRules.validate(layout, g)
	var caps: Dictionary = report.get("capabilities", {})
	caps["has_ladder"] = ladder_n > 0
	caps["ladders"] = ladder_n
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("brick_layout", layout.to_dict())

	var lighting := boat.get_node_or_null("ShipLighting") as ShipLighting
	if lighting != null and lighting.has_method("_gather_lights"):
		lighting.call_deferred("_gather_lights")
	return caps


static func clear(boat: BoatBody) -> void:
	if boat == null:
		return
	var existing := boat.get_node_or_null(FITOUT_ROOT)
	if existing != null:
		boat.remove_child(existing)
		existing.free()
	boat.clear_walk_brick_colliders()
	if boat.has_meta("brick_capabilities"):
		boat.remove_meta("brick_capabilities")
	if boat.has_meta("brick_layout"):
		boat.remove_meta("brick_layout")


static func footprint_center_local(grid: DeckGrid, origin: Vector3i, brick_id: String, yaw: int) -> Vector3:
	## AABB centre of every cell the brick occupies (handles multi-cell + yaw).
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	if yaw_steps < 0:
		yaw_steps += 4
	var occupied := grid.footprint_cells(origin, fp, yaw_steps)
	if occupied.is_empty():
		return grid.cell_center_local(origin)
	var sum := Vector3.ZERO
	for c in occupied:
		sum += grid.cell_center_local(c)
	return sum / float(occupied.size())


static func grid_for_boat(boat: BoatBody) -> DeckGrid:
	var loa := boat.length_m if boat.length_m > 0.1 else Workboat.LOA_M
	var beam := boat.beam_m if boat.beam_m > 0.1 else Workboat.BEAM_M
	var deck_y := 0.0
	if boat is Workboat:
		deck_y = (boat as Workboat)._deck_y()
	elif boat.depth_m > 0.0:
		deck_y = boat.depth_m * 0.85 + 0.12
	return DeckGrid.from_hull(loa, beam, deck_y)


static func capabilities_of(boat: BoatBody) -> Dictionary:
	if boat != null and boat.has_meta("brick_capabilities"):
		return boat.get_meta("brick_capabilities") as Dictionary
	return {}


static func _maybe_window_light(visual: Node3D) -> void:
	var light := ShipLight.new()
	light.name = "WindowLight"
	light.light_type = ShipLight.LightType.WINDOW
	light.position = Vector3(0.0, 0.0, 0.0)
	visual.add_child(light)


static func _add_hull_ladder(visual: Node3D) -> void:
	var board := HullLadderBoard.new()
	board.name = "HullLadderBoard"
	visual.add_child(board)


static func _add_deck_bollard(visual: Node3D) -> void:
	## Keep the brick mesh (cell-centred, yaw from layout). Cleat sits on the cell floor
	## — MooringPoint meshes are base-origin and must not replace the brick visual.
	var cleat := MooringPoint.new()
	cleat.name = "MooringCleat"
	cleat.build_visual = false
	cleat.bollard_rotation_degrees = Vector3.ZERO
	# Brick root = cell centre; drop to cell floor so the rope anchor matches the post base.
	cleat.position = Vector3(0.0, -DeckGrid.CELL_M * 0.5, 0.0)
	cleat.anchor_local_position = Vector3(0.0, 0.55, 0.0)
	cleat.station = "bow" if visual.position.z < 0.0 else "stern"
	cleat.side = "port" if visual.position.x < 0.0 else "starboard"
	visual.add_child(cleat)


static func _collider_spec(brick_id: String) -> Dictionary:
	## Returns { size: Vector3, offset: Vector3 } in brick-local space (visual origin).
	var sz := BrickCatalog.size_m(brick_id)
	match brick_id:
		"railing":
			return {
				"size": Vector3(sz.x * 0.95, sz.y * 0.9, 0.12),
				"offset": Vector3(0.0, 0.0, 0.0),
			}
		"bollard":
			return {
				"size": Vector3(0.45, sz.y * 0.75, 0.45),
				"offset": Vector3(0.0, -sz.y * 0.1, 0.0),
			}
		"ledge_45":
			## Box approx under the slope (lower half) — enough to stand / block.
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"cargo_tile":
			return {
				"size": Vector3(sz.x * 0.95, 0.1, sz.z * 0.95),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.05, 0.0),
			}
		"crane_base":
			return {
				"size": Vector3(sz.x, sz.y * 0.55, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.22, 0.0),
			}
		"crane":
			return {
				"size": Vector3(sz.x * 0.75, sz.y * 0.9, sz.z * 0.75),
				"offset": Vector3(0.0, 0.0, 0.0),
			}
		"hull_ladder":
			## Deck pad only — hanging rungs stay non-colliding so quay approach is free.
			return {
				"size": Vector3(sz.x * 0.9, 0.12, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.06, 0.0),
			}
		_:
			return {"size": sz, "offset": Vector3.ZERO}


static func _add_brick_collider(
	boat: BoatBody,
	brick_id: String,
	boat_local: Vector3,
	yaw: int,
	index: int,
) -> void:
	if boat == null or not BrickCatalog.has(brick_id):
		return
	var spec := _collider_spec(brick_id)
	var size: Vector3 = spec["size"]
	var offset: Vector3 = spec["offset"]
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	var boat_point := boat_local + basis * offset
	boat.add_walk_brick_collider(
		"%s_%d" % [brick_id, index],
		boat_point,
		size,
		float(yaw),
	)


static func _add_cargo_deck(boat: BoatBody, root: Node3D, grid: DeckGrid, cargo_cells: Array[Vector3i]) -> void:
	var min_x := 999
	var max_x := -999
	var min_z := 999
	var max_z := -999
	var sum := Vector3.ZERO
	for c in cargo_cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.z)
		max_z = maxi(max_z, c.z)
		sum += grid.cell_center_local(Vector3i(c.x, 0, c.z))
	var deck := CargoDeckComponent.new()
	deck.name = "CargoDeck_main"
	deck.affects_boat_cargo_mass = true
	var w := float(max_x - min_x + 1) * DeckGrid.CELL_M
	var l := float(max_z - min_z + 1) * DeckGrid.CELL_M
	deck.deck_width_m = w
	deck.deck_length_m = l
	deck.cell_size_x_m = DeckGrid.CELL_M
	deck.cell_size_z_m = DeckGrid.CELL_M
	var center := sum / float(cargo_cells.size())
	center.y = grid.deck_y + 0.06
	deck.position = center
	root.add_child(deck)


static func _add_helm(boat: BoatBody, root: Node3D, grid: DeckGrid, wall_cells: Array[Vector3i]) -> void:
	var sum := Vector3.ZERO
	for c in wall_cells:
		sum += Vector3(c)
	var avg := sum / float(wall_cells.size())
	var cell := Vector3i(int(avg.x), 0, int(avg.z))
	var helm := BridgeInteractable.new()
	helm.name = "BridgeInteractable"
	helm.position = grid.cell_base_local(cell) + Vector3(0.0, 0.1, 0.0)
	helm.exit_deck_offset = Vector2(0.0, 3.0)
	root.add_child(helm)


static func ensure_auto_utilities(boat: BoatBody) -> void:
	## Cleats + nav lights — not player-placed bricks.
	if boat == null:
		return
	if boat.find_child(AUTO_UTILS, true, false) != null:
		return
	var root := Node3D.new()
	root.name = AUTO_UTILS
	var gameplay := boat.get_node_or_null("ShipGameplay")
	if gameplay == null:
		boat.add_child(root)
	else:
		gameplay.add_child(root)

	var loa := boat.length_m
	var beam := boat.beam_m
	var deck_y := DeckFitout.grid_for_boat(boat).deck_y

	var cleats := [
		{"name": "MooringPortFwd", "side": "port", "station": "bow", "pos": Vector3(-beam * 0.45, deck_y + 0.08, -loa * 0.35)},
		{"name": "MooringStbdFwd", "side": "starboard", "station": "bow", "pos": Vector3(beam * 0.45, deck_y + 0.08, -loa * 0.35)},
		{"name": "MooringPortAft", "side": "port", "station": "stern", "pos": Vector3(-beam * 0.45, deck_y + 0.08, loa * 0.35)},
		{"name": "MooringStbdAft", "side": "starboard", "station": "stern", "pos": Vector3(beam * 0.45, deck_y + 0.08, loa * 0.35)},
	]
	for spec in cleats:
		var cleat := MooringPoint.new()
		cleat.name = str(spec["name"])
		cleat.side = str(spec["side"])
		cleat.station = str(spec["station"])
		cleat.position = spec["pos"] as Vector3
		cleat.bollard_scale = 0.85
		root.add_child(cleat)

	var lights := [
		{"type": ShipLight.LightType.NAV_PORT, "pos": Vector3(-beam * 0.48, deck_y + 0.4, -loa * 0.2)},
		{"type": ShipLight.LightType.NAV_STARBOARD, "pos": Vector3(beam * 0.48, deck_y + 0.4, -loa * 0.2)},
		{"type": ShipLight.LightType.NAV_MASTHEAD, "pos": Vector3(0.0, deck_y + 1.8, -loa * 0.35)},
		{"type": ShipLight.LightType.NAV_STERN, "pos": Vector3(0.0, deck_y + 0.5, loa * 0.45)},
	]
	for spec in lights:
		var light := ShipLight.new()
		light.light_type = spec["type"]
		light.position = spec["pos"] as Vector3
		root.add_child(light)
