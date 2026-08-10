extends Node3D

## STRUCTURE STUDIO — the unified parametric builder for vessels and land
## buildings. Replaces the separate shipyard/building brick editors.
##
## Structure is drawn, not stacked:
##   P  piece tool   — pick a piece off the KIT palette, R turns it, click a grid
##                     NODE to stand it there. Every parameter is a stepper or a
##                     dropdown over the piece's own declared set: there is no
##                     field in this tool a number can be typed into, which is the
##                     whole difference between a kit and CAD.
##   W  wall tool    — click-drag along the grid, release to place a wall run
##   D  deck tool    — click-drag a rectangle deck plate
##   S  stairs       — click-drag along the climb direction: a solid stepped
##                     run rising one level, walkable as rendered
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
##
## This app carries its own self-check and DECLARES it to the gate below. The
## gate discovers lane C by this marker alone — there is no list of app names in
## tools/gate.sh, so a second such app joins by adding one line to its own
## script, exactly like `## gate-requires:`.
##
## gate-selfcheck: res://scenes/apps/structure_studio.tscn -- --studio-probe

const STRUCTURES_DIR := "res://resources/data/structures"

## ── The two snaps, and why there are two ────────────────────────────────────
##
## `GRID_SNAP` is 1 m and always was. It is the snap of the DRAW tools (wall,
## deck, stair) and of the move gizmo, and it is not merely a preference: those
## tools re-round in metres anyway — `_place_wall` calls `roundf` on the start and
## the length, `_place_deck` on the origin and both extents — so a half-metre
## cursor would be thrown away one line later. Changing it is a change to those
## three tools, not to this one, and it is left alone here on purpose.
##
## `NODE_SNAP` is the deck cell, 0.5 m, and it is the PIECE tool's snap. It is
## not a new number: `WorldUnits.DECK_CELL_M` is the cell the whole kit counts in
## (`structure_pieces.json` declares `cell_m: 0.5` and `PieceKit` refuses to load
## if the two disagree), and it is ALREADY the spacing this studio draws its grid
## lines at — `_build_grid_lines` steps by `DeckGrid.CELL_M`. So before this tool
## existed the studio drew a 0.5 m grid and snapped to every OTHER line of it,
## and the bottom strip called that "GRID 1 M". The piece tool snaps to the lines
## you can actually see, which is the reconciliation: one of the two numbers was
## describing the drawing and the other was describing the cursor.
const GRID_SNAP := 1.0
const NODE_SNAP := WorldUnits.DECK_CELL_M
const DEFAULT_WALL_HEIGHT := 3.0
## The opening ghost stands this far proud of each face of its host, so the
## preview is visible against the wall it is about to cut instead of z-fighting
## with it.
const OPENING_GHOST_PROUD := 0.07

## Shared colour + material library (maritime palette, StructureBaker materials).
const COLOR_LIBRARY: Array = [
	["Steel", Color(0.62, 0.65, 0.68)], ["White", Color(0.92, 0.93, 0.94)],
	["Cream", Color(0.90, 0.86, 0.76)], ["Timber", Color(0.62, 0.50, 0.38)],
	["Charcoal", Color(0.24, 0.26, 0.28)], ["Slate", Color(0.42, 0.48, 0.52)],
	["Hull red", Color(0.55, 0.20, 0.16)], ["Harbour", Color(0.28, 0.44, 0.52)],
	["Yellow", Color(0.86, 0.68, 0.20)],
]
const MATERIAL_LIBRARY: Array[String] = ["painted", "metal", "wood", "steel"]

## Tints a PLACEMENT may be painted, as exact `#rrggbb` strings.
##
## Hex, not `Color`, and that is deliberate: a placement stores its colour as
## html text, and a swatch defined as floats would go out through
## `Color.to_html` and could land a digit off the tint a fixture was authored
## with. These are the strings themselves, so a swatch and a fixture compare
## equal by construction.
##
## The list carries the maritime tints the fleet's piece-built vessels actually
## use. Every piece's OWN declared colour is offered too, read out of
## `structure_pieces.json` at runtime by `_piece_tints()` — this studio holds no
## piece names and no parameter sets.
const PIECE_TINT_LIBRARY: Array = [
	["Mist grey", "#858a8f"],
	["Funnel ochre", "#9e5c1c"],
	["Near black", "#1c1c1f"],
	["Hull red", "#8c3328"],
	["Harbour blue", "#2f4d5c"],
	["Signal yellow", "#d8a52a"],
]

enum Tool { SELECT, WALL, DECK, STAIR, OPENING, PIECE }

const DEFAULT_STAIR_WIDTH := 1.0

var _plan := StructurePlan.new()
var _context := "vessel"
var _hull_id := "hull_28x10"
var _grid_width := 10
var _grid_length := 28
var _plan_offset := Vector3.ZERO ## grid-corner space -> world

var _tool: Tool = Tool.WALL
var _active_base := 0.0 ## y level being drawn on
var _ghost_levels := true ## structure above the build level renders as x-ray
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
## id -> the ROTATED boxes it renders, world space, only for entities that have
## any (diagonal walls). Their AABB is a loose square, so the cursor is retested
## against these; everything else is its own bound and never lands here.
var _entity_yawed_boxes: Dictionary = {}
## Always-on cursor feedback: what THIS click will do, exactly where.
var _opening_ghost: MeshInstance3D ## the actual door/window/hole, snapped, on its host
var _hover_box: MeshInstance3D ## copper pre-selection outline under the cursor
var _start_marker: MeshInstance3D ## snapped grid point a draw-drag would start from

var _status := ""

## ── Piece tool state ────────────────────────────────────────────────────────
##
## Nothing here names a piece or a parameter. `_piece_id` is whatever
## `PieceKit.ids()` handed the palette, `_piece_params` is keyed by whatever the
## kit declares, and `_piece_settings` remembers a player's settings per piece so
## picking up the corner facet and coming back to the wall panel does not reset
## it. When the kit widens a value set — the rake to eighth-cells, a camber list
## — every stepper in this file follows it with no edit here.
var _piece_id := ""
var _piece_facing := 0
var _piece_color := "" ## "" means "the piece's own declared colour"
var _piece_settings: Dictionary = {} ## piece id -> {param: value}
var _piece_ghost: Node3D
var _piece_ghost_key := ""
## The placement the ghost is currently drawing, or {} when nothing is previewed.
## The commit path places THIS dictionary, which is what makes "it lands where
## the ghost showed it" a property rather than a hope.
var _piece_ghost_placement: Dictionary = {}
var _piece_buttons: Dictionary = {}
var _piece_section: VBoxContainer
var _piece_param_box: VBoxContainer
var _piece_tint_box: HFlowContainer
var _piece_facing_label: Label
var _piece_param_key := ""


func _ready() -> void:
	_build_scene()
	_build_ui()
	_set_context("vessel")
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--studio-probe":
			_run_studio_probe()


