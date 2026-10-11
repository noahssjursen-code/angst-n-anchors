class_name PerfShowcase
extends Node3D

## F6 stream-tier lab — one asset at a time.
## Distance slider simulates stream range (not camera). RMB orbit / wheel zoom to inspect.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const TERRAIN_STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")
const CONTAINER_MODEL := "res://resources/data/models/cargo/container_cube.json"
const FOGHORN_MODEL := "res://resources/data/models/buildings/foghorn_building.json"
const LIGHTHOUSE_MODEL := "res://resources/data/models/buildings/lighthouse_building.json"
const PROVISION_CRANE_SCRIPT := preload("res://scripts/port/provision_crane.gd")
const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")

const TERRAIN_LOD_STEPS: Array[float] = [40.0, 40.0, 100.0, 200.0, 500.0, 500.0]
const MIN_DISTANCE_M := 50.0
const MAX_DISTANCE_M := 20000.0
const MODEL_SETTLE_KEYS := ["provision_crane", "bulk_crane"]

const SPECIMENS: Array[Dictionary] = [
	{"id": "terrain_chunk", "title": "Terrain chunk"},
	{"id": "provision_crane", "title": "Provision crane"},
	{"id": "bulk_crane", "title": "Bulk crane"},
	{"id": "cargo_pad", "title": "Cargo yard pad"},
	{"id": "land_decor", "title": "Village house (decor)"},
	{"id": "foghorn", "title": "Foghorn building"},
	{"id": "lighthouse", "title": "Lighthouse"},
	{"id": "model_cache", "title": "Container model"},
	{"id": "container_node", "title": "Container unit"},
]

@export_range(50.0, 20000.0, 50.0) var simulated_distance_m := 120.0
@export var orbit_yaw_deg := 35.0
@export var orbit_pitch_deg := -22.0
@export var orbit_distance_m := 55.0

var _camera: Camera3D
var _sun: DirectionalLight3D
var _hud: CanvasLayer
var _controls: Label
var _stats_label: Label
var _report_edit: TextEdit
var _autoplay_btn: Button
var _clear_btn: Button
var _copy_btn: Button
var _report_text := ""
var _slider: HSlider
var _slot: Node3D
var _specimen_index := 0
var _world_layout: WorldLayout
var _terrain_land_coord := Vector2i(2, -3)
var _rebuilding := false
var _rebuild_queued := false
var _autoplay_running := false
var _last_stats: Dictionary = {}
var _last_build_ms := -1.0
var _prior_build_ms := -1.0
var _prev_tier := -1
var _lod_mode := ""
var _orbiting := false
var _orbit_yaw := 35.0
var _orbit_pitch := -22.0
var _focus := Vector3(0.0, 6.0, 0.0)
var _distance_rebuild_pending := false
var _bench_rows: Array[Dictionary] = []


func _ready() -> void:
	IMPOSTOR_CACHE.clear()
	_world_layout = WORLD_LAYOUT_GENERATOR.generate(424242)
	_terrain_land_coord = _find_land_chunk_coord()
	_ensure_environment()
	_ensure_camera()
	_ensure_sun()
	_ensure_hud()
	_build_stage()
	call_deferred("_rebuild_async")


func _input(event: InputEvent) -> void:
	if _autoplay_running:
		return
	# Tab must work even while rebuilding / when a Control would steal focus.
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_TAB:
			_cycle_specimen(1)
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_R:
			if key.shift_pressed:
				_clear_all_caches()
			_request_rebuild()
			get_viewport().set_input_as_handled()
			return


func _unhandled_input(event: InputEvent) -> void:
	if _autoplay_running:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance_m = clampf(orbit_distance_m * 0.9, 8.0, 250.0)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance_m = clampf(orbit_distance_m * 1.1, 8.0, 250.0)
			_update_camera()
		return
	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * 0.25
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.25, -85.0, 80.0)
		_update_camera()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_BRACKETLEFT:
				_set_simulated_distance(simulated_distance_m * 0.85)
			KEY_BRACKETRIGHT:
				_set_simulated_distance(simulated_distance_m * 1.15)
			KEY_HOME:
				_orbit_yaw = orbit_yaw_deg
				_orbit_pitch = orbit_pitch_deg
				orbit_distance_m = 55.0
				_update_camera()


