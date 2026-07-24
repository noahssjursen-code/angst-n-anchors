extends Node3D

## STRUCTURE STUDIO — the unified parametric builder for vessels and land
## buildings. Replaces the separate shipyard/building brick editors.
##
## Structure is drawn, not stacked:
##   W  wall tool    — click-drag along the grid, release to place a wall run
##   R  room tool    — click-drag a rectangle, a full room (walls+floor+ceiling)
##   D  deck tool    — click-drag a rectangle deck plate
##   O  opening tool — click a wall or deck to punch the selected opening type
##   Q  select       — click an entity: XYZ gizmo arrows to move, panel to edit,
##                     DEL to delete · Ctrl+D duplicates
##   Ctrl+Z / Ctrl+Y — undo / redo (full-plan snapshots)
##   PgUp/PgDn       — build level up/down (grid follows; upper decks ghost)
##   F               — focus camera on selection · Esc cancels a drag
##   RMB drag orbit · MMB drag pan · wheel zoom
##
## Surfaces resolve through StructureMaterialLibrary (global construction
## catalog). Items/equipment are reserved — catalog ships empty this pass.
##
## Context switch (top bar): Ship (build on a hull) or Building (ground slab).
## Save/Load: JSON plans in res://resources/data/structures/.

const STRUCTURES_DIR := StructureStudioDocument.STRUCTURES_DIR
const GRID_SNAP := 1.0
const DEFAULT_WALL_HEIGHT := 3.0
var _clipboard_entity: Dictionary = {}
var _probe_mode := false
var _ortho_top := false
var _recent_paths: Array[String] = []

enum Tool { SELECT, WALL, ROOM, DECK, OPENING, ITEMS }

var _plan := StructurePlan.new()
var _context := "vessel"
var _hull_id := "hull_28x10"
var _grid_width := 10
var _grid_length := 28
var _plan_offset := Vector3.ZERO ## grid-corner space -> world

var _tool: Tool = Tool.WALL
var _active_base := 0.0 ## y level being drawn on
var _ghost_levels := true ## structure above the build level renders as x-ray
var _show_roofs := false ## VIEW-ONLY: room ceilings hidden while editing (T)
var _ghost_root: Node3D
var _ghost_threshold := INF ## entities at/above this base y are ghosted
var _entity_base_y: Dictionary = {} ## id -> base level (for pick filtering)
var _opening_type := StructurePlan.OPENING_DOOR

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

var _selected_id := -1
var _drag_start := Vector3.ZERO
var _dragging := false
var _gizmo_axis := -1 ## 0=X 1=Y 2=Z while dragging an arrow
var _gizmo_grab_value := 0.0
var _gizmo_start_origin := Vector3.ZERO
## Drag math is measured against a line origin FROZEN at grab time — measuring
## against the moving gizmo caused a feedback loop (position alternated every
## frame). _gizmo_last_applied gates rebakes to actual snapped changes.
var _gizmo_line_origin := Vector3.ZERO
var _gizmo_last_applied := Vector3.INF
## Face-resize mode (double-click-hold-drag a face).
var _resize_mode := false
var _resize_sign := 1
var _resize_start_primary := Vector3.ZERO ## entity origin at grab
var _resize_start_dims := Vector3.ZERO ## (length/width, height, thickness/length2)

var _camera: Camera3D
var _cam_focus := Vector3.ZERO
var _cam_yaw := 0.7
var _cam_pitch := 0.9
var _cam_distance := 34.0
var _orbiting := false
var _panning := false

var _bake_root: Node3D
var _hull_visual: Node3D
var _ghost: MeshInstance3D
var _selection_box: MeshInstance3D
var _gizmo_root: Node3D
var _handle_root: Node3D ## six face-resize pads around the selection
var _entity_bounds: Dictionary = {} ## id -> AABB (world space)
## Always-on cursor feedback: what THIS click will do, exactly where.
var _opening_ghost: MeshInstance3D ## the actual door/window/hole, snapped, on its host
var _hover_box: MeshInstance3D ## copper pre-selection outline under the cursor
var _start_marker: MeshInstance3D ## snapped grid point a draw-drag would start from

var _status := ""
var _dirty := false
var _rebake_queued := false
var _load_list_dirty := true
var _help_visible := false
var _help_panel: PanelContainer
var _material_category := "all"
var _category_buttons: Dictionary = {}
var _level_step := 1.0 ## 1.0 m or storey (DEFAULT_WALL_HEIGHT)
var _building_size := 24
var _autosave_timer: Timer
var _spin_undo_armed := false
var _title_label: Label
var _building_option: OptionButton
var _material_flow: HFlowContainer
var _confirm_dialog: ConfirmationDialog
var _pending_confirm_action: Callable = Callable()
var _hover_last_screen := Vector2(-9999, -9999)
var _suppress_building_signal := false
const BUILDING_SIZES := [16, 24, 32, 48]
const MATERIAL_CATEGORY_FILTERS := [
	"all", "finish", "timber", "cladding", "metal", "marine", "structure", "ground", "fabric",
]


func _ready() -> void:
	StructureMaterialLibrary.reload()
	StructureItemCatalog.reload()
	_build_scene()
	_build_ui()
	_setup_autosave()
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--studio-probe":
			_probe_mode = true
	_set_context("vessel", true)
	if _probe_mode:
		var report := _probe_report()
		print(report)
		_shutdown_for_probe()
		get_tree().quit(0 if report.contains("ok") else 1)


func _probe_report() -> String:
	var mat_ids := StructureMaterialLibrary.ids()
	## Load the demo so the probe exercises a real bake, not an empty plan.
	var demo_path := "%s/demo_workboat.json" % STRUCTURES_DIR
	if FileAccess.file_exists(demo_path):
		_load_plan(demo_path)
	var bake := StructureBaker.bake(_plan, _plan_offset)
	var mesh_count := bake.get_child_count()
	bake.free()
	var report := _plan.validate(_grid_width, _grid_length)
	var ok := bool(report.get("ok", false)) and mat_ids.size() >= 8 and mesh_count > 0
	var prefix := "[structure-studio] probe ok" if ok else "[structure-studio] probe FAIL"
	return "%s — context=%s entities=%d materials=%d bake_meshes=%d items_catalog=%d" % [
		prefix, _context, _plan.entity_count(), mat_ids.size(), mesh_count, StructureItemCatalog.ids().size(),
	]


func _shutdown_for_probe() -> void:
	## Stop per-frame camera/hover work before freeing preview nodes.
	set_process(false)
	## Drop host/bake trees so headless quit does not leak VesselSpawn bodies.
	if _bake_root != null and is_instance_valid(_bake_root):
		_bake_root.free()
		_bake_root = null
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.free()
		_ghost_root = null
	if _hull_visual != null and is_instance_valid(_hull_visual):
		_hull_visual.free()
		_hull_visual = null
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.free()
		_ghost = null
	if _selection_box != null and is_instance_valid(_selection_box):
		_selection_box.free()
		_selection_box = null
	if _opening_ghost != null and is_instance_valid(_opening_ghost):
		_opening_ghost.free()
		_opening_ghost = null
	if _hover_box != null and is_instance_valid(_hover_box):
		_hover_box.free()
		_hover_box = null
	if _start_marker != null and is_instance_valid(_start_marker):
		_start_marker.free()
		_start_marker = null
	if _gizmo_root != null and is_instance_valid(_gizmo_root):
		_gizmo_root.free()
		_gizmo_root = null
	if _handle_root != null and is_instance_valid(_handle_root):
		_handle_root.free()
		_handle_root = null
	_camera = null
	StructureMaterialLibrary.clear_runtime_caches()


# ── Context / plan lifecycle ─────────────────────────────────────────────────

var _deck_grid: DeckGrid
var _suppress_hull_signal := false


## Switch vessel ↔ building. `reset_plan` clears the document (used on true
## context changes). Hull-only changes call `_set_hull` instead so work is kept.
func _set_context(context: String, reset_plan := true) -> void:
	var next := context if context in StructurePlan.CONTEXTS else "vessel"
	var context_changed := next != _context
	if context_changed and reset_plan and _dirty:
		_confirm_if_dirty(
			"Switch context and discard unsaved changes?",
			func() -> void: _set_context_now(next, true),
		)
		return
	_set_context_now(next, reset_plan)


func _set_context_now(context: String, reset_plan := true) -> void:
	var context_changed := context != _context
	_context = context if context in StructurePlan.CONTEXTS else "vessel"
	if reset_plan or context_changed:
		if not _plan.is_empty() and context_changed:
			_snapshot()
		_plan = StructurePlan.new()
		_plan.context = _context
		_undo_stack.clear()
		_redo_stack.clear()
		_selected_id = -1
		_active_base = 0.0
		_clear_dirty()
		if context_changed and not reset_plan:
			_set_status("switched to %s — new plan" % _context)
	_plan.context = _context
	_apply_host_metrics()
	_sync_hull_option()
	_sync_building_option()
	_cam_focus = Vector3.ZERO
	_rebuild_host_visual()
	_request_rebake(true)
	_refresh_panel()


func _set_hull(hull_id: String, keep_plan := true) -> void:
	var next := hull_id.strip_edges()
	if next.is_empty():
		return
	_hull_id = next
	_context = "vessel"
	_plan.context = "vessel"
	_plan.hull_id = _hull_id
	_apply_host_metrics()
	_sync_hull_option()
	if not keep_plan:
		_plan = StructurePlan.new()
		_plan.context = "vessel"
		_plan.hull_id = _hull_id
		_undo_stack.clear()
		_redo_stack.clear()
		_selected_id = -1
	_rebuild_host_visual()
	_request_rebake(true)
	_refresh_panel()
	if keep_plan:
		var report := _plan.validate(_grid_width, _grid_length)
		var warns: PackedStringArray = report.get("warnings", PackedStringArray())
		if not warns.is_empty():
			_set_status("hull changed — %s" % warns[0], false)
		else:
			_set_status("hull: %s" % _hull_id)


func _apply_host_metrics() -> void:
	if _context == "vessel":
		_deck_grid = HullRegistry.make_grid(_hull_id)
		_grid_width = _deck_grid.width
		_grid_length = _deck_grid.length
		_plan.hull_id = _hull_id
		_plan_offset = Vector3(-_deck_grid.half_beam, 0.0, -_deck_grid.half_loa)
	else:
		_deck_grid = null
		_grid_width = _building_size
		_grid_length = _building_size
		_plan.hull_id = ""
		_plan_offset = Vector3(-_grid_width * 0.5, 0.0, -_grid_length * 0.5)


func _sync_hull_option() -> void:
	if _hull_option == null:
		return
	_suppress_hull_signal = true
	var hulls := HullRegistry.catalog()
	for index in hulls.size():
		if str((hulls[index] as Dictionary).get("id", "")) == _hull_id:
			_hull_option.select(index)
			break
	_suppress_hull_signal = false


func _sync_building_option() -> void:
	if _building_option == null:
		return
	_suppress_building_signal = true
	var select_index := 1
	for index in BUILDING_SIZES.size():
		if int(BUILDING_SIZES[index]) == _building_size:
			select_index = index
			break
	_building_option.select(select_index)
	_suppress_building_signal = false


func _set_building_size(size_m: int) -> void:
	var next := clampi(size_m, 12, 64)
	if next == _building_size and _context == "building":
		return
	_building_size = next
	if _context != "building":
		_sync_building_option()
		return
	_apply_host_metrics()
	_rebuild_host_visual()
	_request_rebake(true)
	_refresh_panel()
	_set_status("plot %d×%d m" % [_building_size, _building_size])


func _new_plan() -> void:
	_confirm_if_dirty(
		"Discard unsaved changes and start a new plan?",
		func() -> void: _new_plan_now(),
	)


func _new_plan_now() -> void:
	if not _plan.is_empty():
		_snapshot()
	_plan = StructurePlan.new()
	_plan.context = _context
	if _context == "vessel":
		_plan.hull_id = _hull_id
	_selected_id = -1
	_active_base = 0.0
	_clear_dirty()
	_build_grid_lines()
	_request_rebake(true)
	_refresh_panel()
	_set_status("new plan")


func _rebuild_host_visual() -> void:
	if _hull_visual != null:
		_hull_visual.queue_free()
	_hull_visual = Node3D.new()
	_hull_visual.name = "Host"
	add_child(_hull_visual)
	if _context == "vessel" and not _probe_mode:
		## The REAL hull under the build: deck plane aligned to the grid plane.
		## Headless probes skip VesselSpawn — ship audio streams otherwise leak.
		var boat := VesselSpawn.instantiate(_hull_id, {}, "")
		if boat != null:
			_hull_visual.add_child(boat)
			boat.position = Vector3(0.0, -_deck_grid.deck_y, 0.0)
			boat.freeze = true
			boat.sleeping = true
			boat.process_mode = Node.PROCESS_MODE_DISABLED
	elif _context == "vessel" and _probe_mode:
		var proxy := MeshInstance3D.new()
		var proxy_mesh := BoxMesh.new()
		proxy_mesh.size = Vector3(float(_grid_width) + 2.0, 0.4, float(_grid_length) + 2.0)
		proxy.mesh = proxy_mesh
		var proxy_mat := StandardMaterial3D.new()
		proxy_mat.albedo_color = Color(0.18, 0.22, 0.26)
		proxy.material_override = proxy_mat
		proxy.position = Vector3(0, -0.2, 0)
		_hull_visual.add_child(proxy)
	else:
		var slab := MeshInstance3D.new()
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(float(_grid_width) + 8.0, 1.0, float(_grid_length) + 8.0)
		var ground := StandardMaterial3D.new()
		ground.albedo_color = Color(0.24, 0.30, 0.22)
		slab.material_override = ground
		slab.position = Vector3(0, -0.5, 0)
		slab.mesh = slab_mesh
		_hull_visual.add_child(slab)
	_build_grid_lines()
	_build_orientation_markers()
	_build_scale_mannequin()


var _grid_lines: MeshInstance3D


## Grid lines clipped to the buildable footprint: full squares for full cells,
## the 45° hypotenuse for tapered bow half-cells, nothing outside the hull.
## Drawn at the ACTIVE BUILD LEVEL so upper-deck work has its own grid plane.
func _build_grid_lines() -> void:
	if _grid_lines != null and is_instance_valid(_grid_lines):
		_grid_lines.queue_free()
	var grid := MeshInstance3D.new()
	_grid_lines = grid
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var y := _active_base + 0.03
	for ix in _grid_width:
		for iz in _grid_length:
			var shape := DeckGrid.CellShape.FULL
			if _deck_grid != null:
				shape = _deck_grid.cell_shape(ix, iz)
			var p := _plan_offset + Vector3(float(ix), y, float(iz))
			match shape:
				DeckGrid.CellShape.NONE:
					continue
				DeckGrid.CellShape.BOW_PORT_HALF:
					## Solid corner is (+X, +Z); hypotenuse from (0,1) to (1,0)… draw
					## diagonal plus the two kept edges.
					im.surface_add_vertex(p + Vector3(1, 0, 0))
					im.surface_add_vertex(p + Vector3(0, 0, 1))
					im.surface_add_vertex(p + Vector3(1, 0, 0))
					im.surface_add_vertex(p + Vector3(1, 0, 1))
					im.surface_add_vertex(p + Vector3(0, 0, 1))
					im.surface_add_vertex(p + Vector3(1, 0, 1))
				DeckGrid.CellShape.BOW_STARBOARD_HALF:
					im.surface_add_vertex(p + Vector3(0, 0, 0))
					im.surface_add_vertex(p + Vector3(1, 0, 1))
					im.surface_add_vertex(p + Vector3(0, 0, 0))
					im.surface_add_vertex(p + Vector3(0, 0, 1))
					im.surface_add_vertex(p + Vector3(0, 0, 1))
					im.surface_add_vertex(p + Vector3(1, 0, 1))
				_:
					im.surface_add_vertex(p)
					im.surface_add_vertex(p + Vector3(1, 0, 0))
					im.surface_add_vertex(p)
					im.surface_add_vertex(p + Vector3(0, 0, 1))
					im.surface_add_vertex(p + Vector3(1, 0, 0))
					im.surface_add_vertex(p + Vector3(1, 0, 1))
					im.surface_add_vertex(p + Vector3(0, 0, 1))
					im.surface_add_vertex(p + Vector3(1, 0, 1))
	im.surface_end()
	grid.mesh = im
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.4, 0.62, 0.8, 0.45)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid.material_override = line_mat
	_hull_visual.add_child(grid)


