extends Node3D

## Runnable visual showcase for the large-vessel staged fitout pipeline.
## Space: advance · L: load JSON · R: restart · X: cutaway · A: auto/manual.
##
## ── Why this lives in scenes/showcases/ and not in tests/ ───────────────────
## Moved 2026-08-14. It sat in `tests/`, so the gate globbed it as a lane-B unit
## and burned the full 240 s timeout on it EVERY run — reported as `TIMEOUT`,
## which reads like a hang or a slow test and is neither.
##
## It never called `quit()` because it is not a test and has nothing to quit
## for: it makes no assertion, records no check, and prints no verdict. It is an
## interactive app — an orbiting camera in `_process`, a HUD with buttons, a
## `FileDialog`, and `_unhandled_input` waiting on SPACE/L/R/X/A. There is no
## outcome for it to report, so no amount of adding `quit()` would have turned
## it into a unit; it would only have made the gate green on a unit that checks
## nothing (REALITY.md §4).
##
## Removing it from `tests/` therefore costs ZERO coverage — grep this file for
## `check`, `assert` or a verdict line and there is nothing to lose — and buys
## back 240 s of every gate run. AGENTS.md already classified it as a demo
## ("Current demos"), named to the `<feature>_visual_demo.tscn` convention, and
## already noted it as the only one outside `scenes/showcases/`. It is now where
## its own naming convention says it belongs.
##
## The gate cannot pick it up here: lane A is `tests/*.gd`, lane B is
## `tests/*.tscn`, and lane C requires either a self-check marker or a script
## that speaks the verdict language. This file has neither. If this demo ever
## grows a self-check, it joins lane C by declaring one — see tools/gate.sh for
## the marker's exact spelling, which is deliberately NOT quoted here: the gate
## greps every .gd in the tree for that literal token and a bare mention of it
## in prose is a hard FAIL(selfcheck), which is how this comment first read.

const HULL_ID := "hull_120x28"
const SHELL_CLASSIFIER := preload("res://scripts/ship/brick_shell_classifier.gd")
const EXTERIOR_COLOR := Color(0.08, 0.58, 0.92)
const INTERIOR_COLOR := Color(0.96, 0.38, 0.10)
const READY_COLOR := Color(0.18, 0.85, 0.45)
const WAIT_COLOR := Color(0.22, 0.25, 0.30)

var _boat: BoatBody
var _layout: BrickLayout
var _camera: Camera3D
var _stats: Label
var _instructions: Label
var _log: RichTextLabel
var _file_dialog: FileDialog
var _stage_lights: Array[ColorRect] = []
var _generation := 0
var _auto_mode := true
var _construction_started := false
var _shell_hidden := false
var _orbit_angle := deg_to_rad(35.0)
var _stats_elapsed := 0.0
var _started_usec := 0
var _current_hull_id := HULL_ID
var _registration_id := "general_vessel"
var _source_name := "Generated 4,160-part demo"
var _source_layout_dict: Dictionary = {}
var _primary_count := 0
var _occupied_count := 0


func _ready() -> void:
	_build_world()
	_build_hud()
	_source_layout_dict = _make_large_layout().to_dict()
	_spawn_demo()


