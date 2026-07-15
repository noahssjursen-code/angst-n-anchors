class_name DeckFitout
extends RefCounted

## Rebuilds brick visuals + gameplay nodes on a BoatBody from a BrickLayout.
## New deck equipment = BrickCatalog tag + mount helper + BoatBody discovery.
## Only VesselOutfit-accepted slots become live systems (fair MP / UGC).

const FITOUT_ROOT := "DeckFitout"
const FITOUT_JOB := "DeckFitoutJob"
const FITOUT_JOB_SCRIPT := "res://scripts/ship/deck_fitout_job.gd"
const AUTO_UTILS := "AutoUtilities"
const LARGE_LAYOUT_THRESHOLD := 1000
const READINESS_HULL := 0
const READINESS_EXTERIOR := 1
const READINESS_FULL_VISUAL := 2
const READINESS_INTERACTIVE := 3


static func apply(
	boat: BoatBody,
	layout: BrickLayout,
	grid: DeckGrid = null,
	registration_id: String = "",
) -> Dictionary:
	if boat == null:
		return {}
	if layout == null or layout.is_empty():
		clear(boat)
		return {}
	var g := grid
	if g == null:
		g = grid_for_boat(boat)
	var primary_items := layout.iter_primary_cells()
	if primary_items.size() > LARGE_LAYOUT_THRESHOLD:
		return apply_staged(boat, layout, g, registration_id, primary_items)
	return apply_sync(boat, layout, g, registration_id, primary_items)


static func apply_sync(
	boat: BoatBody,
	layout: BrickLayout,
	grid: DeckGrid = null,
	registration_id: String = "",
	primary_items: Array = [],
) -> Dictionary:
	## Immediate path retained for ordinary boats and parity tests.
	if boat == null or layout == null:
		return {}
	clear(boat)
	var g := grid if grid != null else grid_for_boat(boat)
	var items := primary_items if not primary_items.is_empty() else layout.iter_primary_cells()
	var hull_id := str(layout.hull_id)
	if hull_id.is_empty() and boat.has_meta("editor_hull_id"):
		hull_id = str(boat.get_meta("editor_hull_id"))
	var declared := registration_id.strip_edges()
	if declared.is_empty() and boat.has_meta("registration_id"):
		declared = str(boat.get_meta("registration_id"))
	var outfit := VesselCompliance.validate(layout, hull_id, declared, g)
	var accepted: Dictionary = outfit.get("accepted_slots", {})
	var accepted_fishing: Dictionary = _cell_set(accepted.get("fishing", []))
	var accepted_helm: Dictionary = _cell_set(accepted.get("helm", []))
	var accepted_cargo: Dictionary = {}
	for idx in accepted.get("cargo_zone_indices", []):
		accepted_cargo[int(idx)] = true

	var root := Node3D.new()
	root.name = FITOUT_ROOT
	boat.add_child(root)
	boat.ensure_walk_deck()
	boat.clear_walk_brick_colliders()
	var visual_by_key := {}
	for item_raw in items:
		var item := item_raw as Dictionary
		var visual := create_item_visual(root, g, item)
		if visual != null:
			visual_by_key[BrickLayout.cell_key(item["cell"] as Vector3i)] = visual
	var state := {"brick_i": 0, "ladder_n": 0}
	for item_raw in items:
		var item := item_raw as Dictionary
		var key := BrickLayout.cell_key(item["cell"] as Vector3i)
		var visual := visual_by_key.get(key, null) as Node3D
		if visual != null:
			mount_item_gameplay(
				boat, root, g, item, visual, accepted_fishing, accepted_helm, state
			)
	return finish_fitout(boat, root, layout, g, outfit, accepted_cargo, declared, state)


static func apply_staged(
	boat: BoatBody,
	layout: BrickLayout,
	grid: DeckGrid = null,
	registration_id: String = "",
	primary_items: Array = [],
) -> Dictionary:
	if boat == null or layout == null:
		return {}
	clear(boat)
	var g := grid if grid != null else grid_for_boat(boat)
	var items := primary_items if not primary_items.is_empty() else layout.iter_primary_cells()
	var hull_id := str(layout.hull_id)
	if hull_id.is_empty() and boat.has_meta("editor_hull_id"):
		hull_id = str(boat.get_meta("editor_hull_id"))
	var declared := registration_id.strip_edges()
	if declared.is_empty() and boat.has_meta("registration_id"):
		declared = str(boat.get_meta("registration_id"))
	var root := Node3D.new()
	root.name = FITOUT_ROOT
	boat.add_child(root)
	boat.ensure_walk_deck()
	boat.clear_walk_brick_colliders()
	var job := load(FITOUT_JOB_SCRIPT).new() as Node
	job.name = FITOUT_JOB
	boat.add_child(job)
	var remote := bool(boat.get_meta("remote_replica", false))
	job.call("configure", boat, root, layout, g, hull_id, declared, items, not remote)
	var caps := {"staged": true, "outfit_ok": false}
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("fitout_readiness", READINESS_HULL)
	return caps