## Headless CI workout: drives every tool through its real placement path,
## exercises selection/inspector, undo/redo and save/load, then quits with a
## non-zero exit code on the first broken invariant.
## Run: godot --headless scenes/apps/structure_studio.tscn -- --studio-probe
func _run_studio_probe() -> void:
	var failed: Array[String] = []
	## Counted, so the verdict line can state how many claims were made. A run
	## that asserts nothing must not be able to read as a pass.
	var tally := {"checks": 0}
	var expect := func(label: String, ok: bool) -> void:
		tally["checks"] = int(tally["checks"]) + 1
		if not ok:
			failed.append(label)
	_place_wall(Vector3(0, 0, 6), Vector3(6, 0, 6))
	_place_wall(Vector3(1, 0, 8), Vector3(1, 0, 12))
	_place_deck(Vector3(0, 0, 20), Vector3(6, 0, 24))
	_place_stair(Vector3(1, 0, 24), Vector3(1, 0, 27))
	expect.call("four entities placed", _plan.entity_count() == 4)
	expect.call("one stair in the plan", _plan.stairs.size() == 1)
	## Upper deck first, then a stair beneath it: placement must auto-cut a
	## stairwell through the landing (and the build level must follow).
	_set_build_level(3.0)
	_place_deck(Vector3(6, 3, 14), Vector3(9, 3, 18))
	_set_build_level(0.0)
	_place_stair(Vector3(7, 0, 14), Vector3(7, 0, 18))
	var upper_deck := _plan.decks[1] as Dictionary
	expect.call("upper deck placed at the raised build level", StructurePlan.vec3_of(upper_deck.get("origin")).y == 3.0)
	var auto_holes := upper_deck.get("openings", []) as Array
	expect.call("stair auto-cuts a stairwell in the deck above", auto_holes.size() == 1)
	if auto_holes.size() == 1:
		expect.call(
			"auto stairwell is a stairwell cut",
			str((auto_holes[0] as Dictionary).get("type")) == StructurePlan.OPENING_STAIRWELL
		)
	for collection in [_plan.walls, _plan.decks, _plan.stairs]:
		for entity_variant in collection:
			var id := int((entity_variant as Dictionary).get("id", -1))
			expect.call("entity #%d pickable (has bounds)" % id, _entity_bounds.has(id))
	## Inspector must build for every kind, including the stair fields.
	for collection in [_plan.walls, _plan.decks, _plan.stairs]:
		_selected_id = int((collection[0] as Dictionary).get("id", -1))
		_update_selection_visual()
		_refresh_panel()
	_selected_id = -1
	_probe_diagonal_wall(expect)
	## Cut a door into a wall and confirm the wall panels split around it.
	var door_wall := _plan.walls[0] as Dictionary
	(door_wall["openings"] as Array).append({"type": "door", "offset": 1.0, "width": 1.6, "height": 2.2})
	_rebake()
	var undo_before := _plan.entity_count()
	_undo()
	_undo()
	_redo()
	_redo()
	expect.call("undo/redo returns to the same plan", _plan.entity_count() == undo_before)
	_save_plan("studio_probe_tmp")
	var probe_path := "%s/studio_probe_tmp.json" % STRUCTURES_DIR
	_set_context("vessel") ## wipes the plan
	expect.call("context switch clears the plan", _plan.is_empty())
	_load_plan(probe_path)
	expect.call("save/load restores all entities", _plan.entity_count() == 7)
	expect.call("save/load keeps the stairs", _plan.stairs.size() == 2)
	expect.call(
		"save/load keeps the cut made in a plain wall",
		((_plan.walls[0] as Dictionary).get("openings", []) as Array).size() == 1
	)
	var reloaded_diagonal: Dictionary = {}
	for wall_variant in _plan.walls:
		if StructurePlan.is_diagonal_axis(str((wall_variant as Dictionary).get("axis", ""))):
			reloaded_diagonal = wall_variant as Dictionary
	expect.call("save/load keeps the diagonal axis", str(reloaded_diagonal.get("axis", "")) == "+x-z")
	expect.call(
		"save/load keeps the cut made in the diagonal",
		(reloaded_diagonal.get("openings", []) as Array).size() == 1
	)
	expect.call(
		"reloaded diagonal is still bounded in world space",
		_probe_bounds_hold(reloaded_diagonal)
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))
	var built_count := _plan.entity_count()
	## The shipped fixture this work was measured against: four 45° walls read
	## off disk, every one of them bounded in world space rather than in its
	## own frame.
	_load_plan("%s/probe_trawler_bow_bulwark.json" % STRUCTURES_DIR)
	var diagonals := 0
	var bounded := 0
	for wall_variant in _plan.walls:
		var fixture_wall := wall_variant as Dictionary
		if not StructurePlan.is_diagonal_axis(str(fixture_wall.get("axis", ""))):
			continue
		diagonals += 1
		if _probe_bounds_hold(fixture_wall):
			bounded += 1
	expect.call("bow bulwark fixture loads its four diagonals", diagonals == 4)
	expect.call("every fixture diagonal is bounded in world space", bounded == diagonals)
	## ── The piece tool ──────────────────────────────────────────────────────
	_probe_piece_controls(expect)
	_probe_piece_mouse(expect)
	_probe_piece_selection(expect)
	_probe_piece_persistence(expect)
	_probe_piece_fixture(expect, "%s/probe_piece_trawler.json" % STRUCTURES_DIR, "trawler")
	_probe_piece_fixture(expect, "%s/probe_piece_tug.json" % STRUCTURES_DIR, "tug")
	_probe_piece_tug_recipe(expect)
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--studio-write-fixtures":
			_write_tug_fixture()
	## Speak the suite's verdict language so the gate can tell "ran and passed"
	## from "booted, said nothing, exited 0". A self-check that declares no
	## outcome has not passed — see lane C in tools/gate.sh.
	var checks := int(tally["checks"])
	if checks == 0:
		print("studio_probe: NO CHECKS RAN")
		get_tree().quit(1)
	elif failed.is_empty():
		print("[structure-studio] probe ok — context=%s entities=%d" % [_context, built_count])
		print("studio_probe: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for label in failed:
			print("[structure-studio] probe FAIL — %s" % label)
		print("studio_probe: %d/%d FAILED" % [failed.size(), checks])
		get_tree().quit(1)


## Diagonal-wall leg of the probe. A 45° wall is the case every "is this an
## x-wall or a z-wall?" shortcut gets wrong: what bounds it, what a click
## picks, what F focuses on, and where an opening lands.
func _probe_diagonal_wall(expect: Callable) -> void:
	var start := Vector3(1, 0, 5)
	var length := 6.0
	var wall := _plan.add_wall(start, "+x-z", length, DEFAULT_WALL_HEIGHT)
	_rebake()
	var id := int(wall.get("id", -1))
	expect.call("diagonal wall is pickable (has bounds)", _entity_bounds.has(id))
	expect.call("diagonal bounds contain the geometry the baker draws", _probe_bounds_hold(wall))
	if not _entity_bounds.has(id):
		return
	var bounds := _entity_bounds[id] as AABB
	## A 6 m wall at 45° covers ~4.24 m on BOTH world axes. Measured in the
	## box's own frame it reports 6 × 0.2 and selection aims at empty space.
	expect.call(
		"diagonal bound spans both world axes",
		bounds.size.x > 4.0 and bounds.size.z > 4.0
	)
	var run := StructurePlan.wall_run("+x-z")
	var mid := (
		start + run * (length * 0.5)
		+ Vector3(0.0, DEFAULT_WALL_HEIGHT * 0.5, 0.0) + _plan_offset
	)
	## Where the gizmo sits and what F flies the camera to.
	expect.call("diagonal bound centres on its mid-run", bounds.get_center().distance_to(mid) < 0.05)
	_selected_id = id
	_update_selection_visual()
	_refresh_panel()
	expect.call(
		"selecting the diagonal wraps it",
		_selection_box.visible and _selection_box.position.distance_to(mid) < 0.05
	)
	## The bound is a 4.3 m square with the wall on its diagonal, so most of it
	## is empty air. The cursor must not pick the wall out there.
	var corner := Vector3(
		bounds.position.x + bounds.size.x - 0.4,
		bounds.position.y + bounds.size.y + 5.0,
		bounds.position.z + bounds.size.z - 0.4,
	)
	expect.call(
		"a ray down an empty corner of the bound misses the diagonal",
		_entity_ray_hit(id, corner, Vector3.DOWN) == null
	)
	expect.call(
		"a ray down onto the wall itself still hits it",
		_entity_ray_hit(id, Vector3(mid.x, corner.y, mid.z), Vector3.DOWN) != null
	)
	## Now a REAL cursor ray, square to the wall and aimed 2 m along the run,
	## driven through pick -> context -> commit exactly as a click would be.
	var across := Vector3(-run.z, 0.0, run.x)
	var aim := start + run * 2.0 + Vector3(0.0, 1.2, 0.0) + _plan_offset
	_camera.position = aim - across * 14.0 + Vector3(0.0, 5.0, 0.0)
	_camera.look_at(aim, Vector3.UP)
	var screen := _camera.unproject_position(aim)
	var ctx := _opening_context_at(screen)
	expect.call(
		"cursor ray picks the diagonal",
		int((ctx.get("entity", {}) as Dictionary).get("id", -1)) == id
	)
	if str(ctx.get("kind", "")) == "wall":
		expect.call(
			"the run reads 2 m along where 2 m along was aimed at",
			absf(_ctx_along(ctx, ctx["point"] as Vector3) - 2.0) < 0.05
		)
	_set_tool(Tool.OPENING)
	_begin_opening_drag(screen)
	## The ghost is the ONLY preview of where the cut will land, and its yaw was
	## unasserted: a regression drawing the preview lying ACROSS a diagonal
	## instead of in it would ship silently, because the committed opening would
	## still be correct and every other check would stay green.
	_update_opening_drag(screen)
	expect.call("opening ghost is shown while dragging on the diagonal", _opening_ghost.visible)
	expect.call(
		"opening ghost carries the wall's yaw",
		absf(wrapf(
			_opening_ghost.rotation.y - deg_to_rad(StructureBaker.wall_yaw_deg(wall)), -PI, PI
		)) < 0.001
	)
	## Geometric form of the same claim, and the one that also catches a yaw that
	## is merely non-zero. Turned into the wall the ghost reaches only its own
	## half thickness (0.153 m) across the run; left axis-aligned on this 45°
	## wall its corners reach ~0.46 m, well outside the wall it is previewing.
	var ghost_limit := (
		float(wall.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS)) * 0.5
		+ OPENING_GHOST_PROUD + 0.001
	)
	expect.call(
		"opening ghost lies IN the diagonal, not across it",
		_probe_ghost_across_reach(wall) <= ghost_limit
	)
	_commit_opening(screen)
	var openings := wall.get("openings", []) as Array
	expect.call("opening punched into the diagonal", openings.size() == 1)
	if openings.size() == 1:
		## Default door is 2 m wide, centred on the aim: 1 m from the start.
		expect.call(
			"the cut lands where it was aimed",
			absf(float((openings[0] as Dictionary).get("offset", -1.0)) - 1.0) < 0.01
		)
	expect.call(
		"diagonal panels split around the cut",
		StructureBaker.wall_panels(wall).size() >= 3
	)
	expect.call("bounds still hold with the cut in place", _probe_bounds_hold(wall))
	## Same wall, cursor coming in 45° off square at 4 m along the run. The
	## reading has to stay on the surface it aimed at — measuring where the ray
	## enters the BOUND instead puts this ~2 m down the wall.
	var oblique_aim := start + run * 4.0 + Vector3(0.0, 1.2, 0.0) + _plan_offset
	_camera.position = oblique_aim - Vector3.RIGHT * 16.0 + Vector3(0.0, 5.0, 0.0)
	_camera.look_at(oblique_aim, Vector3.UP)
	var oblique := _opening_context_at(_camera.unproject_position(oblique_aim))
	expect.call(
		"an oblique cursor still reads 4 m along the run",
		str(oblique.get("kind", "")) == "wall"
		and absf(_ctx_along(oblique, oblique["point"] as Vector3) - 4.0) < 0.3
	)
	_selected_id = -1
	_set_tool(Tool.WALL)
	_update_selection_visual()


## How far the opening ghost reaches ACROSS the wall it previews, worst corner,
## measured from the wall's own centre plane. A ghost turned onto its host
## reaches exactly its own half thickness; one left axis-aligned on a diagonal
## reaches most of its length, which is a preview of a cut somewhere else.
func _probe_ghost_across_reach(wall: Dictionary) -> float:
	var run := StructurePlan.wall_run(str(wall.get("axis", "x")))
	var across := Vector3(-run.z, 0.0, run.x)
	var start := StructurePlan.vec3_of(wall.get("start")) + _plan_offset
	var half := ((_opening_ghost.mesh as BoxMesh).size) * 0.5
	var ghost := _opening_ghost.transform
	var worst := 0.0
	for corner in 8:
		var local := Vector3(
			half.x if (corner & 1) != 0 else -half.x,
			half.y if (corner & 2) != 0 else -half.y,
			half.z if (corner & 4) != 0 else -half.z,
		)
		worst = maxf(worst, absf(((ghost * local) - start).dot(across)))
	return worst


## Every vertex StructureBaker actually draws for this wall, in world space:
## own-frame corners turned by the wall's basis. Anything that bounds, picks
## or focuses the wall has to agree with THESE points.
func _probe_wall_vertices(wall: Dictionary) -> PackedVector3Array:
	var wall_basis := StructureBaker.wall_basis(wall)
	var points := PackedVector3Array()
	for box_variant in StructureBaker.wall_boxes(wall):
		var box := box_variant as Dictionary
		var half := (box["size"] as Vector3) * 0.5
		for corner in 8:
			var local := Vector3(
				half.x if (corner & 1) != 0 else -half.x,
				half.y if (corner & 2) != 0 else -half.y,
				half.z if (corner & 4) != 0 else -half.z,
			)
			points.append((box["center"] as Vector3) + wall_basis * local + _plan_offset)
	return points