func _process(delta: float) -> void:
	_orbit_angle += delta * 0.035
	if _camera != null:
		var radius := maxf(45.0, _boat.length_m * 0.73 if _boat != null else 88.0)
		var focus_y := maxf(6.0, _boat.depth_m if _boat != null else 10.0)
		_camera.position = Vector3(
			cos(_orbit_angle) * radius,
			maxf(18.0, radius * 0.34),
			sin(_orbit_angle) * radius,
		)
		_camera.look_at(Vector3(0.0, focus_y, 0.0), Vector3.UP)
	_stats_elapsed += delta
	if _stats_elapsed >= 0.15:
		_stats_elapsed = 0.0
		_refresh_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				if not _construction_started:
					_start_exterior()
				elif _boat != null and DeckFitout.readiness_of(_boat) >= DeckFitout.READINESS_EXTERIOR:
					_promote_full()
			KEY_R:
				_spawn_demo()
			KEY_L:
				_open_file_dialog()
			KEY_X:
				_toggle_shell_cutaway()
			KEY_A:
				_auto_mode = not _auto_mode
				_log_line("Auto mode %s" % ("ON" if _auto_mode else "OFF"))
				_refresh_instructions()


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.045, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.72)
	environment.ambient_light_energy = 0.9
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 58.0
	add_child(_camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(520.0, 360.0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "STAGED VESSEL CONSTRUCTION — VISUAL DEMO"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 14)
	box.add_child(_stats)

	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	box.add_child(file_row)
	var load_button := Button.new()
	load_button.text = "Load vessel JSON…"
	load_button.pressed.connect(_open_file_dialog)
	file_row.add_child(load_button)
	var generated_button := Button.new()
	generated_button.text = "Load generated demo"
	generated_button.pressed.connect(_load_generated_demo)
	file_row.add_child(generated_button)

	var stage_row := HBoxContainer.new()
	stage_row.add_theme_constant_override("separation", 10)
	box.add_child(stage_row)
	for stage_name in ["HULL", "EXTERIOR", "FULL VISUAL", "INTERACTIVE"]:
		var stage_box := VBoxContainer.new()
		var light := ColorRect.new()
		light.custom_minimum_size = Vector2(112.0, 18.0)
		light.color = WAIT_COLOR
		stage_box.add_child(light)
		var caption := Label.new()
		caption.text = stage_name
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 11)
		stage_box.add_child(caption)
		stage_row.add_child(stage_box)
		_stage_lights.append(light)

	_instructions = Label.new()
	_instructions.add_theme_font_size_override("font_size", 13)
	box.add_child(_instructions)
	_refresh_instructions()

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.custom_minimum_size = Vector2(490.0, 170.0)
	_log.scroll_active = true
	_log.scroll_following = true
	box.add_child(_log)

	var legend := Label.new()
	legend.text = "Overlay: CYAN = exterior shell   ORANGE = enclosed/interior"
	legend.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))
	box.add_child(legend)

	_file_dialog = FileDialog.new()
	_file_dialog.title = "Load vessel brick-layout JSON"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.json ; Vessel JSON"])
	_file_dialog.current_dir = ProjectSettings.globalize_path(
		"res://resources/data/vessels/prebuilt"
	)
	_file_dialog.file_selected.connect(_load_vessel_file)
	layer.add_child(_file_dialog)


func _open_file_dialog() -> void:
	if _file_dialog != null:
		_file_dialog.popup_centered_ratio(0.78)


func _load_generated_demo() -> void:
	_current_hull_id = HULL_ID
	_registration_id = "general_vessel"
	_source_name = "Generated 4,160-part demo"
	_source_layout_dict = _make_large_layout().to_dict()
	_spawn_demo()