static func create_item_visual(
	root: Node3D,
	grid: DeckGrid,
	item: Dictionary,
) -> Node3D:
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var brick_id := str(item.get("brick_id", ""))
	var yaw := int(item.get("yaw", 0))
	if root == null or grid == null or not _item_is_valid(grid, cell, brick_id, yaw):
		return null
	var opts: Dictionary = {"color": BrickLayout.color_from_entry(item, brick_id)}
	if BrickCatalog.has_tag(brick_id, "text"):
		opts["text"] = str(item.get("text", ""))
	var visual := BrickCatalog.create_visual(brick_id, opts)
	visual.name = "%s_%d_%d_%d" % [brick_id, cell.x, cell.y, cell.z]
	visual.position = footprint_center_local(grid, cell, brick_id, yaw)
	visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
	root.add_child(visual)

	var sign_id := str(item.get("sign_id", ""))
	if BrickCatalog.has(sign_id) and BrickCatalog.has_tag(sign_id, "text"):
		var sign_yaw := int(item.get("sign_yaw", yaw))
		var sign := BrickCatalog.create_visual(sign_id, {"text": str(item.get("text", ""))})
		sign.name = "Sign_%d_%d_%d" % [cell.x, cell.y, cell.z]
		sign.position = grid.cell_center_local(cell)
		sign.rotation_degrees = Vector3(0.0, float(sign_yaw), 0.0)
		root.add_child(sign)

	var light_id := str(item.get("light_id", ""))
	if BrickCatalog.has(light_id) and BrickCatalog.has_tag(light_id, "light"):
		var light_yaw := int(item.get("light_yaw", yaw))
		_add_mounted_light_visual(root, grid, cell, light_id, light_yaw)
	return visual


static func mount_item_gameplay(
	boat: BoatBody,
	root: Node3D,
	grid: DeckGrid,
	item: Dictionary,
	visual: Node3D,
	accepted_fishing: Dictionary,
	accepted_helm: Dictionary,
	state: Dictionary,
) -> void:
	if boat == null or root == null or grid == null or visual == null:
		return
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var brick_id := str(item.get("brick_id", ""))
	var yaw := int(item.get("yaw", 0))
	if not _item_is_valid(grid, cell, brick_id, yaw):
		return
	var boat_local := footprint_center_local(grid, cell, brick_id, yaw)
	var brick_mass := float(BrickCatalog.get_entry(brick_id).get("mass_kg", 0.0))
	boat.set_mass_entry(
		"brick:%d:%d:%d" % [cell.x, cell.y, cell.z],
		brick_mass,
		boat_local,
		"brick"
	)
	var brick_i := int(state.get("brick_i", 0))
	if (
		not BrickCatalog.has_tag(brick_id, "text")
		and not BrickCatalog.has_tag(brick_id, "door")
		and not BrickCatalog.has_tag(brick_id, "stairs")
		and not BrickCatalog.has_tag(brick_id, "helm")
		and not BrickCatalog.has_tag(brick_id, "light")
	):
		_add_brick_collider(boat, brick_id, boat_local, yaw, brick_i)
		brick_i += 1
	if BrickCatalog.has_tag(brick_id, "door"):
		_add_brick_door(boat, visual, boat_local, yaw, brick_id)
	if BrickCatalog.has_tag(brick_id, "stairs"):
		_add_stairs_colliders(boat, boat_local, yaw, brick_id, brick_i)
		brick_i += 1
	if BrickCatalog.has_tag(brick_id, "helm") and accepted_helm.has(cell):
		_mount_helm(visual)
	if BrickCatalog.has_tag(brick_id, "light"):
		_mount_light(visual, brick_id)
	if BrickCatalog.has_tag(brick_id, "ladder"):
		_mount_ladder(visual)
		state["ladder_n"] = int(state.get("ladder_n", 0)) + 1
	if (
		(BrickCatalog.has_tag(brick_id, "trommel") or BrickCatalog.has_tag(brick_id, "fishing"))
		and accepted_fishing.has(cell)
	):
		_mount_fishing(visual)
	if BrickCatalog.has_tag(brick_id, "mooring"):
		_mount_mooring(visual, brick_id)
	var light_id := str(item.get("light_id", ""))
	if BrickCatalog.has(light_id) and BrickCatalog.has_tag(light_id, "light"):
		var fixture := root.get_node_or_null(_mounted_light_name(cell)) as Node3D
		if fixture != null and fixture.get_node_or_null("ShipLight") == null:
			_mount_light(fixture, light_id)
	state["brick_i"] = brick_i