## True when the studio's bound for a wall contains everything that wall
## renders. A diagonal fails this the instant its bound is read axis-aligned
## in the box's own frame.
func _probe_bounds_hold(wall: Dictionary) -> bool:
	var id := int(wall.get("id", -1))
	if not _entity_bounds.has(id):
		return false
	var bounds := (_entity_bounds[id] as AABB).grow(0.001)
	for point in _probe_wall_vertices(wall):
		if not bounds.has_point(point):
			return false
	return true


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
			## Cell index -> metres. DeckGrid.CELL_M is 0.5, so a cell index is NOT a
			## metre offset; treating it as one drew the grid at twice the hull's size
			## the moment the cell was halved for build detail.
			var c := DeckGrid.CELL_M
			var p := _plan_offset + Vector3(float(ix) * c, y, float(iz) * c)
			match shape:
				DeckGrid.CellShape.NONE:
					continue
				DeckGrid.CellShape.BOW_PORT_HALF:
					## Solid corner is (+X, +Z); hypotenuse from (0,1) to (1,0)… draw
					## diagonal plus the two kept edges.
					im.surface_add_vertex(p + Vector3(c, 0, 0))
					im.surface_add_vertex(p + Vector3(0, 0, c))
					im.surface_add_vertex(p + Vector3(c, 0, 0))
					im.surface_add_vertex(p + Vector3(c, 0, c))
					im.surface_add_vertex(p + Vector3(0, 0, c))
					im.surface_add_vertex(p + Vector3(c, 0, c))
				DeckGrid.CellShape.BOW_STARBOARD_HALF:
					im.surface_add_vertex(p + Vector3(0, 0, 0))
					im.surface_add_vertex(p + Vector3(c, 0, c))
					im.surface_add_vertex(p + Vector3(0, 0, 0))
					im.surface_add_vertex(p + Vector3(0, 0, c))
					im.surface_add_vertex(p + Vector3(0, 0, c))
					im.surface_add_vertex(p + Vector3(c, 0, c))
				_:
					im.surface_add_vertex(p)
					im.surface_add_vertex(p + Vector3(c, 0, 0))
					im.surface_add_vertex(p)
					im.surface_add_vertex(p + Vector3(0, 0, c))
					im.surface_add_vertex(p + Vector3(c, 0, 0))
					im.surface_add_vertex(p + Vector3(c, 0, c))
					im.surface_add_vertex(p + Vector3(0, 0, c))
					im.surface_add_vertex(p + Vector3(c, 0, c))
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
		["BOW", Vector3(_grid_width * 0.5, 0.06, -1.4), 0.0, BrandTokens.BRASS],
		["STERN", Vector3(_grid_width * 0.5, 0.06, _grid_length + 1.4), 180.0, BrandTokens.INK_INVERSE_DIM],
		["PORT", Vector3(-1.6, 0.06, _grid_length * 0.5), 90.0, BrandTokens.ALERT],
		["STARBOARD", Vector3(_grid_width + 1.6, 0.06, _grid_length * 0.5), 270.0, BrandTokens.OK_LIGHT],
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
		for collection in [target.walls, target.decks, target.stairs]:
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
		## A placement's level is its grid NODE, which is counted in cells, not
		## metres — reading `start`/`origin` off it (there is neither) put every
		## piece at y = 0 and ghosted an entire wheelhouse that was in front of you.
		var kept_pieces: Array = []
		for placement_variant in target.pieces:
			var placement := placement_variant as Dictionary
			var node_y := StructurePlan.piece_node_plan(
				StructurePlan.piece_cell(placement)
			).y
			if (node_y < threshold) == keep_below:
				kept_pieces.append(placement)
				if not keep_below:
					any_ghost = true
		target.pieces.assign(kept_pieces)
	_bake_root = StructureBaker.bake(_resolved_for_bake(solid_plan), _plan_offset)
	add_child(_bake_root)
	if any_ghost:
		_ghost_root = StructureBaker.bake(_resolved_for_bake(ghost_plan), _plan_offset, true)
		add_child(_ghost_root)
	_recompute_bounds()
	_update_selection_visual()


func _recompute_bounds() -> void:
	_entity_bounds.clear()
	_entity_base_y.clear()
	_entity_yawed_boxes.clear()
	for collection in [_plan.walls, _plan.decks, _plan.stairs]:
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
	for stair_variant in expanded["stairs"] as Array:
		var stair := stair_variant as Dictionary
		for box_variant in StructureBaker.stair_boxes(stair):
			_grow_bounds(int(stair.get("source_id", -1)), box_variant as Dictionary)
	## A placement's bound is its own resolved plates, taken to plan space by the
	## kit's own `placed_corners` — the same transform the baker applies. Bounding
	## it any other way is a second implementation of the placement, and the
	## diagonal-wall bug in this same file is what that costs: a bound read in a
	## frame nothing else uses puts selection, picking and F on empty air.
	for placement_variant in _plan.pieces:
		var placement := placement_variant as Dictionary
		var id := int(placement.get("id", -1))
		_entity_base_y[id] = StructurePlan.piece_node_plan(
			StructurePlan.piece_cell(placement)
		).y
		var resolved := PieceKit.resolve_placement(placement, 1)
		for step in (resolved["items"] as Array).size():
			for corner in PieceKit.placed_corners(placement, step):
				_grow_point_bounds(id, corner + _plan_offset)


## Grows an entity's world bound by one baked box. `size` is stated in the
## BOX's own frame, so a yawed box (any diagonal wall) has to have its corners
## turned into plan space first — reading the size axis-aligned bounded the
## diagonal in a frame nothing else uses, and selection, picking and focus all
## landed off the wall.
## Grows an entity's world bound by one POINT. A plate is four free corners and
## has no box to read a size off, so the corners themselves are the bound.
func _grow_point_bounds(source_id: int, point: Vector3) -> void:
	if source_id < 0:
		return
	if _entity_bounds.has(source_id):
		_entity_bounds[source_id] = (_entity_bounds[source_id] as AABB).expand(point)
	else:
		_entity_bounds[source_id] = AABB(point, Vector3.ZERO)


func _grow_bounds(source_id: int, box: Dictionary) -> void:
	if source_id < 0:
		return
	var center := (box["center"] as Vector3) + _plan_offset
	var size := box["size"] as Vector3
	var yaw := float(box.get("yaw_deg", 0.0))
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var half := size * 0.5
	## Half-extent of the rotated box on each world axis: the corner that
	## maximises every component is the sum of the |column| contributions.
	var extent := basis.x.abs() * half.x + basis.y.abs() * half.y + basis.z.abs() * half.z
	var aabb := AABB(center - extent, extent * 2.0)
	if not is_zero_approx(yaw):
		## A yawed box's bound is much bigger than the box. Keep the box itself
		## so the cursor can be tested against what is actually there.
		var yawed: Array = _entity_yawed_boxes.get(source_id, [])
		yawed.append({"center": center, "size": size, "yaw_deg": yaw})
		_entity_yawed_boxes[source_id] = yawed
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
		KEY_D:
			_set_tool(Tool.DECK)
		KEY_S:
			_set_tool(Tool.STAIR)
		KEY_O:
			_set_tool(Tool.OPENING)
		KEY_P:
			_set_tool(Tool.PIECE)
		KEY_R:
			## Turns whichever piece is in hand: the selected one if there is one,
			## otherwise the one about to be placed.
			if not _rotate_selected_piece():
				_rotate_piece()
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_F:
			if _selected_id >= 0 and _entity_bounds.has(_selected_id):
				_cam_focus = (_entity_bounds[_selected_id] as AABB).get_center()
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
	if _tool == Tool.PIECE:
		## One click, one piece, at the node the ghost is standing on. No drag: a
		## piece's size is a parameter off a declared set, not something swept out
		## with the mouse — that is the difference between this and the ROOM tool
		## that was deleted for making custom-sized boxes.
		_place_piece_at(_mouse_to_node(screen_pos))
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
		Tool.DECK:
			_place_deck(a, b)
		Tool.STAIR:
			_place_stair(a, b)


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
	if tool != Tool.PIECE:
		_hide_piece_ghost()
	elif _piece_id.is_empty():
		## Arm the first piece the kit declares, so the tool is usable the moment
		## it is picked up. Which piece that is comes out of the data file.
		var ids := _kit_ids()
		if ids.size() > 0:
			_select_piece_type(str(ids[0]))
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
	_stamp_library_style(wall)
	_set_status("WALL %s / %.0f M" % [axis.to_upper(), length])
	_rebake()
	_refresh_panel()


func _place_deck(a: Vector3, b: Vector3) -> void:
	var min_pt := Vector3(roundf(minf(a.x, b.x)), _active_base, roundf(minf(a.z, b.z)))
	var w := roundf(maxf(absf(b.x - a.x), 1.0))
	var l := roundf(maxf(absf(b.z - a.z), 1.0))
	_snapshot()
	var deck := _plan.add_deck(min_pt, Vector2(w, l))
	_stamp_library_style(deck)
	_set_status("DECK PLATE %.0f × %.0f M" % [w, l])
	_rebake()
	_refresh_panel()


## Drag defines the stair footprint AND the climb: the dominant axis of the
## drag is the climb axis, its sign the climb direction, the cross extent the
## width (a straight-line drag gets the default width). Rises one level.
func _place_stair(a: Vector3, b: Vector3) -> void:
	var along_x := absf(b.x - a.x) >= absf(b.z - a.z)
	var dir := ("+x" if b.x >= a.x else "-x") if along_x else ("+z" if b.z >= a.z else "-z")
	var length := roundf(maxf(absf(b.x - a.x) if along_x else absf(b.z - a.z), 2.0))
	var width := roundf(absf(b.z - a.z) if along_x else absf(b.x - a.x))
	if width < 1.0:
		width = DEFAULT_STAIR_WIDTH
	var min_pt := Vector3(roundf(minf(a.x, b.x)), _active_base, roundf(minf(a.z, b.z)))
	_snapshot()
	var stair := _plan.add_stair(min_pt, dir, length, width, DEFAULT_WALL_HEIGHT)
	_stamp_library_style(stair)
	var cut_deck := _auto_stairwell(stair)
	var result := "STAIRS %s / %.0f M / RISE %.0f M" % [dir.to_upper(), length, DEFAULT_WALL_HEIGHT]
	if cut_deck >= 0:
		result += " / STAIRWELL CUT IN DECK %03d" % cut_deck
	_set_status(result)
	_rebake()
	_refresh_panel()