func _build_orientation_markers() -> void:
	## Painted flat on the deck/ground plane just outside the grid.
	var markers: Array = []
	if _context == "vessel":
		markers = [
			["BOW", Vector3(_grid_width * 0.5, 0.06, -1.4), 0.0, HudStyle.C_AMBER],
			["STERN", Vector3(_grid_width * 0.5, 0.06, _grid_length + 1.4), 180.0, HudStyle.C_LABEL],
			["PORT", Vector3(-1.6, 0.06, _grid_length * 0.5), 90.0, HudStyle.C_RED],
			["STARBOARD", Vector3(_grid_width + 1.6, 0.06, _grid_length * 0.5), 270.0, HudStyle.C_GREEN],
		]
	else:
		markers = [
			["N", Vector3(_grid_width * 0.5, 0.06, -1.4), 0.0, HudStyle.C_AMBER],
			["S", Vector3(_grid_width * 0.5, 0.06, _grid_length + 1.4), 180.0, HudStyle.C_LABEL],
			["W", Vector3(-1.6, 0.06, _grid_length * 0.5), 90.0, HudStyle.C_RED],
			["E", Vector3(_grid_width + 1.6, 0.06, _grid_length * 0.5), 270.0, HudStyle.C_GREEN],
		]
	for marker in markers:
		var label := Label3D.new()
		label.text = str(marker[0])
		label.font_size = 132
		label.modulate = Color(marker[3] as Color, 0.85)
		label.position = _plan_offset + (marker[1] as Vector3)
		label.rotation_degrees = Vector3(-90.0, float(marker[2]), 0.0)
		label.no_depth_test = false
		_hull_visual.add_child(label)


## 1.8 m hi-viz mannequin on deck — the constant human scale reference.
func _build_scale_mannequin() -> void:
	var mannequin := Node3D.new()
	mannequin.name = "ScaleMannequin"
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0, 0.75, 0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.95, 0.55, 0.1)
	body.material_override = suit
	mannequin.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0, 1.66, 0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.7, 0.55)
	head.material_override = skin
	mannequin.add_child(head)
	var tag := Label3D.new()
	tag.text = "1.8 m"
	tag.font_size = 96
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.1, 0)
	mannequin.add_child(tag)
	var spot := Vector3(2.0, 0.0, float(_grid_length) - 3.0)
	if _context != "vessel":
		spot = Vector3(2.0, 0.0, 2.0)
	mannequin.position = _plan_offset + spot
	_hull_visual.add_child(mannequin)


var _pending_snapshot: Dictionary = {}


func _snapshot() -> void:
	_undo_stack.append(_plan.to_dict())
	if _undo_stack.size() > 100:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_mark_dirty()


## Drags stage their snapshot at grab time but only commit it to the undo
## stack on the first REAL change — an aborted or zero-distance drag leaves
## no junk undo step.
func _stage_snapshot() -> void:
	_pending_snapshot = _plan.to_dict()


func _commit_staged_snapshot() -> void:
	if _pending_snapshot.is_empty():
		return
	_undo_stack.append(_pending_snapshot)
	if _undo_stack.size() > 100:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_pending_snapshot = {}
	_mark_dirty()


func _cancel_staged_edit() -> void:
	## Restore plan to the pre-drag snapshot (Esc during gizmo/resize).
	if _pending_snapshot.is_empty():
		return
	_plan = StructurePlan.from_dict(_pending_snapshot)
	_pending_snapshot = {}
	_gizmo_last_applied = Vector3.INF
	_request_rebake(true)


func _mark_dirty() -> void:
	_dirty = true
	if _autosave_timer != null:
		_autosave_timer.start()
	_refresh_title()


func _clear_dirty() -> void:
	_dirty = false
	if _autosave_timer != null:
		_autosave_timer.stop()
	_refresh_title()


func _refresh_title() -> void:
	if _title_label == null:
		return
	_title_label.text = "STRUCTURE STUDIO *" if _dirty else "STRUCTURE STUDIO"


## Run `action` immediately when the document is clean; otherwise ask first.
func _confirm_if_dirty(message: String, action: Callable) -> void:
	if not _dirty:
		action.call()
		return
	_ask_confirm(message, action)


func _on_confirm_accepted() -> void:
	var action := _pending_confirm_action
	_pending_confirm_action = Callable()
	if action.is_valid():
		action.call()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_plan.to_dict())
	_plan = StructurePlan.from_dict(_undo_stack.pop_back())
	_selected_id = -1
	_mark_dirty()
	_request_rebake(true)
	_refresh_panel()


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_plan.to_dict())
	_plan = StructurePlan.from_dict(_redo_stack.pop_back())
	_selected_id = -1
	_mark_dirty()
	_request_rebake(true)
	_refresh_panel()


## Queue a rebake. `immediate` flushes this frame (placement/commit); otherwise
## coalesce rapid gizmo/spin updates into one deferred bake.
func _request_rebake(immediate := false) -> void:
	if immediate:
		_rebake_queued = false
		_rebake()
		return
	if _rebake_queued:
		return
	_rebake_queued = true
	call_deferred("_flush_rebake")


func _flush_rebake() -> void:
	if not _rebake_queued:
		return
	_rebake_queued = false
	_rebake()


func _rebake() -> void:
	if _bake_root != null and is_instance_valid(_bake_root):
		_bake_root.free()
		_bake_root = null
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.free()
		_ghost_root = null
	## Ghost threshold tracks the tallest storey starting at the active base
	## so custom room heights stay readable when "ghost upper decks" is on.
	var storey := DEFAULT_WALL_HEIGHT
	for room_variant in _plan.rooms:
		var room := room_variant as Dictionary
		var origin := StructurePlan.vec3_of(room.get("origin"))
		if absf(origin.y - _active_base) < 0.05:
			storey = maxf(storey, float(StructurePlan.vec3_of(room.get("size"), Vector3(4, 3, 4)).y))
	for wall_variant in _plan.walls:
		var wall := wall_variant as Dictionary
		var origin := StructurePlan.vec3_of(wall.get("start"))
		if absf(origin.y - _active_base) < 0.05:
			storey = maxf(storey, float(wall.get("height", DEFAULT_WALL_HEIGHT)))
	storey = maxf(storey - 0.01, 0.5)
	var threshold := _active_base + storey if _ghost_levels else INF
	_ghost_threshold = threshold
	var solid_plan := _filtered_plan_copy(true, threshold)
	var ghost_plan := _filtered_plan_copy(false, threshold)
	var any_ghost := (
		not ghost_plan.walls.is_empty()
		or not ghost_plan.decks.is_empty()
		or not ghost_plan.rooms.is_empty()
	)
	if not _show_roofs:
		for plan_copy in [solid_plan, ghost_plan]:
			for room_variant in (plan_copy as StructurePlan).rooms:
				(room_variant as Dictionary)["roof"] = false
	_bake_root = StructureBaker.bake(solid_plan, _plan_offset)
	add_child(_bake_root)
	_bake_mesh_count = _bake_root.get_child_count()
	if any_ghost:
		_ghost_root = StructureBaker.bake(ghost_plan, _plan_offset, true)
		add_child(_ghost_root)
		_bake_mesh_count += _ghost_root.get_child_count()
	_recompute_bounds()
	_update_selection_visual()


func _filtered_plan_copy(keep_below: bool, threshold: float) -> StructurePlan:
	var copy := StructurePlan.from_dict(_plan.to_dict())
	for collection in [copy.walls, copy.decks, copy.rooms]:
		var kept: Array = []
		for entity in collection:
			var origin := StructurePlan.vec3_of(
				(entity as Dictionary).get("start", (entity as Dictionary).get("origin"))
			)
			var below := origin.y < threshold
			if below == keep_below:
				kept.append(entity)
		(collection as Array).assign(kept)
	return copy


func _recompute_bounds() -> void:
	_entity_bounds.clear()
	_entity_base_y.clear()
	for collection in [_plan.walls, _plan.decks, _plan.rooms]:
		for entity_variant in collection:
			var entity := entity_variant as Dictionary
			_entity_base_y[int(entity.get("id", -1))] = StructurePlan.vec3_of(
				entity.get("start", entity.get("origin"))
			).y
	var expanded := StructureBaker.expand(_plan)
	for wall_variant in expanded["walls"] as Array:
		var wall := wall_variant as Dictionary
		for box_variant in StructureBaker.wall_boxes(wall):
			_grow_bounds(int(wall.get("source_id", -1)), box_variant as Dictionary)
	for deck_variant in expanded["decks"] as Array:
		var deck := deck_variant as Dictionary
		for box_variant in StructureBaker.deck_boxes(deck):
			_grow_bounds(int(deck.get("source_id", -1)), box_variant as Dictionary)


func _grow_bounds(source_id: int, box: Dictionary) -> void:
	if source_id < 0:
		return
	var center := (box["center"] as Vector3) + _plan_offset
	var size := box["size"] as Vector3
	var aabb := AABB(center - size * 0.5, size)
	if _entity_bounds.has(source_id):
		_entity_bounds[source_id] = (_entity_bounds[source_id] as AABB).merge(aabb)
	else:
		_entity_bounds[source_id] = aabb


# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		_handle_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_key(key: InputEventKey) -> void:
	## Keys stay out of the viewport while a text field owns focus.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if key.ctrl_pressed and key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo()
		else:
			_undo()
		return
	if key.ctrl_pressed and key.keycode == KEY_Y:
		_redo()
		return
	if key.ctrl_pressed and key.keycode == KEY_D:
		_duplicate_selected()
		return
	if key.ctrl_pressed and key.keycode == KEY_C:
		_copy_selected()
		return
	if key.ctrl_pressed and key.keycode == KEY_V:
		_paste_clipboard()
		return
	if key.ctrl_pressed and key.keycode == KEY_N:
		_new_plan()
		return
	if key.ctrl_pressed and key.keycode == KEY_S:
		if not _name_edit.text.strip_edges().is_empty():
			_save_plan(_name_edit.text)
		else:
			_set_status("name the structure before saving", false)
		return
	match key.keycode:
		KEY_ESCAPE:
			if _gizmo_axis >= 0:
				_cancel_staged_edit()
				_gizmo_axis = -1
				_resize_mode = false
				_set_status("edit cancelled")
				_refresh_panel()
			elif _dragging or _opening_drag:
				_dragging = false
				_opening_drag = false
				_opening_ctx = {}
				_opening_ghost.visible = false
				_hide_ghost()
			elif _help_visible:
				_toggle_help(false)
			elif _selected_id >= 0:
				_selected_id = -1
				_update_selection_visual()
				_refresh_panel()
			else:
				_set_tool(Tool.SELECT)
		KEY_Q:
			_set_tool(Tool.SELECT)
		KEY_W:
			_set_tool(Tool.WALL)
		KEY_R:
			_set_tool(Tool.ROOM)
		KEY_D:
			_set_tool(Tool.DECK)
		KEY_O:
			_set_tool(Tool.OPENING)
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_F:
			_focus_camera()
		KEY_X:
			if key.shift_pressed:
				_mirror_selected("z")
			else:
				_mirror_selected("x")
		KEY_E:
			_eyedrop_selection_to_library()
		KEY_TAB:
			_cycle_selection(not key.shift_pressed)
		KEY_BRACKETLEFT:
			_cycle_selection_material(-1)
		KEY_BRACKETRIGHT:
			_cycle_selection_material(1)
		KEY_COMMA:
			_rotate_selected(-90)
		KEY_PERIOD:
			_rotate_selected(90)
		KEY_HOME:
			_toggle_ortho_top()
		KEY_T:
			_show_roofs = not _show_roofs
			_request_rebake(true)
			_refresh_panel()
		KEY_G:
			_ghost_levels = not _ghost_levels
			_request_rebake(true)
			_refresh_panel()
		KEY_H, KEY_SLASH:
			_toggle_help(not _help_visible)
		KEY_PAGEUP:
			var step_up := DEFAULT_WALL_HEIGHT if key.shift_pressed else _level_step
			_set_build_level(_active_base + step_up)
		KEY_PAGEDOWN:
			var step_down := DEFAULT_WALL_HEIGHT if key.shift_pressed else _level_step
			_set_build_level(_active_base - step_down)
		KEY_LEFT:
			_nudge_selected(Vector3(-1, 0, 0))
		KEY_RIGHT:
			_nudge_selected(Vector3(1, 0, 0))
		KEY_UP:
			_nudge_selected(Vector3(0, 0, -1) if not key.shift_pressed else Vector3(0, 1, 0))
		KEY_DOWN:
			_nudge_selected(Vector3(0, 0, 1) if not key.shift_pressed else Vector3(0, -1, 0))
		KEY_1:
			if _tool == Tool.OPENING:
				_opening_type = StructurePlan.OPENING_DOOR
				_refresh_panel()
			else:
				_set_tool(Tool.SELECT)
		KEY_2:
			if _tool == Tool.OPENING:
				_opening_type = StructurePlan.OPENING_WINDOW
				_refresh_panel()
			else:
				_set_tool(Tool.WALL)
		KEY_3:
			if _tool == Tool.OPENING:
				_opening_type = StructurePlan.OPENING_HOLE
				_refresh_panel()
			else:
				_set_tool(Tool.ROOM)
		KEY_4:
			_set_tool(Tool.DECK)
		KEY_5:
			_set_tool(Tool.OPENING)


func _set_build_level(level: float) -> void:
	_active_base = maxf(level, 0.0)
	_build_grid_lines()
	_request_rebake(true)
	_refresh_panel()


func _nudge_selected(delta: Vector3) -> void:
	if _selected_id < 0 or _tool != Tool.SELECT:
		return
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		return
	_snapshot()
	var kind := StructurePlan.kind_of_entity(entity)
	var key := "start" if entity.has("start") else "origin"
	var origin := StructurePlan.vec3_of(entity.get(key))
	var dims := _entity_dims(entity, kind)
	var next := _clamp_origin_to_grid(origin + delta, kind, dims)
	entity[key] = [next.x, next.y, next.z]
	_request_rebake(true)
	_refresh_panel()
	_set_status("nudged #%d" % _selected_id)


func _entity_dims(entity: Dictionary, kind: String) -> Vector3:
	match kind:
		"room":
			return StructurePlan.vec3_of(entity.get("size"), Vector3(2, 3, 2))
		"deck":
			var plate: Array = entity.get("size", [1.0, 1.0])
			return Vector3(float(plate[0]), 0.0, float(plate[1]) if plate.size() > 1 else 1.0)
		"wall":
			return Vector3(float(entity.get("length", 1.0)), 0.0, 0.0)
		_:
			return Vector3.ONE


func _toggle_ortho_top() -> void:
	_ortho_top = not _ortho_top
	if _camera == null:
		return
	if _ortho_top:
		_cam_pitch = 1.45
		_cam_yaw = 0.0
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = clampf(_cam_distance * 0.55, 12.0, 80.0)
		_set_status("top-down ortho")
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam_pitch = 0.9
		_cam_yaw = 0.7
		_set_status("perspective")


func _focus_camera() -> void:
	if _selected_id >= 0 and _entity_bounds.has(_selected_id):
		var aabb := _entity_bounds[_selected_id] as AABB
		_cam_focus = aabb.get_center()
		_cam_distance = clampf(aabb.size.length() * 1.8 + 6.0, 10.0, 80.0)
		return
	var has_any := false
	var union := AABB()
	for id in _entity_bounds.keys():
		var piece := _entity_bounds[id] as AABB
		if not has_any:
			union = piece
			has_any = true
		else:
			union = union.merge(piece)
	if has_any:
		_cam_focus = union.get_center()
		_cam_distance = clampf(union.size.length() * 1.4 + 8.0, 14.0, 90.0)
	else:
		_cam_focus = Vector3.ZERO
		_cam_distance = 34.0


## Mirror selection across the plot mid-plane on X or Z (Shift+X = Z).
func _mirror_selected(axis: String) -> void:
	if _selected_id < 0:
		_set_status("nothing selected to mirror", false)
		return
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		return
	var kind := StructurePlan.kind_of_entity(entity)
	_snapshot()
	var key := "start" if entity.has("start") else "origin"
	var origin := StructurePlan.vec3_of(entity.get(key))
	var dims := _entity_dims(entity, kind)
	if axis == "x":
		var width := 0.0
		if kind == "wall" and str(entity.get("axis", "x")) == "x":
			width = float(entity.get("length", 1.0))
		elif kind != "wall":
			width = dims.x
		origin.x = StructureStudioMath.mirror_origin_on_axis(origin.x, width, float(_grid_width))
		if kind == "wall" and str(entity.get("axis", "x")) == "x":
			_flip_wall_opening_offsets(entity)
		elif kind == "room":
			_swap_room_faces(entity, "e", "w")
			_flip_plate_opening_axis(entity, "x", dims.x)
		elif kind == "deck":
			_flip_plate_opening_axis(entity, "x", dims.x)
	else:
		var depth := 0.0
		if kind == "wall" and str(entity.get("axis", "x")) == "z":
			depth = float(entity.get("length", 1.0))
		elif kind != "wall":
			depth = dims.z
		origin.z = StructureStudioMath.mirror_origin_on_axis(origin.z, depth, float(_grid_length))
		if kind == "wall" and str(entity.get("axis", "x")) == "z":
			_flip_wall_opening_offsets(entity)
		elif kind == "room":
			_swap_room_faces(entity, "n", "s")
			_flip_plate_opening_axis(entity, "z", dims.z)
		elif kind == "deck":
			_flip_plate_opening_axis(entity, "z", dims.z)
	origin = _clamp_origin_to_grid(origin, kind, dims)
	entity[key] = [origin.x, origin.y, origin.z]
	_request_rebake(true)
	_refresh_panel()
	_set_status("mirrored #%d on %s" % [_selected_id, axis.to_upper()])