func _cycle_specimen(step: int) -> void:
	_specimen_index = (_specimen_index + step) % SPECIMENS.size()
	if _specimen_index < 0:
		_specimen_index += SPECIMENS.size()
	_last_build_ms = -1.0
	_prior_build_ms = -1.0
	_prev_tier = -1
	_refresh_hud()
	_request_rebuild()


func _set_simulated_distance(value: float) -> void:
	simulated_distance_m = clampf(value, MIN_DISTANCE_M, MAX_DISTANCE_M)
	if _slider != null and not is_equal_approx(_slider.value, simulated_distance_m):
		_slider.set_value_no_signal(simulated_distance_m)
	_refresh_hud()
	_request_rebuild()


func _request_rebuild() -> void:
	if _autoplay_running:
		return
	if _rebuilding:
		_rebuild_queued = true
		return
	call_deferred("_rebuild_async")


func _clear_all_caches() -> void:
	IMPOSTOR_CACHE.clear()
	BuildingCache.clear()
	ModelCache.clear()
	LandDecorCache.clear()
	MeshBuilder.clear_material_cache()


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.68, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


func _ensure_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.current = true
	_orbit_yaw = orbit_yaw_deg
	_orbit_pitch = orbit_pitch_deg
	add_child(_camera)
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		orbit_distance_m * cos(pitch) * sin(yaw),
		orbit_distance_m * sin(pitch) * -1.0,
		orbit_distance_m * cos(pitch) * cos(yaw),
	)
	_camera.position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


func _ensure_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_energy = 1.15
	_sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	_sun.shadow_enabled = true
	add_child(_sun)


func _ensure_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	_hud.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_controls = Label.new()
	_controls.add_theme_font_size_override("font_size", 14)
	_controls.add_theme_color_override("font_color", Color(0.92, 0.96, 0.88))
	box.add_child(_controls)
	var dist_row := HBoxContainer.new()
	box.add_child(dist_row)
	var dist_lbl := Label.new()
	dist_lbl.text = "Simulated stream distance (m)"
	dist_lbl.add_theme_font_size_override("font_size", 13)
	dist_row.add_child(dist_lbl)
	_slider = HSlider.new()
	_slider.min_value = MIN_DISTANCE_M
	_slider.max_value = MAX_DISTANCE_M
	_slider.step = 25.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value = simulated_distance_m
	_slider.value_changed.connect(_on_distance_dragged)
	_slider.drag_ended.connect(_on_distance_drag_ended)
	dist_row.add_child(_slider)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	box.add_child(btn_row)
	_clear_btn = Button.new()
	_clear_btn.text = "Clear caches"
	_clear_btn.focus_mode = Control.FOCUS_NONE
	_clear_btn.pressed.connect(_on_clear_caches_pressed)
	btn_row.add_child(_clear_btn)
	_autoplay_btn = Button.new()
	_autoplay_btn.text = "Clear + autoplay mesh vs impostor"
	_autoplay_btn.focus_mode = Control.FOCUS_NONE
	_autoplay_btn.pressed.connect(_on_autoplay_pressed)
	btn_row.add_child(_autoplay_btn)
	_copy_btn = Button.new()
	_copy_btn.text = "Copy report"
	_copy_btn.focus_mode = Control.FOCUS_NONE
	_copy_btn.pressed.connect(_on_copy_report_pressed)
	btn_row.add_child(_copy_btn)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", Color(0.78, 0.92, 0.98))
	box.add_child(_stats_label)
	# TextEdit (not Label-in-Scroll) — Label+autowrap inside ScrollContainer collapses to 1-char width.
	_report_edit = TextEdit.new()
	_report_edit.custom_minimum_size = Vector2(720, 240)
	_report_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_edit.editable = false
	_report_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_report_edit.scroll_fit_content_height = false
	_report_edit.context_menu_enabled = true
	_report_edit.add_theme_font_size_override("font_size", 12)
	_report_edit.placeholder_text = "Bench report appears here after autoplay. Use Copy report or Ctrl+A / Ctrl+C in this box."
	_set_report("Bench report appears here after autoplay.\nUse Copy report, or select text here and Ctrl+C.")
	box.add_child(_report_edit)
	_refresh_hud()