static func finish_fitout(
	boat: BoatBody,
	root: Node3D,
	layout: BrickLayout,
	grid: DeckGrid,
	outfit: Dictionary,
	accepted_cargo: Dictionary,
	declared: String,
	state: Dictionary,
) -> Dictionary:
	var zone_i := 0
	for zone in layout.iter_cargo_zones():
		if accepted_cargo.has(zone_i):
			_mount_cargo_zone(boat, root, grid, zone as Dictionary, zone_i)
		zone_i += 1
	var ladder_n := int(state.get("ladder_n", 0))
	var caps: Dictionary = outfit.get("capabilities", {}).duplicate(true)
	caps["has_ladder"] = ladder_n > 0
	caps["ladders"] = ladder_n
	caps["outfit_ok"] = bool(outfit.get("ok", false))
	if not bool(outfit.get("ok", false)):
		var errors: PackedStringArray = outfit.get("errors", PackedStringArray())
		push_warning(
			"DeckFitout: illegal outfit on %s — surplus gear not mounted. %s"
			% [boat.name, " · ".join(errors)]
		)
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("brick_layout", layout.to_dict())
	boat.set_meta("vessel_outfit", {
		"ok": outfit.get("ok", false),
		"budget": outfit.get("budget", {}),
		"usage": outfit.get("usage", {}),
		"registration_id": declared,
		"registration_ok": outfit.get("registration_ok", false),
	})
	boat.set_meta("fitout_readiness", READINESS_INTERACTIVE)
	var lighting := boat.get_node_or_null("ShipLighting") as ShipLighting
	if lighting != null and lighting.has_method("_gather_lights"):
		lighting.call_deferred("_gather_lights")
	return caps


static func request_full_detail(boat: BoatBody) -> void:
	if boat == null:
		return
	var job := boat.get_node_or_null(FITOUT_JOB)
	if job != null and job.has_method("request_full_detail"):
		job.call("request_full_detail")


static func readiness_of(boat: BoatBody) -> int:
	if boat == null:
		return READINESS_HULL
	return int(boat.get_meta("fitout_readiness", READINESS_HULL))


static func _item_is_valid(
	grid: DeckGrid,
	cell: Vector3i,
	brick_id: String,
	yaw: int,
) -> bool:
	if not BrickCatalog.has(brick_id):
		return false
	if grid.is_partial_bow_cell(cell):
		return (
			BrickCatalog.has_tag(brick_id, "diagonal_plan")
			and yaw == grid.partial_bow_yaw_degrees(cell)
		)
	return grid.in_bounds(cell)


static func _cell_set(cells: Variant) -> Dictionary:
	var out := {}
	if cells is Array:
		for c in cells as Array:
			if c is Vector3i:
				out[c] = true
	return out


static func clear(boat: BoatBody) -> void:
	if boat == null:
		return
	var job := boat.get_node_or_null(FITOUT_JOB)
	if job != null:
		boat.remove_child(job)
		job.free()
	boat.clear_mass_entries("brick:")
	var existing := boat.get_node_or_null(FITOUT_ROOT)
	if existing != null:
		boat.remove_child(existing)
		existing.free()
	boat.clear_walk_brick_colliders()
	if boat.has_meta("brick_capabilities"):
		boat.remove_meta("brick_capabilities")
	if boat.has_meta("brick_layout"):
		boat.remove_meta("brick_layout")
	if boat.has_meta("vessel_outfit"):
		boat.remove_meta("vessel_outfit")
	if boat.has_meta("fitout_readiness"):
		boat.remove_meta("fitout_readiness")


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
	if boat != null and boat.has_method("deck_grid"):
		var declared: Variant = boat.call("deck_grid")
		if declared is DeckGrid:
			return declared as DeckGrid
	var loa: float = boat.length_m if boat != null and boat.length_m > 0.1 else 28.0
	var beam: float = boat.beam_m if boat != null and boat.beam_m > 0.1 else 10.0
	var deck_y := 0.0
	if boat != null and boat.hull_stations != null:
		deck_y = boat.hull_stations.deck_y + 0.12
	elif boat != null and boat.depth_m > 0.0:
		deck_y = boat.depth_m * 0.85 + 0.12
	return DeckGrid.from_hull(loa, beam, deck_y)