func _swap_room_faces(entity: Dictionary, a: String, b: String) -> void:
	if not entity.has("openings"):
		return
	for opening_variant in entity["openings"] as Array:
		var opening := opening_variant as Dictionary
		var face := str(opening.get("face", ""))
		if face == a:
			opening["face"] = b
		elif face == b:
			opening["face"] = a


func _flip_wall_opening_offsets(entity: Dictionary) -> void:
	var length := float(entity.get("length", 1.0))
	for opening_variant in entity.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off := float(opening.get("offset", 0.0))
		var width := float(opening.get("width", 1.0))
		opening["offset"] = StructureStudioMath.mirror_opening_offset(off, width, length)


func _flip_plate_opening_axis(entity: Dictionary, axis: String, extent: float) -> void:
	for opening_variant in entity.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var face := str(opening.get("face", ""))
		## Room wall openings use scalar offset; only plate cuts use [x,z].
		if entity.has("size") and (entity.get("size") as Array).size() == 3 and face not in ["floor", "ceiling", ""]:
			continue
		var off_raw: Variant = opening.get("offset", [0.0, 0.0])
		if off_raw is not Array:
			continue
		var off: Array = (off_raw as Array).duplicate()
		var hole := StructurePlan.vec2_of(opening.get("size"), Vector2(1, 1))
		if axis == "x" and off.size() > 0:
			off[0] = maxf(extent - float(off[0]) - hole.x, 0.0)
		elif axis == "z":
			if off.size() < 2:
				off.append(0.0)
			off[1] = maxf(extent - float(off[1]) - hole.y, 0.0)
		opening["offset"] = off


func _cycle_selection(forward := true) -> void:
	var ids: Array[int] = []
	for collection in [_plan.rooms, _plan.walls, _plan.decks]:
		for entity_variant in collection:
			ids.append(int((entity_variant as Dictionary).get("id", -1)))
	ids.sort()
	if ids.is_empty():
		return
	var index := ids.find(_selected_id)
	if index < 0:
		index = 0 if forward else ids.size() - 1
	else:
		index = (index + (1 if forward else -1) + ids.size()) % ids.size()
	_selected_id = ids[index]
	_tool = Tool.SELECT
	if _entity_bounds.has(_selected_id):
		_cam_focus = (_entity_bounds[_selected_id] as AABB).get_center()
	_update_selection_visual()
	_refresh_panel()
	_set_status("selected #%d" % _selected_id)


func _raise_selected_to_level() -> void:
	if _selected_id < 0:
		_set_status("nothing selected", false)
		return
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		return
	var key := "start" if entity.has("start") else "origin"
	var origin := StructurePlan.vec3_of(entity.get(key))
	if is_equal_approx(origin.y, _active_base):
		_set_status("already at %.0f m" % _active_base)
		return
	_snapshot()
	origin.y = _active_base
	entity[key] = [origin.x, origin.y, origin.z]
	_request_rebake(true)
	_refresh_panel()
	_set_status("moved #%d to level %.0f m" % [_selected_id, _active_base])


func _snap_selected_to_grid() -> void:
	if _selected_id < 0:
		_set_status("nothing selected", false)
		return
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		return
	var kind := StructurePlan.kind_of_entity(entity)
	var key := "start" if entity.has("start") else "origin"
	var origin := StructurePlan.vec3_of(entity.get(key))
	var snapped := Vector3(roundf(origin.x), roundf(origin.y * 2.0) / 2.0, roundf(origin.z))
	snapped = _clamp_origin_to_grid(snapped, kind, _entity_dims(entity, kind))
	if snapped.is_equal_approx(origin):
		_set_status("already on grid")
		return
	_snapshot()
	entity[key] = [snapped.x, snapped.y, snapped.z]
	_request_rebake(true)
	_refresh_panel()
	_set_status("snapped #%d" % _selected_id)


func _cycle_selection_material(direction: int) -> void:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		_set_status("select a surface to recolour", false)
		return
	var ids := StructureMaterialLibrary.studio_material_ids()
	if ids.is_empty():
		return
	var keys := _library_keys_for_selection()
	if keys.is_empty():
		return
	var current := StructureMaterialLibrary.normalize_id(str((keys["entity"] as Dictionary).get(str(keys["material"]), "painted")))
	var index := ids.find(current)
	if index < 0:
		index = 0
	else:
		index = (index + direction + ids.size()) % ids.size()
	var next_id := ids[index]
	_snapshot()
	(keys["entity"] as Dictionary)[str(keys["material"])] = next_id
	(_lib[_armed_slot] as Dictionary)["material"] = next_id
	_sync_plan_palette_from_library()
	_request_rebake(true)
	_refresh_panel()
	_set_status("material → %s" % StructureMaterialLibrary.label_of(next_id))


## Rotate room/deck footprint 90° about its origin (walls get axis swap).
func _rotate_selected(degrees: int) -> void:
	if _selected_id < 0:
		_set_status("nothing selected", false)
		return
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		return
	var kind := StructurePlan.kind_of_entity(entity)
	_snapshot()
	match kind:
		"wall":
			var axis := str(entity.get("axis", "x"))
			entity["axis"] = "z" if axis == "x" else "x"
		"deck":
			var plate: Array = (entity.get("size", [1.0, 1.0]) as Array).duplicate()
			if plate.size() < 2:
				plate.append(1.0)
			var tmp_w: float = float(plate[0])
			plate[0] = float(plate[1])
			plate[1] = tmp_w
			entity["size"] = plate
			_rotate_plate_openings(entity, degrees)
		"room":
			var size: Array = (entity.get("size", [4, 3, 4]) as Array).duplicate()
			var tmp_w: float = float(size[0])
			size[0] = float(size[2])
			size[2] = tmp_w
			entity["size"] = size
			_rotate_room_faces(entity, degrees)
		_:
			_set_status("cannot rotate this entity", false)
			return
	_request_rebake(true)
	_refresh_panel()
	_set_status("rotated #%d %d°" % [_selected_id, degrees])


func _rotate_room_faces(entity: Dictionary, degrees: int) -> void:
	if not entity.has("openings"):
		return
	var size := StructurePlan.vec3_of(entity.get("size"), Vector3(4, 3, 4))
	for opening_variant in entity["openings"] as Array:
		var opening := opening_variant as Dictionary
		var face := str(opening.get("face", ""))
		if face in ["floor", "ceiling"]:
			_rotate_plate_opening_dict(opening, degrees, size.x, size.z)
			continue
		opening["face"] = StructureStudioMath.rotate_cardinal_face(face, degrees)


func _rotate_plate_openings(entity: Dictionary, degrees: int) -> void:
	var plate := StructurePlan.vec2_of(entity.get("size"), Vector2(1, 1))
	for opening_variant in entity.get("openings", []) as Array:
		_rotate_plate_opening_dict(opening_variant as Dictionary, degrees, plate.x, plate.y)


func _rotate_plate_opening_dict(opening: Dictionary, degrees: int, width: float, length: float) -> void:
	var off := StructurePlan.vec2_of(opening.get("offset"), Vector2.ZERO)
	var hole := StructurePlan.vec2_of(opening.get("size"), Vector2(1, 1))
	var rotated: Dictionary = StructureStudioMath.rotate_plate_opening(off, hole, width, length, degrees)
	var next_off: Vector2 = rotated["offset"]
	var next_hole: Vector2 = rotated["size"]
	opening["offset"] = [next_off.x, next_off.y]
	opening["size"] = [next_hole.x, next_hole.y]


func _stack_selected_above() -> void:
	if _selected_id < 0:
		_set_status("nothing selected", false)
		return
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		return
	var kind := StructurePlan.kind_of_entity(entity)
	var lift := DEFAULT_WALL_HEIGHT
	if kind == "room":
		lift = float(StructurePlan.vec3_of(entity.get("size"), Vector3(4, 3, 4)).y)
	elif kind == "wall":
		lift = float(entity.get("height", DEFAULT_WALL_HEIGHT))
	_snapshot()
	var copy := _plan.duplicate_entity(_selected_id, Vector3(0, lift, 0))
	if copy.is_empty():
		_set_status("stack failed", false)
		return
	_selected_id = int(copy.get("id", -1))
	_active_base = StructurePlan.vec3_of(copy.get("start", copy.get("origin"))).y
	_build_grid_lines()
	_request_rebake(true)
	_refresh_panel()
	_set_status("stacked → #%d at %.0f m" % [_selected_id, _active_base])


func _refresh_entity_list() -> void:
	if _entity_list == null:
		return
	for child in _entity_list.get_children():
		child.queue_free()
	var entries: Array = []
	for collection in [_plan.rooms, _plan.walls, _plan.decks]:
		for entity_variant in collection:
			var entity := entity_variant as Dictionary
			var kind := StructurePlan.kind_of_entity(entity)
			if _entity_list_filter != "all" and kind != _entity_list_filter:
				continue
			entries.append(entity)
	entries.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	for entity_variant in entries:
		var entity: Dictionary = entity_variant
		var id := int(entity.get("id", -1))
		var kind := StructurePlan.kind_of_entity(entity)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "#%d  %s" % [id, kind]
		if id == _selected_id:
			btn.add_theme_color_override("font_color", HudStyle.C_AMBER)
		btn.pressed.connect(func() -> void:
			_selected_id = id
			_tool = Tool.SELECT
			if _entity_bounds.has(id):
				_cam_focus = (_entity_bounds[id] as AABB).get_center()
			_update_selection_visual()
			_refresh_panel()
		)
		_entity_list.add_child(btn)


func _eyedrop_selection_to_library() -> void:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		_set_status("select a surface to sample", false)
		return
	var kind := StructurePlan.kind_of_entity(entity)
	var mat_id := "painted"
	var color_raw: Variant = null
	if kind == "room" or (kind == "wall" and (entity.has("material_in") or entity.has("color_in"))):
		if _armed_slot == "in":
			mat_id = str(entity.get("material_in", "wood"))
			color_raw = entity.get("color_in", entity.get("color", null))
		else:
			mat_id = str(entity.get("material_out", entity.get("material", "painted")))
			color_raw = entity.get("color_out", entity.get("color", null))
	else:
		mat_id = str(entity.get("material", entity.get("material_out", "painted")))
		color_raw = entity.get("color", entity.get("color_out", null))
	mat_id = StructureMaterialLibrary.normalize_id(mat_id)
	(_lib[_armed_slot] as Dictionary)["material"] = mat_id
	if color_raw is Array and (color_raw as Array).size() >= 3:
		(_lib[_armed_slot] as Dictionary)["color"] = (color_raw as Array).duplicate()
	else:
		var sample := StructureMaterialLibrary.default_color(mat_id)
		(_lib[_armed_slot] as Dictionary)["color"] = [sample.r, sample.g, sample.b]
	_sync_plan_palette_from_library()
	_set_status("sampled %s → %s" % [
		StructureMaterialLibrary.label_of(mat_id),
		"outside" if _armed_slot == "out" else "inside",
	])
	_refresh_panel()


func _handle_mouse_button(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_orbiting = button.pressed
		return
	if button.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = button.pressed
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
		_cam_distance = maxf(6.0, _cam_distance * 0.88)
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
		_cam_distance = minf(220.0, _cam_distance * 1.14)
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_on_left_press(button.position)
	else:
		_on_left_release(button.position)


func _on_left_press(screen_pos: Vector2) -> void:
	if _tool == Tool.SELECT:
		if _selected_id >= 0 and _try_grab_handle(screen_pos):
			return
		if _selected_id >= 0 and _try_grab_gizmo(screen_pos):
			return
		var picked := _pick_entity(screen_pos)
		## Empty click clears selection so the inspector returns to guidance.
		_selected_id = picked
		_update_selection_visual()
		_refresh_panel()
		return
	if _tool == Tool.OPENING:
		_begin_opening_drag(screen_pos)
		return
	var grid_point := _mouse_to_grid(screen_pos)
	if grid_point == Vector3.INF:
		return
	_drag_start = grid_point
	_dragging = true


func _on_left_release(screen_pos: Vector2) -> void:
	if _opening_drag:
		_commit_opening(screen_pos)
		return
	if _gizmo_axis >= 0:
		_gizmo_axis = -1
		_flush_rebake()
		if _resize_mode:
			_resize_mode = false
			_set_status("resize committed")
			_refresh_panel()
		else:
			_set_status("move committed")
		return
	if not _dragging:
		return
	_dragging = false
	_hide_ghost()
	var grid_point := _mouse_to_grid(screen_pos)
	if grid_point == Vector3.INF:
		return
	var a := _drag_start
	var b := grid_point
	match _tool:
		Tool.WALL:
			_place_wall(a, b)
		Tool.ROOM:
			_place_rect_entity(a, b, true)
		Tool.DECK:
			_place_rect_entity(a, b, false)


func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	if _orbiting:
		_cam_yaw -= motion.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch + motion.relative.y * 0.006, 0.15, 1.45)
	elif _panning:
		var right := _camera.global_transform.basis.x
		var forward := -_camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var scale := _cam_distance * 0.0016
		_cam_focus += (-right * motion.relative.x + forward * motion.relative.y) * scale
	elif _gizmo_axis >= 0:
		_drag_gizmo(motion.position)
	elif _opening_drag:
		_update_opening_drag(motion.position)
	elif _dragging:
		_update_ghost(motion.position)
		_update_drag_status(motion.position)


func _update_drag_status(screen_pos: Vector2) -> void:
	if _status_label == null:
		return
	var current := _mouse_to_grid(screen_pos)
	if current == Vector3.INF:
		return
	var a := _drag_start
	var b := current
	match _tool:
		Tool.WALL:
			var dx := absf(b.x - a.x)
			var dz := absf(b.z - a.z)
			var axis := "x" if dx >= dz else "z"
			var length := maxf(dx if axis == "x" else dz, 1.0)
			_status_label.text = "wall %s  %.0f m" % [axis, roundf(length)]
		Tool.ROOM:
			var w := maxf(absf(b.x - a.x), 2.0)
			var l := maxf(absf(b.z - a.z), 2.0)
			_status_label.text = "room  %.0f × %.0f m" % [roundf(w), roundf(l)]
		Tool.DECK:
			var w := maxf(absf(b.x - a.x), 1.0)
			var l := maxf(absf(b.z - a.z), 1.0)
			_status_label.text = "deck  %.0f × %.0f m" % [roundf(w), roundf(l)]


# ── Tools ────────────────────────────────────────────────────────────────────

func _set_tool(tool: Tool) -> void:
	if tool == Tool.ITEMS:
		_set_status("Items / equipment — coming in a later pass", false)
		return
	_tool = tool
	_dragging = false
	_hover_last_screen = Vector2(-9999, -9999)
	_hide_ghost()
	_refresh_panel()


func _place_wall(a: Vector3, b: Vector3) -> void:
	var spec := StructureStudioMath.wall_from_drag(a, b, _active_base, _grid_width, _grid_length)
	var start: Vector3 = spec["start"]
	var axis := str(spec["axis"])
	var length := float(spec["length"])
	if not _is_buildable_corner(start) and _context == "vessel":
		_set_status("wall start outside buildable deck", false)
		return
	if length < 1.0:
		_set_status("wall clipped to empty by grid edge", false)
		return
	_snapshot()
	var wall := _plan.add_wall(start, axis, length, DEFAULT_WALL_HEIGHT)
	_stamp_library_style(wall, false)
	_selected_id = int(wall.get("id", -1))
	_set_status("wall %s ×%.0f m" % [axis, length])
	_request_rebake(true)
	_refresh_panel()