func _on_clear_caches_pressed() -> void:
	if _autoplay_running:
		return
	_clear_all_caches()
	_set_report("Caches cleared (impostor / building / model / land decor / materials).")
	_request_rebuild()


func _on_autoplay_pressed() -> void:
	if _autoplay_running:
		return
	call_deferred("_run_autoplay_bench")


func _on_copy_report_pressed() -> void:
	var text := _report_text
	if text.is_empty() and _report_edit != null:
		text = _report_edit.text
	if text.is_empty():
		return
	DisplayServer.clipboard_set(text)
	if _copy_btn != null:
		_copy_btn.text = "Copied!"
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if _copy_btn != null:
				_copy_btn.text = "Copy report"
		)


func _on_distance_dragged(value: float) -> void:
	simulated_distance_m = value
	_distance_rebuild_pending = true
	_refresh_hud()


func _on_distance_drag_ended(_value_changed: bool) -> void:
	if _distance_rebuild_pending:
		_distance_rebuild_pending = false
		_request_rebuild()


func _build_stage() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	var pad := MeshBuilder.box(
		Vector3(36.0, 0.4, 36.0),
		Color(0.20, 0.22, 0.24),
		0.92,
		0.0,
	)
	pad.position = Vector3(0.0, 0.2, 0.0)
	stage.add_child(pad)
	_slot = Node3D.new()
	_slot.name = "SpecimenSlot"
	_slot.position = Vector3(0.0, 0.45, 0.0)
	stage.add_child(_slot)


func _refresh_hud() -> void:
	var spec: Dictionary = SPECIMENS[_specimen_index]
	var tier := BuildProfiler.tier_index(simulated_distance_m)
	var mode := "AUTOPLAY…" if _autoplay_running else str(spec.get("title", ""))
	_controls.text = (
		"Stream tier lab — %s\nTab item · R rebuild · Shift+R clear · [ / ] stream distance · RMB orbit · wheel zoom\nUse buttons: Clear caches · Clear + autoplay mesh vs impostor"
		% mode
	)
	if _autoplay_btn != null:
		_autoplay_btn.disabled = _autoplay_running
	if _clear_btn != null:
		_clear_btn.disabled = _autoplay_running
	if _last_stats.is_empty():
		_stats_label.text = "Simulated %.0f m · %s · rebuilding…" % [
			simulated_distance_m,
			BuildProfiler.tier_label(tier),
		]
	else:
		var delta := ""
		if _prior_build_ms >= 0.0:
			var diff := _last_build_ms - _prior_build_ms
			delta = " (%+.1f ms vs last rebuild)" % diff
		_stats_label.text = (
			"Simulated %.0f m · %s · %s\nBuild: %.1f ms · %d mesh · %d nodes · %d coll%s"
			% [
				simulated_distance_m,
				BuildProfiler.tier_label(tier),
				_lod_mode,
				_last_build_ms,
				int(_last_stats.get("mesh_instances", 0)),
				int(_last_stats.get("node_count", 0)),
				int(_last_stats.get("collision_shapes", 0)),
				delta,
			]
		)


func _clear_slot() -> void:
	for child in _slot.get_children():
		child.queue_free()


