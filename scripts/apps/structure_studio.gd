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
##                     DEL to delete
##   Ctrl+Z / Ctrl+Y — undo / redo (full-plan snapshots)
##   PgUp/PgDn       — build level up/down (grid follows; upper decks ghost)
##   F               — focus camera on selection · Esc cancels a drag
##   RMB drag orbit · MMB drag pan · wheel zoom
##
## Context switch (top bar): Ship (build on a hull) or Building (ground slab).
## Save/Load: JSON plans in res://resources/data/structures/.

const STRUCTURES_DIR := "res://resources/data/structures"
const GRID_SNAP := 1.0
const DEFAULT_WALL_HEIGHT := 3.0

## Shared colour + material library (maritime palette, StructureBaker materials).
const COLOR_LIBRARY: Array = [
	["Steel", Color(0.62, 0.65, 0.68)], ["White", Color(0.92, 0.93, 0.94)],
	["Cream", Color(0.90, 0.86, 0.76)], ["Timber", Color(0.62, 0.50, 0.38)],
	["Charcoal", Color(0.24, 0.26, 0.28)], ["Slate", Color(0.42, 0.48, 0.52)],
	["Hull red", Color(0.55, 0.20, 0.16)], ["Harbour", Color(0.28, 0.44, 0.52)],
	["Yellow", Color(0.86, 0.68, 0.20)],
]
const MATERIAL_LIBRARY: Array[String] = ["painted", "metal", "wood", "steel"]

enum Tool { SELECT, WALL, ROOM, DECK, OPENING }

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


func _ready() -> void:
	_build_scene()
	_build_ui()
	_set_context("vessel")
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--studio-probe":
			print("[structure-studio] probe ok — context=%s entities=%d" % [_context, _plan.entity_count()])
			get_tree().quit(0)


# ── Context / plan lifecycle ─────────────────────────────────────────────────

var _deck_grid: DeckGrid


func _set_context(context: String) -> void:
	_context = context
	_plan = StructurePlan.new()
	_plan.context = context
	_undo_stack.clear()
	_redo_stack.clear()
	_selected_id = -1
	if context == "vessel":
		_deck_grid = HullRegistry.make_grid(_hull_id)
		_grid_width = _deck_grid.width
		_grid_length = _deck_grid.length
		_plan.hull_id = _hull_id
		_plan_offset = Vector3(-_deck_grid.half_beam, 0.0, -_deck_grid.half_loa)
	else:
		_deck_grid = null
		_grid_width = 24
		_grid_length = 24
		_plan_offset = Vector3(-_grid_width * 0.5, 0.0, -_grid_length * 0.5)
	_cam_focus = Vector3.ZERO
	_rebuild_host_visual()
	_rebake()
	_refresh_panel()


func _rebuild_host_visual() -> void:
	if _hull_visual != null:
		_hull_visual.queue_free()
	_hull_visual = Node3D.new()
	_hull_visual.name = "Host"
	add_child(_hull_visual)
	if _context == "vessel":
		## The REAL hull under the build: deck plane aligned to the grid plane.
		var boat := VesselSpawn.instantiate(_hull_id, {}, "")
		if boat != null:
			_hull_visual.add_child(boat)
			boat.position = Vector3(0.0, -_deck_grid.deck_y, 0.0)
			boat.freeze = true
			boat.sleeping = true
			boat.process_mode = Node.PROCESS_MODE_DISABLED
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
	if _context != "vessel":
		return
	## Painted flat on the deck plane just outside the grid — stencilled harbour
	## markings, not floating billboards that block the camera. Family palette:
	## amber bow, muted stern, nav red/green for port/starboard.
	var markers := [
		["BOW", Vector3(_grid_width * 0.5, 0.06, -1.4), 0.0, HudStyle.C_AMBER],
		["STERN", Vector3(_grid_width * 0.5, 0.06, _grid_length + 1.4), 180.0, HudStyle.C_LABEL],
		["PORT", Vector3(-1.6, 0.06, _grid_length * 0.5), 90.0, HudStyle.C_RED],
		["STARBOARD", Vector3(_grid_width + 1.6, 0.06, _grid_length * 0.5), 270.0, HudStyle.C_GREEN],
	]
	for marker in markers:
		var label := Label3D.new()
		label.text = str(marker[0])
		label.font_size = 132
		label.modulate = Color(marker[3] as Color, 0.85)
		label.position = _plan_offset + (marker[1] as Vector3)
		## Lay the text onto the deck plane, reading outward from the hull.
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


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_plan.to_dict())
	_plan = StructurePlan.from_dict(_undo_stack.pop_back())
	_selected_id = -1
	_rebake()
	_refresh_panel()


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_plan.to_dict())
	_plan = StructurePlan.from_dict(_redo_stack.pop_back())
	_selected_id = -1
	_rebake()
	_refresh_panel()