func _place_rect_entity(a: Vector3, b: Vector3, as_room: bool) -> void:
	var min_size := 2.0 if as_room else 1.0
	var spec := StructureStudioMath.rect_from_drag(a, b, _active_base, min_size)
	var min_pt: Vector3 = spec["origin"]
	var w: float = minf(float(spec["width"]), float(_grid_width) - min_pt.x)
	var l: float = minf(float(spec["length"]), float(_grid_length) - min_pt.z)
	if w < min_size or l < min_size:
		_set_status("footprint too small for this grid", false)
		return
	_snapshot()
	if as_room:
		var room := _plan.add_room(min_pt, Vector3(w, DEFAULT_WALL_HEIGHT, l))
		_stamp_library_style(room, true)
		_selected_id = int(room.get("id", -1))
		_set_status("room %.0f×%.0f×%.0f" % [w, DEFAULT_WALL_HEIGHT, l])
	else:
		var deck := _plan.add_deck(min_pt, Vector2(w, l))
		_stamp_library_style(deck, false)
		_selected_id = int(deck.get("id", -1))
		_set_status("deck plate %.0f×%.0f" % [w, l])
	_request_rebake(true)
	_refresh_panel()


func _is_buildable_corner(plan_point: Vector3) -> bool:
	if plan_point.x < 0.0 or plan_point.z < 0.0:
		return false
	if plan_point.x > float(_grid_width) or plan_point.z > float(_grid_length):
		return false
	if _deck_grid == null:
		return true
	## Corner is buildable if any adjacent cell exists.
	var base_x := int(plan_point.x)
	var base_z := int(plan_point.z)
	for ix in 2:
		for iz in 2:
			var cx: int = base_x + ix - 1
			var cz: int = base_z + iz - 1
			if cx < 0 or cz < 0 or cx >= _grid_width or cz >= _grid_length:
				continue
			if _deck_grid.cell_shape(cx, cz) != DeckGrid.CellShape.NONE:
				return true
	return false


func _clamp_origin_to_grid(origin: Vector3, kind: String, dims: Vector3) -> Vector3:
	return StructureStudioMath.clamp_origin(origin, kind, dims, _grid_width, _grid_length)


# ── Openings: one context shared by hover, drag and commit ───────────────────

var _opening_drag := false
var _opening_ctx: Dictionary = {}
var _opening_anchor := Vector2.ZERO ## walls: (along, 0) · plates: (u, v)


func _opening_defaults() -> Dictionary:
	return StructureStudioOpenings.defaults_for(_opening_type)


## Resolves what an opening interaction at this cursor position would cut:
## a plan wall, a room wall face, a room roof/floor, or a deck plate.
func _opening_context_at(screen_pos: Vector2) -> Dictionary:
	var hit := _pick_entity_hit(screen_pos)
	if hit.is_empty():
		return {}
	var entity := _plan.entity_by_id(int(hit["id"]))
	if entity.is_empty():
		return {}
	var p: Vector3 = (hit["point"] as Vector3) - _plan_offset
	if entity.has("axis"):
		return {
			"kind": "wall", "entity": entity,
			"axis_z": str(entity.get("axis")) == "z",
			"start": StructurePlan.vec3_of(entity.get("start")),
			"length": float(entity.get("length", 1.0)),
			"thickness": float(entity.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS)),
			"point": p,
		}
	if entity.has("size") and (entity.get("size") as Array).size() == 3:
		var origin := StructurePlan.vec3_of(entity.get("origin"))
		var size := StructurePlan.vec3_of(entity.get("size"))
		var top := origin.y + size.y
		if absf(p.y - top) < 0.35 or absf(p.y - origin.y) < 0.35:
			var face := "ceiling" if absf(p.y - top) < 0.35 else "floor"
			## No visible roof (view toggle or open-top room): a click from
			## above punches the floor instead of an invisible ceiling.
			if face == "ceiling" and (not _show_roofs or not bool(entity.get("roof", true))):
				face = "floor"
			return {
				"kind": "room_plate", "entity": entity,
				"face": face,
				"origin": origin, "extent": Vector2(size.x, size.z),
				"plane_y": top if face == "ceiling" else origin.y,
				"point": p,
			}
		var candidates := {
			"n": absf(p.z - origin.z), "s": absf(p.z - (origin.z + size.z)),
			"w": absf(p.x - origin.x), "e": absf(p.x - (origin.x + size.x)),
		}
		var face := "n"
		var best := INF
		for key in candidates.keys():
			if float(candidates[key]) < best:
				best = float(candidates[key])
				face = str(key)
		return {
			"kind": "room_wall", "entity": entity, "face": face,
			"origin": origin, "size": size,
			"length": size.x if face in ["n", "s"] else size.z,
			"point": p,
		}
	if entity.has("size"):
		var plate: Array = entity.get("size", [1.0, 1.0])
		var origin := StructurePlan.vec3_of(entity.get("origin"))
		return {
			"kind": "plate", "entity": entity, "origin": origin,
			"extent": Vector2(float(plate[0]), float(plate[1]) if plate.size() > 1 else 1.0),
			"plane_y": origin.y, "point": p,
		}
	return {}


func _ctx_along(ctx: Dictionary, p: Vector3) -> float:
	match str(ctx.get("kind")):
		"wall":
			var start := ctx["start"] as Vector3
			return (p.z - start.z) if bool(ctx["axis_z"]) else (p.x - start.x)
		"room_wall":
			var origin := ctx["origin"] as Vector3
			return (p.x - origin.x) if str(ctx["face"]) in ["n", "s"] else (p.z - origin.z)
		_:
			return 0.0


func _ctx_uv(ctx: Dictionary, p: Vector3) -> Vector2:
	var origin := ctx["origin"] as Vector3
	return Vector2(p.x - origin.x, p.z - origin.z)


func _wall_span(ctx: Dictionary, a: float, b: float, dragged: bool) -> Vector2:
	return StructureStudioOpenings.wall_span(
		float(ctx["length"]), a, b, dragged, float(_opening_defaults()["width"])
	)


func _plate_rect(ctx: Dictionary, a: Vector2, b: Vector2, dragged: bool) -> Rect2:
	return StructureStudioOpenings.plate_rect(ctx["extent"] as Vector2, a, b, dragged)


func _opening_geom(ctx: Dictionary, span: Vector2, rect: Rect2) -> Dictionary:
	var defaults := _opening_defaults()
	var sill := float(defaults["sill"])
	var height := float(defaults["height"])
	match str(ctx.get("kind")):
		"wall":
			return StructureStudioOpenings.wall_geom(
				ctx["start"] as Vector3, bool(ctx["axis_z"]), float(ctx["thickness"]), span, sill, height
			)
		"room_wall":
			return StructureStudioOpenings.room_wall_geom(
				ctx["origin"] as Vector3, ctx["size"] as Vector3, str(ctx["face"]), span, sill, height
			)
		"room_plate", "plate":
			return StructureStudioOpenings.plate_geom(
				ctx["origin"] as Vector3, float(ctx["plane_y"]), rect
			)
	return {}


func _begin_opening_drag(screen_pos: Vector2) -> void:
	_opening_ctx = _opening_context_at(screen_pos)
	if _opening_ctx.is_empty():
		_set_status("opening: aim at a wall, deck or room", false)
		return
	var p := _opening_ctx["point"] as Vector3
	if str(_opening_ctx["kind"]) in ["wall", "room_wall"]:
		_opening_anchor = Vector2(_ctx_along(_opening_ctx, p), 0.0)
	else:
		_opening_anchor = _ctx_uv(_opening_ctx, p)
	_opening_drag = true


func _update_opening_drag(screen_pos: Vector2) -> void:
	if _opening_ctx.is_empty():
		return
	var hit := _pick_entity_hit(screen_pos)
	var p: Vector3 = ((hit["point"] as Vector3) - _plan_offset) if not hit.is_empty() else (_opening_ctx["point"] as Vector3)
	var geom: Dictionary
	if str(_opening_ctx["kind"]) in ["wall", "room_wall"]:
		geom = _opening_geom(_opening_ctx, _wall_span(_opening_ctx, _opening_anchor.x, _ctx_along(_opening_ctx, p), true), Rect2())
	else:
		geom = _opening_geom(_opening_ctx, Vector2.ZERO, _plate_rect(_opening_ctx, _opening_anchor, _ctx_uv(_opening_ctx, p), true))
	if not geom.is_empty():
		(_opening_ghost.mesh as BoxMesh).size = geom["size"] as Vector3
		_opening_ghost.position = (geom["center"] as Vector3) + _plan_offset
		_opening_ghost.visible = true


func _commit_opening(screen_pos: Vector2) -> void:
	var ctx := _opening_ctx
	_opening_drag = false
	_opening_ctx = {}
	if ctx.is_empty():
		return
	var hit := _pick_entity_hit(screen_pos)
	var p: Vector3 = ((hit["point"] as Vector3) - _plan_offset) if not hit.is_empty() else (ctx["point"] as Vector3)
	var entity := ctx["entity"] as Dictionary
	_snapshot()
	if str(ctx["kind"]) in ["wall", "room_wall"]:
		var current := _ctx_along(ctx, p)
		var dragged := absf(current - _opening_anchor.x) > 0.3
		var span := _wall_span(ctx, _opening_anchor.x, current, dragged)
		var spec := _opening_defaults()
		spec["offset"] = span.x
		spec["width"] = span.y
		if str(ctx["kind"]) == "room_wall":
			spec["face"] = str(ctx["face"])
		(entity["openings"] as Array).append(spec)
		_set_status("%s  %.1f m" % [str(spec["type"]), span.y])
	else:
		var uv := _ctx_uv(ctx, p)
		var dragged := uv.distance_to(_opening_anchor) > 0.3
		var rect := _plate_rect(ctx, _opening_anchor, uv, dragged)
		var face := str(ctx.get("face", "floor"))
		var hole_type := StructureStudioOpenings.plate_opening_type(_opening_type, face)
		var hole := {
			"type": hole_type,
			"offset": [rect.position.x, rect.position.y],
			"size": [rect.size.x, rect.size.y],
		}
		if str(ctx["kind"]) == "room_plate":
			hole["face"] = face
		(entity["openings"] as Array).append(hole)
		_set_status("%s  %.0f × %.0f m" % [hole_type, rect.size.x, rect.size.y])
	_request_rebake(true)
	_refresh_panel()



# ── Picking / gizmo ──────────────────────────────────────────────────────────

func _mouse_ray(screen_pos: Vector2) -> Array:
	return [_camera.project_ray_origin(screen_pos), _camera.project_ray_normal(screen_pos)]


func _mouse_to_grid(screen_pos: Vector2) -> Vector3:
	var ray := _mouse_ray(screen_pos)
	var origin := ray[0] as Vector3
	var direction := ray[1] as Vector3
	if absf(direction.y) < 0.0001:
		return Vector3.INF
	var t := (_active_base - origin.y) / direction.y
	if t < 0.0:
		return Vector3.INF
	var world := origin + direction * t
	var plan_point := world - _plan_offset
	plan_point.x = clampf(roundf(plan_point.x), 0.0, float(_grid_width))
	plan_point.z = clampf(roundf(plan_point.z), 0.0, float(_grid_length))
	plan_point.y = _active_base
	if _context == "vessel" and _deck_grid != null and not _is_buildable_corner(plan_point):
		plan_point = _nearest_buildable_corner(plan_point)
	return plan_point


func _nearest_buildable_corner(plan_point: Vector3) -> Vector3:
	## Search expanding rings for a valid deck corner; keep Y at build level.
	if _is_buildable_corner(plan_point):
		return plan_point
	var best := Vector3.INF
	var best_dist := INF
	for radius in range(1, maxi(_grid_width, _grid_length) + 1):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var candidate := Vector3(
					clampf(plan_point.x + float(dx), 0.0, float(_grid_width)),
					_active_base,
					clampf(plan_point.z + float(dz), 0.0, float(_grid_length)),
				)
				if not _is_buildable_corner(candidate):
					continue
				var dist := candidate.distance_squared_to(plan_point)
				if dist < best_dist:
					best_dist = dist
					best = candidate
		if best != Vector3.INF:
			return best
	return Vector3.INF


func _pick_entity(screen_pos: Vector2) -> int:
	var hit := _pick_entity_hit(screen_pos)
	return int(hit.get("id", -1))


func _pick_entity_hit(screen_pos: Vector2) -> Dictionary:
	var ray := _mouse_ray(screen_pos)
	var origin := ray[0] as Vector3
	var direction := ray[1] as Vector3
	var best_t := INF
	var best_id := -1
	for id in _entity_bounds.keys():
		## Ghosted upper-level geometry is view-only: the cursor passes
		## straight through it to the deck being edited.
		if float(_entity_base_y.get(id, 0.0)) >= _ghost_threshold:
			continue
		var aabb := _entity_bounds[id] as AABB
		var hit_variant: Variant = aabb.grow(0.05).intersects_ray(origin, direction)
		if hit_variant != null:
			var t := (hit_variant as Vector3).distance_to(origin)
			if t < best_t:
				best_t = t
				best_id = int(id)
	if best_id < 0:
		return {}
	return {"id": best_id, "point": origin + direction * best_t}


func _try_grab_gizmo(screen_pos: Vector2) -> bool:
	if _gizmo_root == null or not _gizmo_root.visible:
		return false
	var ray := _mouse_ray(screen_pos)
	var origin := ray[0] as Vector3
	var direction := ray[1] as Vector3
	for axis in 3:
		var arrow := _gizmo_root.get_child(axis) as Node3D
		var center: Vector3 = arrow.global_position
		var aabb := AABB(center - Vector3.ONE * 0.6, Vector3.ONE * 1.2)
		if aabb.intersects_ray(origin, direction) != null:
			_gizmo_axis = axis
			_resize_mode = false
			var entity := _plan.entity_by_id(_selected_id)
			_gizmo_start_origin = StructurePlan.vec3_of(entity.get("start", entity.get("origin")))
			_gizmo_line_origin = _gizmo_root.global_position
			_gizmo_last_applied = Vector3.INF
			_gizmo_grab_value = _axis_value_at(screen_pos, axis)
			_stage_snapshot()
			return true
	return false


## Face handles: pads on every face of the selection. Dragging one pulls that
## face — the resize interaction, no double-click involved.
func _try_grab_handle(screen_pos: Vector2) -> bool:
	if _handle_root == null or not _handle_root.visible:
		return false
	var ray := _mouse_ray(screen_pos)
	var origin := ray[0] as Vector3
	var direction := ray[1] as Vector3
	for index in _handle_root.get_child_count():
		var pad := _handle_root.get_child(index) as Node3D
		if not pad.visible:
			continue
		var reach := 0.55 * maxf(pad.scale.x, 0.5)
		var aabb := AABB(pad.global_position - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
		if aabb.intersects_ray(origin, direction) != null:
			@warning_ignore("integer_division")
			var axis := index / 2
			var sign := 1 if index % 2 == 0 else -1
			_begin_face_resize(axis, sign, pad.global_position, screen_pos)
			return true
	return false


func _begin_face_resize(axis: int, sign: int, line_origin: Vector3, screen_pos: Vector2) -> void:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty():
		return
	_gizmo_axis = axis
	_resize_mode = true
	_resize_sign = sign
	_resize_start_primary = StructurePlan.vec3_of(entity.get("start", entity.get("origin")))
	if entity.has("axis"):
		_resize_start_dims = Vector3(
			float(entity.get("length", 1.0)),
			float(entity.get("height", 3.0)),
			float(entity.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS)),
		)
	elif entity.has("size") and (entity.get("size") as Array).size() == 3:
		var size_list: Array = entity.get("size")
		_resize_start_dims = Vector3(float(size_list[0]), float(size_list[1]), float(size_list[2]))
	else:
		var plate_size: Array = entity.get("size", [1.0, 1.0])
		_resize_start_dims = Vector3(
			float(plate_size[0]),
			float(entity.get("thickness", StructurePlan.DEFAULT_PLATE_THICKNESS)),
			float(plate_size[1]) if plate_size.size() > 1 else 1.0,
		)
	_gizmo_line_origin = line_origin
	_gizmo_last_applied = Vector3.INF
	_gizmo_grab_value = _axis_value_at(screen_pos, axis)
	_stage_snapshot()
	_set_status("resizing — release to commit")