func _rebuild_async() -> void:
	if _autoplay_running:
		return
	if _rebuilding:
		_rebuild_queued = true
		return
	_rebuilding = true
	_rebuild_queued = false
	_clear_slot()
	await get_tree().process_frame
	var spec: Dictionary = SPECIMENS[_specimen_index]
	var id := str(spec.get("id", ""))
	var tier := BuildProfiler.tier_index(simulated_distance_m)
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	var node: Node = await _spawn_specimen(id, tier)
	if node != null and node.get_parent() == null:
		_slot.add_child(node)
	var t1 := Time.get_ticks_usec()
	var f1 := Engine.get_process_frames()
	var stats := BuildProfiler.analyze_node(node)
	stats["ms"] = float(t1 - t0) / 1000.0
	stats["frames"] = maxi(1, f1 - f0 + 1)
	stats["tier"] = tier
	_prior_build_ms = _last_build_ms
	_last_build_ms = float(stats.get("ms", 0.0))
	_prev_tier = tier
	_last_stats = stats
	_rebuilding = false
	_refresh_hud()
	if _rebuild_queued and not _autoplay_running:
		call_deferred("_rebuild_async")


func _run_autoplay_bench() -> void:
	_autoplay_running = true
	_rebuild_queued = false
	_bench_rows.clear()
	_clear_all_caches()
	_autoplay_btn.text = "Running…"
	_refresh_hud()
	var report := "Cleared caches.\nAutoplay (machine speed): MESH vs IMPOSTOR per asset…\n\n"

	for i in range(SPECIMENS.size()):
		var spec: Dictionary = SPECIMENS[i]
		var id := str(spec.get("id", ""))
		var title := str(spec.get("title", id))
		if id == "terrain_chunk":
			report += "skip  %s (mesh LOD only, no impostor)\n" % title
			continue
		_specimen_index = i
		var row := await _bench_one_specimen(id, title)
		_bench_rows.append(row)
		report += _format_bench_row(row)

	report += "\n" + _format_bench_totals()
	_set_report(report)
	_autoplay_running = false
	_autoplay_btn.text = "Clear + autoplay mesh vs impostor"
	_refresh_hud()
	_request_rebuild()


func _bench_one_specimen(id: String, title: String) -> Dictionary:
	var cache_key := _cache_key_for(id)
	var builder := _full_builder_for(id)
	var row := {
		"title": title,
		"id": id,
		"mesh_ms": 0.0,
		"mesh_mi": 0,
		"mesh_nodes": 0,
		"mesh_coll": 0,
		"bake_ms": 0.0,
		"stamp_ms": 0.0,
		"stamp_mi": 0,
		"stamp_nodes": 0,
		"stamp_coll": 0,
	}

	# --- cold full mesh ---
	_clear_all_caches()
	_clear_slot()
	await get_tree().process_frame
	_lod_mode = "BENCH mesh"
	var t0 := Time.get_ticks_usec()
	var mesh_node := await _spawn_full_for_bench(cache_key, builder)
	var t1 := Time.get_ticks_usec()
	var mesh_stats := BuildProfiler.analyze_node(mesh_node)
	row["mesh_ms"] = float(t1 - t0) / 1000.0
	row["mesh_mi"] = int(mesh_stats.get("mesh_instances", 0))
	row["mesh_nodes"] = int(mesh_stats.get("node_count", 0))
	row["mesh_coll"] = int(mesh_stats.get("collision_shapes", 0))
	_last_stats = mesh_stats
	_last_build_ms = float(row["mesh_ms"])

	# --- bake impostor from live mesh, then stamp ---
	if mesh_node == null or not is_instance_valid(mesh_node):
		return row
	var tb0 := Time.get_ticks_usec()
	await IMPOSTOR_CACHE.bake_from_node(self, cache_key, mesh_node as Node3D, 128)
	var tb1 := Time.get_ticks_usec()
	row["bake_ms"] = float(tb1 - tb0) / 1000.0

	_clear_slot()
	await get_tree().process_frame
	_lod_mode = "BENCH impostor stamp"
	var ts0 := Time.get_ticks_usec()
	var stamp := IMPOSTOR_CACHE.instance(cache_key)
	_slot.add_child(stamp)
	var ts1 := Time.get_ticks_usec()
	var stamp_stats := BuildProfiler.analyze_node(stamp)
	row["stamp_ms"] = float(ts1 - ts0) / 1000.0
	row["stamp_mi"] = int(stamp_stats.get("mesh_instances", 0))
	row["stamp_nodes"] = int(stamp_stats.get("node_count", 0))
	row["stamp_coll"] = int(stamp_stats.get("collision_shapes", 0))
	_last_stats = stamp_stats
	_last_build_ms = float(row["stamp_ms"])
	return row