func _rebake() -> void:
	if _bake_root != null:
		_bake_root.queue_free()
	if _ghost_root != null:
		_ghost_root.queue_free()
		_ghost_root = null
	## Everything above the working level renders as ghost x-ray, so the deck
	## being edited stays fully readable without losing the shape above it.
	## Ghosted geometry is also excluded from picking (see _pick_entity_hit).
	var threshold := _active_base + 2.99 if _ghost_levels else INF
	_ghost_threshold = threshold
	var solid_plan := StructurePlan.from_dict(_plan.to_dict())
	var ghost_plan := StructurePlan.from_dict(_plan.to_dict())
	var any_ghost := false
	for plans in [[solid_plan, true], [ghost_plan, false]]:
		var target := plans[0] as StructurePlan
		var keep_below := bool(plans[1])
		for collection in [target.walls, target.decks, target.rooms]:
			var kept: Array = []
			for entity in collection:
				var origin := StructurePlan.vec3_of(
					(entity as Dictionary).get("start", (entity as Dictionary).get("origin"))
				)
				var below := origin.y < threshold
				if below == keep_below:
					kept.append(entity)
					if not keep_below:
						any_ghost = true
			(collection as Array).assign(kept)
	## View-only roof hiding: strips ceilings from the render copies while the
	## plan data (and the saved ship) keeps its roofs.
	if not _show_roofs:
		for plan_copy in [solid_plan, ghost_plan]:
			for room_variant in (plan_copy as StructurePlan).rooms:
				(room_variant as Dictionary)["roof"] = false
	_bake_root = StructureBaker.bake(solid_plan, _plan_offset)
	add_child(_bake_root)
	if any_ghost:
		_ghost_root = StructureBaker.bake(ghost_plan, _plan_offset, true)
		add_child(_ghost_root)
	_recompute_bounds()
	_update_selection_visual()


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
		_undo()
		return
	if key.ctrl_pressed and key.keycode == KEY_Y:
		_redo()
		return
	match key.keycode:
		KEY_ESCAPE:
			if _dragging or _gizmo_axis >= 0 or _opening_drag:
				## Cancel the in-flight interaction, keep the current tool.
				_dragging = false
				_gizmo_axis = -1
				_resize_mode = false
				_opening_drag = false
				_opening_ctx = {}
				_opening_ghost.visible = false
				_hide_ghost()
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
			if _selected_id >= 0 and _entity_bounds.has(_selected_id):
				_cam_focus = (_entity_bounds[_selected_id] as AABB).get_center()
		KEY_T:
			_show_roofs = not _show_roofs
			_rebake()
			_refresh_panel()
		KEY_PAGEUP:
			_set_build_level(_active_base + 1.0)
		KEY_PAGEDOWN:
			_set_build_level(_active_base - 1.0)


func _set_build_level(level: float) -> void:
	_active_base = maxf(level, 0.0)
	_build_grid_lines()
	_rebake()
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
		_selected_id = _pick_entity(screen_pos)
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
		if _resize_mode:
			_resize_mode = false
			_set_status("resize committed")
			_refresh_panel()
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


# ── Tools ────────────────────────────────────────────────────────────────────

func _set_tool(tool: Tool) -> void:
	_tool = tool
	_dragging = false
	_hide_ghost()
	_refresh_panel()