func _axis_value_at(screen_pos: Vector2, axis: int) -> float:
	## Parameter of the closest point on the drag axis line to the mouse ray.
	## The line origin is FROZEN at grab time (_gizmo_line_origin): measuring
	## against a moving origin oscillates.
	var ray := _mouse_ray(screen_pos)
	var ray_origin := ray[0] as Vector3
	var ray_direction := ray[1] as Vector3
	var line_direction := Vector3.RIGHT
	match axis:
		1:
			line_direction = Vector3.UP
		2:
			line_direction = Vector3.BACK
	var w0 := _gizmo_line_origin - ray_origin
	var b := line_direction.dot(ray_direction)
	var d := line_direction.dot(w0)
	var e := ray_direction.dot(w0)
	var denominator := 1.0 - b * b
	if absf(denominator) < 0.0001:
		return 0.0
	return (b * e - d) / denominator


func _drag_gizmo(screen_pos: Vector2) -> void:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty():
		return
	var delta := _axis_value_at(screen_pos, _gizmo_axis) - _gizmo_grab_value
	var snap := 0.5 if _gizmo_axis == 1 else GRID_SNAP
	var snapped_delta := roundf(delta / snap) * snap
	if _resize_mode:
		_apply_face_resize(entity, snapped_delta)
		return
	var new_origin := _gizmo_start_origin
	match _gizmo_axis:
		0:
			new_origin.x += snapped_delta
		1:
			new_origin.y += snapped_delta
		2:
			new_origin.z += snapped_delta
	new_origin.y = maxf(new_origin.y, 0.0)
	var kind := StructurePlan.kind_of_entity(entity)
	var dims := Vector3.ONE
	if kind == "wall":
		dims = Vector3(float(entity.get("length", 1.0)), float(entity.get("height", 3.0)), 0.0)
	elif kind == "room":
		dims = StructurePlan.vec3_of(entity.get("size"), Vector3(2, 3, 2))
	elif kind == "deck":
		var plate: Array = entity.get("size", [1.0, 1.0])
		dims = Vector3(float(plate[0]), 0.0, float(plate[1]) if plate.size() > 1 else 1.0)
	new_origin = _clamp_origin_to_grid(new_origin, kind, dims)
	if new_origin.is_equal_approx(_gizmo_last_applied):
		return ## same snapped cell — no churn, no rebake
	if new_origin.is_equal_approx(_gizmo_start_origin) and _gizmo_last_applied == Vector3.INF:
		return ## has not left the starting cell yet
	_commit_staged_snapshot()
	_gizmo_last_applied = new_origin
	var key := "start" if entity.has("start") else "origin"
	entity[key] = [new_origin.x, new_origin.y, new_origin.z]
	_request_rebake(false)
	_update_selection_visual()


## Pulls the grabbed face outward (+delta along the face normal grows the
## entity; inward shrinks). Negative-side faces shift the origin so the
## opposite face stays put.
func _apply_face_resize(entity: Dictionary, snapped_delta: float) -> void:
	var face_move := snapped_delta * float(_resize_sign)
	var marker := Vector3(face_move, float(_gizmo_axis), 0.0)
	if marker.is_equal_approx(_gizmo_last_applied):
		return
	if absf(face_move) < 0.001 and _gizmo_last_applied == Vector3.INF:
		return ## no movement yet
	_commit_staged_snapshot()
	_gizmo_last_applied = marker
	var origin := _resize_start_primary
	if entity.has("axis"):
		var wall_axis := 0 if str(entity.get("axis")) == "x" else 2
		if _gizmo_axis == wall_axis:
			var new_length := maxf(_resize_start_dims.x + face_move, 1.0)
			entity["length"] = new_length
			if _resize_sign < 0:
				origin[wall_axis] = _resize_start_primary[wall_axis] - (new_length - _resize_start_dims.x)
				entity["start"] = [origin.x, origin.y, origin.z]
		elif _gizmo_axis == 1:
			entity["height"] = clampf(_resize_start_dims.y + face_move, 0.5, 12.0)
		else:
			entity["thickness"] = clampf(_resize_start_dims.z + face_move, 0.05, 0.5)
	elif entity.has("size") and (entity.get("size") as Array).size() == 3:
		var size_list: Array = entity.get("size")
		var dims := [_resize_start_dims.x, _resize_start_dims.y, _resize_start_dims.z]
		var minimums := [2.0, 1.5, 2.0]
		var new_dim := maxf(float(dims[_gizmo_axis]) + face_move, float(minimums[_gizmo_axis]))
		size_list[_gizmo_axis] = new_dim
		if _resize_sign < 0 and _gizmo_axis != 1:
			origin[_gizmo_axis] = _resize_start_primary[_gizmo_axis] - (new_dim - float(dims[_gizmo_axis]))
			entity["origin"] = [origin.x, origin.y, origin.z]
	else:
		if _gizmo_axis == 1:
			entity["thickness"] = clampf(_resize_start_dims.y + face_move, 0.05, 0.5)
		else:
			var plate_size: Array = entity.get("size", [1.0, 1.0])
			var dim_index := 0 if _gizmo_axis == 0 else 1
			var start_dim := _resize_start_dims.x if dim_index == 0 else _resize_start_dims.z
			var new_dim := maxf(start_dim + face_move, 1.0)
			plate_size[dim_index] = new_dim
			if _resize_sign < 0:
				origin[_gizmo_axis] = _resize_start_primary[_gizmo_axis] - (new_dim - start_dim)
				entity["origin"] = [origin.x, origin.y, origin.z]
	## Keep resized footprints inside the host grid.
	var kind := StructurePlan.kind_of_entity(entity)
	if kind in ["room", "deck", "wall"]:
		var key := "start" if entity.has("start") else "origin"
		var origin_now := StructurePlan.vec3_of(entity.get(key))
		var dims := Vector3.ONE
		if kind == "room":
			dims = StructurePlan.vec3_of(entity.get("size"), Vector3(2, 3, 2))
		elif kind == "deck":
			var plate: Array = entity.get("size", [1.0, 1.0])
			dims = Vector3(float(plate[0]), 0.0, float(plate[1]) if plate.size() > 1 else 1.0)
		elif kind == "wall":
			dims = Vector3(float(entity.get("length", 1.0)), 0.0, 0.0)
		var clamped := _clamp_origin_to_grid(origin_now, kind, dims)
		entity[key] = [clamped.x, clamped.y, clamped.z]
	_request_rebake(false)
	_update_selection_visual()


# ── Ghost preview ────────────────────────────────────────────────────────────

func _update_ghost(screen_pos: Vector2) -> void:
	var current := _mouse_to_grid(screen_pos)
	if current == Vector3.INF:
		return
	var a := _drag_start
	var b := current
	var min_pt := Vector3(minf(a.x, b.x), _active_base, minf(a.z, b.z))
	var size := Vector3(maxf(absf(b.x - a.x), 0.2), 0.3, maxf(absf(b.z - a.z), 0.2))
	if _tool == Tool.WALL:
		if absf(b.x - a.x) >= absf(b.z - a.z):
			size = Vector3(maxf(absf(b.x - a.x), 0.5), DEFAULT_WALL_HEIGHT, 0.2)
			min_pt.z = roundf(a.z) - 0.1
		else:
			size = Vector3(0.2, DEFAULT_WALL_HEIGHT, maxf(absf(b.z - a.z), 0.5))
			min_pt.x = roundf(a.x) - 0.1
	elif _tool == Tool.ROOM:
		## Match placement mins so the ghost agrees with the commit.
		size.x = maxf(size.x, 2.0)
		size.z = maxf(size.z, 2.0)
		size.y = DEFAULT_WALL_HEIGHT
	elif _tool == Tool.DECK:
		size.x = maxf(size.x, 1.0)
		size.z = maxf(size.z, 1.0)
		size.y = 0.2
	_ghost.visible = true
	(_ghost.mesh as BoxMesh).size = size
	_ghost.position = _plan_offset + min_pt + size * 0.5


func _hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false


func _update_selection_visual() -> void:
	var has_selection := _selected_id >= 0 and _entity_bounds.has(_selected_id)
	_selection_box.visible = has_selection
	_gizmo_root.visible = has_selection
	if _handle_root != null:
		_handle_root.visible = has_selection
	if not has_selection:
		return
	var aabb := _entity_bounds[_selected_id] as AABB
	(_selection_box.mesh as BoxMesh).size = aabb.size + Vector3.ONE * 0.1
	_selection_box.position = aabb.get_center()
	_gizmo_root.position = aabb.get_center()
	## One resize pad on every face, just proud of the surface.
	var center := aabb.get_center()
	var half := aabb.size * 0.5
	var pad_scale := maxf(_gizmo_root.scale.x, 0.6)
	var directions := [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD,
	]
	var extents := [half.x, half.x, half.y, half.y, half.z, half.z]
	for index in 6:
		var pad := _handle_root.get_child(index) as Node3D
		pad.position = center + (directions[index] as Vector3) * (float(extents[index]) + 0.45 * pad_scale)


# ── Persistence ──────────────────────────────────────────────────────────────

func _save_plan(plan_name: String) -> void:
	var path := StructureStudioDocument.path_for_name(plan_name)
	if path.is_empty():
		_set_status("name the structure first", false)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STRUCTURES_DIR))
	if FileAccess.file_exists(path):
		_ask_confirm(
			"Overwrite existing file %s?" % path.get_file(),
			func() -> void: _save_plan_now(path),
		)
		return
	_save_plan_now(path)


func _ask_confirm(message: String, action: Callable) -> void:
	_pending_confirm_action = action
	if _confirm_dialog == null:
		action.call()
		return
	_confirm_dialog.dialog_text = message
	_confirm_dialog.popup_centered()


func _save_plan_now(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("save failed: %s" % path, false)
		return
	file.store_string(JSON.stringify(_plan.to_dict(), "\t"))
	file.close()
	_clear_dirty()
	_load_list_dirty = true
	_remember_recent_path(path)
	_set_status("saved %s" % path.get_file())
	_refresh_panel()


func _load_plan(path: String) -> void:
	_confirm_if_dirty(
		"Load %s and discard unsaved changes?" % path.get_file(),
		func() -> void: _load_plan_now(path),
	)


func _load_plan_now(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("load failed: %s" % path, false)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary or not StructurePlan.is_plan(parsed as Dictionary):
		_set_status("not a structure plan: %s" % path.get_file(), false)
		return
	if not _plan.is_empty():
		_snapshot()
	_plan = StructurePlan.from_dict(parsed as Dictionary)
	_context = _plan.context if _plan.context in StructurePlan.CONTEXTS else "vessel"
	if _context == "vessel":
		if not _plan.hull_id.is_empty():
			_hull_id = _plan.hull_id
		else:
			_plan.hull_id = _hull_id
	_selected_id = -1
	_active_base = 0.0
	_apply_host_metrics()
	_sync_hull_option()
	_sync_building_option()
	_name_edit.text = path.get_file().get_basename()
	_clear_dirty()
	_remember_recent_path(path)
	_rebuild_host_visual()
	_request_rebake(true)
	_refresh_panel()
	var report := _plan.validate(_grid_width, _grid_length)
	var warns: PackedStringArray = report.get("warnings", PackedStringArray())
	if not warns.is_empty():
		_set_status("loaded %s — %s" % [path.get_file(), warns[0]], false)
	else:
		_set_status("loaded %s" % path.get_file())


func _saved_plan_paths() -> PackedStringArray:
	return StructureStudioDocument.list_plan_paths(STRUCTURES_DIR)


func _remember_recent_path(path: String) -> void:
	var cleaned := path.strip_edges()
	if cleaned.is_empty():
		return
	var next: Array[String] = [cleaned]
	for existing in _recent_paths:
		if existing != cleaned:
			next.append(existing)
		if next.size() >= 5:
			break
	_recent_paths = next


# ── Scene / camera / UI ──────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _ortho_top:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = clampf(_cam_distance * 0.55, 12.0, 80.0)
		_camera.position = _cam_focus + Vector3(0.0, maxf(_cam_distance, 20.0), 0.01)
		_camera.look_at(_cam_focus, Vector3.FORWARD)
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		var offset := Vector3(
			cos(_cam_pitch) * sin(_cam_yaw), sin(_cam_pitch), cos(_cam_pitch) * cos(_cam_yaw)
		) * _cam_distance
		_camera.position = _cam_focus + offset
		_camera.look_at(_cam_focus, Vector3.UP)
	## Manipulators keep a usable on-screen size at any zoom.
	var manipulator_scale := clampf(_cam_distance / 30.0, 0.7, 4.0)
	if _gizmo_root != null and is_instance_valid(_gizmo_root):
		_gizmo_root.scale = Vector3.ONE * manipulator_scale
	if _handle_root != null and is_instance_valid(_handle_root):
		for pad in _handle_root.get_children():
			(pad as Node3D).scale = Vector3.ONE * manipulator_scale
	_update_hover_feedback()


## Always-on cursor feedback, refreshed every frame: the Opening tool shows
## the EXACT snapped cut on its host, draw tools show their snapped start
## point, Select shows what a click would pick. Same snapping code as the
## actual placement, so the preview can never lie.
func _update_hover_feedback() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _opening_ghost == null or _hover_box == null or _start_marker == null:
		return
	if not is_instance_valid(_opening_ghost) or not is_instance_valid(_hover_box) or not is_instance_valid(_start_marker):
		return
	var busy := _orbiting or _panning or _gizmo_axis >= 0 or _dragging or _opening_drag
	var over_ui := get_viewport().gui_get_hovered_control() != null
	if busy or over_ui:
		_opening_ghost.visible = false
		_hover_box.visible = false
		_start_marker.visible = false
		_hover_last_screen = Vector2(-9999, -9999)
		return
	var mouse := get_viewport().get_mouse_position()
	## Skip redundant pick work when the cursor barely moved.
	if mouse.distance_to(_hover_last_screen) < 1.5:
		return
	_hover_last_screen = mouse
	_opening_ghost.visible = false
	_hover_box.visible = false
	_start_marker.visible = false
	match _tool:
		Tool.OPENING:
			var ctx := _opening_context_at(mouse)
			if ctx.is_empty():
				return
			var p := ctx["point"] as Vector3
			var geom: Dictionary
			if str(ctx["kind"]) in ["wall", "room_wall"]:
				var along := _ctx_along(ctx, p)
				geom = _opening_geom(ctx, _wall_span(ctx, along, along, false), Rect2())
			else:
				var uv := _ctx_uv(ctx, p)
				geom = _opening_geom(ctx, Vector2.ZERO, _plate_rect(ctx, uv, uv, false))
			if geom.is_empty():
				return
			(_opening_ghost.mesh as BoxMesh).size = geom["size"] as Vector3
			_opening_ghost.position = (geom["center"] as Vector3) + _plan_offset
			_opening_ghost.visible = true
		Tool.WALL, Tool.ROOM, Tool.DECK:
			var grid_point := _mouse_to_grid(mouse)
			if grid_point == Vector3.INF:
				return
			_start_marker.position = _plan_offset + grid_point
			_start_marker.visible = true
		Tool.SELECT:
			var hit := _pick_entity_hit(mouse)
			if hit.is_empty():
				return
			var id := int(hit["id"])
			if id == _selected_id or not _entity_bounds.has(id):
				return
			var aabb := _entity_bounds[id] as AABB
			(_hover_box.mesh as BoxMesh).size = aabb.size + Vector3.ONE * 0.08
			_hover_box.position = aabb.get_center()
			_hover_box.visible = true


func _build_scene() -> void:
	## Key + fill from opposing angles so interior faces and cut openings keep
	## visible contrast from any camera direction.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, 30, 0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 205, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.82, 0.92)
	add_child(fill)
	## Same viewport mood as the vessel builder's build view.
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.08, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.2, 0.22, 0.26)
	environment.ambient_light_energy = 0.95
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.far = 2000.0
	add_child(_camera)
	## Ghost preview in family copper, selection in buoy amber (HudStyle accents).
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(HudStyle.C_COPPER, 0.35)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = ghost_mat
	_ghost.visible = false
	add_child(_ghost)
	_selection_box = MeshInstance3D.new()
	_selection_box.mesh = BoxMesh.new()
	var select_mat := StandardMaterial3D.new()
	select_mat.albedo_color = Color(HudStyle.C_AMBER, 0.20)
	select_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	select_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	select_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_selection_box.material_override = select_mat
	_selection_box.visible = false
	add_child(_selection_box)
	## Opening preview: the real cut, amber, always at the cursor when the
	## Opening tool hovers a valid host.
	_opening_ghost = MeshInstance3D.new()
	_opening_ghost.mesh = BoxMesh.new()
	var opening_mat := StandardMaterial3D.new()
	opening_mat.albedo_color = Color(HudStyle.C_AMBER, 0.45)
	opening_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	opening_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opening_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_opening_ghost.material_override = opening_mat
	_opening_ghost.visible = false
	add_child(_opening_ghost)
	## Copper hover outline: what a Select click would pick.
	_hover_box = MeshInstance3D.new()
	_hover_box.mesh = BoxMesh.new()
	var hover_mat := StandardMaterial3D.new()
	hover_mat.albedo_color = Color(HudStyle.C_COPPER, 0.14)
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_box.material_override = hover_mat
	_hover_box.visible = false
	add_child(_hover_box)
	## Snapped start point for draw tools before the drag begins.
	_start_marker = MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.35, 0.35, 0.35)
	_start_marker.mesh = marker_mesh
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(HudStyle.C_AMBER, 0.85)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_start_marker.material_override = marker_mat
	_start_marker.visible = false
	add_child(_start_marker)
	_gizmo_root = Node3D.new()
	_gizmo_root.visible = false
	add_child(_gizmo_root)
	var axis_colors := [Color(0.95, 0.3, 0.3), Color(0.35, 0.9, 0.4), Color(0.35, 0.55, 0.95)]
	var axis_offsets := [Vector3(1.4, 0, 0), Vector3(0, 1.4, 0), Vector3(0, 0, 1.4)]
	var axis_sizes := [Vector3(1.6, 0.22, 0.22), Vector3(0.22, 1.6, 0.22), Vector3(0.22, 0.22, 1.6)]
	for axis in 3:
		var arrow := MeshInstance3D.new()
		var arrow_mesh := BoxMesh.new()
		arrow_mesh.size = axis_sizes[axis]
		arrow.mesh = arrow_mesh
		var arrow_mat := StandardMaterial3D.new()
		arrow_mat.albedo_color = axis_colors[axis]
		arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		## Manipulators must never hide inside or behind geometry.
		arrow_mat.no_depth_test = true
		arrow_mat.render_priority = 20
		arrow.material_override = arrow_mat
		arrow.position = axis_offsets[axis]
		_gizmo_root.add_child(arrow)
	## Six face-resize pads (axis pairs: +X −X +Y −Y +Z −Z), copper, on top.
	_handle_root = Node3D.new()
	_handle_root.visible = false
	add_child(_handle_root)
	for index in 6:
		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(0.5, 0.5, 0.5)
		pad.mesh = pad_mesh
		var pad_mat := StandardMaterial3D.new()
		pad_mat.albedo_color = Color(HudStyle.C_COPPER, 0.95)
		pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pad_mat.no_depth_test = true
		pad_mat.render_priority = 19
		pad.material_override = pad_mat
		_handle_root.add_child(pad)