static func capabilities_of(boat: BoatBody) -> Dictionary:
	if boat != null and boat.has_meta("brick_capabilities"):
		return boat.get_meta("brick_capabilities") as Dictionary
	return {}


static func _mount_ladder(visual: Node3D) -> void:
	var board := HullLadderBoard.new()
	board.name = "HullLadderBoard"
	visual.add_child(board)


static func _mount_fishing(visual: Node3D) -> void:
	## Drop catalog preview meshes — FishingSystem owns the live trommel + net.
	for child in visual.get_children():
		visual.remove_child(child)
		child.free()
	var fishing := FishingSystem.new()
	fishing.name = "FishingSystem"
	fishing.anchored_to_brick = true
	visual.add_child(fishing)


static func _add_brick_door(
	boat: BoatBody,
	visual: Node3D,
	boat_local: Vector3,
	yaw: int,
	brick_id: String,
) -> void:
	var sz := BrickCatalog.size_m(brick_id)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	## Static jambs stay solid; the swinging leaf is handled by BrickDoor.
	var post := Vector3(0.14, sz.y * 0.95, maxf(sz.z * 0.3, 0.2))
	boat.add_walk_brick_collider(
		"door_jamb_l_%d" % int(boat_local.length() * 100.0),
		boat_local + basis * Vector3(-sz.x * 0.5 + 0.07, 0.0, 0.0),
		post,
		float(yaw),
	)
	boat.add_walk_brick_collider(
		"door_jamb_r_%d" % int(boat_local.length() * 100.0),
		boat_local + basis * Vector3(sz.x * 0.5 - 0.07, 0.0, 0.0),
		post,
		float(yaw),
	)
	var door := BrickDoor.new()
	door.name = "BrickDoor"
	door.configure(
		boat,
		boat_local,
		float(yaw),
		Vector3(sz.x * 0.8, sz.y * 0.88, 0.12),
	)
	visual.add_child(door)


static func _add_stairs_colliders(
	boat: BoatBody,
	boat_local: Vector3,
	yaw: int,
	brick_id: String,
	index: int,
) -> void:
	## One walk box per tread so step-up works with player max_step_height (~0.45 m).
	if boat == null:
		return
	var entry := BrickCatalog.get_entry(brick_id)
	var n := maxi(int(entry.get("stair_steps", 4)), 2)
	var sz := BrickCatalog.size_m(brick_id)
	var riser := sz.y / float(n)
	var tread := sz.z / float(n)
	var hy := sz.y * 0.5
	var hz := sz.z * 0.5
	var overlap := 0.004
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	for k in range(n):
		var h := riser * float(k + 1)
		var local_off := Vector3(0.0, -hy + h * 0.5, hz - (float(k) + 0.5) * tread)
		boat.add_walk_brick_collider(
			"stairs_%d_%d" % [index, k],
			boat_local + basis * local_off,
			Vector3(sz.x, h, tread + overlap),
			float(yaw),
		)