func _place_wall(a: Vector3, b: Vector3) -> void:
	var dx := absf(b.x - a.x)
	var dz := absf(b.z - a.z)
	var axis := "x" if dx >= dz else "z"
	var length := roundf(maxf(dx if axis == "x" else dz, 1.0))
	var start := Vector3(
		minf(a.x, b.x) if axis == "x" else roundf(a.x),
		_active_base,
		minf(a.z, b.z) if axis == "z" else roundf(a.z),
	)
	start.x = roundf(start.x)
	start.z = roundf(start.z)
	_snapshot()
	var wall := _plan.add_wall(start, axis, length, DEFAULT_WALL_HEIGHT)
	_stamp_library_style(wall, false)
	_status = "wall %s ×%.0f m" % [axis, length]
	_rebake()
	_refresh_panel()


func _place_rect_entity(a: Vector3, b: Vector3, as_room: bool) -> void:
	var min_pt := Vector3(roundf(minf(a.x, b.x)), _active_base, roundf(minf(a.z, b.z)))
	var w := roundf(maxf(absf(b.x - a.x), 2.0 if as_room else 1.0))
	var l := roundf(maxf(absf(b.z - a.z), 2.0 if as_room else 1.0))
	_snapshot()
	if as_room:
		var room := _plan.add_room(min_pt, Vector3(w, DEFAULT_WALL_HEIGHT, l))
		_stamp_library_style(room, true)
		_status = "room %.0f×%.0f×%.0f" % [w, DEFAULT_WALL_HEIGHT, l]
	else:
		var deck := _plan.add_deck(min_pt, Vector2(w, l))
		_stamp_library_style(deck, false)
		_status = "deck plate %.0f×%.0f" % [w, l]
	_rebake()
	_refresh_panel()


# ── Openings: one context shared by hover, drag and commit ───────────────────

var _opening_drag := false
var _opening_ctx: Dictionary = {}
var _opening_anchor := Vector2.ZERO ## walls: (along, 0) · plates: (u, v)


func _opening_defaults() -> Dictionary:
	## Whole-metre widths so default cuts land flush on grid lines.
	match _opening_type:
		StructurePlan.OPENING_WINDOW:
			return {"type": "window", "width": 2.0, "sill": 1.2, "height": 1.2}
		StructurePlan.OPENING_HOLE:
			return {"type": "hole", "width": 2.0, "sill": 0.0, "height": 2.4}
		_:
			return {"type": "door", "width": 2.0, "sill": 0.0, "height": 2.2}


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


## Wall opening span (offset, width). Click: default width centered, edges on
## whole metres. Drag: both edges snap to the half-metre grid, min 1 m, never
## past the host ends.
func _wall_span(ctx: Dictionary, a: float, b: float, dragged: bool) -> Vector2:
	var length := float(ctx["length"])
	if not dragged:
		var width: float = minf(float(_opening_defaults()["width"]), length)
		var off := clampf(roundf(a - width * 0.5), 0.0, maxf(length - width, 0.0))
		return Vector2(off, width)
	var e0 := roundf(minf(a, b) * 2.0) / 2.0
	var e1 := roundf(maxf(a, b) * 2.0) / 2.0
	e0 = clampf(e0, 0.0, maxf(length - 1.0, 0.0))
	e1 = clampf(maxf(e1, e0 + 1.0), e0 + 1.0, length)
	return Vector2(e0, e1 - e0)


## Plate hole rect. Click: 1×3 stairwell footprint on whole metres. Drag: the
## rectangle you sweep, whole-metre edges, min 1×1, clamped inside the plate.
func _plate_rect(ctx: Dictionary, a: Vector2, b: Vector2, dragged: bool) -> Rect2:
	var extent := ctx["extent"] as Vector2
	if not dragged:
		var w := minf(1.0, extent.x)
		var l := minf(3.0, extent.y)
		return Rect2(
			clampf(roundf(a.x - w * 0.5), 0.0, maxf(extent.x - w, 0.0)),
			clampf(roundf(a.y - l * 0.5), 0.0, maxf(extent.y - l, 0.0)),
			w, l,
		)
	var mn := Vector2(roundf(minf(a.x, b.x)), roundf(minf(a.y, b.y)))
	var mx := Vector2(roundf(maxf(a.x, b.x)), roundf(maxf(a.y, b.y)))
	mn = mn.clamp(Vector2.ZERO, Vector2(maxf(extent.x - 1.0, 0.0), maxf(extent.y - 1.0, 0.0)))
	mx = mx.clamp(mn + Vector2.ONE, extent)
	return Rect2(mn, mx - mn)