func _spawn_full_for_bench(cache_key: String, builder: Callable) -> Node:
	var full := builder.call() as Node3D
	if full == null:
		return Node3D.new()
	_slot.add_child(full)
	await get_tree().process_frame
	await get_tree().process_frame
	if cache_key in MODEL_SETTLE_KEYS:
		await get_tree().process_frame
		await get_tree().process_frame
	if full is CargoSlotPadComponent:
		(full as CargoSlotPadComponent).prefill_general_cargo(12, "perf_showcase", -1.0)
		await get_tree().process_frame
	return full


func _cache_key_for(id: String) -> String:
	match id:
		"land_decor":
			return "land_house"
		"model_cache":
			return "container_cube"
		_:
			return id


func _full_builder_for(id: String) -> Callable:
	match id:
		"provision_crane":
			return func() -> Node3D:
				var crane := PROVISION_CRANE_SCRIPT.new() as ProvisionCrane
				crane.name = "ProvisionCrane"
				return crane
		"bulk_crane":
			return func() -> Node3D:
				var crane := BULK_CRANE_SCRIPT.new() as BulkCrane
				crane.name = "BulkCrane"
				crane.show_operator = false
				return crane
		"cargo_pad":
			return func() -> Node3D:
				var pad := CargoSlotPadComponent.new()
				pad.is_quay_yard_pad = true
				pad.affects_boat_cargo_mass = false
				pad.deck_width_m = 16.0
				pad.deck_length_m = 24.0
				return pad
		"land_decor":
			return func() -> Node3D: return LandDecorCache.house_instance(2, 0.35, 0.6) as Node3D
		"foghorn":
			return func() -> Node3D: return ModelCache.instance(FOGHORN_MODEL, 1.0) as Node3D
		"lighthouse":
			return func() -> Node3D: return ModelCache.instance(LIGHTHOUSE_MODEL, 1.0) as Node3D
		"model_cache":
			return func() -> Node3D: return ModelCache.instance(CONTAINER_MODEL, 1.0) as Node3D
		"container_node":
			return func() -> Node3D:
				var n := ContainerNode.new()
				n.setup(ContainerFactory.make_one("showcase", "", "provisions"), true)
				return n
		_:
			return func() -> Node3D: return Node3D.new()


func _format_bench_row(row: Dictionary) -> String:
	var mesh_ms := float(row.get("mesh_ms", 0.0))
	var stamp_ms := float(row.get("stamp_ms", 0.0))
	var speedup := mesh_ms / maxf(stamp_ms, 0.001)
	return (
		"%s\n  MESH     %6.1f ms · %3d mi · %4d nodes · %3d coll\n  BAKE     %6.1f ms (once)\n  IMPOSTOR %6.1f ms · %3d mi · %4d nodes · %3d coll  (%.1fx vs mesh)\n\n"
		% [
			str(row.get("title", "")),
			mesh_ms,
			int(row.get("mesh_mi", 0)),
			int(row.get("mesh_nodes", 0)),
			int(row.get("mesh_coll", 0)),
			float(row.get("bake_ms", 0.0)),
			stamp_ms,
			int(row.get("stamp_mi", 0)),
			int(row.get("stamp_nodes", 0)),
			int(row.get("stamp_coll", 0)),
			speedup,
		]
	)


func _format_bench_totals() -> String:
	if _bench_rows.is_empty():
		return "No rows."
	var mesh_ms := 0.0
	var bake_ms := 0.0
	var stamp_ms := 0.0
	var mesh_mi := 0
	var stamp_mi := 0
	for row in _bench_rows:
		mesh_ms += float(row.get("mesh_ms", 0.0))
		bake_ms += float(row.get("bake_ms", 0.0))
		stamp_ms += float(row.get("stamp_ms", 0.0))
		mesh_mi += int(row.get("mesh_mi", 0))
		stamp_mi += int(row.get("stamp_mi", 0))
	return (
		"TOTALS (%d assets)\n  MESH load      %7.1f ms · %d mesh instances\n  IMPOSTOR bake  %7.1f ms (one-time)\n  IMPOSTOR stamp %7.1f ms · %d mesh instances  (%.1fx faster load than mesh)\n"
		% [
			_bench_rows.size(),
			mesh_ms,
			mesh_mi,
			bake_ms,
			stamp_ms,
			stamp_mi,
			mesh_ms / maxf(stamp_ms, 0.001),
		]
	)