# ── UI (native maritime chrome: HudStyle + UiBuilder family) ─────────────────

var _ui_root: Control
var _status_label: Label ## toast, right side of the context strip
var _hint_label: Label
var _context_label: Label
var _tool_buttons: Dictionary = {}
var _context_buttons: Dictionary = {}
var _opening_buttons: Dictionary = {}
var _opening_section: VBoxContainer
var _level_label: Label
var _ghost_button: Button
var _roofs_button: Button
var _storey_step_button: Button
var _material_search: LineEdit
## Modal surface library: arm a slot (Outside/Inside), then every swatch or
## material click paints that slot of the selection — and defines the style
## every NEWLY drawn room/wall/deck is born with.
var _armed_slot := "out"
var _lib: Dictionary = {
	"out": {"color": [0.82, 0.84, 0.86], "material": "painted"},
	"in": {"color": [0.78, 0.70, 0.58], "material": "wood"},
}
var _slot_buttons: Dictionary = {}
var _lib_material_buttons: Dictionary = {}
var _drawer: PanelContainer
var _drawer_info: Label
var _inspector_box: VBoxContainer
var _load_option: OptionButton
var _name_edit: LineEdit
var _hull_option: OptionButton
var _hull_row: VBoxContainer
var _entities_label: Label
var _entity_list: VBoxContainer
var _entity_list_filter := "all" ## all|room|wall|deck
var _bake_mesh_count := 0
var _check_report_label: Label
var _toast_timer: Timer

const TOOL_HINTS := {
	Tool.SELECT: "Select: click to pick — arrows move, face pads resize, DEL removes, Ctrl+D duplicates.",
	Tool.WALL: "Wall: click-drag along the grid, release to raise one wall run. Armed materials apply on place.",
	Tool.ROOM: "Room: drag a footprint — walls, floor and ceiling come up as one piece with inside/outside surfaces.",
	Tool.DECK: "Deck: drag a footprint to lay a deck plate.",
	Tool.OPENING: "Opening: click for a standard cut, or click-drag along the surface to size it yourself.",
	Tool.ITEMS: "Items: reserved for equipment and decor once the catalog is authored.",
}


func _setup_autosave() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = 45.0
	_autosave_timer.timeout.connect(_autosave_if_named)
	add_child(_autosave_timer)


func _autosave_if_named() -> void:
	if not _dirty:
		return
	var name_text := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name_text.is_empty():
		_set_status("autosave skipped — name the structure", false)
		return
	var path := StructureStudioDocument.path_for_name(name_text)
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STRUCTURES_DIR))
	_save_plan_now(path)
	_set_status("autosaved %s" % StructureStudioDocument.sanitize_name(name_text))


func _toggle_help(show_help: bool) -> void:
	_help_visible = show_help
	if _help_panel != null:
		_help_panel.visible = show_help


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 14
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = HudStyle.make_theme()
	layer.add_child(_ui_root)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _status_label.text = "")
	add_child(_toast_timer)
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Structure Studio"
	_confirm_dialog.ok_button_text = "Continue"
	_confirm_dialog.cancel_button_text = "Cancel"
	_confirm_dialog.confirmed.connect(_on_confirm_accepted)
	_confirm_dialog.canceled.connect(func() -> void: _pending_confirm_action = Callable())
	add_child(_confirm_dialog)
	_build_top_bar()
	_build_tool_palette()
	_build_drawer()
	_build_context_strip()
	_build_help_overlay()


func _build_help_overlay() -> void:
	_help_panel = UiBuilder.panel(Vector2(520, 0))
	_help_panel.name = "HelpOverlay"
	_help_panel.visible = false
	_help_panel.set_anchors_preset(Control.PRESET_CENTER)
	_help_panel.offset_left = -260
	_help_panel.offset_right = 260
	_help_panel.offset_top = -280
	_help_panel.offset_bottom = 280
	_ui_root.add_child(_help_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_help_panel.add_child(box)
	var header := Label.new()
	header.text = "HELP  [H]"
	HudStyle.apply_display_font(header, 20, HudStyle.C_AMBER)
	box.add_child(header)
	var body := Label.new()
	body.text = StructureStudioHelp.text()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(body, 12, HudStyle.C_TEXT)
	box.add_child(body)
	var close := UiBuilder.compact_button("Close", 0.0)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: _toggle_help(false))
	box.add_child(close)


func _build_top_bar() -> void:
	var bar := UiBuilder.inner_panel()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 54)
	_ui_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_title_label = Label.new()
	_title_label.text = "STRUCTURE STUDIO"
	HudStyle.apply_display_font(_title_label, 24, HudStyle.C_AMBER)
	row.add_child(_title_label)
	var divider := VSeparator.new()
	divider.custom_minimum_size = Vector2(1, 0)
	row.add_child(divider)
	_context_label = Label.new()
	_context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_context_label, 13, HudStyle.C_LABEL)
	row.add_child(_context_label)
	for context in ["vessel", "building"]:
		var btn := UiBuilder.tool_button(context.capitalize(), 88.0)
		btn.toggle_mode = true
		btn.pressed.connect(func() -> void:
			if context == _context:
				_refresh_panel()
				return
			_set_context(context, true)
		)
		row.add_child(btn)
		_context_buttons[context] = btn
	_hull_option = OptionButton.new()
	_hull_option.focus_mode = Control.FOCUS_NONE
	_hull_option.custom_minimum_size = Vector2(150, 34)
	var hulls := HullRegistry.catalog()
	for index in hulls.size():
		_hull_option.add_item(str((hulls[index] as Dictionary).get("id", "?")), index)
		if str((hulls[index] as Dictionary).get("id", "")) == _hull_id:
			_hull_option.select(index)
	_hull_option.item_selected.connect(func(index: int) -> void:
		if _suppress_hull_signal:
			return
		var next_hull := str((hulls[index] as Dictionary).get("id", _hull_id))
		_set_hull(next_hull, true)
	)
	row.add_child(_hull_option)
	_building_option = OptionButton.new()
	_building_option.focus_mode = Control.FOCUS_NONE
	_building_option.custom_minimum_size = Vector2(120, 34)
	_building_option.tooltip_text = "Building plot size (metres)"
	for index in BUILDING_SIZES.size():
		var size_m: int = BUILDING_SIZES[index]
		_building_option.add_item("%d×%d m" % [size_m, size_m], index)
		if size_m == _building_size:
			_building_option.select(index)
	_building_option.item_selected.connect(func(index: int) -> void:
		if _suppress_building_signal:
			return
		_set_building_size(int(BUILDING_SIZES[index]))
	)
	row.add_child(_building_option)
	row.add_child(VSeparator.new())
	var new_btn := UiBuilder.compact_button("New", 56.0)
	new_btn.pressed.connect(func() -> void: _new_plan())
	row.add_child(new_btn)
	var undo_btn := UiBuilder.compact_button("Undo", 64.0)
	undo_btn.pressed.connect(func() -> void: _undo())
	row.add_child(undo_btn)
	var redo_btn := UiBuilder.compact_button("Redo", 64.0)
	redo_btn.pressed.connect(func() -> void: _redo())
	row.add_child(redo_btn)
	var focus_btn := UiBuilder.compact_button("Focus", 64.0)
	focus_btn.pressed.connect(func() -> void: _focus_camera())
	row.add_child(focus_btn)
	var ortho_btn := UiBuilder.compact_button("Top", 52.0)
	ortho_btn.tooltip_text = "Toggle top-down ortho  [Home]"
	ortho_btn.pressed.connect(func() -> void: _toggle_ortho_top())
	row.add_child(ortho_btn)


func _build_tool_palette() -> void:
	var palette := UiBuilder.panel(Vector2(238, 0))
	palette.name = "ToolPalette"
	palette.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	palette.offset_top = 60.0
	palette.offset_bottom = -50.0
	_ui_root.add_child(palette)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	palette.add_child(box)
	box.add_child(UiBuilder.section_header("TOOLS"))
	var tool_defs := [
		[Tool.SELECT, "Select / Move  [Q]"],
		[Tool.WALL, "Wall run  [W]"],
		[Tool.ROOM, "Room  [R]"],
		[Tool.DECK, "Deck plate  [D]"],
		[Tool.OPENING, "Opening  [O]"],
	]
	## Items tool stays hidden while the equipment catalog is empty.
	if not StructureItemCatalog.is_empty():
		tool_defs.append([Tool.ITEMS, "Items  [I]"])
	for tool_def in tool_defs:
		var tool: Tool = tool_def[0]
		var btn := UiBuilder.tool_button(str(tool_def[1]), 0.0)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		btn.pressed.connect(func() -> void: _set_tool(tool))
		box.add_child(btn)
		_tool_buttons[tool] = btn
	_opening_section = VBoxContainer.new()
	_opening_section.add_theme_constant_override("separation", 4)
	_opening_section.add_child(UiBuilder.section_header("OPENING TYPE"))
	var opening_defs := [
		[StructurePlan.OPENING_DOOR, "Door  [1]"],
		[StructurePlan.OPENING_WINDOW, "Window  [2]"],
		[StructurePlan.OPENING_HOLE, "Hole  [3]"],
	]
	for opening_def in opening_defs:
		var opening_type := str(opening_def[0])
		var btn := UiBuilder.tool_button(str(opening_def[1]), 0.0)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			_opening_type = opening_type
			_refresh_panel()
		)
		_opening_section.add_child(btn)
		_opening_buttons[opening_type] = btn
	box.add_child(_opening_section)
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("BUILD LEVEL"))
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 6)
	var level_down := UiBuilder.compact_button("−", 34.0)
	level_down.tooltip_text = "Down 1 m (Shift+click = storey)"
	level_down.pressed.connect(func() -> void:
		var step := DEFAULT_WALL_HEIGHT if Input.is_key_pressed(KEY_SHIFT) else _level_step
		_set_build_level(_active_base - step)
	)
	level_row.add_child(level_down)
	_level_label = Label.new()
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_level_label, 12, HudStyle.C_TEXT, true)
	level_row.add_child(_level_label)
	var level_up := UiBuilder.compact_button("+", 34.0)
	level_up.tooltip_text = "Up 1 m (Shift+click = storey)"
	level_up.pressed.connect(func() -> void:
		var step := DEFAULT_WALL_HEIGHT if Input.is_key_pressed(KEY_SHIFT) else _level_step
		_set_build_level(_active_base + step)
	)
	level_row.add_child(level_up)
	box.add_child(level_row)
	_storey_step_button = UiBuilder.tool_button("Step by storey (3 m)", 0.0)
	_storey_step_button.toggle_mode = true
	_storey_step_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storey_step_button.pressed.connect(func() -> void:
		_level_step = DEFAULT_WALL_HEIGHT if is_equal_approx(_level_step, 1.0) else 1.0
		_refresh_panel()
	)
	box.add_child(_storey_step_button)
	var ghost_btn := UiBuilder.tool_button("Ghost upper decks", 0.0)
	ghost_btn.toggle_mode = true
	ghost_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ghost_btn.pressed.connect(func() -> void:
		_ghost_levels = not _ghost_levels
		_request_rebake(true)
		_refresh_panel()
	)
	box.add_child(ghost_btn)
	_ghost_button = ghost_btn
	var roofs_btn := UiBuilder.tool_button("Show roofs  [T]", 0.0)
	roofs_btn.toggle_mode = true
	roofs_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roofs_btn.pressed.connect(func() -> void:
		_show_roofs = not _show_roofs
		_request_rebake(true)
		_refresh_panel()
	)
	box.add_child(roofs_btn)
	_roofs_button = roofs_btn
	box.add_child(UiBuilder.separator())
	_entities_label = Label.new()
	_entities_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_entities_label, 12, HudStyle.C_LABEL)
	box.add_child(_entities_label)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	for filter_def in [["all", "All"], ["room", "Rm"], ["wall", "Wl"], ["deck", "Dk"]]:
		var filter_key := str(filter_def[0])
		var filter_btn := UiBuilder.compact_button(str(filter_def[1]), 0.0)
		filter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_btn.pressed.connect(func() -> void:
			_entity_list_filter = filter_key
			_refresh_entity_list()
		)
		filter_row.add_child(filter_btn)
	box.add_child(filter_row)
	var entity_scroll := ScrollContainer.new()
	entity_scroll.custom_minimum_size = Vector2(0, 120)
	entity_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entity_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(entity_scroll)
	_entity_list = VBoxContainer.new()
	_entity_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_list.add_theme_constant_override("separation", 2)
	entity_scroll.add_child(_entity_list)
	var hints := Label.new()
	hints.text = "RMB orbit · MMB pan · wheel zoom\nPgUp/PgDn level · F focus · E sample\nX mirror · DEL delete · Ctrl+D dup\nCtrl+Z/Y undo · Ctrl+S save · H help"
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(hints, 11, HudStyle.C_LABEL)
	box.add_child(hints)


func _build_drawer() -> void:
	_drawer = UiBuilder.panel(Vector2(300, 0))
	_drawer.name = "PropertiesDrawer"
	_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_top = 60.0
	_drawer.offset_bottom = -50.0
	_ui_root.add_child(_drawer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	_build_library_section(box)
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("PROPERTIES"))
	_drawer_info = Label.new()
	_drawer_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_drawer_info, 12, HudStyle.C_LABEL)
	box.add_child(_drawer_info)
	_inspector_box = VBoxContainer.new()
	_inspector_box.add_theme_constant_override("separation", 8)
	box.add_child(_inspector_box)
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("STRUCTURE FILE"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "structure name…"
	_name_edit.max_length = 40
	box.add_child(_name_edit)
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 6)
	var save_btn := UiBuilder.compact_button("Save  [Ctrl+S]", 0.0)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func() -> void: _save_plan(_name_edit.text))
	file_row.add_child(save_btn)
	var validate_btn := UiBuilder.compact_button("Check", 64.0)
	validate_btn.pressed.connect(func() -> void: _validate_current_plan())
	file_row.add_child(validate_btn)
	box.add_child(file_row)
	_check_report_label = Label.new()
	_check_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_check_report_label, 11, HudStyle.C_LABEL)
	box.add_child(_check_report_label)
	_load_option = OptionButton.new()
	_load_option.focus_mode = Control.FOCUS_NONE
	_load_option.custom_minimum_size = Vector2(0, 34)
	box.add_child(_load_option)
	var load_btn := UiBuilder.compact_button("Load selected", 0.0)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(func() -> void:
		var index := _load_option.selected
		if index >= 0:
			_load_plan(str(_load_option.get_item_metadata(index)))
	)
	box.add_child(load_btn)
	box.add_child(UiBuilder.section_header("RECENT"))
	var recent_box := VBoxContainer.new()
	recent_box.name = "RecentList"
	recent_box.add_theme_constant_override("separation", 4)
	box.add_child(recent_box)
	## Placeholder; filled on refresh.
	var recent_hint := Label.new()
	recent_hint.name = "RecentHint"
	recent_hint.text = "No recent files yet."
	HudStyle.apply_body_font(recent_hint, 11, HudStyle.C_LABEL)
	recent_box.add_child(recent_hint)
	for demo_def in [
		["demo_workboat.json", "Demo workboat"],
		["demo_bridge_cabin.json", "Demo bridge cabin"],
		["demo_fish_hold.json", "Demo fish hold"],
		["demo_harbour_shed.json", "Demo harbour shed"],
		["demo_quay_office.json", "Demo quay office"],
		["demo_canopy.json", "Demo canopy"],
	]:
		var demo_file := str(demo_def[0])
		var demo_btn := UiBuilder.compact_button(str(demo_def[1]), 0.0)
		demo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		demo_btn.pressed.connect(func() -> void:
			_load_plan("%s/%s" % [STRUCTURES_DIR, demo_file])
		)
		box.add_child(demo_btn)