## Ghost geometry for a wall span or plate rect, in plan space.
func _opening_geom(ctx: Dictionary, span: Vector2, rect: Rect2) -> Dictionary:
	var defaults := _opening_defaults()
	match str(ctx.get("kind")):
		"wall":
			var start := ctx["start"] as Vector3
			var u := span.x + span.y * 0.5
			var v: float = start.y + float(defaults["sill"]) + float(defaults["height"]) * 0.5
			var t := float(ctx["thickness"]) + 0.14
			if bool(ctx["axis_z"]):
				return {"center": Vector3(start.x, v, start.z + u), "size": Vector3(t, float(defaults["height"]), span.y)}
			return {"center": Vector3(start.x + u, v, start.z), "size": Vector3(span.y, float(defaults["height"]), t)}
		"room_wall":
			var origin := ctx["origin"] as Vector3
			var size := ctx["size"] as Vector3
			var u := span.x + span.y * 0.5
			var v: float = origin.y + float(defaults["sill"]) + float(defaults["height"]) * 0.5
			match str(ctx["face"]):
				"n":
					return {"center": Vector3(origin.x + u, v, origin.z), "size": Vector3(span.y, float(defaults["height"]), 0.34)}
				"s":
					return {"center": Vector3(origin.x + u, v, origin.z + size.z), "size": Vector3(span.y, float(defaults["height"]), 0.34)}
				"w":
					return {"center": Vector3(origin.x, v, origin.z + u), "size": Vector3(0.34, float(defaults["height"]), span.y)}
				_:
					return {"center": Vector3(origin.x + size.x, v, origin.z + u), "size": Vector3(0.34, float(defaults["height"]), span.y)}
		"room_plate", "plate":
			var origin := ctx["origin"] as Vector3
			return {
				"center": Vector3(
					origin.x + rect.position.x + rect.size.x * 0.5,
					float(ctx["plane_y"]),
					origin.z + rect.position.y + rect.size.y * 0.5,
				),
				"size": Vector3(rect.size.x, 0.4, rect.size.y),
			}
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
		var hole := {
			"type": StructurePlan.OPENING_STAIRWELL,
			"offset": [rect.position.x, rect.position.y],
			"size": [rect.size.x, rect.size.y],
		}
		if str(ctx["kind"]) == "room_plate":
			hole["face"] = str(ctx["face"])
		(entity["openings"] as Array).append(hole)
		_set_status("hole  %.0f × %.0f m" % [rect.size.x, rect.size.y])
	_rebake()
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
	return plan_point


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
	if new_origin.is_equal_approx(_gizmo_last_applied):
		return ## same snapped cell — no churn, no rebake
	if new_origin.is_equal_approx(_gizmo_start_origin) and _gizmo_last_applied == Vector3.INF:
		return ## has not left the starting cell yet
	_commit_staged_snapshot()
	_gizmo_last_applied = new_origin
	var key := "start" if entity.has("start") else "origin"
	entity[key] = [new_origin.x, new_origin.y, new_origin.z]
	_rebake()


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
	_rebake()


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
		size.y = DEFAULT_WALL_HEIGHT
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
	var trimmed := plan_name.strip_edges().to_snake_case()
	if trimmed.is_empty():
		_status = "name the structure first"
		_refresh_panel()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STRUCTURES_DIR))
	var path := "%s/%s.json" % [STRUCTURES_DIR, trimmed]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status = "save failed: %s" % path
	else:
		file.store_string(JSON.stringify(_plan.to_dict(), "\t"))
		file.close()
		_status = "saved %s" % path
	_refresh_panel()