func _set_report(text: String) -> void:
	_report_text = text
	if _report_edit != null:
		_report_edit.text = _report_text


func _append_report(text: String) -> void:
	_report_text += text
	if _report_edit != null:
		_report_edit.text = _report_text
		_report_edit.scroll_vertical = _report_edit.get_line_count()


func _spawn_specimen(id: String, tier: int) -> Node:
	match id:
		"terrain_chunk":
			_lod_mode = "mesh LOD step"
			return _build_terrain_at_tier(tier)
		"provision_crane":
			return await _spawn_provision_crane(tier)
		"bulk_crane":
			return await _spawn_bulk_crane(tier)
		"cargo_pad":
			return await _spawn_cargo_pad(tier)
		"land_decor":
			return await _spawn_with_impostor(
				"land_house",
				tier,
				func() -> Node3D: return LandDecorCache.house_instance(2, 0.35, 0.6) as Node3D,
			)
		"foghorn":
			return await _spawn_with_impostor(
				"foghorn",
				tier,
				func() -> Node3D: return ModelCache.instance(FOGHORN_MODEL, 1.0) as Node3D,
			)
		"lighthouse":
			return await _spawn_with_impostor(
				"lighthouse",
				tier,
				func() -> Node3D: return ModelCache.instance(LIGHTHOUSE_MODEL, 1.0) as Node3D,
			)
		"model_cache":
			return await _spawn_with_impostor(
				"container_cube",
				tier,
				func() -> Node3D: return ModelCache.instance(CONTAINER_MODEL, 1.0) as Node3D,
			)
		"container_node":
			return await _spawn_with_impostor(
				"container_node",
				tier,
				func() -> Node3D:
					var n := ContainerNode.new()
					n.setup(ContainerFactory.make_one("showcase", "", "provisions"), true)
					return n,
			)
		_:
			_lod_mode = "empty"
			return Node3D.new()


## Full mesh near, 6-face impostor mid/far, flat slab at horizon.
func _spawn_with_impostor(cache_key: String, tier: int, full_builder: Callable) -> Node:
	if tier >= 5:
		_lod_mode = "dormant slab"
		return _silhouette_box(Vector3(4.0, 0.4, 4.0), Color(0.3, 0.3, 0.32))
	if tier >= 4:
		_lod_mode = "horizon slab"
		return _silhouette_box(Vector3(8.0, 0.8, 8.0), Color(0.35, 0.34, 0.33))
	if tier >= 2:
		var baked_now := false
		if not IMPOSTOR_CACHE.has_key(cache_key):
			baked_now = true
			var source := full_builder.call() as Node3D
			if source == null:
				_lod_mode = "impostor bake failed"
				return Node3D.new()
			_slot.add_child(source)
			await get_tree().process_frame
			await get_tree().process_frame
			if source is CargoSlotPadComponent:
				(source as CargoSlotPadComponent).prefill_general_cargo(4, "perf_showcase", -1.0)
				await get_tree().process_frame
			if cache_key in MODEL_SETTLE_KEYS:
				await get_tree().process_frame
				await get_tree().process_frame
			await IMPOSTOR_CACHE.bake_from_node(self, cache_key, source, 128)
			source.queue_free()
			await get_tree().process_frame
		_lod_mode = "impostor BAKE (once)" if baked_now else "impostor stamp (6 quads)"
		return IMPOSTOR_CACHE.instance(cache_key)
	_lod_mode = "FULL mesh"
	var full := full_builder.call() as Node3D
	if full == null:
		return Node3D.new()
	_slot.add_child(full)
	await get_tree().process_frame
	await get_tree().process_frame
	if cache_key in MODEL_SETTLE_KEYS:
		await get_tree().process_frame
		await get_tree().process_frame
	if full is CargoSlotPadComponent:
		_apply_cargo_pad_tier(full as CargoSlotPadComponent, tier)
		await get_tree().process_frame
	return full