## After placing a stair, punch a matching stairwell through the first plan
## deck plate lying at the stair's landing height, so the climb is passable
## without a manual Opening pass (same undo step as the stair itself). The
## cut covers the top of the run far enough back for ~2.1 m of head
## clearance. Returns the cut deck's id, or -1 when nothing needed cutting.
func _auto_stairwell(stair: Dictionary) -> int:
	var start := StructurePlan.vec3_of(stair.get("start"))
	var length := float(stair.get("length", 3.0))
	var width := float(stair.get("width", 1.0))
	var height := float(stair.get("height", 3.0))
	var dir := str(stair.get("dir", "+x"))
	var top_y := start.y + height
	var hole_len := clampf(2.1 * length / maxf(height, 0.5), 1.0, length)
	## The cut rect in plan space, hugging the TOP end of the run.
	## Rect2 carries (x, z) in (position.x, position.y).
	var rect: Rect2
	match dir:
		"+x":
			rect = Rect2(start.x + length - hole_len, start.z, hole_len, width)
		"-x":
			rect = Rect2(start.x, start.z, hole_len, width)
		"+z":
			rect = Rect2(start.x, start.z + length - hole_len, width, hole_len)
		_:
			rect = Rect2(start.x, start.z, width, hole_len)
	for deck_variant in _plan.decks:
		var deck := deck_variant as Dictionary
		var origin := StructurePlan.vec3_of(deck.get("origin"))
		if absf(origin.y - top_y) > 0.5:
			continue
		var size_list: Array = deck.get("size", [1.0, 1.0])
		var extent := Vector2(float(size_list[0]), float(size_list[1]) if size_list.size() > 1 else 1.0)
		var local := Rect2(rect.position - Vector2(origin.x, origin.z), rect.size)
		var clipped := local.intersection(Rect2(Vector2.ZERO, extent))
		if clipped.size.x < 0.5 or clipped.size.y < 0.5:
			continue
		for opening_variant in deck.get("openings", []) as Array:
			var opening := opening_variant as Dictionary
			var off: Array = opening.get("offset", [0.0, 0.0])
			var hole_size: Array = opening.get("size", [1.0, 1.0])
			var existing := Rect2(
				float(off[0]), float(off[1]) if off.size() > 1 else 0.0,
				float(hole_size[0]), float(hole_size[1]) if hole_size.size() > 1 else 1.0,
			)
			if existing.intersects(clipped):
				return -1 ## the landing already has a hole — nothing to cut
		(deck["openings"] as Array).append({
			"type": StructurePlan.OPENING_STAIRWELL,
			"offset": [clipped.position.x, clipped.position.y],
			"size": [clipped.size.x, clipped.size.y],
		})
		return int(deck.get("id", -1))
	return -1


# ── The piece tool ───────────────────────────────────────────────────────────
#
# THE TOOL, NOT THE PRIMITIVE. The ROOM tool was deleted for making boxes and
# nothing replaced it, so this editor could not author superstructure at all
# while `structure_pieces.json` and `PieceKit` got steadily more capable. A
# format is not a feature; this is the feature.
#
# Everything below is driven ENTIRELY by the data file. There is no piece name in
# this script, no `if id == …`, and no parameter value list: the palette is
# `PieceKit.ids()`, every stepper's range is the piece's own declared `values`
# array, and every dropdown's entries are its declared choice set. When the kit
# widens the rake to eighth-cells or adds a camber list, this file does not
# change and the new values appear in the controls.
#
# And there is nothing here a number can be typed into. Numeric parameters step
# through their declared set by index; choice parameters are an OptionButton.
# `SpinBox` — which the wall/deck/stair inspector uses and which accepts typed
# text — appears nowhere in this section on purpose.

const NO_NODE := Vector3i(-2147483648, -2147483648, -2147483648)

## Metres per unit, for the units the kit declares today. A unit that is not in
## here simply gets no metre readout — the stepper still works, because the value
## set it steps through came out of the data file. A kit that adds `eighth_cells`
## therefore degrades to "no hint", never to a wrong hint.
const PIECE_UNIT_METRES := {
	"cells": WorldUnits.DECK_CELL_M,
	"quarter_cells": WorldUnits.DECK_CELL_M * 0.5,
}


## The kit's piece ids, in the kit's own order. Empty when the data file failed
## to load, which is a state the palette shows rather than crashes on.
func _kit_ids() -> PackedStringArray:
	return PieceKit.ids()


## Swatches a placement may be painted: every colour the KIT itself declares for
## a piece (read out of the data file, deduplicated, kit order first) followed by
## the studio's own maritime tints. So the six pieces' default liveries are one
## click away and never restated here.
func _piece_tints() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for id_variant in _kit_ids():
		var id := str(id_variant)
		var hex := _kit_color_hex(id)
		if hex.is_empty() or seen.has(hex):
			continue
		seen[hex] = true
		out.append([PieceKit.display_name(id), hex])
	for entry_variant in PIECE_TINT_LIBRARY:
		var entry := entry_variant as Array
		var hex := str(entry[1])
		if seen.has(hex):
			continue
		seen[hex] = true
		out.append([str(entry[0]), hex])
	return out


## A piece's own declared colour as `#rrggbb`. The kit parses its colour into a
## `Color`, so this is the one place the studio converts back — and
## `_probe_piece_tool` asserts the conversion is exact for every piece in the
## kit, because a tint that drifts by one digit is a placement that no longer
## compares equal to the fixture it was copied from.
func _kit_color_hex(piece_id: String) -> String:
	var piece := PieceKit.get_piece(piece_id)
	if not piece.has("color"):
		return ""
	return "#%s" % (piece["color"] as Color).to_html(false)


## Picking a piece off the palette. Restores that piece's remembered settings, or
## the kit's declared defaults the first time it is picked up.
func _select_piece_type(piece_id: String) -> void:
	if not PieceKit.has(piece_id):
		_set_status("no piece \"%s\" in the kit" % piece_id, false)
		return
	_piece_id = piece_id
	if not _piece_settings.has(piece_id):
		var defaults: Dictionary = {}
		var declared := PieceKit.params_of(piece_id)
		for key in declared.keys():
			defaults[str(key)] = (declared[key] as Dictionary)["default"]
		_piece_settings[piece_id] = defaults
	## A newly picked piece is painted its own livery unless the player has armed
	## a tint. Written out explicitly rather than left blank so a saved placement
	## says what colour it is.
	_piece_color = _kit_color_hex(piece_id)
	_piece_ghost_key = ""
	_set_status("%s selected" % PieceKit.display_name(piece_id))
	_refresh_panel()


func _piece_params_for(piece_id: String) -> Dictionary:
	if not _piece_settings.has(piece_id):
		_select_piece_type(piece_id)
	return _piece_settings.get(piece_id, {}) as Dictionary


## Sets one parameter of the piece about to be placed, REFUSING anything the kit
## refuses. Two legal values can still make an illegal piece — a glazed panel
## whose coaming and glass fill its whole height has no header left — and the
## kit says so in the piece's own words. A stepper that walked into that setting
## and left the player holding a piece that will not place would be worse than
## one that stops. Returns true when the value was taken.
func _set_piece_param(name: String, value: Variant) -> bool:
	if _piece_id.is_empty():
		return false
	var params := (_piece_params_for(_piece_id) as Dictionary).duplicate()
	params[name] = value
	var probe := PieceKit.resolve_params(_piece_id, params)
	var errors := probe["errors"] as PackedStringArray
	if errors.size() > 0:
		_set_status(errors[0], false)
		return false
	_piece_settings[_piece_id] = params
	_piece_ghost_key = ""
	_refresh_panel()
	return true


## One step along a numeric parameter's DECLARED value list, by index. Not by
## arithmetic: the sets are not evenly spaced (span is 1, 2, 3, 4, 6, 8) and
## adding one to a 4 would ask for a 5, which the kit refuses. Clamped at the
## ends rather than wrapping, so holding a stepper cannot silently take a wall
## from 8 cells back to 1.
func _step_piece_param(name: String, delta: int) -> bool:
	if _piece_id.is_empty():
		return false
	var declared := PieceKit.params_of(_piece_id)
	if not declared.has(name):
		return false
	var spec := declared[name] as Dictionary
	var values := spec["values"] as Array
	var current: Variant = (_piece_params_for(_piece_id) as Dictionary).get(name, spec["default"])
	var index := values.find(current)
	if index < 0:
		index = values.find(spec["default"])
	var next := clampi(index + delta, 0, values.size() - 1)
	if next == index:
		return false
	return _set_piece_param(name, values[next])


## The four facings, in order, on a key. Nothing is ever placed at 45 degrees —
## `corner_45` carries its own chord — so this steps a list rather than adding
## degrees, and the list is the kit's.
func _rotate_piece(steps := 1) -> void:
	var facings := PieceKit.FACINGS
	var index := facings.find(_piece_facing)
	if index < 0:
		index = 0
	_piece_facing = int(facings[posmod(index + steps, facings.size())])
	_piece_ghost_key = ""
	_set_status("facing %d°" % _piece_facing)
	_refresh_panel()


## Arms a tint for the next placement, and repaints the selected one if there is
## one — the same modal behaviour the surface library already has for walls.
func _set_piece_color(hex: String) -> void:
	_piece_color = hex
	var selected := _selected_piece()
	if not selected.is_empty():
		_snapshot()
		selected["color"] = hex
		_rebake()
	_piece_ghost_key = ""
	_set_status("tint %s" % hex)
	_refresh_panel()


## The grid NODE under the cursor, in whole cells. Cells are 0.5 m volumes and a
## piece stands on the LINE between them, so this rounds to `NODE_SNAP` and
## reports a CELL INDEX — not the metre position `_mouse_to_grid` returns, which
## would put every wall panel half a cell out at best.
func _mouse_to_node(screen_pos: Vector2) -> Vector3i:
	var ray := _mouse_ray(screen_pos)
	var origin := ray[0] as Vector3
	var direction := ray[1] as Vector3
	if absf(direction.y) < 0.0001:
		return NO_NODE
	var t := (_active_base - origin.y) / direction.y
	if t < 0.0:
		return NO_NODE
	var plan_point := (origin + direction * t) - _plan_offset
	return Vector3i(
		clampi(roundi(plan_point.x / NODE_SNAP), 0, _grid_width),
		roundi(_active_base / NODE_SNAP),
		clampi(roundi(plan_point.z / NODE_SNAP), 0, _grid_length),
	)


## The placement the tool would commit at this node, with no id yet. ONE
## function, used by the ghost and by the commit, which is what makes "it lands
## where the ghost showed it" a property of the code rather than a hope.
func _piece_placement_at(cell: Vector3i) -> Dictionary:
	return StructurePlan.normalize_piece({
		"piece": _piece_id,
		"cell": [cell.x, cell.y, cell.z],
		"facing": _piece_facing,
		"params": _piece_params_for(_piece_id),
		"color": _piece_color,
	})


## The ghost is the REAL BAKE of the placement about to be committed, drawn
## through `PieceKit` and `StructureBaker` exactly as the committed piece will
## be. A ghost drawn any other way is a second implementation of the placement
## and would eventually disagree with the first.
func _update_piece_ghost(cell: Vector3i) -> void:
	if _piece_id.is_empty() or cell == NO_NODE:
		_hide_piece_ghost()
		return
	var placement := _piece_placement_at(cell)
	var key := JSON.stringify(placement)
	if key == _piece_ghost_key and _piece_ghost != null and is_instance_valid(_piece_ghost):
		_piece_ghost.visible = true
		return
	_hide_piece_ghost()
	var probe := StructurePlan.new()
	probe.context = _context
	probe.hull_id = _hull_id
	probe.pieces = [placement]
	var resolved := PieceKit.resolve_document(probe.to_dict())
	if (resolved["errors"] as PackedStringArray).size() > 0:
		_piece_ghost_placement = {}
		return
	_piece_ghost = StructureBaker.bake(
		StructurePlan.from_dict(resolved["doc"] as Dictionary), _plan_offset, true
	)
	add_child(_piece_ghost)
	_piece_ghost_key = key
	_piece_ghost_placement = placement