func _load_plan(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary or not StructurePlan.is_plan(parsed as Dictionary):
		_status = "not a structure plan: %s" % path
		_refresh_panel()
		return
	_snapshot()
	_plan = StructurePlan.from_dict(parsed as Dictionary)
	_context = _plan.context
	if _context == "vessel" and not _plan.hull_id.is_empty():
		_hull_id = _plan.hull_id
	_selected_id = -1
	_status = "loaded %s" % path.get_file()
	_rebuild_host_visual()
	_rebake()
	_refresh_panel()


func _saved_plan_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(STRUCTURES_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			out.append("%s/%s" % [STRUCTURES_DIR, file_name])
	return out


# ── Scene / camera / UI ──────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var offset := Vector3(
		cos(_cam_pitch) * sin(_cam_yaw), sin(_cam_pitch), cos(_cam_pitch) * cos(_cam_yaw)
	) * _cam_distance
	_camera.position = _cam_focus + offset
	_camera.look_at(_cam_focus, Vector3.UP)
	## Manipulators keep a usable on-screen size at any zoom.
	var manipulator_scale := clampf(_cam_distance / 30.0, 0.7, 4.0)
	if _gizmo_root != null:
		_gizmo_root.scale = Vector3.ONE * manipulator_scale
	if _handle_root != null:
		for pad in _handle_root.get_children():
			(pad as Node3D).scale = Vector3.ONE * manipulator_scale
	_update_hover_feedback()


## Always-on cursor feedback, refreshed every frame: the Opening tool shows
## the EXACT snapped cut on its host, draw tools show their snapped start
## point, Select shows what a click would pick. Same snapping code as the
## actual placement, so the preview can never lie.
func _update_hover_feedback() -> void:
	if _camera == null:
		return
	var busy := _orbiting or _panning or _gizmo_axis >= 0 or _dragging or _opening_drag
	var over_ui := get_viewport().gui_get_hovered_control() != null
	if busy or over_ui:
		_opening_ghost.visible = false
		_hover_box.visible = false
		_start_marker.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
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
var _toast_timer: Timer

const TOOL_HINTS := {
	Tool.SELECT: "Select: click to pick — arrows move it, drag a face pad to resize, DEL removes.",
	Tool.WALL: "Wall: click-drag along the grid, release to raise one wall run.",
	Tool.ROOM: "Room: drag a footprint — walls, floor and ceiling come up as one piece.",
	Tool.DECK: "Deck: drag a footprint to lay a deck plate.",
	Tool.OPENING: "Opening: click for a standard cut, or click-drag along the surface to size it yourself.",
}


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
	_build_top_bar()
	_build_tool_palette()
	_build_drawer()
	_build_context_strip()


func _build_top_bar() -> void:
	var bar := UiBuilder.inner_panel()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 54)
	_ui_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var title := Label.new()
	title.text = "STRUCTURE STUDIO"
	HudStyle.apply_display_font(title, 24, HudStyle.C_AMBER)
	row.add_child(title)
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
		btn.pressed.connect(func() -> void: _set_context(context))
		row.add_child(btn)
		_context_buttons[context] = btn
	_hull_option = OptionButton.new()
	_hull_option.focus_mode = Control.FOCUS_NONE
	_hull_option.custom_minimum_size = Vector2(130, 34)
	var hulls := HullRegistry.catalog()
	for index in hulls.size():
		_hull_option.add_item(str((hulls[index] as Dictionary).get("id", "?")), index)
		if str((hulls[index] as Dictionary).get("id", "")) == _hull_id:
			_hull_option.select(index)
	_hull_option.item_selected.connect(func(index: int) -> void:
		_hull_id = str((hulls[index] as Dictionary).get("id", _hull_id))
		_set_context("vessel")
	)
	row.add_child(_hull_option)
	row.add_child(VSeparator.new())
	var undo_btn := UiBuilder.compact_button("Undo", 64.0)
	undo_btn.pressed.connect(func() -> void: _undo())
	row.add_child(undo_btn)
	var redo_btn := UiBuilder.compact_button("Redo", 64.0)
	redo_btn.pressed.connect(func() -> void: _redo())
	row.add_child(redo_btn)


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
		[Tool.SELECT, "Select / Move"],
		[Tool.WALL, "Wall run"],
		[Tool.ROOM, "Room"],
		[Tool.DECK, "Deck plate"],
		[Tool.OPENING, "Opening"],
	]
	for tool_def in tool_defs:
		var tool: Tool = tool_def[0]
		var btn := UiBuilder.tool_button(str(tool_def[1]), 0.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 38)
		btn.pressed.connect(func() -> void: _set_tool(tool))
		box.add_child(btn)
		_tool_buttons[tool] = btn
	_opening_section = VBoxContainer.new()
	_opening_section.add_theme_constant_override("separation", 4)
	_opening_section.add_child(UiBuilder.section_header("OPENING TYPE"))
	for opening_type in [StructurePlan.OPENING_DOOR, StructurePlan.OPENING_WINDOW, StructurePlan.OPENING_HOLE]:
		var btn := UiBuilder.tool_button(opening_type.capitalize(), 0.0)
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
	level_down.pressed.connect(func() -> void: _set_build_level(_active_base - 1.0))
	level_row.add_child(level_down)
	_level_label = Label.new()
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_level_label, 12, HudStyle.C_TEXT, true)
	level_row.add_child(_level_label)
	var level_up := UiBuilder.compact_button("+", 34.0)
	level_up.pressed.connect(func() -> void: _set_build_level(_active_base + 1.0))
	level_row.add_child(level_up)
	box.add_child(level_row)
	var ghost_btn := UiBuilder.tool_button("Ghost upper decks", 0.0)
	ghost_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ghost_btn.pressed.connect(func() -> void:
		_ghost_levels = not _ghost_levels
		_rebake()
		_refresh_panel()
	)
	box.add_child(ghost_btn)
	_ghost_button = ghost_btn
	var roofs_btn := UiBuilder.tool_button("Show roofs  [T]", 0.0)
	roofs_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roofs_btn.pressed.connect(func() -> void:
		_show_roofs = not _show_roofs
		_rebake()
		_refresh_panel()
	)
	box.add_child(roofs_btn)
	_roofs_button = roofs_btn
	box.add_child(UiBuilder.separator())
	_entities_label = Label.new()
	_entities_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_entities_label, 12, HudStyle.C_LABEL)
	box.add_child(_entities_label)
	var hints := Label.new()
	hints.text = "RMB orbit · MMB pan · wheel zoom\nPgUp/PgDn build level · F focus\nDEL delete · Ctrl+Z / Ctrl+Y"
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(hints, 11, HudStyle.C_LABEL)
	box.add_child(hints)