func _load_vessel_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_log_line("LOAD ERROR: could not open " + path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_log_line("LOAD ERROR: JSON root must be an object.")
		return
	var record := parsed as Dictionary
	var layout_dict: Dictionary = {}
	if record.get("brick_layout", null) is Dictionary:
		layout_dict = (record.get("brick_layout", {}) as Dictionary).duplicate(true)
	elif record.get("prebuilt_layout", null) is Dictionary:
		layout_dict = (record.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	elif record.get("cells", null) is Dictionary:
		layout_dict = record.duplicate(true)
	if layout_dict.is_empty():
		_log_line("LOAD ERROR: expected brick_layout, prebuilt_layout, or raw cells.")
		return
	var hull_id := str(record.get("hull_id", layout_dict.get("hull_id", ""))).strip_edges()
	hull_id = HullRegistry.resolve_network_hull_id(hull_id)
	if not HullCatalog.has_id(hull_id) and HullRegistry.scene_path_for(hull_id).is_empty():
		_log_line("LOAD ERROR: unknown hull_id '%s'." % hull_id)
		return
	layout_dict["hull_id"] = hull_id
	_current_hull_id = hull_id
	_registration_id = str(record.get("registration_id", "general_vessel")).strip_edges()
	if _registration_id.is_empty():
		_registration_id = "general_vessel"
	_source_name = str(record.get("name", record.get("display", path.get_file())))
	_source_layout_dict = layout_dict
	_spawn_demo()


func _spawn_demo() -> void:
	_generation += 1
	_construction_started = false
	_shell_hidden = false
	if _boat != null and is_instance_valid(_boat):
		_boat.queue_free()
	_boat = VesselSpawn.instantiate(
		_current_hull_id,
		{"hull_id": _current_hull_id, "cells": {}},
		_registration_id,
	)
	if _boat == null:
		_log_line("Could not instantiate hull: " + _current_hull_id)
		return
	_boat.name = "StagedVesselDemo"
	_boat.set_meta("remote_replica", true)
	_boat.freeze = true
	_boat.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	add_child(_boat)
	_layout = BrickLayout.from_dict(_source_layout_dict)
	_layout.hull_id = _current_hull_id
	_paint_stage_overlay(_layout)
	_primary_count = _layout.iter_primary_cells().size()
	_occupied_count = _layout.count()
	_started_usec = Time.get_ticks_usec()
	_log.clear()
	_set_stage_light(0)
	_log_line(
		"Hull ready: %s [%s]. Loaded %d primary parts (%d occupied cells)."
		% [
			_source_name,
			_current_hull_id,
			_primary_count,
			_occupied_count,
		]
	)
	_refresh_stats()
	var run_generation := _generation
	if _auto_mode:
		await get_tree().create_timer(1.5).timeout
		if run_generation == _generation:
			_start_exterior()


func _start_exterior() -> void:
	if _construction_started or _boat == null:
		return
	_construction_started = true
	_started_usec = Time.get_ticks_usec()
	_log_line("Applying large layout: exterior shell is first priority.")
	## Force staged application in this showcase so small custom boats demonstrate
	## the same shell/interior sequence as large production vessels.
	DeckFitout.apply_staged(
		_boat,
		_layout,
		HullRegistry.make_grid(_current_hull_id),
		_registration_id,
	)
	var job := _boat.get_node_or_null(DeckFitout.FITOUT_JOB)
	if job != null and job.has_signal("readiness_changed"):
		job.connect("readiness_changed", _on_readiness_changed)


func _promote_full() -> void:
	if _boat == null or DeckFitout.readiness_of(_boat) < DeckFitout.READINESS_EXTERIOR:
		return
	_log_line("Simulated range <= 50 m: requesting interior and gameplay detail.")
	DeckFitout.request_full_detail(_boat)


func _on_readiness_changed(readiness: int) -> void:
	_set_stage_light(readiness)
	var elapsed_ms := float(Time.get_ticks_usec() - _started_usec) / 1000.0
	match readiness:
		DeckFitout.READINESS_EXTERIOR:
			_log_line("EXTERIOR ready at %.1f ms." % elapsed_ms)
			var run_generation := _generation
			if _auto_mode:
				await get_tree().create_timer(2.0).timeout
				if run_generation == _generation:
					_promote_full()
		DeckFitout.READINESS_FULL_VISUAL:
			_log_line("FULL VISUAL ready at %.1f ms; colliders/systems continue." % elapsed_ms)
		DeckFitout.READINESS_INTERACTIVE:
			_log_line("INTERACTIVE ready at %.1f ms." % elapsed_ms)
	_refresh_stats()


func _make_large_layout() -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	var grid := HullRegistry.make_grid(HULL_ID)
	var x0 := 4
	var x1 := 23
	## `z0` used to be a bare 20, and hull_120x28's bow taper is 28 cells deep, so
	## the whole forward end of this box stood on cells the deck does not have —
	## drawn anyway, because the skin bake never asked. `set_brick` refuses them
	## now, so the box starts aft of the taper instead of losing its bow rows.
	var z0 := maxi(20, grid.bow_taper_cells)
	var z1 := 99
	var top_y := 10
	var refused := 0
	for y in range(top_y):
		for x in range(x0, x1 + 1):
			var end_id := "block_window" if y > 0 and x % 3 != 0 else "block"
			refused += 0 if layout.set_brick(grid, Vector3i(x, y, z0), end_id, 0) else 1
			refused += 0 if layout.set_brick(grid, Vector3i(x, y, z1), end_id, 180) else 1
		for z in range(z0 + 1, z1):
			var side_id := "block_window" if y > 0 and z % 3 != 0 else "block"
			refused += 0 if layout.set_brick(grid, Vector3i(x0, y, z), side_id, 90) else 1
			refused += 0 if layout.set_brick(grid, Vector3i(x1, y, z), side_id, 270) else 1
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			refused += 0 if layout.set_brick(grid, Vector3i(x, top_y, z), "roof_flat", 0) else 1
	## Enclosed corridor wall: deliberately hidden until full-detail promotion.
	var corridor_x := int((x0 + x1) / 2)
	for y in range(top_y):
		for z in range(z0 + 10, z1 - 9):
			refused += 0 if layout.set_brick(grid, Vector3i(corridor_x, y, z), "block", 0) else 1
	if refused > 0:
		push_warning(
			"staged_vessel_visual_demo: %d generated cells are off the %d x %d deck"
			% [refused, grid.width, grid.length]
		)
	return layout


func _paint_stage_overlay(layout: BrickLayout) -> void:
	var classified: Dictionary = SHELL_CLASSIFIER.classify(
		layout, HullRegistry.make_grid(_current_hull_id)
	)
	var exterior_keys: Dictionary = classified.get("exterior_keys", {})
	for item_raw in layout.iter_primary_cells():
		var item := item_raw as Dictionary
		var cell: Vector3i = item.get("cell", Vector3i.ZERO)
		var key := BrickLayout.cell_key(cell)
		var entry := (layout.cells.get(key, {}) as Dictionary).duplicate(true)
		var color := EXTERIOR_COLOR if exterior_keys.has(key) else INTERIOR_COLOR
		entry["color"] = BrickLayout.color_to_array(color)
		layout.cells[key] = entry


func _toggle_shell_cutaway() -> void:
	_shell_hidden = not _shell_hidden
	var root := _boat.get_node_or_null(DeckFitout.FITOUT_ROOT) if _boat != null else null
	if root != null:
		for child in root.get_children():
			if child is Node3D and str(child.get_meta("fitout_stage", "")) == "exterior":
				(child as Node3D).visible = not _shell_hidden
	_log_line("Exterior cutaway %s." % ("ON" if _shell_hidden else "OFF"))


func _refresh_stats() -> void:
	if _stats == null or _layout == null:
		return
	var exterior_n := 0
	var interior_n := 0
	var root := _boat.get_node_or_null(DeckFitout.FITOUT_ROOT) if _boat != null else null
	if root != null:
		for child in root.get_children():
			if not child is Node3D:
				continue
			match str(child.get_meta("fitout_stage", "")):
				"exterior":
					exterior_n += 1
				"interior":
					interior_n += 1
	var readiness := DeckFitout.readiness_of(_boat) if _boat != null else 0
	var worst_ms := (
		float(_boat.get_meta("fitout_max_frame_usec", 0)) / 1000.0
		if _boat != null else 0.0
	)
	_stats.text = (
		"Primary parts: %d   Occupied cells: %d\n"
		+ "Rendered exterior: %d   Rendered interior: %d\n"
		+ "Readiness: %s   Worst construction frame: %.1f ms"
	) % [
		_primary_count,
		_occupied_count,
		exterior_n,
		interior_n,
		_readiness_name(readiness),
		worst_ms,
	]


func _set_stage_light(readiness: int) -> void:
	for i in range(_stage_lights.size()):
		_stage_lights[i].color = READY_COLOR if i <= readiness else WAIT_COLOR


func _refresh_instructions() -> void:
	_instructions.text = (
		"SPACE advance   L load JSON   R restart   X exterior cutaway   A auto/manual\n"
		+ "Mode: %s   Camera: slow close-range orbit"
	) % ("AUTO" if _auto_mode else "MANUAL")


func _log_line(message: String) -> void:
	if _log == null:
		return
	var elapsed := float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	_log.append_text("[color=#9fb3c8]%6.2fs[/color]  %s\n" % [elapsed, message])
	print("[StagedVesselDemo] ", message)


func _readiness_name(value: int) -> String:
	match value:
		DeckFitout.READINESS_EXTERIOR:
			return "EXTERIOR"
		DeckFitout.READINESS_FULL_VISUAL:
			return "FULL VISUAL"
		DeckFitout.READINESS_INTERACTIVE:
			return "INTERACTIVE"
	return "HULL"
