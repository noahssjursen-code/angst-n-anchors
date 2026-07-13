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

	var cargo_zones: Array = layout.iter_cargo_zones()
	var crane_origins: Array[Vector3i] = []
	var ladder_n := 0
	var fishing_n := 0
	var brick_i := 0

	for item in layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		var yaw := int(item.get("yaw", 0))
		if not BrickCatalog.has(brick_id):
			continue
		var opts: Dictionary = {}
		if BrickCatalog.has_tag(brick_id, "text"):
			opts["text"] = str(item.get("text", ""))
		var visual := BrickCatalog.create_visual(brick_id, opts)
		visual.name = "%s_%d_%d_%d" % [brick_id, cell.x, cell.y, cell.z]
		var boat_local := footprint_center_local(g, cell, brick_id, yaw)
		visual.position = boat_local
		visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
		root.add_child(visual)
		var brick_mass := float(BrickCatalog.get_entry(brick_id).get("mass_kg", 0.0))
		boat.set_mass_entry(
			"brick:%d:%d:%d" % [cell.x, cell.y, cell.z],
			brick_mass,
			boat_local,
			"brick"
		)
		## Doors / stairs / helm / lights manage their own colliders (or none).
		if (
			not BrickCatalog.has_tag(brick_id, "text")
			and not BrickCatalog.has_tag(brick_id, "door")
			and not BrickCatalog.has_tag(brick_id, "stairs")
			and not BrickCatalog.has_tag(brick_id, "helm")
			and not BrickCatalog.has_tag(brick_id, "light")
		):
			_add_brick_collider(boat, brick_id, boat_local, yaw, brick_i)
			brick_i += 1

		var sign_id := str(item.get("sign_id", ""))
		if BrickCatalog.has(sign_id) and BrickCatalog.has_tag(sign_id, "text"):
			var sign_yaw := int(item.get("sign_yaw", yaw))
			var sign := BrickCatalog.create_visual(sign_id, {"text": str(item.get("text", ""))})
			sign.name = "Sign_%d_%d_%d" % [cell.x, cell.y, cell.z]
			## Mount on the host cell centre so a wall keeps its mesh; plaque sticks out.
			sign.position = g.cell_center_local(cell)
			sign.rotation_degrees = Vector3(0.0, float(sign_yaw), 0.0)
			root.add_child(sign)

		var light_id := str(item.get("light_id", ""))
		if BrickCatalog.has(light_id) and BrickCatalog.has_tag(light_id, "light"):
			var light_yaw := int(item.get("light_yaw", yaw))
			_add_mounted_light(root, g, cell, light_id, light_yaw)

		if BrickCatalog.has_tag(brick_id, "door"):
			_add_brick_door(boat, visual, boat_local, yaw, brick_id)
		if BrickCatalog.has_tag(brick_id, "stairs"):
			_add_stairs_colliders(boat, boat_local, yaw, brick_id, brick_i)
			brick_i += 1
		if BrickCatalog.has_tag(brick_id, "helm"):
			_add_helm_station(visual)
		if BrickCatalog.has_tag(brick_id, "light"):
			## Free-standing light brick (empty-cell placement).
			_add_brick_light(visual, brick_id)
		if BrickCatalog.has_tag(brick_id, "crane"):
			crane_origins.append(cell)
		if BrickCatalog.has_tag(brick_id, "ladder"):
			_add_hull_ladder(visual)
			ladder_n += 1
		if BrickCatalog.has_tag(brick_id, "trommel") or BrickCatalog.has_tag(brick_id, "fishing"):
			## One live FishingSystem per hull — first trommel wins.
			if fishing_n == 0:
				_add_trommel_fishing(visual)
			fishing_n += 1
		if BrickCatalog.has_tag(brick_id, "mooring"):
			_add_deck_bollard(visual)

	var zone_i := 0
	for zone in cargo_zones:
		_add_cargo_deck_zone(boat, root, g, zone as Dictionary, zone_i)
		zone_i += 1

	var report := BrickRules.validate(layout, g)
	var caps: Dictionary = report.get("capabilities", {})
	caps["has_ladder"] = ladder_n > 0
	caps["ladders"] = ladder_n
	caps["has_fishing"] = fishing_n > 0
	caps["trommels"] = fishing_n
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("brick_layout", layout.to_dict())

	var lighting := boat.get_node_or_null("ShipLighting") as ShipLighting
	if lighting != null and lighting.has_method("_gather_lights"):
		lighting.call_deferred("_gather_lights")
	return caps


static func clear(boat: BoatBody) -> void:
	if boat == null:
		return
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


static func _add_hull_ladder(visual: Node3D) -> void:
	var board := HullLadderBoard.new()
	board.name = "HullLadderBoard"
	visual.add_child(board)


static func _add_trommel_fishing(visual: Node3D) -> void:
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
		"block_window":
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
	boat.add_walk_brick_collider(
		"%s_%d" % [brick_id, index],
		boat_point,
		size,
		float(yaw),
	)


static func _add_cargo_deck_zone(
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


static func _add_helm_station(visual: Node3D) -> void:
	## Player-placed console — F only when looking at this station.
	var helm := BridgeInteractable.new()
	helm.name = "BridgeInteractable"
	helm.position = Vector3.ZERO
	helm.interact_range = 2.8
	helm.look_distance = 4.0
	helm.exit_deck_offset = Vector2(0.0, 1.2)
	visual.add_child(helm)


static func _add_brick_light(visual: Node3D, brick_id: String) -> void:
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
	var lens := _find_lens_mesh(visual)
	if head != null:
		## Beam inherits housing pitch; sit at / just past the lens face.
		head.add_child(light)
		light.position = Vector3(0.0, 0.0, -0.34) if lens == null else lens.position
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


static func _add_mounted_light(
	root: Node3D,
	grid: DeckGrid,
	cell: Vector3i,
	light_id: String,
	light_yaw: int,
) -> void:
	## Fixture on host face — yaw aims throw (−Z); flood pitch from catalog (45° / 25° down).
	var visual := BrickCatalog.create_visual(light_id)
	visual.name = "Light_%d_%d_%d" % [cell.x, cell.y, cell.z]
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(light_yaw)), 0.0))
	## High on the outward face (floods live on high ground).
	var y_lift := 0.15 if BrickCatalog.has_tag(light_id, "work") else 0.0
	var face_off := basis * Vector3(0.0, y_lift, -DeckGrid.CELL_M * 0.42)
	visual.position = grid.cell_center_local(cell) + face_off
	visual.rotation_degrees = Vector3(0.0, float(light_yaw), 0.0)
	root.add_child(visual)
	_add_brick_light(visual, light_id)


static func light_mount_offset(light_yaw: int, light_id: String = "") -> Vector3:
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