func _build_drawer() -> void:
	_drawer = UiBuilder.panel(Vector2(272, 0))
	_drawer.name = "PropertiesDrawer"
	_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_top = 60.0
	_drawer.offset_bottom = -50.0
	_ui_root.add_child(_drawer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_drawer.add_child(box)
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
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("STRUCTURE FILE"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "structure name…"
	_name_edit.max_length = 32
	box.add_child(_name_edit)
	var save_btn := UiBuilder.compact_button("Save JSON", 0.0)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func() -> void: _save_plan(_name_edit.text))
	box.add_child(save_btn)
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
	_rebake()
	_refresh_panel()


func _refresh_panel() -> void:
	if _status_label == null:
		return
	for tool in _tool_buttons.keys():
		(_tool_buttons[tool] as Button).set_pressed_no_signal(tool == _tool)
	for context in _context_buttons.keys():
		(_context_buttons[context] as Button).set_pressed_no_signal(context == _context)
	_opening_section.visible = _tool == Tool.OPENING
	for opening_type in _opening_buttons.keys():
		(_opening_buttons[opening_type] as Button).set_pressed_no_signal(opening_type == _opening_type)
	_level_label.text = "%.0f m" % _active_base
	_ghost_button.set_pressed_no_signal(_ghost_levels)
	_roofs_button.set_pressed_no_signal(_show_roofs)
	for slot in _slot_buttons.keys():
		(_slot_buttons[slot] as Button).set_pressed_no_signal(slot == _armed_slot)
	var armed_material := str((_lib[_armed_slot] as Dictionary)["material"])
	for material_name in _lib_material_buttons.keys():
		(_lib_material_buttons[material_name] as Button).set_pressed_no_signal(material_name == armed_material)
	_entities_label.text = "Entities: %d\nUndo steps: %d" % [_plan.entity_count(), _undo_stack.size()]
	_hull_option.visible = _context == "vessel"
	_context_label.text = (
		"Vessel — %s" % _hull_id if _context == "vessel" else "Land building"
	)
	_hint_label.text = str(TOOL_HINTS.get(_tool, ""))
	_refresh_load_list()
	_refresh_inspector()


func _refresh_load_list() -> void:
	var previous := _load_option.selected
	_load_option.clear()
	var paths := _saved_plan_paths()
	for index in paths.size():
		_load_option.add_item(paths[index].get_file(), index)
		_load_option.set_item_metadata(index, paths[index])
	if previous >= 0 and previous < _load_option.item_count:
		_load_option.select(previous)


func _refresh_inspector() -> void:
	for child in _inspector_box.get_children():
		child.queue_free()
	var entity := _plan.entity_by_id(_selected_id)
	if _selected_id < 0 or entity.is_empty():
		_drawer_info.text = "Nothing selected. Use Select / Move and click a wall, room or deck plate."
		return
	var kind := "wall"
	if entity.has("axis"):
		kind = "wall"
	elif entity.has("size") and (entity.get("size") as Array).size() == 3:
		kind = "room"
	else:
		kind = "deck"
	_drawer_info.text = ""
	var header := Label.new()
	header.text = "%s  #%d" % [kind.to_upper(), _selected_id]
	HudStyle.apply_body_font(header, 13, HudStyle.C_AMBER, true)
	_inspector_box.add_child(header)
	var fields: Array = []
	match kind:
		"wall":
			fields = [["length", 1.0, 60.0, 1.0], ["height", 0.5, 12.0, 0.5], ["thickness", 0.05, 0.5, 0.05]]
		"deck":
			fields = [["thickness", 0.05, 0.5, 0.05]]
	for field in fields:
		var field_name := str(field[0])
		_inspector_box.add_child(_spin_row(
			field_name, float(entity.get(field_name, 1.0)),
			float(field[1]), float(field[2]), float(field[3]),
			func(value: float) -> void:
				_snapshot()
				entity[field_name] = value
				_rebake()
		))
	if kind == "room":
		var size_list: Array = entity.get("size", [4, 3, 4])
		var axis_names := ["width", "height", "length"]
		for axis_index in 3:
			var captured := axis_index
			_inspector_box.add_child(_spin_row(
				axis_names[axis_index], float(size_list[axis_index]), 1.0, 60.0, 0.5,
				func(value: float) -> void:
					_snapshot()
					(entity["size"] as Array)[captured] = value
					_rebake()
			))
		## Open-top holds / floorless shelters: toggle either plate.
		var plate_row := HBoxContainer.new()
		plate_row.add_theme_constant_override("separation", 6)
		for plate_def in [["roof", "Roof"], ["floor", "Floor"]]:
			var plate_key := str(plate_def[0])
			var plate_btn := UiBuilder.tool_button(str(plate_def[1]), 0.0)
			plate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			plate_btn.set_pressed_no_signal(bool(entity.get(plate_key, true)))
			plate_btn.pressed.connect(func() -> void:
				_snapshot()
				entity[plate_key] = not bool(entity.get(plate_key, true))
				_rebake()
				_refresh_panel()
			)
			plate_row.add_child(plate_btn)
		_inspector_box.add_child(plate_row)
	## Surface readout — painting happens through the armed MATERIAL LIBRARY.
	if kind == "room":
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Outside", str(entity.get("material_out", "painted")).capitalize()
		))
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Inside", str(entity.get("material_in", "wood")).capitalize()
		))
	else:
		_inspector_box.add_child(UiBuilder.key_value_row(
			"Surface", str(entity.get("material", "painted")).capitalize()
		))
	var openings: Array = entity.get("openings", [])
	if not openings.is_empty():
		var opening_info := Label.new()
		opening_info.text = "Openings: %d" % openings.size()
		HudStyle.apply_body_font(opening_info, 12, HudStyle.C_TEXT)
		_inspector_box.add_child(opening_info)
		var pop_btn := UiBuilder.compact_button("Remove last opening", 0.0)
		pop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pop_btn.pressed.connect(func() -> void:
			_snapshot()
			openings.pop_back()
			_rebake()
			_refresh_panel()
		)
		_inspector_box.add_child(pop_btn)
	_inspector_box.add_child(UiBuilder.separator())
	var delete_btn := UiBuilder.compact_button("Delete entity  [DEL]", 0.0)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.add_theme_color_override("font_color", HudStyle.C_RED)
	delete_btn.add_theme_color_override("font_hover_color", HudStyle.C_RED)
	delete_btn.pressed.connect(func() -> void: _delete_selected())
	_inspector_box.add_child(delete_btn)