func _hide_piece_ghost() -> void:
	if _piece_ghost != null and is_instance_valid(_piece_ghost):
		_piece_ghost.queue_free()
	_piece_ghost = null
	_piece_ghost_key = ""
	_piece_ghost_placement = {}


## Stands the armed piece on a grid node. Returns the placement, or {} when the
## kit refused it — refused, never clamped, because a kit whose pieces quietly
## change size is worse than one that says no.
func _place_piece_at(cell: Vector3i) -> Dictionary:
	if _piece_id.is_empty():
		_set_status("pick a piece first", false)
		return {}
	if cell == NO_NODE:
		return {}
	var placement := _piece_placement_at(cell)
	var probe := PieceKit.resolve_placement(placement, 1)
	var errors := probe["errors"] as PackedStringArray
	if errors.size() > 0:
		_set_status(errors[0], false)
		return {}
	_snapshot()
	var placed := _plan.add_piece(
		str(placement["piece"]), cell, int(placement["facing"]),
		placement["params"] as Dictionary, str(placement.get("color", ""))
	)
	_set_status("%s at cell %d,%d,%d facing %d°" % [
		PieceKit.display_name(_piece_id), cell.x, cell.y, cell.z, _piece_facing,
	])
	_rebake()
	_refresh_panel()
	return placed


## The selected entity, if it is a placement. A placement is the only plan entity
## with a `piece` key, which is how the inspector tells the four kinds apart.
func _selected_piece() -> Dictionary:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or not entity.has("piece"):
		return {}
	return entity


## Editing a PLACED piece, through the same refusal path a new one goes through.
func _set_selected_piece_param(name: String, value: Variant) -> bool:
	var placement := _selected_piece()
	if placement.is_empty():
		return false
	var params := (placement.get("params", {}) as Dictionary).duplicate()
	params[name] = value
	var probe := PieceKit.resolve_params(str(placement["piece"]), params)
	var errors := probe["errors"] as PackedStringArray
	if errors.size() > 0:
		_set_status(errors[0], false)
		return false
	_snapshot()
	placement["params"] = params
	_rebake()
	_refresh_panel()
	return true


func _step_selected_piece_param(name: String, delta: int) -> bool:
	var placement := _selected_piece()
	if placement.is_empty():
		return false
	var declared := PieceKit.params_of(str(placement["piece"]))
	if not declared.has(name):
		return false
	var spec := declared[name] as Dictionary
	var values := spec["values"] as Array
	var index := values.find((placement.get("params", {}) as Dictionary).get(name, spec["default"]))
	if index < 0:
		index = values.find(spec["default"])
	var next := clampi(index + delta, 0, values.size() - 1)
	if next == index:
		return false
	return _set_selected_piece_param(name, values[next])


func _rotate_selected_piece(steps := 1) -> bool:
	var placement := _selected_piece()
	if placement.is_empty():
		return false
	var facings := PieceKit.FACINGS
	var index := facings.find(int(placement.get("facing", 0)))
	if index < 0:
		index = 0
	_snapshot()
	placement["facing"] = int(facings[posmod(index + steps, facings.size())])
	_rebake()
	_refresh_panel()
	return true


## A plan whose placements have become the plates `StructureBaker` already bakes.
## The kit's contract verbatim: pieces in, `items[]` out, and what comes back is
## an ordinary plan — so the baker never learns a new word and a capture rig
## reaches the same geometry with no studio in the room.
func _resolved_for_bake(plan: StructurePlan) -> StructurePlan:
	if plan.pieces.is_empty():
		return plan
	var result := PieceKit.resolve_document(plan.to_dict())
	return StructurePlan.from_dict(result["doc"] as Dictionary)


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


## The one place a wall's direction is derived. `run` is the unit vector the
## wall runs along (all six axes, diagonals included), `across` the horizontal
## unit normal its thickness is measured on, `yaw_deg` the rotation the baker
## draws its boxes with. Everything downstream projects onto these instead of
## asking "x wall or z wall?" — that question has four wrong answers.
func _wall_frame(entity: Dictionary) -> Dictionary:
	var run := StructurePlan.wall_run(str(entity.get("axis", "x")))
	return {
		"run": run,
		"across": Vector3(-run.z, 0.0, run.x),
		"yaw_deg": StructureBaker.wall_yaw_deg(entity),
	}


## Resolves what an opening interaction at this cursor position would cut:
## a wall run or a deck plate.
func _opening_context_at(screen_pos: Vector2) -> Dictionary:
	var hit := _pick_entity_hit(screen_pos)
	if hit.is_empty():
		return {}
	var entity := _plan.entity_by_id(int(hit["id"]))
	if entity.is_empty():
		return {}
	var p: Vector3 = (hit["point"] as Vector3) - _plan_offset
	if entity.has("axis"):
		var frame := _wall_frame(entity)
		return {
			"kind": "wall", "entity": entity,
			"axis": str(entity.get("axis", "x")),
			"run": frame["run"], "across": frame["across"], "yaw_deg": frame["yaw_deg"],
			"start": StructurePlan.vec3_of(entity.get("start")),
			"length": float(entity.get("length", 1.0)),
			"thickness": float(entity.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS)),
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
			## Distance from the start ALONG the run — for "x" and "z" this is
			## still exactly p.x - start.x / p.z - start.z, and it is the only
			## form that means anything on a diagonal.
			return (p - (ctx["start"] as Vector3)).dot(ctx["run"] as Vector3)
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
			var t := float(ctx["thickness"]) + OPENING_GHOST_PROUD * 2.0
			## Centre rides the run; size is stated in the wall's OWN frame and
			## carries the baker's yaw, exactly like StructureBaker.wall_boxes.
			var center := start + (ctx["run"] as Vector3) * u
			center.y = v
			return {
				"center": center,
				"size": (
					Vector3(t, float(defaults["height"]), span.y) if str(ctx["axis"]) == "z"
					else Vector3(span.y, float(defaults["height"]), t)
				),
				"yaw_deg": ctx["yaw_deg"],
			}
		"plate":
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
		_set_status("opening: aim at a wall or a deck plate", false)
		return
	var p := _opening_ctx["point"] as Vector3
	if str(_opening_ctx["kind"]) == "wall":
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
	if str(_opening_ctx["kind"]) == "wall":
		geom = _opening_geom(_opening_ctx, _wall_span(_opening_ctx, _opening_anchor.x, _ctx_along(_opening_ctx, p), true), Rect2())
	else:
		geom = _opening_geom(_opening_ctx, Vector2.ZERO, _plate_rect(_opening_ctx, _opening_anchor, _ctx_uv(_opening_ctx, p), true))
	if not geom.is_empty():
		_show_opening_ghost(geom)


## Puts the preview cut on its host: plan space -> world, plus the host's yaw
## so a diagonal wall's opening sits IN the wall instead of across it.
func _show_opening_ghost(geom: Dictionary) -> void:
	(_opening_ghost.mesh as BoxMesh).size = geom["size"] as Vector3
	_opening_ghost.position = (geom["center"] as Vector3) + _plan_offset
	_opening_ghost.rotation = Vector3(0.0, deg_to_rad(float(geom.get("yaw_deg", 0.0))), 0.0)
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
	if str(ctx["kind"]) == "wall":
		var current := _ctx_along(ctx, p)
		var dragged := absf(current - _opening_anchor.x) > 0.3
		var span := _wall_span(ctx, _opening_anchor.x, current, dragged)
		var spec := _opening_defaults()
		spec["offset"] = span.x
		spec["width"] = span.y
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
	## `_grid_width` / `_grid_length` are CELL COUNTS, and plan space is METRES —
	## the same units mistake `_build_grid_lines` carries a note about. Clamping
	## metres against a cell count let the draw tools run 10 m off the starboard
	## side of a 10 m hull and 28 m astern of a 28 m one.
	var extent := Vector2(float(_grid_width), float(_grid_length)) * DeckGrid.CELL_M
	plan_point.x = clampf(roundf(plan_point.x), 0.0, extent.x)
	plan_point.z = clampf(roundf(plan_point.z), 0.0, extent.y)
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
	var best_point := Vector3.ZERO
	for id in _entity_bounds.keys():
		## Ghosted upper-level geometry is view-only: the cursor passes
		## straight through it to the deck being edited.
		if float(_entity_base_y.get(id, 0.0)) >= _ghost_threshold:
			continue
		var hit_variant: Variant = _entity_ray_hit(int(id), origin, direction)
		if hit_variant != null:
			var t := (hit_variant as Vector3).distance_to(origin)
			if t < best_t:
				best_t = t
				best_id = int(id)
				best_point = hit_variant as Vector3
	if best_id < 0:
		return {}
	return {"id": best_id, "point": best_point}