func _build_context_strip() -> void:
	var strip := UiBuilder.inner_panel()
	strip.name = "ContextStrip"
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.custom_minimum_size = Vector2(0, 44)
	_ui_root.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_hint_label, 12, HudStyle.C_LABEL)
	row.add_child(_hint_label)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_status_label, 12, HudStyle.C_GREEN, true)
	row.add_child(_status_label)


func _set_status(text: String, ok := true) -> void:
	_status = text
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", HudStyle.C_GREEN if ok else HudStyle.C_RED
	)
	_toast_timer.start(3.2)


func _delete_selected() -> void:
	if _selected_id < 0:
		_set_status("nothing selected", false)
		return
	_snapshot()
	if _plan.remove_entity(_selected_id):
		_set_status("deleted #%d" % _selected_id)
	else:
		_set_status("delete failed for #%d" % _selected_id, false)
	_selected_id = -1
	_request_rebake(true)
	_refresh_panel()


func _duplicate_selected() -> void:
	if _selected_id < 0:
		_set_status("nothing selected", false)
		return
	_snapshot()
	var copy := _plan.duplicate_entity(_selected_id, Vector3(1, 0, 1))
	if copy.is_empty():
		_set_status("duplicate failed", false)
		return
	_selected_id = int(copy.get("id", -1))
	_set_status("duplicated → #%d" % _selected_id)
	_request_rebake(true)
	_refresh_panel()


func _copy_selected() -> void:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or entity.has("item_id"):
		_set_status("nothing to copy", false)
		return
	_clipboard_entity = entity.duplicate(true)
	_set_status("copied #%d" % _selected_id)


func _paste_clipboard() -> void:
	if _clipboard_entity.is_empty():
		_set_status("clipboard empty", false)
		return
	_snapshot()
	## Create a fresh entity of the same kind, then copy surface/opening fields.
	var kind := StructurePlan.kind_of_entity(_clipboard_entity)
	var pasted: Dictionary = {}
	match kind:
		"wall":
			var start := StructurePlan.vec3_of(_clipboard_entity.get("start")) + Vector3(1, 0, 1)
			pasted = _plan.add_wall(
				start,
				str(_clipboard_entity.get("axis", "x")),
				float(_clipboard_entity.get("length", 1.0)),
				float(_clipboard_entity.get("height", DEFAULT_WALL_HEIGHT)),
				float(_clipboard_entity.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS)),
			)
		"deck":
			var origin := StructurePlan.vec3_of(_clipboard_entity.get("origin")) + Vector3(1, 0, 1)
			var plate := StructurePlan.vec2_of(_clipboard_entity.get("size"), Vector2(1, 1))
			pasted = _plan.add_deck(
				origin, plate,
				float(_clipboard_entity.get("thickness", StructurePlan.DEFAULT_PLATE_THICKNESS)),
			)
		"room":
			var origin := StructurePlan.vec3_of(_clipboard_entity.get("origin")) + Vector3(1, 0, 1)
			var size := StructurePlan.vec3_of(_clipboard_entity.get("size"), Vector3(4, 3, 4))
			pasted = _plan.add_room(origin, size)
		_:
			_set_status("cannot paste this entity", false)
			return
	var new_id := int(pasted.get("id", -1))
	var keep_origin: Variant = pasted.get("start", pasted.get("origin"))
	for key in _clipboard_entity.keys():
		if key == "id":
			continue
		var value: Variant = _clipboard_entity[key]
		if value is Array:
			pasted[key] = (value as Array).duplicate(true)
		elif value is Dictionary:
			pasted[key] = (value as Dictionary).duplicate(true)
		else:
			pasted[key] = value
	## Keep the offset paste position, not the clipboard origin.
	if pasted.has("start"):
		pasted["start"] = keep_origin
	if pasted.has("origin"):
		pasted["origin"] = keep_origin
	pasted["id"] = new_id
	_selected_id = new_id
	_set_status("pasted → #%d" % _selected_id)
	_request_rebake(true)
	_refresh_panel()


func _validate_current_plan() -> void:
	var report := _plan.validate(_grid_width, _grid_length)
	var errors: PackedStringArray = report.get("errors", PackedStringArray())
	var warns: PackedStringArray = report.get("warnings", PackedStringArray())
	_update_check_report(errors, warns)
	if not errors.is_empty():
		_set_status("check failed (%d): %s" % [errors.size(), errors[0]], false)
	elif not warns.is_empty():
		_set_status("check: %d warning%s — %s" % [
			warns.size(), "s" if warns.size() != 1 else "", warns[0],
		], false)
	else:
		_set_status("check ok — %d entities" % _plan.entity_count())


func _update_check_report(errors: PackedStringArray, warns: PackedStringArray) -> void:
	if _check_report_label == null:
		return
	if errors.is_empty() and warns.is_empty():
		_check_report_label.text = "Check: clean"
		_check_report_label.add_theme_color_override("font_color", HudStyle.C_GREEN)
		return
	var lines: PackedStringArray = []
	for error in errors:
		lines.append("ERR  %s" % error)
	for warn in warns:
		lines.append("WARN %s" % warn)
		if lines.size() >= 6:
			break
	if errors.size() + warns.size() > lines.size():
		lines.append("… +%d more" % (errors.size() + warns.size() - lines.size()))
	_check_report_label.text = "\n".join(lines)
	_check_report_label.add_theme_color_override(
		"font_color", HudStyle.C_RED if not errors.is_empty() else HudStyle.C_AMBER
	)


func _refresh_panel() -> void:
	if _status_label == null:
		return
	for tool in _tool_buttons.keys():
		var btn := _tool_buttons[tool] as Button
		if tool == Tool.ITEMS:
			btn.set_pressed_no_signal(false)
		else:
			btn.set_pressed_no_signal(tool == _tool)
	for context in _context_buttons.keys():
		(_context_buttons[context] as Button).set_pressed_no_signal(context == _context)
	_opening_section.visible = _tool == Tool.OPENING
	for opening_type in _opening_buttons.keys():
		(_opening_buttons[opening_type] as Button).set_pressed_no_signal(opening_type == _opening_type)
	var step_label := "storey" if not is_equal_approx(_level_step, 1.0) else "1 m"
	_level_label.text = "%.0f m  [%s]" % [_active_base, step_label]
	_ghost_button.set_pressed_no_signal(_ghost_levels)
	_roofs_button.set_pressed_no_signal(_show_roofs)
	if _storey_step_button != null:
		_storey_step_button.set_pressed_no_signal(not is_equal_approx(_level_step, 1.0))
	for slot in _slot_buttons.keys():
		(_slot_buttons[slot] as Button).set_pressed_no_signal(slot == _armed_slot)
	_entities_label.text = "Structure: %d   Bake: %d\nUndo: %d   Level: %.0f m%s" % [
		_plan.structure_count(), _bake_mesh_count, _undo_stack.size(), _active_base,
		"  · dirty" if _dirty else "",
	]
	_refresh_entity_list()
	_hull_option.visible = _context == "vessel"
	if _building_option != null:
		_building_option.visible = _context == "building"
	_context_label.text = (
		"Vessel — %s  (%d×%d m)" % [_hull_id, _grid_width, _grid_length]
		if _context == "vessel"
		else "Land building  (%d×%d m)" % [_grid_width, _grid_length]
	)
	_hint_label.text = str(TOOL_HINTS.get(_tool, ""))
	_refresh_title()
	_refresh_material_category_buttons()
	_refresh_load_list()
	_refresh_recent_list()
	_refresh_inspector()
	_update_selection_visual()
	## Soft check strip stays current without a toast on every edit.
	var report := _plan.validate(_grid_width, _grid_length)
	_update_check_report(
		report.get("errors", PackedStringArray()),
		report.get("warnings", PackedStringArray()),
	)


func _refresh_recent_list() -> void:
	if _drawer == null:
		return
	var recent_box := _drawer.find_child("RecentList", true, false) as VBoxContainer
	if recent_box == null:
		return
	for child in recent_box.get_children():
		child.queue_free()
	if _recent_paths.is_empty():
		var hint := Label.new()
		hint.text = "No recent files yet."
		HudStyle.apply_body_font(hint, 11, HudStyle.C_LABEL)
		recent_box.add_child(hint)
		return
	for path in _recent_paths:
		var btn := UiBuilder.compact_button(path.get_file(), 0.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: _load_plan(path))
		recent_box.add_child(btn)


func _refresh_load_list() -> void:
	if _load_option == null:
		return
	if not _load_list_dirty and _load_option.item_count > 0:
		return
	var previous_path := ""
	if _load_option.selected >= 0:
		previous_path = str(_load_option.get_item_metadata(_load_option.selected))
	_load_option.clear()
	var paths := _saved_plan_paths()
	var select_index := 0
	for index in paths.size():
		_load_option.add_item(paths[index].get_file(), index)
		_load_option.set_item_metadata(index, paths[index])
		if paths[index] == previous_path:
			select_index = index
	if _load_option.item_count > 0:
		_load_option.select(select_index)
	_load_list_dirty = false


func _refresh_inspector() -> void:
	for child in _inspector_box.get_children():
		child.queue_free()
	_spin_undo_armed = false
	var entity := _plan.entity_by_id(_selected_id)
	if _selected_id < 0 or entity.is_empty():
		_drawer_info.text = "Nothing selected.\n\nDraw with Wall / Room / Deck, or switch to Select and click a piece.\n\nArm Outside/Inside above, then paint materials onto the selection."
		return
	var kind := StructurePlan.kind_of_entity(entity)
	_drawer_info.text = ""
	var header := Label.new()
	header.text = "%s  #%d" % [kind.to_upper(), _selected_id]
	HudStyle.apply_body_font(header, 13, HudStyle.C_AMBER, true)
	_inspector_box.add_child(header)
	match kind:
		"wall":
			for field in [["length", 1.0, 60.0, 1.0], ["height", 0.5, 12.0, 0.5], ["thickness", 0.05, 0.5, 0.05]]:
				var field_name := str(field[0])
				_inspector_box.add_child(_spin_row(
					field_name, float(entity.get(field_name, 1.0)),
					float(field[1]), float(field[2]), float(field[3]),
					func(value: float) -> void:
						_spin_commit()
						entity[field_name] = value
						_request_rebake(false)
						_update_selection_visual()
				))
		"deck":
			var deck_size: Array = entity.get("size", [1.0, 1.0])
			_inspector_box.add_child(_spin_row(
				"width", float(deck_size[0]), 1.0, 60.0, 1.0,
				func(value: float) -> void:
					_spin_commit()
					(entity["size"] as Array)[0] = value
					_request_rebake(false)
					_update_selection_visual()
			))
			_inspector_box.add_child(_spin_row(
				"length", float(deck_size[1]) if deck_size.size() > 1 else 1.0, 1.0, 60.0, 1.0,
				func(value: float) -> void:
					_spin_commit()
					var sizes: Array = entity["size"] as Array
					if sizes.size() < 2:
						sizes.append(value)
					else:
						sizes[1] = value
					_request_rebake(false)
					_update_selection_visual()
			))
			_inspector_box.add_child(_spin_row(
				"thickness", float(entity.get("thickness", 0.15)), 0.05, 0.5, 0.05,
				func(value: float) -> void:
					_spin_commit()
					entity["thickness"] = value
					_request_rebake(false)
					_update_selection_visual()
			))
		"room":
			var size_list: Array = entity.get("size", [4, 3, 4])
			var axis_names := ["width", "height", "length"]
			var mins := [2.0, 1.5, 2.0]
			for axis_index in 3:
				var captured := axis_index
				_inspector_box.add_child(_spin_row(
					axis_names[axis_index], float(size_list[axis_index]), float(mins[axis_index]), 60.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						(entity["size"] as Array)[captured] = value
						_request_rebake(false)
						_update_selection_visual()
				))
			_inspector_box.add_child(_spin_row(
				"wall_thickness", float(entity.get("wall_thickness", StructurePlan.DEFAULT_WALL_THICKNESS)),
				0.05, 0.5, 0.05,
				func(value: float) -> void:
					_spin_commit()
					entity["wall_thickness"] = value
					_request_rebake(false)
					_update_selection_visual()
			))
			## Open-top holds / floorless shelters: toggle either plate.
			var plate_row := HBoxContainer.new()
			plate_row.add_theme_constant_override("separation", 6)
			for plate_def in [["roof", "Roof"], ["floor", "Floor"]]:
				var plate_key := str(plate_def[0])
				var plate_btn := UiBuilder.tool_button(str(plate_def[1]), 0.0)
				plate_btn.toggle_mode = true
				plate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				plate_btn.set_pressed_no_signal(bool(entity.get(plate_key, true)))
				plate_btn.pressed.connect(func() -> void:
					_snapshot()
					entity[plate_key] = not bool(entity.get(plate_key, true))
					_request_rebake(true)
					_refresh_panel()
				)
				plate_row.add_child(plate_btn)
			_inspector_box.add_child(plate_row)
	## Surface readout — painting happens through the armed MATERIAL LIBRARY.
	if kind == "room" or (kind == "wall" and (entity.has("material_in") or entity.has("color_in"))):
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Outside", StructureMaterialLibrary.label_of(
				str(entity.get("material_out", entity.get("material", "painted")))
			)
		))
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Inside", StructureMaterialLibrary.label_of(
				str(entity.get("material_in", "wood"))
			)
		))
	elif kind != "item":
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Surface", StructureMaterialLibrary.label_of(
				str(entity.get("material", entity.get("material_out", "painted")))
			)
		))
	if kind == "item":
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Item", str(entity.get("item_id", "?"))
		))
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Yaw", "%d°" % int(entity.get("yaw", 0))
		))
	var openings: Array = entity.get("openings", [])
	if not openings.is_empty():
		_inspector_box.add_child(UiBuilder.section_header("OPENINGS (%d)" % openings.size()))
		for opening_index in openings.size():
			var opening := openings[opening_index] as Dictionary
			var opening_box := VBoxContainer.new()
			opening_box.add_theme_constant_override("separation", 4)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var label := Label.new()
			var face := str(opening.get("face", ""))
			var type_name := str(opening.get("type", "?"))
			if face.is_empty():
				label.text = "%d. %s" % [opening_index + 1, type_name]
			else:
				label.text = "%d. %s/%s" % [opening_index + 1, face, type_name]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudStyle.apply_body_font(label, 11, HudStyle.C_TEXT)
			row.add_child(label)
			var captured_index := opening_index
			var type_btn := UiBuilder.compact_button("type", 44.0)
			type_btn.tooltip_text = "Cycle opening type"
			type_btn.pressed.connect(func() -> void:
				_snapshot()
				if captured_index < 0 or captured_index >= openings.size():
					return
				var current := openings[captured_index] as Dictionary
				current["type"] = _cycle_opening_type(str(current.get("type", "door")), kind)
				_request_rebake(true)
				_refresh_panel()
			)
			row.add_child(type_btn)
			var remove_btn := UiBuilder.compact_button("×", 28.0)
			remove_btn.pressed.connect(func() -> void:
				_snapshot()
				if captured_index >= 0 and captured_index < openings.size():
					openings.remove_at(captured_index)
				_request_rebake(true)
				_refresh_panel()
			)
			row.add_child(remove_btn)
			opening_box.add_child(row)
			var captured_opening := opening
			var offset_raw: Variant = opening.get("offset", 0.0)
			if offset_raw is Array:
				var off: Array = offset_raw as Array
				opening_box.add_child(_spin_row(
					"off_x", float(off[0]) if off.size() > 0 else 0.0, 0.0, 60.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						var list: Array = captured_opening.get("offset", [0.0, 0.0]) as Array
						if list.is_empty():
							list = [0.0, 0.0]
						list[0] = value
						captured_opening["offset"] = list
						_request_rebake(false)
				))
				opening_box.add_child(_spin_row(
					"off_z", float(off[1]) if off.size() > 1 else 0.0, 0.0, 60.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						var list: Array = captured_opening.get("offset", [0.0, 0.0]) as Array
						if list.size() < 2:
							list.append(value)
						else:
							list[1] = value
						captured_opening["offset"] = list
						_request_rebake(false)
				))
				var hole_size: Array = opening.get("size", [1.0, 1.0])
				opening_box.add_child(_spin_row(
					"hole_w", float(hole_size[0]), 0.5, 20.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						var list: Array = captured_opening.get("size", [1.0, 1.0]) as Array
						list[0] = value
						captured_opening["size"] = list
						_request_rebake(false)
				))
				opening_box.add_child(_spin_row(
					"hole_l", float(hole_size[1]) if hole_size.size() > 1 else 1.0, 0.5, 20.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						var list: Array = captured_opening.get("size", [1.0, 1.0]) as Array
						if list.size() < 2:
							list.append(value)
						else:
							list[1] = value
						captured_opening["size"] = list
						_request_rebake(false)
				))
			else:
				opening_box.add_child(_spin_row(
					"offset", float(offset_raw), 0.0, 60.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						captured_opening["offset"] = value
						_request_rebake(false)
				))
				opening_box.add_child(_spin_row(
					"width", float(opening.get("width", 1.0)), 0.5, 20.0, 0.5,
					func(value: float) -> void:
						_spin_commit()
						captured_opening["width"] = value
						_request_rebake(false)
				))
				if str(opening.get("type", "")) != StructurePlan.OPENING_DOOR:
					opening_box.add_child(_spin_row(
						"sill", float(opening.get("sill", 0.0)), 0.0, 8.0, 0.1,
						func(value: float) -> void:
							_spin_commit()
							captured_opening["sill"] = value
							_request_rebake(false)
					))
				opening_box.add_child(_spin_row(
					"height", float(opening.get("height", 2.0)), 0.5, 8.0, 0.1,
					func(value: float) -> void:
						_spin_commit()
						captured_opening["height"] = value
						_request_rebake(false)
				))
			_inspector_box.add_child(opening_box)
	_inspector_box.add_child(UiBuilder.separator())
	var util_row := HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 6)
	var sample_btn := UiBuilder.compact_button("Sample  [E]", 0.0)
	sample_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sample_btn.pressed.connect(func() -> void: _eyedrop_selection_to_library())
	util_row.add_child(sample_btn)
	var raise_btn := UiBuilder.compact_button("To level", 0.0)
	raise_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raise_btn.tooltip_text = "Move selection base to the current build level"
	raise_btn.pressed.connect(func() -> void: _raise_selected_to_level())
	util_row.add_child(raise_btn)
	_inspector_box.add_child(util_row)
	var util_row2 := HBoxContainer.new()
	util_row2.add_theme_constant_override("separation", 6)
	var snap_btn := UiBuilder.compact_button("Snap grid", 0.0)
	snap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_btn.pressed.connect(func() -> void: _snap_selected_to_grid())
	util_row2.add_child(snap_btn)
	var stack_btn := UiBuilder.compact_button("Stack ↑", 0.0)
	stack_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_btn.tooltip_text = "Duplicate selection one storey above"
	stack_btn.pressed.connect(func() -> void: _stack_selected_above())
	util_row2.add_child(stack_btn)
	_inspector_box.add_child(util_row2)
	var rot_row := HBoxContainer.new()
	rot_row.add_theme_constant_override("separation", 6)
	var rot_left := UiBuilder.compact_button("⟲  [,]", 0.0)
	rot_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_left.pressed.connect(func() -> void: _rotate_selected(-90))
	rot_row.add_child(rot_left)
	var rot_right := UiBuilder.compact_button("⟳  [.] ", 0.0)
	rot_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_right.pressed.connect(func() -> void: _rotate_selected(90))
	rot_row.add_child(rot_right)
	_inspector_box.add_child(rot_row)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	var dup_btn := UiBuilder.compact_button("Duplicate", 0.0)
	dup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup_btn.pressed.connect(func() -> void: _duplicate_selected())
	action_row.add_child(dup_btn)
	var delete_btn := UiBuilder.compact_button("Delete", 0.0)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.add_theme_color_override("font_color", HudStyle.C_RED)
	delete_btn.add_theme_color_override("font_hover_color", HudStyle.C_RED)
	delete_btn.pressed.connect(func() -> void: _delete_selected())
	action_row.add_child(delete_btn)
	_inspector_box.add_child(action_row)