## The standing right-hand surface library. Modal: arm Outside or Inside, then
## clicks on materials/swatches paint that slot of the current selection AND
## become the default style for everything drawn next.
func _build_library_section(box: VBoxContainer) -> void:
	box.add_child(UiBuilder.section_header("MATERIAL LIBRARY"))
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	for slot_def in [["out", "Outside"], ["in", "Inside"]]:
		var slot := str(slot_def[0])
		var btn := UiBuilder.tool_button(str(slot_def[1]), 0.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			_armed_slot = slot
			_refresh_panel()
		)
		slot_row.add_child(btn)
		_slot_buttons[slot] = btn
	box.add_child(slot_row)
	var material_flow := HFlowContainer.new()
	material_flow.add_theme_constant_override("h_separation", 4)
	material_flow.add_theme_constant_override("v_separation", 4)
	for material_name in MATERIAL_LIBRARY:
		var btn := UiBuilder.tool_button(material_name.capitalize(), 62.0)
		btn.pressed.connect(func() -> void: _apply_library_material(material_name))
		material_flow.add_child(btn)
		_lib_material_buttons[material_name] = btn
	box.add_child(material_flow)
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 4)
	swatches.add_theme_constant_override("v_separation", 4)
	for swatch_variant in COLOR_LIBRARY:
		var swatch_color := swatch_variant[1] as Color
		var swatch := Button.new()
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.tooltip_text = str(swatch_variant[0])
		var sb := StyleBoxFlat.new()
		sb.bg_color = swatch_color
		sb.border_color = HudStyle.C_BRASS
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		swatch.add_theme_stylebox_override("normal", sb)
		swatch.add_theme_stylebox_override("hover", sb)
		swatch.add_theme_stylebox_override("pressed", sb)
		swatch.pressed.connect(func() -> void:
			_apply_library_color([swatch_color.r, swatch_color.g, swatch_color.b])
		)
		swatches.add_child(swatch)
	box.add_child(swatches)