## Where the cursor ray meets one entity, world space, or null. The bound is
## the whole answer for anything axis-aligned. A diagonal wall's bound is a
## loose square around it, so the ray is retested against the rotated boxes the
## wall renders — otherwise a click in an empty corner of the bound selects the
## wall and reports a point metres off the surface, which is then what the
## opening tool measures its offset from.
func _entity_ray_hit(id: int, origin: Vector3, direction: Vector3) -> Variant:
	var coarse: Variant = (_entity_bounds[id] as AABB).grow(0.05).intersects_ray(origin, direction)
	if coarse == null or not _entity_yawed_boxes.has(id):
		return coarse
	var best: Variant = null
	var best_t := INF
	for box_variant in _entity_yawed_boxes[id] as Array:
		var box := box_variant as Dictionary
		var box_basis := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"])))
		var into_box := box_basis.transposed() ## orthonormal: transpose == inverse
		var box_center := box["center"] as Vector3
		var size := box["size"] as Vector3
		var local: Variant = AABB(-size * 0.5, size).grow(0.05).intersects_ray(
			into_box * (origin - box_center), into_box * direction
		)
		if local == null:
			continue
		var world := box_center + box_basis * (local as Vector3)
		var t := world.distance_to(origin)
		if t < best_t:
			best_t = t
			best = world
	return best


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
	elif entity.has("dir"):
		_resize_start_dims = Vector3(
			float(entity.get("length", 3.0)),
			float(entity.get("height", DEFAULT_WALL_HEIGHT)),
			float(entity.get("width", DEFAULT_STAIR_WIDTH)),
		)
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
		if _gizmo_axis == 1:
			entity["height"] = clampf(_resize_start_dims.y + face_move, 0.5, 12.0)
		else:
			## Which dimension a horizontal pad edits is decided by projecting the
			## pad's OUTWARD normal onto the wall's own frame, not by naming a
			## world axis: "x wall or z wall?" has four wrong answers. For "x" and
			## "z" the projections are 1 and 0, so this is the old behaviour
			## exactly; on a diagonal every horizontal pad sits on an END of the
			## run (its thickness faces never reach the bound's sides), so they
			## all edit length — thickness stays an inspector field there.
			var axis_vector := Vector3.RIGHT if _gizmo_axis == 0 else Vector3.BACK
			var normal := axis_vector * float(_resize_sign)
			var frame := _wall_frame(entity)
			var along := normal.dot(frame["run"] as Vector3)
			var across := normal.dot(frame["across"] as Vector3)
			if absf(along) >= absf(across):
				## The grabbed face tracks the cursor on ITS world axis, so the
				## run grows by the drag divided by the run's share of that axis.
				var new_length := maxf(_resize_start_dims.x + face_move / absf(along), 1.0)
				entity["length"] = new_length
				if along < 0.0:
					## Start end grabbed: the start slides back so the far end stays.
					origin = _resize_start_primary - (frame["run"] as Vector3) * (new_length - _resize_start_dims.x)
					entity["start"] = [origin.x, origin.y, origin.z]
			else:
				entity["thickness"] = clampf(
					_resize_start_dims.z + face_move / absf(across), 0.05, 0.5
				)
	elif entity.has("dir"):
		## Stairs: the climb axis edits length, vertical edits total rise,
		## the cross axis edits width. (dims: x=length, y=height, z=width)
		var climb_axis := 0 if str(entity.get("dir")) in ["+x", "-x"] else 2
		if _gizmo_axis == climb_axis:
			var new_length := maxf(_resize_start_dims.x + face_move, 1.0)
			entity["length"] = new_length
			if _resize_sign < 0:
				origin[climb_axis] = _resize_start_primary[climb_axis] - (new_length - _resize_start_dims.x)
				entity["start"] = [origin.x, origin.y, origin.z]
		elif _gizmo_axis == 1:
			entity["height"] = clampf(_resize_start_dims.y + face_move, 0.5, 12.0)
		else:
			var new_width := maxf(_resize_start_dims.z + face_move, 0.5)
			entity["width"] = new_width
			if _resize_sign < 0:
				origin[_gizmo_axis] = _resize_start_primary[_gizmo_axis] - (new_width - _resize_start_dims.z)
				entity["start"] = [origin.x, origin.y, origin.z]
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
	elif _tool == Tool.STAIR:
		## Footprint plus a half-height block: reads as "mass rising" without
		## pretending to know the final step layout mid-drag.
		size.y = DEFAULT_WALL_HEIGHT * 0.5
		if absf(b.x - a.x) >= absf(b.z - a.z):
			size.z = maxf(size.z, DEFAULT_STAIR_WIDTH)
		else:
			size.x = maxf(size.x, DEFAULT_STAIR_WIDTH)
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
		_set_status("NAME THE STRUCTURE FIRST", false)
		_refresh_panel()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STRUCTURES_DIR))
	var path := "%s/%s.json" % [STRUCTURES_DIR, trimmed]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("SAVE FAILED / %s" % path, false)
	else:
		file.store_string(JSON.stringify(_plan.to_dict(), "\t"))
		file.close()
		_set_status("SAVED / %s" % path)
	_refresh_panel()


func _load_plan(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary or not StructurePlan.is_plan(parsed as Dictionary):
		_set_status("NOT A STRUCTURE PLAN / %s" % path, false)
		_refresh_panel()
		return
	_snapshot()
	_plan = StructurePlan.from_dict(parsed as Dictionary)
	_context = _plan.context
	if _context == "vessel" and not _plan.hull_id.is_empty():
		_hull_id = _plan.hull_id
	_selected_id = -1
	_set_status("LOADED / %s" % path.get_file())
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
		if _piece_ghost != null and is_instance_valid(_piece_ghost):
			_piece_ghost.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
	_opening_ghost.visible = false
	_hover_box.visible = false
	_start_marker.visible = false
	if _tool != Tool.PIECE and _piece_ghost != null and is_instance_valid(_piece_ghost):
		_piece_ghost.visible = false
	match _tool:
		Tool.PIECE:
			var node := _mouse_to_node(mouse)
			_update_piece_ghost(node)
			if node != NO_NODE:
				_start_marker.position = _plan_offset + StructurePlan.piece_node_plan(node)
				_start_marker.visible = true
		Tool.OPENING:
			var ctx := _opening_context_at(mouse)
			if ctx.is_empty():
				return
			var p := ctx["point"] as Vector3
			var geom: Dictionary
			if str(ctx["kind"]) == "wall":
				var along := _ctx_along(ctx, p)
				geom = _opening_geom(ctx, _wall_span(ctx, along, along, false), Rect2())
			else:
				var uv := _ctx_uv(ctx, p)
				geom = _opening_geom(ctx, Vector2.ZERO, _plate_rect(ctx, uv, uv, false))
			if geom.is_empty():
				return
			_show_opening_ghost(geom)
		Tool.WALL, Tool.DECK:
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
	## Ghost preview and selection share the branded brass interaction accent.
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(BrandTokens.BRASS_DEEP, 0.35)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = ghost_mat
	_ghost.visible = false
	add_child(_ghost)
	_selection_box = MeshInstance3D.new()
	_selection_box.mesh = BoxMesh.new()
	var select_mat := StandardMaterial3D.new()
	select_mat.albedo_color = Color(BrandTokens.BRASS, 0.20)
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
	opening_mat.albedo_color = Color(BrandTokens.BRASS, 0.45)
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
	hover_mat.albedo_color = Color(BrandTokens.BRASS_DEEP, 0.14)
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
	marker_mat.albedo_color = Color(BrandTokens.BRASS, 0.85)
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
		pad_mat.albedo_color = Color(BrandTokens.BRASS_DEEP, 0.95)
		pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pad_mat.no_depth_test = true
		pad_mat.render_priority = 19
		pad.material_override = pad_mat
		_handle_root.add_child(pad)


# ── UI (drawing-office composition from the shared brand system) ─────────────

var _ui_root: Control
var _status_label: Label ## toast, right side of the context strip
var _metrics_label: Label
var _hint_label: Label
var _context_label: Label
var _tool_buttons: Dictionary = {}
var _context_buttons: Dictionary = {}
var _opening_buttons: Dictionary = {}
var _opening_section: VBoxContainer
var _level_label: Label
var _ghost_button: Button
## Modal surface library: arm a slot (Outside/Inside), then every swatch or
## material click paints that slot of the selection — and defines the style
## every NEWLY drawn wall/deck/stair is born with.
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
	Tool.PIECE: "Piece: pick one off the kit palette, R turns it, click a grid node to stand it there. Every setting is a stepper over the piece's own list — nothing is typed.",
	Tool.SELECT: "Select: click to pick — arrows move it, drag a face pad to resize, DEL removes.",
	Tool.WALL: "Wall: click-drag along the grid, release to raise one wall run.",
	Tool.DECK: "Deck: drag a footprint to lay a deck plate.",
	Tool.STAIR: "Stairs: drag along the climb direction — a walkable run up one level. Cut a stairwell in the deck above to pass through.",
	Tool.OPENING: "Opening: click for a standard cut, or click-drag along the surface to size it yourself.",
}


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 14
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = BrandTheme.shared()
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
	var bar := BrandComponents.toolbar_panel()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 60)
	_ui_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	bar.add_child(row)

	var mark := TextureRect.new()
	mark.texture = load("res://resources/ui/brand/anchor-mark-ink.svg")
	mark.custom_minimum_size = Vector2(28, 28)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(mark)

	var title := BrandLabel.new("STRUCTURE STUDIO", BrandLabel.Role.DISPLAY_SMALL)
	title.custom_minimum_size.x = 178
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)

	var divider := VSeparator.new()
	divider.custom_minimum_size = Vector2(1, 0)
	row.add_child(divider)

	var tool_defs := [
		[Tool.SELECT, "SELECT"],
		[Tool.PIECE, "PIECE"],
		[Tool.WALL, "WALL"],
		[Tool.DECK, "DECK"],
		[Tool.STAIR, "STAIR"],
		[Tool.OPENING, "OPENING"],
	]
	for tool_def in tool_defs:
		var tool: Tool = tool_def[0]
		var button := BrandComponents.tool_button(str(tool_def[1]), 78.0)
		button.pressed.connect(func() -> void: _set_tool(tool))
		row.add_child(button)
		_tool_buttons[tool] = button

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var undo_btn := BrandComponents.compact_button("UNDO", 72.0)
	undo_btn.pressed.connect(func() -> void: _undo())
	row.add_child(undo_btn)
	var redo_btn := BrandComponents.compact_button("REDO", 72.0)
	redo_btn.pressed.connect(func() -> void: _redo())
	row.add_child(redo_btn)

	var save_btn := BrandButton.new("SAVE PLAN", BrandButton.Variant.LOUD)
	save_btn.custom_minimum_size.x = 124
	save_btn.pressed.connect(func() -> void: _save_plan(_name_edit.text))
	row.add_child(save_btn)


func _build_tool_palette() -> void:
	var palette := BrandComponents.panel(Vector2(276, 0), BrandPanel.Variant.PAPER)
	palette.name = "ToolPalette"
	palette.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	palette.offset_top = 60.0
	palette.offset_bottom = -36.0
	_ui_root.add_child(palette)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	palette.add_child(box)

	box.add_child(BrandComponents.section_header("BUILD CONTEXT"))
	var context_row := HBoxContainer.new()
	context_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	box.add_child(context_row)
	for context in ["vessel", "building"]:
		var button := BrandComponents.tool_button(context.to_upper(), 0.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _set_context(context))
		context_row.add_child(button)
		_context_buttons[context] = button

	_context_label = BrandLabel.new("", BrandLabel.Role.DATA)
	box.add_child(_context_label)

	_hull_option = OptionButton.new()
	_hull_option.focus_mode = Control.FOCUS_ALL
	_hull_option.custom_minimum_size = Vector2(0, BrandTokens.MIN_HIT_TARGET)
	var hulls := HullRegistry.catalog()
	for index in hulls.size():
		_hull_option.add_item(str((hulls[index] as Dictionary).get("id", "?")), index)
		if str((hulls[index] as Dictionary).get("id", "")) == _hull_id:
			_hull_option.select(index)
	_hull_option.item_selected.connect(func(index: int) -> void:
		_hull_id = str((hulls[index] as Dictionary).get("id", _hull_id))
		_set_context("vessel")
	)
	box.add_child(_hull_option)

	box.add_child(BrandComponents.separator())
	box.add_child(BrandComponents.section_header("ACTIVE LEVEL"))
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var level_down := BrandComponents.compact_button("−", BrandTokens.MIN_HIT_TARGET)
	level_down.pressed.connect(func() -> void: _set_build_level(_active_base - 1.0))
	level_row.add_child(level_down)
	_level_label = BrandLabel.new("", BrandLabel.Role.DATA)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_row.add_child(_level_label)
	var level_up := BrandComponents.compact_button("+", BrandTokens.MIN_HIT_TARGET)
	level_up.pressed.connect(func() -> void: _set_build_level(_active_base + 1.0))
	level_row.add_child(level_up)
	box.add_child(level_row)

	var ghost_btn := BrandComponents.tool_button("GHOST ABOVE  [G]", 0.0)
	ghost_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ghost_btn.pressed.connect(func() -> void:
		_ghost_levels = not _ghost_levels
		_rebake()
		_refresh_panel()
	)
	box.add_child(ghost_btn)
	_ghost_button = ghost_btn

	box.add_child(BrandComponents.separator())
	_opening_section = VBoxContainer.new()
	_opening_section.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	_opening_section.add_child(BrandComponents.section_header("OPENING TYPE"))
	var opening_row := HBoxContainer.new()
	opening_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	_opening_section.add_child(opening_row)
	for opening_type in [StructurePlan.OPENING_DOOR, StructurePlan.OPENING_WINDOW, StructurePlan.OPENING_HOLE]:
		var btn := BrandComponents.tool_button(opening_type.capitalize(), 0.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			_opening_type = opening_type
			_refresh_panel()
		)
		opening_row.add_child(btn)
		_opening_buttons[opening_type] = btn
	box.add_child(_opening_section)
	_build_piece_section(box)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	box.add_child(BrandComponents.separator())
	_entities_label = BrandLabel.new("", BrandLabel.Role.DATA_MUTED)
	_entities_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_entities_label)
	var hints := BrandLabel.new(
		"RMB ORBIT · MMB PAN · WHEEL ZOOM\nPGUP/PGDN LEVEL · F FOCUS\nDEL DELETE · CTRL+Z / CTRL+Y",
		BrandLabel.Role.MICRO_DATA
	)
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hints)