func _spin_commit() -> void:
	## One undo step per continuous SpinBox edit session; rebuild clears the arm.
	if _spin_undo_armed:
		return
	_snapshot()
	_spin_undo_armed = true


func _cycle_opening_type(current: String, host_kind: String) -> String:
	var wall_cycle := [
		StructurePlan.OPENING_DOOR,
		StructurePlan.OPENING_WINDOW,
		StructurePlan.OPENING_HOLE,
	]
	var plate_cycle := [
		StructurePlan.OPENING_STAIRWELL,
		StructurePlan.OPENING_HOLE,
	]
	var cycle: Array = plate_cycle if host_kind == "deck" else wall_cycle
	var index := cycle.find(current)
	if index < 0:
		return str(cycle[0])
	return str(cycle[(index + 1) % cycle.size()])


## The standing right-hand surface library. Modal: arm Outside or Inside, then
## clicks on materials/swatches paint that slot of the current selection AND
## become the default style for everything drawn next.
## Materials come from StructureMaterialLibrary (global construction catalog).
func _build_library_section(box: VBoxContainer) -> void:
	box.add_child(UiBuilder.section_header("MATERIAL LIBRARY"))
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	for slot_def in [["out", "Outside"], ["in", "Inside"]]:
		var slot := str(slot_def[0])
		var btn := UiBuilder.tool_button(str(slot_def[1]), 0.0)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			_armed_slot = slot
			_refresh_panel()
		)
		slot_row.add_child(btn)
		_slot_buttons[slot] = btn
	box.add_child(slot_row)
	var armed_hint := Label.new()
	armed_hint.name = "ArmedHint"
	armed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(armed_hint, 11, HudStyle.C_LABEL)
	armed_hint.text = "Armed slot paints selection + next draws."
	box.add_child(armed_hint)
	_material_search = LineEdit.new()
	_material_search.placeholder_text = "filter materials…"
	_material_search.clear_button_enabled = true
	_material_search.text_changed.connect(func(_text: String) -> void: _rebuild_material_buttons())
	box.add_child(_material_search)
	var category_flow := HFlowContainer.new()
	category_flow.add_theme_constant_override("h_separation", 4)
	category_flow.add_theme_constant_override("v_separation", 4)
	for category in MATERIAL_CATEGORY_FILTERS:
		var cat_btn := UiBuilder.compact_button(category.capitalize() if category != "all" else "All", 0.0)
		cat_btn.toggle_mode = true
		cat_btn.pressed.connect(func() -> void:
			_material_category = category
			_rebuild_material_buttons()
			_refresh_panel()
		)
		category_flow.add_child(cat_btn)
		_category_buttons[category] = cat_btn
	box.add_child(category_flow)
	_material_flow = HFlowContainer.new()
	_material_flow.add_theme_constant_override("h_separation", 4)
	_material_flow.add_theme_constant_override("v_separation", 4)
	box.add_child(_material_flow)
	_rebuild_material_buttons()
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 4)
	swatches.add_theme_constant_override("v_separation", 4)
	for swatch_variant in StructureMaterialLibrary.swatches():
		var swatch := swatch_variant as Dictionary
		var swatch_color := StructureMaterialLibrary.color_of(swatch.get("color"), Color.WHITE)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(26, 26)
		button.tooltip_text = str(swatch.get("label", swatch.get("id", "")))
		var sb := StyleBoxFlat.new()
		sb.bg_color = swatch_color
		sb.border_color = HudStyle.C_BRASS
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		button.add_theme_stylebox_override("normal", sb)
		button.add_theme_stylebox_override("hover", sb)
		button.add_theme_stylebox_override("pressed", sb)
		button.pressed.connect(func() -> void:
			_apply_library_color([swatch_color.r, swatch_color.g, swatch_color.b])
		)
		swatches.add_child(button)
	box.add_child(swatches)


func _rebuild_material_buttons() -> void:
	if _material_flow == null:
		return
	for child in _material_flow.get_children():
		child.queue_free()
	_lib_material_buttons.clear()
	var query := ""
	if _material_search != null:
		query = _material_search.text.strip_edges().to_lower()
	for material_name in StructureMaterialLibrary.ids_in_category(_material_category):
		var label := StructureMaterialLibrary.label_of(material_name)
		if not query.is_empty():
			var hay := ("%s %s %s" % [label, material_name, StructureMaterialLibrary.category_of(material_name)]).to_lower()
			if not hay.contains(query):
				continue
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(70, 34)
		btn.tooltip_text = "%s · %s (%s)" % [
			label,
			StructureMaterialLibrary.category_of(material_name),
			material_name,
		]
		btn.text = label
		var sample := StructureMaterialLibrary.default_color(material_name)
		var chip := StyleBoxFlat.new()
		chip.bg_color = sample
		chip.set_corner_radius_all(3)
		chip.content_margin_left = 10.0
		chip.content_margin_right = 8.0
		chip.content_margin_top = 6.0
		chip.content_margin_bottom = 6.0
		chip.border_color = HudStyle.C_BRASS
		chip.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", chip)
		var chip_hover := chip.duplicate() as StyleBoxFlat
		chip_hover.border_color = HudStyle.C_AMBER
		btn.add_theme_stylebox_override("hover", chip_hover)
		btn.add_theme_stylebox_override("pressed", chip_hover)
		var luminance := sample.r * 0.3 + sample.g * 0.59 + sample.b * 0.11
		var ink := Color(0.08, 0.09, 0.1) if luminance > 0.55 else Color(0.95, 0.95, 0.92)
		HudStyle.apply_body_font(btn, 11, ink)
		btn.pressed.connect(func() -> void: _apply_library_material(material_name))
		_material_flow.add_child(btn)
		_lib_material_buttons[material_name] = btn


func _refresh_material_category_buttons() -> void:
	for category in _category_buttons.keys():
		(_category_buttons[category] as Button).set_pressed_no_signal(category == _material_category)
	var armed_material := str((_lib[_armed_slot] as Dictionary)["material"])
	for material_name in _lib_material_buttons.keys():
		(_lib_material_buttons[material_name] as Button).set_pressed_no_signal(material_name == armed_material)


func _library_keys_for_selection() -> Dictionary:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty():
		return {}
	var kind := StructurePlan.kind_of_entity(entity)
	if kind == "item":
		return {}
	if kind == "room":
		return {
			"entity": entity,
			"color": "color_out" if _armed_slot == "out" else "color_in",
			"material": "material_out" if _armed_slot == "out" else "material_in",
		}
	if kind == "wall":
		## Walls become two-sided as soon as the Inside slot is painted.
		if _armed_slot == "in":
			_ensure_wall_two_sided(entity)
			return {"entity": entity, "color": "color_in", "material": "material_in"}
		if entity.has("material_in") or entity.has("color_in"):
			return {"entity": entity, "color": "color_out", "material": "material_out"}
		return {"entity": entity, "color": "color", "material": "material"}
	## Deck plates stay single-surface for now.
	return {"entity": entity, "color": "color", "material": "material"}


func _ensure_wall_two_sided(entity: Dictionary) -> void:
	if entity.has("material_out") or entity.has("color_out"):
		return
	## Promote legacy single-surface keys into outside identity.
	if entity.has("color"):
		entity["color_out"] = (entity["color"] as Array).duplicate()
	if entity.has("material"):
		entity["material_out"] = str(entity["material"])
	if not entity.has("material_out"):
		entity["material_out"] = str((_lib["out"] as Dictionary)["material"])
	if not entity.has("color_out"):
		entity["color_out"] = ((_lib["out"] as Dictionary)["color"] as Array).duplicate()


func _apply_library_color(rgb: Array) -> void:
	(_lib[_armed_slot] as Dictionary)["color"] = rgb.duplicate()
	_sync_plan_palette_from_library()
	var keys := _library_keys_for_selection()
	if not keys.is_empty():
		_snapshot()
		(keys["entity"] as Dictionary)[str(keys["color"])] = rgb.duplicate()
		_request_rebake(true)
	_set_status("%s colour set" % ("outside" if _armed_slot == "out" else "inside"))
	_refresh_panel()


func _apply_library_material(material_name: String) -> void:
	var id := StructureMaterialLibrary.normalize_id(material_name)
	(_lib[_armed_slot] as Dictionary)["material"] = id
	_sync_plan_palette_from_library()
	## Shift+click paints every entity of the selection's kind (or all structure
	## if nothing is selected).
	if Input.is_key_pressed(KEY_SHIFT):
		_paint_material_bulk(id)
		return
	var keys := _library_keys_for_selection()
	if not keys.is_empty():
		_snapshot()
		(keys["entity"] as Dictionary)[str(keys["material"])] = id
		_request_rebake(true)
	_set_status("%s material: %s" % [
		"outside" if _armed_slot == "out" else "inside",
		StructureMaterialLibrary.label_of(id),
	])
	_refresh_panel()


func _paint_material_bulk(material_id: String) -> void:
	var target_kind := ""
	var selected := _plan.entity_by_id(_selected_id)
	if not selected.is_empty() and not selected.has("item_id"):
		target_kind = StructurePlan.kind_of_entity(selected)
	_snapshot()
	var painted := 0
	for collection in [_plan.rooms, _plan.walls, _plan.decks]:
		for entity_variant in collection:
			var entity := entity_variant as Dictionary
			var kind := StructurePlan.kind_of_entity(entity)
			if not target_kind.is_empty() and kind != target_kind:
				continue
			if kind == "room":
				entity["material_out" if _armed_slot == "out" else "material_in"] = material_id
			elif kind == "wall":
				if _armed_slot == "in":
					_ensure_wall_two_sided(entity)
					entity["material_in"] = material_id
				elif entity.has("material_in") or entity.has("color_in"):
					entity["material_out"] = material_id
				else:
					entity["material"] = material_id
					entity["material_out"] = material_id
			else:
				entity["material"] = material_id
			painted += 1
	_request_rebake(true)
	_refresh_panel()
	_set_status("painted %d %s → %s" % [
		painted,
		target_kind if not target_kind.is_empty() else "parts",
		StructureMaterialLibrary.label_of(material_id),
	])


func _sync_plan_palette_from_library() -> void:
	## Keep plan.palette aligned with the armed outside/deck defaults so bare
	## walls/decks without per-entity colour still pick up Studio intent.
	var out := _lib["out"] as Dictionary
	_plan.palette["wall"] = (out["color"] as Array).duplicate()
	_plan.palette["deck"] = (out["color"] as Array).duplicate()


## Style every new entity with the armed library so drawing is paint-first.
func _stamp_library_style(entity: Dictionary, is_room: bool) -> void:
	var out := _lib["out"] as Dictionary
	var interior := _lib["in"] as Dictionary
	if is_room:
		entity["color_out"] = (out["color"] as Array).duplicate()
		entity["material_out"] = StructureMaterialLibrary.normalize_id(str(out["material"]))
		entity["color_in"] = (interior["color"] as Array).duplicate()
		entity["material_in"] = StructureMaterialLibrary.normalize_id(str(interior["material"]))
	else:
		entity["color"] = (out["color"] as Array).duplicate()
		entity["material"] = StructureMaterialLibrary.normalize_id(str(out["material"]))
		## Walls also get an outside identity so Inside painting can promote
		## them to two-sided without losing the original surface.
		if entity.has("axis"):
			entity["color_out"] = (out["color"] as Array).duplicate()
			entity["material_out"] = StructureMaterialLibrary.normalize_id(str(out["material"]))


func _spin_row(label_text: String, value: float, min_value: float, max_value: float, step: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text.capitalize()
	label.custom_minimum_size = Vector2(84, 0)
	HudStyle.apply_body_font(label, 12, HudStyle.C_LABEL)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	return row