func _library_keys_for_selection() -> Dictionary:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty():
		return {}
	var is_room := entity.has("size") and (entity.get("size") as Array).size() == 3
	if is_room:
		return {
			"entity": entity,
			"color": "color_out" if _armed_slot == "out" else "color_in",
			"material": "material_out" if _armed_slot == "out" else "material_in",
		}
	## Walls and plates carry a single surface — both slots address it.
	return {"entity": entity, "color": "color", "material": "material"}


func _apply_library_color(rgb: Array) -> void:
	(_lib[_armed_slot] as Dictionary)["color"] = rgb.duplicate()
	var keys := _library_keys_for_selection()
	if not keys.is_empty():
		_snapshot()
		(keys["entity"] as Dictionary)[str(keys["color"])] = rgb.duplicate()
		_rebake()
	_set_status("%s colour set" % ("outside" if _armed_slot == "out" else "inside"))
	_refresh_panel()


func _apply_library_material(material_name: String) -> void:
	(_lib[_armed_slot] as Dictionary)["material"] = material_name
	var keys := _library_keys_for_selection()
	if not keys.is_empty():
		_snapshot()
		(keys["entity"] as Dictionary)[str(keys["material"])] = material_name
		_rebake()
	_set_status("%s material: %s" % ["outside" if _armed_slot == "out" else "inside", material_name])
	_refresh_panel()


## Style every new entity with the armed library so drawing is paint-first.
func _stamp_library_style(entity: Dictionary, is_room: bool) -> void:
	var out := _lib["out"] as Dictionary
	if is_room:
		var interior := _lib["in"] as Dictionary
		entity["color_out"] = (out["color"] as Array).duplicate()
		entity["material_out"] = str(out["material"])
		entity["color_in"] = (interior["color"] as Array).duplicate()
		entity["material_in"] = str(interior["material"])
	else:
		entity["color"] = (out["color"] as Array).duplicate()
		entity["material"] = str(out["material"])


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