static func _mount_mooring(visual: Node3D, brick_id: String = "bollard") -> void:
	## Keep the brick mesh (cell-centred, yaw from layout). Cleat sits on the cell floor
	## — MooringPoint meshes are base-origin and must not replace the brick visual.
	var cleat := MooringPoint.new()
	cleat.name = "MooringCleat"
	cleat.build_visual = false
	cleat.bollard_rotation_degrees = Vector3.ZERO
	if BrickCatalog.has_tag(brick_id, "railing"):
		## Railing stays on −Z; the mooring bit is cell-centred like a deck bollard.
		cleat.position = Vector3(0.0, -DeckGrid.CELL_M * 0.5, 0.0)
		cleat.anchor_local_position = Vector3(0.0, 0.45, 0.0)
	else:
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
		"bollard":
			return {
				"size": Vector3(0.45, sz.y * 0.75, 0.45),
				"offset": Vector3(0.0, -sz.y * 0.1, 0.0),
			}
		"mast_base":
			return {
				"size": Vector3(sz.x * 0.9, 0.28, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.14, 0.0),
			}
		"mast_pole":
			return {
				"size": Vector3(0.22, sz.y * 0.95, 0.22),
				"offset": Vector3.ZERO,
			}
		"chimney_2x3x2", "chimney_4x5x4":
			return {
				"size": Vector3(sz.x * 0.72, sz.y * 0.96, sz.z * 0.72),
				"offset": Vector3.ZERO,
			}
		"light_mast_white":
			return {
				"size": Vector3(0.4, 0.7, 0.4),
				"offset": Vector3(0.0, -sz.y * 0.15, 0.0),
			}
		"ledge_45":
			## Box approx under the slope (lower half) — enough to stand / block.
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_slope":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_slope_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"roof_corner":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_corner_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"ledge_45_corner":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"ledge_45_corner_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"roof_corner_inner", "ledge_45_inner":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_corner_inner_inv", "ledge_45_inner_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"block_window", "block_windshield":
			## Thin wall on the glazed −Z face.
			return {
				"size": Vector3(sz.x * 0.95, sz.y * 0.95, 0.14),
				"offset": Vector3(0.0, 0.0, -sz.z * 0.5 + 0.07),
			}
		"block_window_corner":
			## L-shaped approx: full cell thin enough to stand against.
			return {
				"size": Vector3(sz.x * 0.95, sz.y * 0.95, sz.z * 0.95),
				"offset": Vector3.ZERO,
			}
		"railing", "railing_mooring":
			## On the local −Z face so it meets 45° corner posts at cell corners.
			return {
				"size": Vector3(sz.x, sz.y * 0.94, 0.12),
				"offset": Vector3(0.0, 0.0, -sz.z * 0.5 + 0.06),
			}
		"railing_45":
			return {
				"size": Vector3(DeckGrid.CELL_M * sqrt(2.0), sz.y * 0.94, 0.12),
				"offset": Vector3.ZERO,
			}
		"cargo_zone", "cargo_tile":
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
		"trommel_small":
			return {
				"size": Vector3(sz.x * 0.9, 0.14, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.07, 0.0),
			}
		"bench":
			## Full footprint volume.
			return {
				"size": Vector3(sz.x * 0.94, sz.y * 0.92, sz.z * 0.72),
				"offset": Vector3(0.0, -sz.y * 0.04, sz.z * 0.08),
			}
		"table":
			return {
				"size": Vector3(sz.x * 0.9, sz.y * 0.92, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.04, 0.0),
			}
		"deck_text", "wall_text":
			return {"size": Vector3.ZERO, "offset": Vector3.ZERO}
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
	if BrickCatalog.has_tag(brick_id, "text"):
		return
	var spec := _collider_spec(brick_id)
	var size: Vector3 = spec["size"]
	if size.length_squared() < 1e-6:
		return
	var offset: Vector3 = spec["offset"]
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	var boat_point := boat_local + basis * offset
	if BrickCatalog.has_tag(brick_id, "diagonal_railing"):
		boat.add_walk_brick_collider(
			"%s_%d" % [brick_id, index],
			boat_point,
			size,
			float(yaw + 45),
		)
		return
	if BrickCatalog.has_tag(brick_id, "diagonal_plan"):
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var hz := size.z * 0.5
		boat.add_walk_brick_convex_collider(
			"%s_%d" % [brick_id, index],
			boat_point,
			PackedVector3Array([
				Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, hz),
				Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, hz),
			]),
			float(yaw),
		)
		return
	boat.add_walk_brick_collider(
		"%s_%d" % [brick_id, index],
		boat_point,
		size,
		float(yaw),
	)


static func _mount_cargo_zone(
	boat: BoatBody,
	root: Node3D,
	grid: DeckGrid,
	zone: Dictionary,
	index: int,
) -> void:
	var mn := BrickLayout.zone_min(zone)
	var mx := BrickLayout.zone_max(zone)
	var w := float(mx.x - mn.x + 1) * DeckGrid.CELL_M
	var l := float(mx.z - mn.z + 1) * DeckGrid.CELL_M
	var sum := Vector3.ZERO
	var n := 0
	for ix in range(mn.x, mx.x + 1):
		for iz in range(mn.z, mx.z + 1):
			sum += grid.cell_center_local(Vector3i(ix, 0, iz))
			n += 1
	if n <= 0:
		return
	var deck := CargoDeckComponent.new()
	deck.name = "CargoDeck_%d" % index
	deck.affects_boat_cargo_mass = true
	deck.deck_width_m = w
	deck.deck_length_m = l
	deck.cell_size_x_m = DeckGrid.CELL_M
	deck.cell_size_z_m = DeckGrid.CELL_M
	var center := sum / float(n)
	center.y = grid.deck_y + 0.06
	deck.position = center
	root.add_child(deck)