## THE PALETTE. Six buttons, or however many `structure_pieces.json` declares —
## this function does not know and must not. A seventh piece appears here by
## being added to the data file.
func _build_piece_section(box: VBoxContainer) -> void:
	_piece_section = VBoxContainer.new()
	_piece_section.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	_piece_section.add_child(BrandComponents.section_header("PIECE KIT"))

	var kit_errors := PieceKit.load_errors()
	if kit_errors.size() > 0:
		## A kit that failed to load is a palette with nothing on it, and a blank
		## panel is indistinguishable from a tool that has not been picked up yet.
		var broken := BrandLabel.new(
			"KIT FAILED TO LOAD\n%s" % "\n".join(kit_errors), BrandLabel.Role.MICRO_DATA
		)
		broken.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		broken.add_theme_color_override(&"font_color", BrandTokens.ALERT)
		_piece_section.add_child(broken)

	var flow := VBoxContainer.new()
	flow.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	for id_variant in _kit_ids():
		var id := str(id_variant)
		var button := BrandComponents.tool_button(PieceKit.display_name(id).to_upper(), 0.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(PieceKit.get_piece(id).get("description", ""))
		button.pressed.connect(func() -> void: _select_piece_type(id))
		flow.add_child(button)
		_piece_buttons[id] = button
	_piece_section.add_child(flow)

	var facing_row := HBoxContainer.new()
	facing_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var turn_back := BrandComponents.compact_button("⟲", BrandTokens.MIN_HIT_TARGET)
	turn_back.pressed.connect(func() -> void:
		if not _rotate_selected_piece(-1):
			_rotate_piece(-1)
	)
	facing_row.add_child(turn_back)
	_piece_facing_label = BrandLabel.new("", BrandLabel.Role.DATA)
	_piece_facing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_piece_facing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_piece_facing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	facing_row.add_child(_piece_facing_label)
	var turn_on := BrandComponents.compact_button("⟳", BrandTokens.MIN_HIT_TARGET)
	turn_on.pressed.connect(func() -> void:
		if not _rotate_selected_piece(1):
			_rotate_piece(1)
	)
	facing_row.add_child(turn_on)
	_piece_section.add_child(facing_row)

	_piece_param_box = VBoxContainer.new()
	_piece_param_box.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	_piece_section.add_child(_piece_param_box)

	_piece_tint_box = HFlowContainer.new()
	_piece_tint_box.add_theme_constant_override(&"h_separation", BrandTokens.SPACE_XS)
	_piece_tint_box.add_theme_constant_override(&"v_separation", BrandTokens.SPACE_XS)
	for tint_variant in _piece_tints():
		var tint := tint_variant as Array
		var hex := str(tint[1])
		var swatch := Button.new()
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(30, 30)
		swatch.tooltip_text = "%s  %s" % [str(tint[0]), hex]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(hex)
		style.border_color = BrandTokens.SEA_LINE
		style.set_border_width_all(1)
		style.set_corner_radius_all(0)
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", style)
		swatch.add_theme_stylebox_override("pressed", style)
		swatch.pressed.connect(func() -> void: _set_piece_color(hex))
		_piece_tint_box.add_child(swatch)
	_piece_section.add_child(_piece_tint_box)
	box.add_child(_piece_section)


## Rebuilt whenever the armed piece, its settings or its facing change. Cheap —
## six rows — and rebuilding beats keeping a parallel copy of the values in the
## widgets, which is how a control ends up disagreeing with the thing it edits.
func _refresh_piece_section() -> void:
	if _piece_section == null:
		return
	_piece_section.visible = _tool == Tool.PIECE
	for id in _piece_buttons.keys():
		(_piece_buttons[id] as Button).set_pressed_no_signal(str(id) == _piece_id)
	_piece_facing_label.text = "FACING %d°" % _piece_facing
	if not _piece_section.visible or _piece_id.is_empty():
		return
	var key := "%s|%d|%s" % [
		_piece_id, _piece_facing, JSON.stringify(_piece_params_for(_piece_id))
	]
	if key == _piece_param_key:
		return
	_piece_param_key = key
	for child in _piece_param_box.get_children():
		_piece_param_box.remove_child(child)
		child.queue_free()
	_build_piece_param_rows(
		_piece_param_box, _piece_id, _piece_params_for(_piece_id),
		func(name: String, delta: int) -> void: _step_piece_param(name, delta),
		func(name: String, value: Variant) -> void: _set_piece_param(name, value),
	)


## ONE ROW PER DECLARED PARAMETER, and the row's KIND comes from the data file:
## `numeric` gets a stepper over its own `values` list, anything else gets a
## dropdown of its declared choices. Nothing here can produce a value the kit did
## not declare, and nothing here accepts typed input.
func _build_piece_param_rows(
	into: VBoxContainer, piece_id: String, values: Dictionary,
	on_step: Callable, on_choose: Callable,
) -> void:
	var declared := PieceKit.params_of(piece_id)
	for key in declared.keys():
		var name := str(key)
		var spec := declared[key] as Dictionary
		var current: Variant = values.get(name, spec["default"])
		if bool(spec.get("numeric", false)):
			into.add_child(_piece_stepper_row(name, spec, current, on_step))
		else:
			into.add_child(_piece_choice_row(name, spec, current, on_choose))


func _piece_stepper_row(
	name: String, spec: Dictionary, current: Variant, on_step: Callable
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var label := BrandLabel.new(name.to_upper(), BrandLabel.Role.SECTION)
	label.custom_minimum_size = Vector2(74, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var down := BrandComponents.compact_button("◀", BrandTokens.MIN_HIT_TARGET)
	down.tooltip_text = "%s: %s" % [name, str(spec["values"])]
	down.pressed.connect(func() -> void: on_step.call(name, -1))
	row.add_child(down)
	var value := BrandLabel.new(_piece_value_text(spec, current), BrandLabel.Role.DATA)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	var up := BrandComponents.compact_button("▶", BrandTokens.MIN_HIT_TARGET)
	up.tooltip_text = down.tooltip_text
	up.pressed.connect(func() -> void: on_step.call(name, 1))
	row.add_child(up)
	return row


func _piece_choice_row(
	name: String, spec: Dictionary, current: Variant, on_choose: Callable
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var label := BrandLabel.new(name.to_upper(), BrandLabel.Role.SECTION)
	label.custom_minimum_size = Vector2(74, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_ALL
	option.custom_minimum_size = Vector2(0, BrandTokens.MIN_HIT_TARGET)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choices := spec["values"] as Array
	for index in choices.size():
		option.add_item(str(choices[index]).capitalize(), index)
		if str(choices[index]) == str(current):
			option.select(index)
	option.item_selected.connect(func(index: int) -> void:
		on_choose.call(name, str(choices[index]))
	)
	row.add_child(option)
	return row


## A parameter value as a player reads it: the grid count it IS, plus the metres
## it means when the unit is one the studio knows how to convert. An unknown unit
## prints the count and the unit's own name — never a converted number, because a
## wrong metre reading is worse than none.
func _piece_value_text(spec: Dictionary, value: Variant) -> String:
	var unit := str(spec.get("unit", ""))
	if not (value is int or value is float):
		return str(value)
	if PIECE_UNIT_METRES.has(unit):
		return "%d   %.2f m" % [int(value), float(value) * float(PIECE_UNIT_METRES[unit])]
	return "%d   %s" % [int(value), unit.replace("_", " ")]


func _build_drawer() -> void:
	_drawer = BrandComponents.panel(Vector2(320, 0), BrandPanel.Variant.PAPER)
	_drawer.name = "PropertiesDrawer"
	_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_top = 60.0
	_drawer.offset_bottom = -36.0
	_ui_root.add_child(_drawer)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	_drawer.add_child(root_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	scroll.add_child(box)

	box.add_child(BrandComponents.section_header("SURFACE LIBRARY"))
	_build_library_section(box)
	box.add_child(BrandComponents.separator())
	box.add_child(BrandComponents.section_header("PROPERTIES"))
	_drawer_info = BrandLabel.new("", BrandLabel.Role.BODY_MUTED)
	_drawer_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_drawer_info)
	_inspector_box = VBoxContainer.new()
	_inspector_box.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	box.add_child(_inspector_box)

	root_box.add_child(BrandComponents.separator())
	root_box.add_child(BrandComponents.section_header("STRUCTURE FILE"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Structure name"
	_name_edit.max_length = 32
	root_box.add_child(_name_edit)
	var save_btn := BrandComponents.primary_button("SAVE JSON", Vector2(0, BrandTokens.MIN_HIT_TARGET))
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func() -> void: _save_plan(_name_edit.text))
	root_box.add_child(save_btn)
	_load_option = OptionButton.new()
	_load_option.focus_mode = Control.FOCUS_ALL
	_load_option.custom_minimum_size = Vector2(0, BrandTokens.MIN_HIT_TARGET)
	root_box.add_child(_load_option)
	var load_btn := BrandComponents.compact_button("LOAD SELECTED", 0.0)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(func() -> void:
		var index := _load_option.selected
		if index >= 0:
			_load_plan(str(_load_option.get_item_metadata(index)))
	)
	root_box.add_child(load_btn)


func _build_context_strip() -> void:
	var strip := BrandComponents.panel(Vector2.ZERO, BrandPanel.Variant.BAND)
	strip.name = "ContextStrip"
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.custom_minimum_size = Vector2(0, 36)
	_ui_root.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_LG)
	strip.add_child(row)

	_metrics_label = BrandLabel.new("", BrandLabel.Role.INVERSE_DATA)
	_metrics_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_metrics_label)

	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 1
	row.add_child(divider)

	_hint_label = BrandLabel.new("", BrandLabel.Role.MICRO_DATA)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
	row.add_child(_hint_label)

	_status_label = BrandLabel.new("", BrandLabel.Role.STATUS_OK)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override(&"font_color", BrandTokens.OK_LIGHT)
	row.add_child(_status_label)


func _set_status(text: String, ok := true) -> void:
	_status = text
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", BrandTokens.OK_LIGHT if ok else BrandTokens.ALERT
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
	_refresh_piece_section()
	for opening_type in _opening_buttons.keys():
		(_opening_buttons[opening_type] as Button).set_pressed_no_signal(opening_type == _opening_type)
	_level_label.text = "LEVEL %.0f M" % _active_base
	_ghost_button.set_pressed_no_signal(_ghost_levels)
	for slot in _slot_buttons.keys():
		(_slot_buttons[slot] as Button).set_pressed_no_signal(slot == _armed_slot)
	var armed_material := str((_lib[_armed_slot] as Dictionary)["material"])
	for material_name in _lib_material_buttons.keys():
		(_lib_material_buttons[material_name] as Button).set_pressed_no_signal(material_name == armed_material)
	_entities_label.text = "STRUCTURE\n%d PARTS\n%d KIT PIECES\n%d UNDO STEPS" % [
		_plan.entity_count(), _plan.pieces.size(), _undo_stack.size()
	]
	_hull_option.visible = _context == "vessel"
	_context_label.text = (
		"VESSEL / %s" % _hull_id.to_upper() if _context == "vessel" else "LAND BUILDING"
	)
	_metrics_label.text = _studio_metrics_text()
	_hint_label.text = str(TOOL_HINTS.get(_tool, "")).to_upper()
	_refresh_load_list()
	_refresh_inspector()


func _studio_metrics_text() -> String:
	var wall_metres := 0.0
	for wall_raw in _plan.walls:
		wall_metres += float((wall_raw as Dictionary).get("length", 0.0))
	var deck_area := 0.0
	for deck_raw in _plan.decks:
		var deck_size := (deck_raw as Dictionary).get("size", [0.0, 0.0]) as Array
		if deck_size.size() >= 2:
			deck_area += float(deck_size[0]) * float(deck_size[1])
	## "GRID 1 M" was a lie for as long as it has been on screen: the grid this
	## studio DRAWS is `DeckGrid.CELL_M`, half a metre, and only the draw tools'
	## cursor was ever on whole metres. Both numbers, named for what they are.
	return "CELL %.2f M   DRAW SNAP %.0f M   LEVEL %.0f M   PARTS %d   PIECES %d   WALL %.0f M   DECK %.0f M²" % [
		NODE_SNAP,
		GRID_SNAP,
		_active_base,
		_plan.entity_count(),
		_plan.pieces.size(),
		wall_metres,
		deck_area,
	]


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
		_drawer_info.text = "Nothing selected. Use Select / Move and click a wall, deck plate or stair."
		return
	var kind := "wall"
	## A placement is tested for FIRST: it has no `axis`, no `dir` and no `size`,
	## so the wall/stair/deck ladder below would have called every piece a deck
	## plate and offered it a thickness field it does not have.
	if entity.has("piece"):
		kind = "piece"
	elif entity.has("axis"):
		kind = "wall"
	elif entity.has("dir"):
		kind = "stair"
	else:
		kind = "deck"
	if kind == "piece":
		_refresh_piece_inspector(entity)
		return
	_drawer_info.text = ""
	var header := BrandLabel.new(
		"%s / PART %03d" % [kind.to_upper(), _selected_id],
		BrandLabel.Role.DATA
	)
	header.add_theme_color_override(&"font_color", BrandTokens.BRASS_DEEP)
	_inspector_box.add_child(header)
	var fields: Array = []
	match kind:
		"wall":
			fields = [["length", 1.0, 60.0, 1.0], ["height", 0.5, 12.0, 0.5], ["thickness", 0.05, 0.5, 0.05]]
		"deck":
			fields = [["thickness", 0.05, 0.5, 0.05]]
		"stair":
			fields = [["length", 1.0, 30.0, 1.0], ["width", 0.5, 8.0, 0.5], ["height", 0.5, 12.0, 0.5]]
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
	if kind == "stair":
		var steps := StructureBaker.stair_step_count(entity)
		_inspector_box.add_child(BrandComponents.key_value_row(
			"Steps", "%d × %.0f cm rise" % [steps, float(entity.get("height", 3.0)) / float(steps) * 100.0]
		))
		var rotate_btn := BrandComponents.compact_button("Rotate climb  ⟳", 0.0)
		rotate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotate_btn.pressed.connect(func() -> void:
			_snapshot()
			var order := ["+x", "+z", "-x", "-z"]
			var next := (order.find(str(entity.get("dir", "+x"))) + 1) % order.size()
			entity["dir"] = order[next]
			## The footprint swaps axes with the climb direction so the run
			## keeps its length along the new climb axis.
			_rebake()
			_refresh_panel()
		)
		_inspector_box.add_child(rotate_btn)
	## Surface readout — painting happens through the armed MATERIAL LIBRARY.
	_inspector_box.add_child(BrandComponents.key_value_row(
		"Surface", str(entity.get("material", "painted")).capitalize()
	))
	var openings: Array = entity.get("openings", [])
	if not openings.is_empty():
		var opening_info := BrandLabel.new(
			"OPENINGS  %d" % openings.size(),
			BrandLabel.Role.DATA
		)
		_inspector_box.add_child(opening_info)
		var pop_btn := BrandComponents.compact_button("REMOVE LAST OPENING", 0.0)
		pop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pop_btn.pressed.connect(func() -> void:
			_snapshot()
			openings.pop_back()
			_rebake()
			_refresh_panel()
		)
		_inspector_box.add_child(pop_btn)
	_inspector_box.add_child(BrandComponents.separator())
	var delete_btn := BrandButton.new("DELETE PART  [DEL]", BrandButton.Variant.DANGER)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.pressed.connect(func() -> void: _delete_selected())
	_inspector_box.add_child(delete_btn)


## Inspector for a PLACED piece. Same controls as the palette's — steppers over
## declared sets and dropdowns over declared choices — because "see and edit its
## params" and "set them before placing" are the same act on the same data, and
## two different UIs for it would drift.
func _refresh_piece_inspector(placement: Dictionary) -> void:
	var piece_id := str(placement.get("piece", ""))
	var cell := StructurePlan.piece_cell(placement)
	_drawer_info.text = str(PieceKit.get_piece(piece_id).get("description", ""))
	var header := BrandLabel.new(
		"%s / PART %03d" % [PieceKit.display_name(piece_id).to_upper(), _selected_id],
		BrandLabel.Role.DATA
	)
	header.add_theme_color_override(&"font_color", BrandTokens.BRASS_DEEP)
	_inspector_box.add_child(header)
	_inspector_box.add_child(BrandComponents.key_value_row(
		"Node", "cell %d, %d, %d" % [cell.x, cell.y, cell.z]
	))
	var facing_row := HBoxContainer.new()
	facing_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var back := BrandComponents.compact_button("⟲", BrandTokens.MIN_HIT_TARGET)
	back.pressed.connect(func() -> void: _rotate_selected_piece(-1))
	facing_row.add_child(back)
	var facing := BrandLabel.new(
		"FACING %d°" % int(placement.get("facing", 0)), BrandLabel.Role.DATA
	)
	facing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	facing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	facing_row.add_child(facing)
	var forward := BrandComponents.compact_button("⟳  [R]", BrandTokens.MIN_HIT_TARGET)
	forward.pressed.connect(func() -> void: _rotate_selected_piece(1))
	facing_row.add_child(forward)
	_inspector_box.add_child(facing_row)
	_build_piece_param_rows(
		_inspector_box, piece_id, placement.get("params", {}) as Dictionary,
		func(name: String, delta: int) -> void: _step_selected_piece_param(name, delta),
		func(name: String, value: Variant) -> void: _set_selected_piece_param(name, value),
	)
	_inspector_box.add_child(BrandComponents.key_value_row(
		"Tint", str(placement.get("color", _kit_color_hex(piece_id)))
	))
	_inspector_box.add_child(BrandComponents.separator())
	var delete_btn := BrandButton.new("DELETE PIECE  [DEL]", BrandButton.Variant.DANGER)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.pressed.connect(func() -> void: _delete_selected())
	_inspector_box.add_child(delete_btn)


## The standing right-hand surface library. Modal: arm Outside or Inside, then
## clicks on materials/swatches paint that slot of the current selection AND
## become the default style for everything drawn next.
func _build_library_section(box: VBoxContainer) -> void:
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	for slot_def in [["out", "Outside"], ["in", "Inside"]]:
		var slot := str(slot_def[0])
		var btn := BrandComponents.tool_button(str(slot_def[1]).to_upper(), 0.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			_armed_slot = slot
			_refresh_panel()
		)
		slot_row.add_child(btn)
		_slot_buttons[slot] = btn
	box.add_child(slot_row)
	var material_flow := HFlowContainer.new()
	material_flow.add_theme_constant_override(&"h_separation", BrandTokens.SPACE_XS)
	material_flow.add_theme_constant_override(&"v_separation", BrandTokens.SPACE_XS)
	for material_name in MATERIAL_LIBRARY:
		var btn := BrandComponents.tool_button(material_name.to_upper(), 62.0)
		btn.pressed.connect(func() -> void: _apply_library_material(material_name))
		material_flow.add_child(btn)
		_lib_material_buttons[material_name] = btn
	box.add_child(material_flow)
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override(&"h_separation", BrandTokens.SPACE_XS)
	swatches.add_theme_constant_override(&"v_separation", BrandTokens.SPACE_XS)
	for swatch_variant in COLOR_LIBRARY:
		var swatch_color := swatch_variant[1] as Color
		var swatch := Button.new()
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(32, 32)
		swatch.tooltip_text = str(swatch_variant[0])
		var sb := StyleBoxFlat.new()
		sb.bg_color = swatch_color
		sb.border_color = BrandTokens.SEA_LINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(0)
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
	## A placement's colour is an `#rrggbb` string and its material belongs to the
	## piece, not to the placement. Writing this library's `[r, g, b]` array into
	## it would produce a placement no reader accepts — the PIECE TINT swatches
	## are the control for that, and they write hex.
	if entity.has("piece"):
		return {}
	## Walls, plates and stairs carry a single surface — both slots address it.
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
func _stamp_library_style(entity: Dictionary) -> void:
	var out := _lib["out"] as Dictionary
	entity["color"] = (out["color"] as Array).duplicate()
	entity["material"] = str(out["material"])


func _spin_row(label_text: String, value: float, min_value: float, max_value: float, step: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	var label := BrandLabel.new(label_text.to_upper(), BrandLabel.Role.SECTION)
	label.custom_minimum_size = Vector2(84, 0)
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
