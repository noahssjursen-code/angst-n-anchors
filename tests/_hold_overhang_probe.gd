extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Measures the DRAWN extent of every CatchHoldComponent on every vessel that
## mounts one, in boat-local metres, against the hull's own half-beam and deck
## ends. Reads the meshes the fitout actually committed, not the constants that
## produced them.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const PLAYER_HEIGHT := 1.8


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f (noon) — the HOUR is fixed; see this file's header for what that closes"
		% CaptureClock.pin(get_tree()))
	## Is `half_beam` invariant under the open CELL_M decision? It is
	## `floor(beam/CELL_M) * CELL_M * 0.5`, so the constant cancels whenever the
	## beam is a whole number of cells. Printed against beam/2 for every hull.
	for hull_raw in HullRegistry.catalog():
		var hull := hull_raw as Dictionary
		var g := HullRegistry.make_grid(str(hull.get("id", "")))
		print("HULL %-14s beam=%6.2f width=%3d cells  half_beam=%7.3f  beam/2=%7.3f  delta=%+.6f" % [
			str(hull.get("id", "")), float(hull.get("beam_m", 0.0)), g.width,
			g.half_beam, float(hull.get("beam_m", 0.0)) * 0.5,
			g.half_beam - float(hull.get("beam_m", 0.0)) * 0.5,
		])
	for entry_raw in PrebuiltVesselCatalog.catalog_entries():
		var entry := entry_raw as Dictionary
		await _survey(entry)
	await _shoot_trawler()
	print("PROBE DONE")
	get_tree().quit(0)


## The 28 m `fishing_trawler` preset is the OTHER shipped vessel whose hold this
## touches, and no capture rig photographs it — `trawler_render_capture` shoots a
## structure-plan fixture, not this brick preset. Same rig rules as
## `_starter_shot`: pale sky, shadows on, a 1.8 m figure on deck, counted.
##
## ── REPRODUCIBILITY, 2026-08-16 ────────────────────────────────────────────
##
## The frame this writes was recorded in STATE.md as `figure_px 3521`. Re-run
## today with no code change it prints **3947**, and the PNG differs from the
## committed one by **22.49% of its pixels**. Cause and cure are written up at
## the top of `tests/_starter_shot.gd`: `WorldClock` runs a 24-REAL-MINUTE day
## off the Unix clock and `ShipLighting` rescales every light on the vessel from
## it. Two BACK-TO-BACK runs of this rig agree exactly (0.0000%), which is why
## the drift was never seen — a fast pair cannot detect a time-of-day
## dependency. The clock is pinned at noon now and the hour is printed.
func _shoot_trawler() -> void:
	var out_dir := "res://screenshots/vessels"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var record := {}
	for entry_raw in PrebuiltVesselCatalog.catalog_entries():
		var entry := entry_raw as Dictionary
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			record = entry
			break
	if record.is_empty():
		print("SHOT ABORTED — no fishing_trawler preset")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.85, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.70, 0.78)
	env.ambient_light_energy = 0.85
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	world.add_child(sun)
	var boat := VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({
		"uid": VesselSpawn.new_vessel_uid(str(record.get("hull_id", ""))),
		"hull_id": str(record.get("hull_id", "")),
		"registration_id": str(record.get("registration_id", "fishing_vessel")),
		"name": "Day Trawler",
		"display": "Day Trawler",
		"shaft_power_kw": float(record.get("shaft_power_kw", 1871.0)),
		"brick_layout": (record.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
	}))
	if boat == null:
		print("SHOT ABORTED — the trawler preset would not spawn")
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	world.add_child(boat)
	boat.position = Vector3(0.0, -1.5 - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	var figure := _figure()
	figure.position = Vector3(
		boat.beam_m * 0.28, boat.hull_stations.deck_y + 0.12, boat.length_m * 0.10
	)
	boat.add_child(figure)
	var camera := Camera3D.new()
	camera.current = true
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.05
	camera.far = 800.0
	camera.fov = 40.0
	world.add_child(camera)
	camera.look_at_from_position(
		Vector3(22.0, 11.0, 30.0), Vector3(0.0, -1.5 + 3.0, 2.0), Vector3.UP
	)
	figure.visible = false
	await CaptureClock.settle(get_tree(), 4)
	var without := viewport.get_texture().get_image()
	figure.visible = true
	await CaptureClock.settle(get_tree(), 4)
	var image := viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(
		"%s/fishing_trawler_28m__stern_quarter.png" % out_dir
	))
	var moved := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := without.get_pixel(x, y)
			var b := image.get_pixel(x, y)
			if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
				moved += 1
	print("SHOT fishing_trawler_28m__stern_quarter figure_px=%d %s" % [
		moved, "<<< FIGURE IN NO FRAME" if moved == 0 else "",
	])