static func _mount_helm(visual: Node3D) -> void:
	## Player-placed console — F only when looking at this station.
	var helm := BridgeInteractable.new()
	helm.name = "BridgeInteractable"
	helm.position = Vector3.ZERO
	helm.interact_range = 2.8
	helm.look_distance = 4.0
	helm.exit_deck_offset = Vector2(0.0, 1.2)
	visual.add_child(helm)


static func _mount_light(visual: Node3D, brick_id: String) -> void:
	## Parent the beam under FloodHead (or at Lens) so throw matches the fixture.
	var entry := BrickCatalog.get_entry(brick_id)
	var light := ShipLight.new()
	light.name = "ShipLight"
	light.build_housing = false
	## Spot params before light_type / add_child so _ready rebuild uses them.
	if entry.has("spot_pitch_deg"):
		light.spot_pitch_deg = float(entry.get("spot_pitch_deg", 0.0))
	if entry.has("spot_range_m"):
		light.spot_range_m = float(entry.get("spot_range_m", 22.0))
	if entry.has("spot_energy"):
		light.spot_energy = float(entry.get("spot_energy", 55.0))
	if entry.has("spot_angle_deg"):
		light.spot_angle_deg = float(entry.get("spot_angle_deg", 48.0))
	light.light_type = int(entry.get("light_type", ShipLight.LightType.WORK)) as ShipLight.LightType

	var head := visual.get_node_or_null("FloodHead") as Node3D
	var emitter := visual.get_node_or_null("Emitter") as Node3D
	var lens := _find_lens_mesh(visual)
	if head != null:
		## Beam inherits housing pitch; sit at / just past the lens face.
		head.add_child(light)
		light.position = Vector3(0.0, 0.0, -0.34) if lens == null else lens.position
		light.rotation_degrees = Vector3.ZERO
	elif emitter != null:
		## All-round lanterns: emitter sits clear of solid housing mesh.
		visual.add_child(light)
		light.position = emitter.position
		light.rotation_degrees = Vector3.ZERO
	elif lens != null:
		visual.add_child(light)
		light.position = lens.position
		light.rotation_degrees = Vector3.ZERO
	else:
		visual.add_child(light)
		if BrickCatalog.has_tag(brick_id, "cabin_light"):
			light.position = Vector3(0.0, DeckGrid.CELL_M * 0.35, 0.0)
		else:
			light.position = Vector3(0.0, 0.0, -0.1)


static func _find_lens_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == "Lens":
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_lens_mesh(child)
		if found != null:
			return found
	return null


static func _mount_mounted_light(
	root: Node3D,
	grid: DeckGrid,
	cell: Vector3i,
	light_id: String,
	light_yaw: int,
) -> void:
	var visual := _add_mounted_light_visual(root, grid, cell, light_id, light_yaw)
	if visual != null:
		_mount_light(visual, light_id)


static func _add_mounted_light_visual(
	root: Node3D,
	grid: DeckGrid,
	cell: Vector3i,
	light_id: String,
	light_yaw: int,
) -> Node3D:
	if root == null or grid == null:
		return null
	var existing := root.get_node_or_null(_mounted_light_name(cell)) as Node3D
	if existing != null:
		return existing
	var visual := BrickCatalog.create_visual(light_id)
	visual.name = _mounted_light_name(cell)
	visual.position = grid.cell_center_local(cell) + light_mount_offset(light_yaw, light_id)
	visual.rotation_degrees = Vector3(0.0, float(light_yaw), 0.0)
	root.add_child(visual)
	return visual


static func _mounted_light_name(cell: Vector3i) -> String:
	return "Light_%d_%d_%d" % [cell.x, cell.y, cell.z]


static func light_mount_offset(light_yaw: int, light_id: String = "") -> Vector3:
	## Work / top-mount floods stand on the cell roof; attach lights hug the −Z face.
	if light_id != "" and (
		BrickCatalog.has_tag(light_id, "top_mount") or BrickCatalog.has_tag(light_id, "work")
	) and not BrickCatalog.has_tag(light_id, "attach"):
		return Vector3(0.0, DeckGrid.CELL_M * 0.5 + 0.02, 0.0)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(light_yaw)), 0.0))
	var y_lift := 0.15 if light_id != "" and BrickCatalog.has_tag(light_id, "work") else 0.0
	return basis * Vector3(0.0, y_lift, -DeckGrid.CELL_M * 0.42)


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