func _spawn_provision_crane(tier: int) -> Node:
	return await _spawn_with_impostor(
		"provision_crane",
		tier,
		func() -> Node3D:
			var crane := PROVISION_CRANE_SCRIPT.new() as ProvisionCrane
			crane.name = "ProvisionCrane"
			return crane,
	)


func _spawn_bulk_crane(tier: int) -> Node:
	return await _spawn_with_impostor(
		"bulk_crane",
		tier,
		func() -> Node3D:
			var crane := BULK_CRANE_SCRIPT.new() as BulkCrane
			crane.name = "BulkCrane"
			crane.show_operator = false
			return crane,
	)


func _spawn_cargo_pad(tier: int) -> Node:
	if tier >= 4:
		_lod_mode = "horizon slab"
		return MeshBuilder.box(Vector3(16.0, 0.15, 24.0), Color(0.18, 0.19, 0.20), 0.95, 0.0)
	if tier >= 2:
		return await _spawn_with_impostor(
			"cargo_pad",
			tier,
			func() -> Node3D:
				var pad := CargoSlotPadComponent.new()
				pad.is_quay_yard_pad = true
				pad.affects_boat_cargo_mass = false
				pad.deck_width_m = 16.0
				pad.deck_length_m = 24.0
				return pad,
		)
	_lod_mode = "FULL mesh"
	var pad := CargoSlotPadComponent.new()
	pad.is_quay_yard_pad = true
	pad.affects_boat_cargo_mass = false
	pad.deck_width_m = 16.0
	pad.deck_length_m = 24.0
	_slot.add_child(pad)
	await get_tree().process_frame
	_apply_cargo_pad_tier(pad, tier)
	await get_tree().process_frame
	return pad


func _find_land_chunk_coord() -> Vector2i:
	for z in range(-8, 9):
		for x in range(-8, 9):
			var probe := TERRAIN_STREAMER.build_chunk_mesh_data(
				_world_layout,
				Vector2i(x, z),
				200.0,
				[],
				0.0,
			)
			if not (probe["indices"] as PackedInt32Array).is_empty():
				return Vector2i(x, z)
	return Vector2i(2, -3)


func _build_terrain_at_tier(tier: int) -> Node:
	var root := Node3D.new()
	root.name = "TerrainChunk"
	var step: float = TERRAIN_LOD_STEPS[clampi(tier, 0, TERRAIN_LOD_STEPS.size() - 1)]
	var skirt: float = 12.0 if tier <= 1 else (6.0 if tier == 2 else 0.0)
	var data := TERRAIN_STREAMER.build_chunk_mesh_data(
		_world_layout,
		_terrain_land_coord,
		step,
		[],
		skirt,
	)
	var indices: PackedInt32Array = data["indices"]
	var mesh := ArrayMesh.new()
	if not indices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = data["normals"]
		arrays[Mesh.ARRAY_COLOR] = data["colors"]
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshBuilder.make_material(Color(0.42, 0.38, 0.32), 0.9, 0.0)
	# Center the chunk under the stage (streamer verts are world-space).
	var origin: Vector2 = TERRAIN_STREAMER.chunk_origin(_terrain_land_coord)
	mi.position = Vector3(-origin.x - 500.0, 0.0, -origin.y - 500.0)
	mi.scale = Vector3(0.06, 0.06, 0.06)
	root.add_child(mi)
	return root


func _apply_cargo_pad_tier(pad: CargoSlotPadComponent, tier: int) -> void:
	match tier:
		0:
			pad.prefill_general_cargo(12, "perf_showcase", -1.0)
		1:
			pad.prefill_general_cargo(6, "perf_showcase", -1.0)
		_:
			pass


func _silhouette_box(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshBuilder.box(size, color, 0.9, 0.0)
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(mi)
	return root