func _figure() -> Node3D:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.98, 0.42, 0.05)
	body.material_override = suit
	figure.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.90, 0.74, 0.58)
	head.material_override = skin
	figure.add_child(head)
	return figure


func _survey(entry: Dictionary) -> void:
	var pid := str(entry.get("prebuilt_id", ""))
	var hull_id := str(entry.get("hull_id", ""))
	var record := VesselSpawn.normalize_record({
		"uid": VesselSpawn.new_vessel_uid(hull_id),
		"hull_id": hull_id,
		"registration_id": str(entry.get("registration_id", "")),
		"name": pid,
		"display": pid,
		"shaft_power_kw": float(entry.get("shaft_power_kw", 500.0)),
		"brick_layout": (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
	})
	var boat := VesselSpawn.instantiate_from_record(record)
	if boat == null:
		print("%-18s %-12s SPAWN FAILED" % [pid, hull_id])
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	add_child(boat)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := HullRegistry.make_grid(hull_id)
	var holds := CatchHoldComponent.get_all_for_ship(boat)
	print("%-18s hull=%-12s half_beam=%.3f half_loa=%.3f deck_y=%.3f bow_taper=%d holds=%d" % [
		pid, hull_id, grid.half_beam, grid.half_loa, grid.deck_y,
		grid.bow_taper_cells, holds.size(),
	])
	for hold in holds:
		var aabb := _drawn_aabb(hold, boat)
		if aabb.size == Vector3.ZERO:
			print("    hold %-18s NO GEOMETRY" % hold.name)
			continue
		var mn := aabb.position
		var mx := aabb.end
		var over_port := maxf(0.0, -mn.x - grid.half_beam)
		var over_stbd := maxf(0.0, mx.x - grid.half_beam)
		var over_bow := maxf(0.0, -mn.z - grid.half_loa)
		var over_stern := maxf(0.0, mx.z - grid.half_loa)
		print("    hold %-16s pos=(%.3f, %.3f, %.3f) scale=(%.3f, %.3f, %.3f) cap=%.0f kg" % [
			hold.name, hold.position.x, hold.position.y, hold.position.z,
			hold.scale.x, hold.scale.y, hold.scale.z, hold.capacity_kg,
		])
		print("    drawn x %.3f .. %.3f   y %.3f .. %.3f   z %.3f .. %.3f" % [
			mn.x, mx.x, mn.y, mx.y, mn.z, mx.z,
		])
		print("    OVERHANG port %.3f  stbd %.3f  bow %.3f  stern %.3f" % [
			over_port, over_stbd, over_bow, over_stern,
		])
		## Widest FULL-cell span the hull actually has over the hold's z range,
		## i.e. the deck the hold has to sit on rather than the hull's midship beam.
		var narrow := _narrowest_half_beam(grid, mn.z, mx.z)
		print("    narrowest deck half-beam over the hold's z span: %.3f  → overhang %.3f" % [
			narrow, maxf(maxf(0.0, -mn.x - narrow), maxf(0.0, mx.x - narrow)),
		])
		## Is the hatch inside the deckhouse? Query the walk colliders directly
		## above the hatch centre with a standing player capsule.
		_hatch_report(boat, hold, grid, aabb)
		_footprint_report(entry, grid, aabb)
	remove_child(boat)
	boat.free()
	await get_tree().process_frame


func _narrowest_half_beam(grid: DeckGrid, z0: float, z1: float) -> float:
	var narrow := 1e9
	var found := false
	for iz in range(grid.length):
		var zc := -grid.half_loa + (float(iz) + 0.5) * DeckGrid.CELL_M
		if zc < z0 - DeckGrid.CELL_M or zc > z1 + DeckGrid.CELL_M:
			continue
		var lo := -1
		var hi := -1
		for ix in range(grid.width):
			if grid.cell_shape(ix, iz) == DeckGrid.CellShape.FULL:
				if lo < 0:
					lo = ix
				hi = ix
		if lo < 0:
			narrow = 0.0
			found = true
			continue
		var left := -grid.half_beam + float(lo) * DeckGrid.CELL_M
		var right := -grid.half_beam + float(hi + 1) * DeckGrid.CELL_M
		narrow = minf(narrow, minf(absf(left), absf(right)))
		found = true
	return narrow if found else grid.half_beam


func _drawn_aabb(hold: CatchHoldComponent, boat: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in hold.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var local := mi.get_aabb()
		var xf := boat.global_transform.affine_inverse() * mi.global_transform
		for i in range(8):
			var corner := xf * local.get_endpoint(i)
			if first:
				out = AABB(corner, Vector3.ZERO)
				first = false
			else:
				out = out.expand(corner)
	return out


func _hatch_report(
	boat: BoatBody, hold: CatchHoldComponent, grid: DeckGrid, aabb: AABB
) -> void:
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk == null:
		print("    hatch: no WalkDeck")
		return
	var space := walk.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = PLAYER_HEIGHT
	var blocked := 0
	var samples := 0
	## A ring 0.55 m outside the drawn hatch — where a deckhand stands to work it.
	var reach := 0.55
	var ring := [
		Vector3(aabb.position.x - reach, 0.0, (aabb.position.z + aabb.end.z) * 0.5),
		Vector3(aabb.end.x + reach, 0.0, (aabb.position.z + aabb.end.z) * 0.5),
		Vector3((aabb.position.x + aabb.end.x) * 0.5, 0.0, aabb.position.z - reach),
		Vector3((aabb.position.x + aabb.end.x) * 0.5, 0.0, aabb.end.z + reach),
	]
	for local in ring:
		samples += 1
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = capsule
		params.transform = Transform3D(
			Basis.IDENTITY,
			boat.to_global(Vector3(local.x, grid.deck_y + 0.25 + PLAYER_HEIGHT * 0.5, local.z))
		)
		params.collision_mask = BoatBody.LAYER_BOAT_WALK
		var hits := space.intersect_shape(params, 4)
		var names := PackedStringArray()
		for h in hits:
			names.append(str((h.get("collider") as Node).name if h.get("collider") != null else "?"))
		if not hits.is_empty():
			blocked += 1
			print("        blocked at %v by %s" % [local, " ".join(names)])
		## And the cell must be deck at all.
		var cell := grid.local_to_cell(Vector3(local.x, grid.deck_y, local.z))
		if grid.cell_shape(cell.x, cell.z) != DeckGrid.CellShape.FULL:
			print("        no deck under %v (cell %v)" % [local, cell])
	print("    hatch approach: %d of %d standing positions around the hatch are inside structure"
		% [blocked, samples])


## Which built bricks does the hold's drawn footprint stand inside?
func _footprint_report(entry: Dictionary, grid: DeckGrid, aabb: AABB) -> void:
	var layout := BrickLayout.from_dict((entry.get("prebuilt_layout", {}) as Dictionary))
	var counts := {}
	for item_raw in layout.iter_primary_cells():
		var item := item_raw as Dictionary
		var cell: Vector3i = item["cell"]
		var brick_id := str(item["brick_id"])
		var fp := BrickCatalog.footprint_of(brick_id)
		var yaw_steps := int(round(float(int(item.get("yaw", 0))) / 90.0)) % 4
		for c in grid.footprint_cells(cell, fp, yaw_steps):
			var p := grid.cell_center_local(c)
			if p.x < aabb.position.x or p.x > aabb.end.x:
				continue
			if p.z < aabb.position.z or p.z > aabb.end.z:
				continue
			counts[brick_id] = int(counts.get(brick_id, 0)) + 1
	var parts := PackedStringArray()
	for k in counts:
		parts.append("%s=%d" % [k, counts[k]])
	print("    brick cells standing inside the hold's drawn footprint: %s"
		% ("none" if parts.is_empty() else " ".join(parts)))
