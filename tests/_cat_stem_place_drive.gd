extends Node3D

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_cat_stem_place_drive.tscn
##
## CAN A PLAYER PUT A DECKHOUSE WALL ON A CELL THE LOFT CALLS WATER?
##
## Drives the real app: instantiate `structure_studio.tscn`, pick
## `hull_45x16_cat` off the REAL hull dropdown (the popup's own
## `index_pressed`), pick the PIECE tool off the REAL tool button, then push a
## real `InputEventMouseButton` at the screen point that projects onto the
## forward-port grid node. Nothing here calls `_place_piece_at` directly.
##
## Then asks the three things that could still refuse it:
##   1. `PlanOutfit.compliance` — the studio's own on-hull fence
##   2. `StructureBaker` — does geometry come out there
##   3. `DeckFitout.apply_any` — the path a SPAWNED vessel takes
##
## Writes a studio screenshot so the offer can be looked at, not just counted.
##
## ⚠ THESE TWO FRAMES ARE NOT REPRODUCIBLE AND MUST NOT BE DIFFED. This rig does
## not pin `WorldClock` and grabs after `process_frame` rather than
## `frame_post_draw` — CONVENTIONS §3's two rules for a byte-stable rig, both
## deliberately skipped because the subject here is a UI state, not a silhouette.
## `tests/_cat_stem_sea_shot.gd` is the one that pins the clock.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const OUT_DIR := "res://screenshots/studio"

var _studio: Node
var _shots := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	for i in range(4):
		await get_tree().process_frame

	_hide_hud()
	await _pick_hull("hull_45x16_cat")
	await _pick_piece_tool()

	## The three offending rows are iz 0..2 (z = -22.25, -21.75, -21.25). Take
	## the outermost offered cell of the worst row: ix = 0 (port) at iz = 0.
	var targets := [Vector3i(0, 0, 0), Vector3i(31, 0, 0), Vector3i(0, 0, 1)]
	print("\n=== 1. DRIVING A REAL CLICK ONTO THE STEM CORNER NODE ===")
	for cell in targets:
		await _click_node(cell)

	var plan: StructurePlan = _studio.get("_plan")
	print("\n  plan now holds %d entities (%d pieces)"
		% [plan.entity_count(), plan.pieces.size()])
	for placement in plan.pieces:
		print("    piece %s at cell %s" % [placement.get("piece"), placement.get("cell")])

	print("\n=== 2. DOES ANYTHING DOWNSTREAM REFUSE IT? ===")
	_ask_the_fence(plan)

	print("\n=== 3. WHAT THE STUDIO PANEL SAYS ===")
	var entities_label: Label = _studio.get("_entities_label")
	print("  ENTITIES LABEL: %s" % entities_label.text.replace("\n", " | "))
	print("  STATUS:         %s" % str(_studio.get("_status")))
	print("  _off_hull:      %d rows" % (_studio.get("_off_hull") as Array).size())

	print("\n=== 4. WHERE THE BAKED GEOMETRY LANDED ===")
	_measure_bake(plan)

	await _shoot("studio_cat_stem__plan", Vector3(0.0, 3.0, 0.0), 0.0, 1.45, 62.0)
	await _shoot("studio_cat_stem__bow_quarter", Vector3(0.0, 3.0, -16.0), 3.85, 0.22, 30.0)
	print("\nDRIVE DONE — %d frames written to %s" % [_shots, OUT_DIR])
	get_tree().quit(0)


# ── driving the real controls ────────────────────────────────────────────────

func _pick_hull(hull_id: String) -> void:
	var option: OptionButton = _studio.get("_hull_option")
	var index := -1
	for i in option.item_count:
		if str(option.get_item_text(i)) == hull_id:
			index = i
			break
	if index < 0:
		print("  the hull dropdown does not offer %s" % hull_id)
		return
	option.get_popup().index_pressed.emit(index)
	for i in range(4):
		await get_tree().process_frame
	print("  hull dropdown -> %s (studio _hull_id = %s, grid %d x %d)" % [
		hull_id, str(_studio.get("_hull_id")),
		int(_studio.get("_grid_width")), int(_studio.get("_grid_length")),
	])
	## Hold the host hull still — a BoatBody's LOD revokes freeze one second in.
	for node in _descendants(_studio):
		if node is RigidBody3D and "hull_size" in node:
			CaptureSubject.hold_still(node)


func _pick_piece_tool() -> void:
	var buttons: Dictionary = _studio.get("_tool_buttons")
	for key in buttons.keys():
		var button := buttons[key] as Button
		if button == null:
			continue
		if str(button.text).to_upper().contains("PIECE"):
			button.pressed.emit()
			await get_tree().process_frame
			print("  tool button \"%s\" pressed -> tool=%d piece=\"%s\""
				% [button.text, int(_studio.get("_tool")), str(_studio.get("_piece_id"))])
			return
	print("  no PIECE tool button found; buttons = %s" % [buttons.keys()])


## Aim the camera at the node, project it to a screen point, and push a real
## left click there — so `_mouse_to_node` does the cell arithmetic, not this file.
func _click_node(cell: Vector3i) -> void:
	var offset: Vector3 = _studio.get("_plan_offset")
	var base: float = _studio.get("_active_base")
	var node_snap := 0.5
	var world := offset + Vector3(float(cell.x) * node_snap, base, float(cell.z) * node_snap)

	## Orbit the studio's own camera onto the node, exactly as the app's
	## `_process` computes it, then let a frame pass so the ghost updates.
	_studio.set("_cam_focus", world)
	_studio.set("_cam_yaw", 0.7)
	_studio.set("_cam_pitch", 0.55)
	_studio.set("_cam_distance", 24.0)
	for i in range(3):
		await get_tree().process_frame

	var camera: Camera3D = _studio.get("_camera")
	var screen := camera.unproject_position(world)
	var before := (_studio.get("_plan") as StructurePlan).pieces.size()

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen
	down.global_position = screen
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen
	up.global_position = screen
	get_viewport().push_input(up, true)
	for i in range(3):
		await get_tree().process_frame

	var after := (_studio.get("_plan") as StructurePlan).pieces.size()
	print("  click at screen %v (world %v, cell %v): pieces %d -> %d   status: %s"
		% [screen.round(), world.snappedf(0.01), cell, before, after, str(_studio.get("_status"))])


# ── what could still refuse it ───────────────────────────────────────────────

func _ask_the_fence(plan: StructurePlan) -> void:
	var grid := HullRegistry.make_grid("hull_45x16_cat")
	var off := PlanOutfit.off_hull_entities(plan, grid)
	print("  PlanOutfit.off_hull_entities  -> %d refused" % off.size())
	for row in off:
		print("      %s" % str((row as Dictionary)["message"]))
	var report: Dictionary = PlanOutfit.compliance(plan, "hull_45x16_cat", "general_vessel", grid)
	var errors: Array = report.get("errors", [])
	print("  PlanOutfit.compliance errors  -> %d" % errors.size())
	for e in errors:
		print("      %s" % str(e))
	var kept := PlanOutfit.on_hull_plan(plan, grid)
	print("  on_hull_plan keeps %d of %d entities" % [kept.entity_count(), plan.entity_count()])


func _measure_bake(plan: StructurePlan) -> void:
	var grid := HullRegistry.make_grid("hull_45x16_cat")
	var offset := Vector3(-grid.half_beam, 0.0, -grid.half_loa)
	var resolved := PieceKit.resolve_document(plan.to_dict())
	var built := StructureBaker.bake(StructurePlan.from_dict(resolved["doc"] as Dictionary), offset)
	if built == null:
		print("  bake returned null")
		return
	add_child(built)
	var meshes := 0
	var tris := 0
	var bounds := AABB()
	var have := false
	for node in _descendants(built):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		meshes += 1
		for s in range(mi.mesh.get_surface_count()):
			tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
		var a := mi.global_transform * mi.mesh.get_aabb()
		if have:
			bounds = bounds.merge(a)
		else:
			bounds = a
			have = true
	var boxes: Array = StructureBaker.collect_colliders(
		StructurePlan.from_dict(resolved["doc"] as Dictionary), offset
	)
	print("  baked %d mesh instances, %d triangles, %d collider boxes"
		% [meshes, tris, boxes.size()])
	print("  baked geometry AABB pos %v size %v"
		% [bounds.position.snappedf(0.001), bounds.size.snappedf(0.001)])
	print("  the loft's half-breadth at that z is %.3f m; this geometry reaches |x| = %.3f"
		% [_loft_half_breadth("hull_45x16_cat", bounds.position.z + bounds.size.z * 0.5),
			maxf(absf(bounds.position.x), absf(bounds.position.x + bounds.size.x))])
	built.queue_free()


func _loft_half_breadth(hull_id: String, z: float) -> float:
	var boat := HullRegistry.build_hull(hull_id)
	var st: HullStations = boat.hull_stations
	var list: Array = st.stations
	var i := 0
	while i < list.size() - 2 and float(list[i + 1]["z"]) < z:
		i += 1
	var z0 := float(list[i]["z"])
	var z1 := float(list[i + 1]["z"])
	var t := clampf((z - z0) / maxf(z1 - z0, 1e-6), 0.0, 1.0)
	var a := list[i]["section"] as Array
	var b := list[i + 1]["section"] as Array
	var best := 0.0
	for j in range(mini(a.size(), b.size())):
		best = maxf(best, lerpf((a[j] as Vector2).y, (b[j] as Vector2).y, t))
	boat.free()
	return best


# ── frames ───────────────────────────────────────────────────────────────────

func _shoot(stem: String, focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	_studio.set("_cam_focus", focus)
	_studio.set("_cam_yaw", yaw)
	_studio.set("_cam_pitch", pitch)
	_studio.set("_cam_distance", distance)
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, stem]))
	_shots += 1
	print("  wrote %s/%s.png" % [OUT_DIR, stem])


func _hide_hud() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas(child)


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas(child)


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out
