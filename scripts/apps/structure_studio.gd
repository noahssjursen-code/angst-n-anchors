extends Node3D

## gate-selfcheck: res://scenes/apps/structure_studio.tscn -- --studio-probe
## ^ MUST stay inside the first 40 lines. It was at line 59 on 2026-08-15 —
## header prose had pushed it past the limit and the gate scored this unit
## FAIL(selfcheck) with no probe run at all. Kept at the top, above the prose,
## so growing the header cannot silently unhook the app from the gate again.

## STRUCTURE STUDIO — the unified parametric builder for vessels and land
## buildings. Replaces the separate shipyard/building brick editors.
##
## Structure is drawn, not stacked:
##   P  piece tool   — pick a piece off the KIT palette, R turns it, click a grid
##                     NODE to stand it there. Every parameter is a stepper or a
##                     dropdown over the piece's own declared set: there is no
##                     field in this tool a number can be typed into, which is the
##                     whole difference between a kit and CAD.
##   I  fitting tool — pick a fitting off the CATALOGUE palette, R turns it by
##                     that part's own declared yaw step, click a grid node to
##                     stand it there. Bollards, helm, navigation lights: the
##                     gear a registration counts. Placed at the part's declared
##                     default size — sizing a fitting is not in this tool yet,
##                     and that limit is stated on `_fitting_id` rather than
##                     worked around with a step this file invented.
##   W  wall tool    — click-drag along the grid, release to place a wall run
##   D  deck tool    — click-drag a rectangle deck plate
##   S  stairs       — click-drag along the climb direction: a solid stepped
##                     run rising one level, walkable as rendered
##   O  opening tool — click a wall or deck to punch the selected opening type
##   Q  select       — click an entity: XYZ gizmo arrows to move, panel to edit,
##                     DEL to delete
##   Ctrl+Z / Ctrl+Y — undo / redo (full-plan snapshots, INCLUDING the two steps
##                     that used to be unrecoverable: a BUILD CONTEXT switch and
##                     a hull change. Both start a new plan; both leave the old
##                     one on the stack, on its own hull. See `_set_context`.)
##   PgUp/PgDn       — build level up/down (grid follows; upper decks ghost)
##   F               — focus camera on selection · Esc cancels a drag
##   RMB drag orbit · MMB drag pan · wheel zoom
##
## Context switch (left palette): Vessel (build on a hull) or Building (ground
## slab). Save/Load: JSON plans in res://resources/data/structures/.
##
## THE SIDE PANELS SCROLL AND THE SCROLLBAR IS 0 PX WIDE. `brand_theme.gd` styles
## every branded `ScrollContainer`'s bar with no border and no margin, so nothing
## on screen says the drawer holds 1565 px of content in a 948 px viewport, or
## the fitting palette 1627. Measured through `Viewport.push_input`: the WHEEL
## reaches all of it — 7 notches to the foot of the drawer, and the camera behind
## does not move while it does — so SAVE JSON and LOAD SELECTED are reachable but
## unsignposted. Held by `_probe_below_the_fold_is_reachable`; first measured in
## `tests/_studio_wheel_probe.gd`, and what a visible bar would cost the other
## eleven branded ScrollContainers is measured in `tests/_studio_scrollbar_cost.gd`
## (a 6 px bar makes each studio scroll 6 px WIDER than the panel holding it, so
## it is a layout change in every one of them, not a theme constant).
##
## KNOWN AND NOT FIXED: once a panel is at the end of its travel the notch is not
## consumed, so it falls through to `_handle_mouse_button` and zooms the camera —
## 34.000 to 38.760 on the eighth notch over the drawer, and on EVERY notch over a
## palette short enough not to scroll.
##
## This app carries its own self-check and DECLARES it to the gate below. The
## gate discovers lane C by this marker alone — there is no list of app names in
## tools/gate.sh, so a second such app joins by adding one line to its own
## script, exactly like `## gate-requires:`.
##

## The SHIPPED plans — the worked examples the fleet is built from, versioned in
## git and read by nine gate fixtures. READ ONLY, from this app's point of view.
const STRUCTURES_DIR := "res://resources/data/structures"

## ── WHERE A BUILDER'S OWN PLAN GOES, AND WHY IT IS NOT THE LINE ABOVE ───────
##
## `_save_plan` used to write `res://resources/data/structures/<name>.json`, the
## same directory the line above declares read-only, with `FileAccess.WRITE` and
## no existence check. Two consequences, both measured
## (`tests/_studio_drawer_drive.gd`, section 6):
##
##  1. A name that snake-cases onto a shipped fixture REPLACES IT, silently, with
##     the toast reading `SAVED /` exactly as it does for a new file. Measured: a
##     249-byte plan carrying a marker string, saved over by a builder typing
##     "Audit Decoy Fixture", came back 489 bytes with the marker gone. There is
##     no confirmation, no backup and no undo — `_undo` restores the PLAN, never
##     the file. And `to_snake_case` collapses "Demo Workboat", "demo workboat",
##     "DemoWorkboat" and "demo-workboat" onto the one file name, so the collision
##     does not need the builder to type the fixture's name.
##  2. `res://` is inside the PCK in an exported build and is not writable there,
##     so the whole control could only ever have worked from a source tree. Every
##     other thing a player writes in this project goes to `user://`
##     (`AssetPaths.USER_SAVE_DIR`, `USER_ORDERS_DIR`, `LocalCaptainStore.ROOT_DIR`);
##     the studio was the one place that did not.
##
## So a builder's plans live here, and the shipped fixtures stay where they are.
## `_saved_plan_paths` reads BOTH — the worked examples are the point of the LOAD
## list — and a builder's own saves come first, because those are the ones they
## are looking for.
const SAVED_PLANS_DIR := "user://structures"

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

enum Tool { SELECT, WALL, DECK, STAIR, OPENING, PIECE, FITTING }

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

## ── The FITTING tool ────────────────────────────────────────────────────────
##
## Same shape as the piece tool and for the same reason (§5): before this, this
## studio could author walls, decks, stairs, openings and kit pieces, and
## `_plan.items` — every fitting in `PartCatalog`, which is every object a
## registration counts — could be written by a JSON author and by nothing else.
## `add_item` appeared nowhere in this file. So a player could draw a hull full
## of superstructure and could not place the bollard, the helm or the navigation
## light that makes it a legal vessel: seventeen of seventeen catalogue parts
## were unreachable with a mouse. Fixing the rule vocabulary (STATE.md 2f) only
## moves that blocker unless the fittings can be fitted.
##
## Nothing here names a part. The palette is `PartCatalog.ids()`, the rotation
## step is the part's own declared `yaw_step`, and the tooltip is its own
## `description`.
##
## THE LIMIT, NAMED RATHER THAN PAPERED OVER: a part is placed at its DECLARED
## DEFAULT parameters. A `params` entry is a continuous `{default, min, max}`
## range, not the finite `values` list a kit piece declares, so there is no
## declared step to walk — and inventing one here would be this studio choosing
## the quantisation of somebody else's data, which is what `PIECE_UNIT_METRES`
## deliberately refuses to do. Sizing a fitting is the next tool, not this one.
var _fitting_id := ""
var _fitting_yaw := 0.0
var _fitting_ghost: Node3D
var _fitting_ghost_key := ""
## The item the ghost is currently drawing, or {} when nothing is previewed. The
## commit path places THIS dictionary — same property the piece tool has.
var _fitting_ghost_item: Dictionary = {}
var _fitting_buttons: Dictionary = {}
var _fitting_section: VBoxContainer
var _fitting_yaw_label: Label


func _ready() -> void:
	_build_scene()
	_build_ui()
	_set_context("vessel")
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--studio-probe":
			_run_studio_probe()
		elif str(arg) == "--studio-shot":
			_shoot_piece_tool()
		elif str(arg) == "--studio-fitting-shot":
			_shoot_fitting_tool()
		elif str(arg) == "--studio-registration-shot":
			_shoot_registration_checklist()
		elif str(arg) == "--studio-drawer-shot":
			_shoot_properties_drawer()


## A photograph of the piece tool in use, because a UI surface is not reviewable
## from a diff (CONVENTIONS §3). Loads the tug the tool built, arms the palette,
## stands a ghost on a grid node and writes one stable-named PNG.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://scenes/apps/structure_studio.tscn -- --studio-shot
func _shoot_piece_tool() -> void:
	_load_plan("%s/probe_piece_tug.json" % STRUCTURES_DIR)
	_set_tool(Tool.PIECE)
	var ids := _kit_ids()
	if ids.size() > 0:
		## Whichever piece the kit lists as "wall_glazed" is not named here: the
		## shot picks the one whose display name is longest, which is a stand-in
		## for "the most interesting", and it keeps this file free of piece names.
		var pick := str(ids[0])
		for id_variant in ids:
			if PieceKit.display_name(str(id_variant)).length() > PieceKit.display_name(pick).length():
				pick = str(id_variant)
		_select_piece_type(pick)
	_set_build_level(2.0)
	var node := Vector3i(8, 4, 34)
	_update_piece_ghost(node)
	_start_marker.position = _plan_offset + StructurePlan.piece_node_plan(node)
	_start_marker.visible = true
	_cam_focus = _plan_offset + Vector3(4.5, 2.6, 15.0)
	_cam_yaw = 3.75
	_cam_pitch = 0.30
	_cam_distance = 13.0
	_set_status("piece tool — ghost standing on cell 9, 4, 22")
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "res://screenshots/studio/structure_studio__piece_tool.png"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://screenshots/studio")
	)
	var error := get_viewport().get_texture().get_image().save_png(out)
	print("[structure-studio] piece tool shot -> %s (%d)" % [out, error])
	get_tree().quit(0 if error == OK else 1)


## A photograph of the FITTING tool in use — same reason as the piece shot, and
## the surface a reviewer has to look at to answer "could a player fit a
## navigation light". Stands a deck under the fittings, places the legal outfit
## through the tool's own click path and leaves a ghost on the cursor node.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://scenes/apps/structure_studio.tscn -- --studio-fitting-shot
func _shoot_fitting_tool() -> void:
	_set_context("vessel")
	_place_deck(Vector3(1, 0, 8), Vector3(9, 0, 24))
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("helm_console", Vector3i(10, 0, 40))
	for i in 4:
		_probe_click_fitting("bollard_pair", Vector3i(4 + i * 4, 0, 20))
	_probe_click_fitting("lantern_sidelight_port", Vector3i(3, 0, 30))
	_probe_click_fitting("lantern_sidelight_starboard", Vector3i(17, 0, 30))
	for _press in 6:
		_set_build_level(_active_base + NODE_SNAP)
	_probe_click_fitting("lantern_all_round", Vector3i(10, 6, 38))
	_set_build_level(0.0)
	_select_fitting_type("bollard_pair")
	var node := Vector3i(10, 0, 26)
	_update_fitting_ghost(node)
	_start_marker.position = _plan_offset + _fitting_plan_point(node)
	_start_marker.visible = true
	_cam_focus = _plan_offset + Vector3(5.0, 1.2, 14.0)
	_cam_yaw = 3.9
	_cam_pitch = 0.34
	_cam_distance = 15.0
	_set_status("fitting tool — bollard ghost standing on node 10, 0, 26")
	_refresh_panel()
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "res://screenshots/studio/structure_studio__fitting_tool.png"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://screenshots/studio")
	)
	var error := get_viewport().get_texture().get_image().save_png(out)
	print("[structure-studio] fitting tool shot -> %s (%d)" % [out, error])
	get_tree().quit(0 if error == OK else 1)


## TWO PHOTOGRAPHS OF THE SAME BOAT: one that does not certify and one that does.
##
## The claim this wave has to survive is REALITY.md §5 — can a player who has
## never read the source tell, from the screen, what is missing and where to get
## it — and that is a taste answer, so it is judged by LOOKING at these two, not
## by the check count beside them (REALITY.md §1, §2).
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://scenes/apps/structure_studio.tscn -- --studio-registration-shot
func _shoot_registration_checklist() -> void:
	_set_context("vessel")
	_place_deck(Vector3(1, 0, 8), Vector3(9, 0, 24))
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	## A boat somebody has started: helm aboard, two of the four mooring points
	## down, not one navigation light. Six of the eight requirements outstanding.
	_probe_click_fitting("helm_console", Vector3i(10, 0, 40))
	for i in 2:
		_probe_click_fitting("bollard_pair", Vector3i(4 + i * 8, 0, 20))
	_cam_focus = _plan_offset + Vector3(5.0, 1.2, 14.0)
	_cam_yaw = 3.9
	_cam_pitch = 0.34
	_cam_distance = 17.0
	_set_status("two mooring points and no lights", false)
	_refresh_panel()
	await _write_shot("structure_studio__registration_incomplete.png")
	## The same boat, finished with the tool: two more bollards, the sidelights on
	## their own sides, the masthead light six PgUp presses above them.
	for i in 2:
		_probe_click_fitting("bollard_pair", Vector3i(8 + i * 8, 0, 20))
	_probe_click_fitting("lantern_sidelight_port", Vector3i(3, 0, 30))
	_probe_click_fitting("lantern_sidelight_starboard", Vector3i(17, 0, 30))
	for _press in 6:
		_set_build_level(_active_base + NODE_SNAP)
	_probe_click_fitting("lantern_all_round", Vector3i(10, 6, 38))
	_set_build_level(0.0)
	_cam_focus = _plan_offset + Vector3(5.0, 1.2, 14.0)
	_cam_yaw = 3.9
	_cam_pitch = 0.34
	_cam_distance = 17.0
	_set_status("registration complete")
	_refresh_panel()
	await _write_shot("structure_studio__registration_certified.png")
	get_tree().quit(0)


## TWO PHOTOGRAPHS OF THE PROPERTIES DRAWER, WHICH HAS NEVER BEEN PHOTOGRAPHED.
##
## `2ab3eee` put the drawer on screen and shot the REGISTRATION checklist at the
## top of it. Everything under that has still only ever been seen as a rect in a
## probe's output: the surface library, the inspector, and the file controls. The
## drawer's own scroll is 948 px tall over 1565 px of content, so the second frame
## is the one a builder has to scroll to, and the reason both frames exist is that
## the gap between them IS the finding.
##
## THE SECOND FRAME IS SCROLLED WITH THE WHEEL, not by assigning `scroll_vertical`.
## The first cut of this shot assigned it, which is why the audit that took it
## could not say whether a builder could reach the bottom at all — an assignment
## moves a ScrollContainer whether or not any input can. Seven notches, pushed
## through `Viewport.push_input`, is what a player's hand does.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://scenes/apps/structure_studio.tscn -- --studio-drawer-shot
func _shoot_properties_drawer() -> void:
	_set_context("vessel")
	_place_deck(Vector3(1, 0, 8), Vector3(9, 0, 24))
	_place_wall(Vector3(2, 0, 10), Vector3(8, 0, 10))
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("helm_console", Vector3i(10, 0, 40))
	for index in 4:
		_probe_click_fitting("bollard_pair", Vector3i(4 + index * 4, 0, 20))
	_probe_click_fitting("lantern_sidelight_port", Vector3i(3, 0, 30))
	_probe_click_fitting("lantern_sidelight_starboard", Vector3i(17, 0, 30))
	## Select the port sidelight: the inspector that used to read DECK / PART 007
	## with a thickness spinner on it.
	_set_tool(Tool.SELECT)
	_selected_id = int((_plan.items[_plan.items.size() - 2] as Dictionary)["id"])
	_update_selection_visual()
	_cam_focus = _plan_offset + Vector3(5.0, 1.2, 14.0)
	_cam_yaw = 3.9
	_cam_pitch = 0.34
	_cam_distance = 17.0
	_set_status("port sidelight selected")
	_refresh_panel()
	_drawer_scroll.scroll_vertical = 0
	await _write_shot("structure_studio__drawer_top.png")
	## And the same frame WHEELED to the bottom, which is where the properties the
	## panel is NAMED for actually are.
	var at := _drawer_scroll.get_global_rect().get_center()
	var notches := 0
	while notches < 400:
		var was := _drawer_scroll.scroll_vertical
		await _probe_wheel(at)
		notches += 1
		if _drawer_scroll.scroll_vertical == was:
			break
	_set_status("%d wheel notches over the drawer" % notches)
	print("[structure-studio] drawer wheeled %d notches to scroll_vertical=%d" % [
		notches, _drawer_scroll.scroll_vertical
	])
	await _write_shot("structure_studio__drawer_properties.png")
	get_tree().quit(0)


func _write_shot(file_name: String) -> void:
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "res://screenshots/studio/%s" % file_name
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://screenshots/studio")
	)
	var error := get_viewport().get_texture().get_image().save_png(out)
	print("[structure-studio] shot -> %s (%d)" % [out, error])


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
	var probe_path := _plan_save_path("studio_probe_tmp")
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
	_probe_piece_levels(expect)
	_probe_piece_mouse(expect)
	_probe_piece_selection(expect)
	_probe_piece_persistence(expect)
	_probe_piece_fixture(expect, "%s/probe_piece_trawler.json" % STRUCTURES_DIR, "trawler")
	_probe_piece_fixture(expect, "%s/probe_piece_tug.json" % STRUCTURES_DIR, "tug")
	_probe_piece_tug_recipe(expect)
	_probe_entity_ids(expect)
	_probe_off_hull_is_on_screen(expect)
	## ── The fitting tool ────────────────────────────────────────────────────
	_probe_fitting_palette(expect)
	_probe_fitting_mouse(expect)
	_probe_a_mouse_built_vessel_certifies(expect)
	## ── The registration checklist ──────────────────────────────────────────
	_probe_panels_are_on_screen(expect)
	_probe_panel_and_spawn_agree(expect)
	_probe_the_checklist_says_where_to_go(expect)
	_probe_the_advice_matches_the_state(expect)
	_probe_every_fixture_lands_on_its_own_hull(expect)
	## ── The properties drawer's own controls ────────────────────────────────
	_probe_the_inspector_names_what_is_selected(expect)
	_probe_the_library_paints_what_it_says(expect)
	_probe_saving_cannot_touch_shipped_data(expect)
	_probe_the_round_trip_is_the_same_plan(expect)
	## ── The controls that throw a plan away ─────────────────────────────────
	await _probe_a_click_cannot_lose_the_plan(expect)
	await _probe_below_the_fold_is_reachable(expect)
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


## ── Piece-tool probe ────────────────────────────────────────────────────────
##
## Everything below drives the PLAYER'S PATH: the palette button's callback, the
## stepper's callback, the rotate key's callback, the cursor ray, the click. Not
## `_plan.add_piece`. The question this file has to answer is REALITY.md's — could
## a player do this with a mouse, without typing a number — and a probe that
## reaches past the controls into the plan cannot answer it.


## Does a builder who drags a wall off the boat SEE it? (REALITY.md §3d.)
##
## `PlanOutfit` refuses off-hull entities and `DeckFitout.apply_plan` then does
## not build them — but the identical chain on the brick side computed every
## error correctly and threw it away one line before the Label, so a player never
## saw one (STATE.md 2c). This asserts the sentence is on the panel, not that the
## function returned a list. Restoring the panel line to the plain entity count
## turns this red.
func _probe_off_hull_is_on_screen(expect: Callable) -> void:
	_set_context("vessel")
	_place_wall(Vector3(2, 0, 6), Vector3(8, 0, 6))
	expect.call("control: a wall on the deck is not reported off the hull", _off_hull.is_empty())
	var clean_panel := _entities_label.text
	expect.call(
		"control: the panel says nothing about the hull",
		not clean_panel.contains("OFF THE HULL")
	)
	_place_wall(Vector3(900, 0, 900), Vector3(906, 0, 900))
	expect.call("a wall 900 m off the bow is reported off the hull", _off_hull.size() == 1)
	_refresh_panel()
	expect.call(
		"and the STRUCTURE panel TELLS the builder it will not be built",
		_entities_label.text.contains("1 OFF THE HULL — NOT BUILT")
	)
	expect.call(
		"and the toast names the entity and the deck it missed",
		_status.contains("WALL") and _status.contains("10.0 X 28.0 M HULL")
	)
	_set_context("vessel")


## ── Fitting-tool probe ──────────────────────────────────────────────────────
##
## REALITY.md §5, asked of the catalogue: could a player place a bollard with a
## mouse? Until this tool landed the answer was NO for all seventeen parts —
## `add_item` appeared nowhere in this file — so every object a registration
## counts was authorable in JSON and nowhere else. Fixing the rule vocabulary
## (STATE.md 2f) would only have moved that blocker.
##
## Same method the wheelhouse wave used on the brick editor's palette: count how
## many catalogue ids are UNREACHABLE, and carry a made-up id as the control so
## the count is known to be capable of being non-zero.
func _probe_fitting_palette(expect: Callable) -> void:
	_set_context("vessel")
	var ids := PartCatalog.ids()
	expect.call("the catalogue loads for the palette (%d parts)" % ids.size(), ids.size() > 0)
	expect.call(
		"the catalogue loads clean (%s)" % ", ".join(PartCatalog.load_errors()),
		PartCatalog.load_errors().is_empty()
	)
	_set_tool(Tool.FITTING)
	expect.call("picking up the FITTING tool arms a fitting", not _fitting_id.is_empty())

	var unreachable := PackedStringArray()
	for id_variant in ids:
		var id := str(id_variant)
		if not _fitting_buttons.has(id):
			unreachable.append("%s: not on the palette" % id)
			continue
		var button := _fitting_buttons[id] as Button
		## Visible in the TREE, not merely present in the dictionary — a button
		## under a hidden section is a button nobody can press, and pressing it
		## from code would not notice.
		if not button.is_visible_in_tree():
			unreachable.append("%s: on the palette but not visible" % id)
			continue
		button.pressed.emit()
		if _fitting_id != id:
			unreachable.append("%s: the palette button did not arm it" % id)
	expect.call(
		"every catalogue part is reachable off the palette (%d of %d unreachable%s)"
		% [unreachable.size(), ids.size(),
			"" if unreachable.is_empty() else ": " + ", ".join(unreachable)],
		unreachable.is_empty()
	)
	## Seventeen buttons are taller than this panel, and the capture showed it.
	## The palette scrolls, which is the only reason the parts below the fold are
	## reachable at all — the piece tool learned this when the kit grew from four
	## parameters to seven and RAKE fell off the bottom of the window.
	var scrolled := false
	var walk: Node = _fitting_section
	while walk != null:
		if walk is ScrollContainer:
			scrolled = true
			break
		walk = walk.get_parent()
	expect.call("the fittings palette is inside a scroll container", scrolled)

	## THE CONTROL. A part id the catalogue does not hold must be refused, or the
	## loop above is only saying that a dictionary has keys.
	var armed_before := _fitting_id
	_select_fitting_type("bollard_of_the_gods")
	expect.call(
		"control: a part the catalogue never heard of does not arm",
		_fitting_id == armed_before
	)
	expect.call(
		"control: and the builder is told why",
		_status.to_lower().contains("bollard_of_the_gods")
	)

	## R turns the armed fitting by the PART's own step, which the catalogue
	## declares — this file holds no angle.
	_select_fitting_type(str(ids[0]))
	var step := PartCatalog.yaw_step_of(str(ids[0]))
	var before := _fitting_yaw
	_rotate_fitting(1)
	expect.call(
		"R turns the armed fitting by its own declared step (%d°)" % step,
		is_equal_approx(_fitting_yaw, fposmod(before + float(step), 360.0))
	)
	_rotate_fitting(-1)
	expect.call("and back again", is_equal_approx(_fitting_yaw, before))


## THE CURSOR: a grid node under the mouse, a ghost standing on it, and a click
## that puts the fitting exactly where the ghost was.
func _probe_fitting_mouse(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.FITTING)
	_select_fitting_type("bollard_pair")
	_set_build_level(0.0)

	var want := Vector3i(8, 0, 24)
	var aim := _plan_offset + _fitting_plan_point(want)
	_camera.position = aim + Vector3(0.0, 14.0, 14.0)
	_camera.look_at(aim, Vector3.UP)
	var screen := _camera.unproject_position(aim)
	var node := _mouse_to_node(screen)
	expect.call(
		"the cursor reads grid node (%d, %d, %d) under the fitting tool"
		% [node.x, node.y, node.z],
		node == want
	)
	_update_fitting_ghost(node)
	expect.call("a ghost is drawn at the node", _fitting_ghost != null)
	var ghost_item := _fitting_ghost_item.duplicate(true)
	var ghost_bounds := _probe_node_bounds(_fitting_ghost)
	expect.call("the ghost has a real extent", ghost_bounds.size.length() > 0.1)

	var placed := _place_fitting_at(node)
	expect.call("the click places a fitting", not placed.is_empty())
	if placed.is_empty():
		return
	var committed := placed.duplicate(true)
	var previewed := ghost_item.duplicate(true)
	committed.erase("id")
	previewed.erase("id")
	expect.call(
		"THE FITTING COMMITTED IS THE FITTING THE GHOST DREW (%s vs %s)"
		% [JSON.stringify(previewed), JSON.stringify(committed)],
		committed == previewed
	)
	## Selection, focus and DEL all read `_entity_bounds`, and items had no entry
	## in it at all before this — a fitting in a loaded plan could not be clicked.
	var id := int(placed["id"])
	expect.call("the placed fitting is pickable (has bounds)", _entity_bounds.has(id))
	if _entity_bounds.has(id):
		expect.call(
			"and it lands inside the volume the ghost showed",
			ghost_bounds.grow(0.05).encloses((_entity_bounds[id] as AABB))
		)
	## Selecting it and pressing DEL removes it, through the same path a player uses.
	_selected_id = id
	_delete_selected()
	expect.call("DEL removes the fitting", _plan.entity_by_id(id).is_empty())


## THE PAYOFF, and the sentence STATE.md 2f exists for: a vessel a player built
## with a mouse is a vessel the registration system certifies.
##
## Every placement below goes through the palette button, the level control and
## the click — never `_plan.add_item` — and the verdict comes from
## `PlanOutfit.compliance`, the same call `DeckFitout.apply_plan` makes.
func _probe_a_mouse_built_vessel_certifies(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)

	## Port is −x on the deck grid and this hull is 20 cells in the beam, so a
	## node at x = 2 is to port and x = 18 to starboard.
	_probe_click_fitting("helm_console", Vector3i(10, 0, 46))
	for i in 4:
		_probe_click_fitting("bollard_pair", Vector3i(4 + i * 4, 0, 8))
	_probe_click_fitting("lantern_sidelight_port", Vector3i(2, 0, 30))
	_probe_click_fitting("lantern_sidelight_starboard", Vector3i(18, 0, 30))
	## PgUp six times: the masthead light goes 3 m up, above the sidelights.
	for _press in 6:
		_set_build_level(_active_base + NODE_SNAP)
	expect.call("PgUp reaches 3.00 m for the masthead light", is_equal_approx(_active_base, 3.0))
	_probe_click_fitting("lantern_all_round", Vector3i(10, 6, 44))
	_set_build_level(0.0)

	expect.call("eight fittings were placed with the mouse", _plan.items.size() == 8)
	expect.call("and none of them is off the hull", _off_hull.is_empty())

	var report := PlanOutfitScript.compliance(_plan, _hull_id, "general_vessel", _deck_grid)
	var failed := PackedStringArray()
	for raw in report.get("checklist", []) as Array:
		if not bool((raw as Dictionary).get("ok", false)):
			failed.append(str((raw as Dictionary).get("id", "")))
	expect.call(
		"A VESSEL BUILT WITH THE MOUSE IS CERTIFIED A GENERAL VESSEL (failed: %s)"
		% ("none" if failed.is_empty() else ", ".join(failed)),
		bool(report.get("registration_ok", false))
	)
	expect.call("and the whole report is ok", bool(report.get("ok", false)))

	## THE LAW STILL BITES. Pull the port sidelight back off and the same vessel
	## is refused — the rule sees the light, it did not stop asking for one.
	var port_id := -1
	for item_variant in _plan.items:
		if str((item_variant as Dictionary).get("item_id", "")) == "lantern_sidelight_port":
			port_id = int((item_variant as Dictionary).get("id", -1))
	_selected_id = port_id
	_delete_selected()
	var dark := PlanOutfitScript.compliance(_plan, _hull_id, "general_vessel", _deck_grid)
	expect.call(
		"deleting the port sidelight refuses the vessel again",
		not bool(dark.get("registration_ok", true))
	)
	_set_context("vessel")


## ── The registration checklist probe ────────────────────────────────────────
##
## Three questions, in the order they have to be true in:
##   1. is the panel on the screen at all
##   2. does it say the same thing the spawn will say
##   3. can a person who has never read the source act on it


## REALITY.md §8, applied to a UI: check the instrument. Every panel this studio
## draws must be INSIDE the viewport, and two of them were not — the properties
## drawer stood at x = 1920 on a 1920-wide viewport and the context strip at
## y = 1080 on a 1080-tall one, so the inspector, the surface library, SAVE JSON,
## LOAD SELECTED, the tool hint, the metrics line and every `_set_status` toast
## have been rendering perfectly into nobody's eyes.
##
## This asserts RECTS, not text. The off-hull probe below it checks a `_status`
## STRING and passed the whole time the label carrying that string was off the
## bottom of the screen — which is exactly the gap between "computed" and "shown"
## this wave exists to close.
func _probe_panels_are_on_screen(expect: Callable) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	var offscreen := PackedStringArray()
	for name in ["TopBar", "ToolPalette", "PropertiesDrawer", "ContextStrip"]:
		var panel := _ui_root.get_node_or_null(NodePath(name)) as Control
		if panel == null:
			offscreen.append("%s: not in the tree" % name)
			continue
		if not panel.is_visible_in_tree():
			offscreen.append("%s: hidden" % name)
			continue
		## `grow(1)` absorbs the one-pixel rounding a panel's own border adds;
		## the failures this catches were 320 and 40 pixels out, not one.
		if not view.grow(1.0).encloses(panel.get_global_rect()):
			offscreen.append("%s: %s outside %s" % [name, panel.get_global_rect(), view])
	expect.call(
		"every studio panel is inside the viewport (%s)"
		% ("all four on screen" if offscreen.is_empty() else ", ".join(offscreen)),
		offscreen.is_empty()
	)
	## The checklist specifically, since it is the thing this wave delivers: it
	## is no use being inside a panel that is off the screen.
	_refresh_panel()
	expect.call(
		"the REGISTRATION checklist is visible in the tree",
		_registration_verdict != null and _registration_verdict.is_visible_in_tree()
	)


## THE ONE THAT MATTERS: what the panel says and what the boat is judged to be
## cannot disagree.
##
## A checklist that reads CERTIFIED over a vessel the spawn refuses is worse than
## no checklist — it is a lie with a UI, and it would be believed. So this does
## not compare two dictionaries: it authors the plan through the tool's own click
## path, reads the TEXT OFF THE LABELS, then puts the same plan through
## `VesselSpawn.instantiate` -> `DeckFitout.apply_plan` and compares the panel's
## words against the boat's own `vessel_outfit` meta and against the checklist
## `DeckFitout.compliance_for_layout` computes from the layout THE BOAT STORED.
##
## Both states are checked, because agreement on "no" is cheap: an INCOMPLETE
## vessel (helm and mooring only) and then the same vessel with its three lights.
func _probe_panel_and_spawn_agree(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("helm_console", Vector3i(10, 0, 46))
	for i in 4:
		_probe_click_fitting("bollard_pair", Vector3i(4 + i * 4, 0, 8))
	_refresh_panel()
	_probe_agreement_at(expect, "an unlit boat", false)

	_probe_click_fitting("lantern_sidelight_port", Vector3i(2, 0, 30))
	_probe_click_fitting("lantern_sidelight_starboard", Vector3i(18, 0, 30))
	for _press in 6:
		_set_build_level(_active_base + NODE_SNAP)
	_probe_click_fitting("lantern_all_round", Vector3i(10, 6, 44))
	_set_build_level(0.0)
	_refresh_panel()
	_probe_agreement_at(expect, "the same boat, lit", true)
	## No reset: `_set_context` rebuilds the host vessel, which is the single most
	## expensive call in this probe file, and the next probe opens with its own.


## One comparison of the screen against a spawned vessel. `expect_certified` is
## the wave's own claim about which state this is, so a mutation that makes the
## panel agree with the spawn by making BOTH of them say "no" still reddens.
func _probe_agreement_at(expect: Callable, what: String, expect_certified: bool) -> void:
	var panel_certified := _registration_verdict.text.begins_with("CERTIFIED")
	var panel_failed := _panel_failed_labels()
	expect.call(
		"%s: the panel's own verdict is the one this probe is testing (panel says %s)"
		% [what, _registration_verdict.text],
		panel_certified == expect_certified
	)

	var boat := VesselSpawn.instantiate(_hull_id, _plan.to_dict(), _registration_id)
	expect.call("%s: it spawns" % what, boat != null)
	if boat == null:
		return
	var outfit: Dictionary = boat.get_meta("vessel_outfit", {}) as Dictionary
	var spawned_certified := bool(outfit.get("registration_ok", false))
	expect.call(
		"%s: THE PANEL AND THE SPAWNED VESSEL AGREE (panel %s, boat %s)"
		% [what, panel_certified, spawned_certified],
		panel_certified == spawned_certified
	)
	## And rule by rule, off the layout the BOAT is carrying — the same call
	## persistence and deployment make on a saved record.
	var spawned := DeckFitout.compliance_for_layout(
		boat.get_meta("brick_layout", {}) as Dictionary,
		_hull_id,
		_registration_id,
		_deck_grid,
	)
	var spawn_failed := PackedStringArray()
	for raw in spawned.get("checklist", []) as Array:
		if not bool((raw as Dictionary).get("ok", false)):
			spawn_failed.append(str((raw as Dictionary).get("label", "")).to_upper())
	panel_failed.sort()
	spawn_failed.sort()
	expect.call(
		"%s: and they name the SAME failed requirements (panel [%s] vs spawn [%s])"
		% [what, ", ".join(panel_failed), ", ".join(spawn_failed)],
		panel_failed == spawn_failed
	)
	boat.free()


## The requirements the panel is telling a player it has failed, read back OUT OF
## THE LABELS — not out of `_compliance`. Reading the dictionary would prove the
## dictionary agrees with itself (REALITY.md §3).
func _panel_failed_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _registration_rows.get_children():
		var label := child as Label
		if label == null or not label.text.begins_with("✗"):
			continue
		out.append(label.text.substr(1).strip_edges())
	return out


## REALITY.md §5: could a player who has never read the source act on this?
##
## "FAILS 3" is not that. Neither is `white_light_height`. So for a boat that is
## short of exactly one thing, the screen has to carry the NAME OF THE FITTING
## that closes it and the TOOL it is on — and the name this probe looks for is
## fetched from `PartCatalog` by the rule's own tag, so the check is not a copy
## of the panel's string.
func _probe_the_checklist_says_where_to_go(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("helm_console", Vector3i(10, 0, 46))
	_refresh_panel()

	var failed := _panel_failed_labels()
	expect.call(
		"a boat with a helm and nothing else fails several requirements (%d)" % failed.size(),
		failed.size() >= 4
	)
	## Every failed requirement is followed by a sentence. A row with no advice
	## under it is the "FAILS 3" panel this wave replaced.
	var rows := _registration_rows.get_children()
	var unadvised := PackedStringArray()
	for index in rows.size():
		var label := rows[index] as Label
		if label == null or not label.text.begins_with("✗"):
			continue
		var advice := (rows[index + 1] as Label) if index + 1 < rows.size() else null
		if advice == null or advice.text.strip_edges().length() < 20:
			unadvised.append(label.text)
	expect.call(
		"every failed requirement carries a sentence saying what to do (%s)"
		% ("all advised" if unadvised.is_empty() else ", ".join(unadvised)),
		unadvised.is_empty()
	)

	var screen := _registration_panel_text()
	## The port sidelight is missing, and the catalogue says which fitting is a
	## port sidelight. The panel has to name it, and name a tool.
	var wanted := PackedStringArray()
	for id_variant in PartCatalog.ids():
		var id := str(id_variant)
		if PartCatalog.has_tag(id, "nav_port"):
			wanted.append(PartCatalog.display_name(id).to_upper())
	expect.call(
		"the catalogue has something tagged nav_port to name (%s)" % ", ".join(wanted),
		not wanted.is_empty()
	)
	var named := false
	for name in wanted:
		if screen.contains(name):
			named = true
	expect.call(
		"THE SCREEN NAMES THE FITTING THAT WOULD FIX THE MISSING PORT LIGHT (%s)"
		% ", ".join(wanted),
		named
	)
	expect.call(
		"and names the tool it is on, so a player knows where to click",
		screen.contains(FITTING_TOOL)
	)
	## THE CABIN RULE, AND WHAT THIS CHECK USED TO SAY. It read *"the cabin rule
	## no plan can satisfy admits it rather than inventing a tool"* and matched
	## the panel for "CANNOT SATISFY THIS REQUIREMENT", because
	## `PlanOutfit.has_cabin` returned false for every plan and the honest thing
	## was to say so. It is measured off geometry now, so the panel's job changed
	## from admitting a dead end to naming the three tools that draw a cabin —
	## and this check has to change with it or it pins the dead end in place.
	_registration_id = "passenger_vessel"
	_recompute_compliance()
	_refresh_panel()
	var passenger_screen := _registration_panel_text()
	expect.call(
		"the cabin rule names the tools that draw one instead of a dead end",
		passenger_screen.contains("WALL TOOL")
			and passenger_screen.contains("DECK TOOL")
			and passenger_screen.contains("OPENING TOOL")
	)
	expect.call(
		"...and it does NOT still tell the builder to pick another licence",
		not passenger_screen.contains("CANNOT SATISFY THIS REQUIREMENT")
	)
	## And with no licence chosen at all, the panel says what that costs.
	_registration_id = ""
	_recompute_compliance()
	_refresh_panel()
	expect.call(
		"an unregistered plan is told it cannot be spawned",
		_registration_verdict.text.contains("NOT REGISTERED")
			and _registration_panel_text().contains("PICK A LICENCE")
	)
	_registration_id = "general_vessel"
	_recompute_compliance()
	_refresh_panel()
	## The helm-only boat is left standing on purpose —
	## `_probe_the_advice_matches_the_state` runs next and needs exactly it.


## THE GRID FOLLOWS THE DOCUMENT — run over EVERY shipped fixture, not the one
## this wave was working on (REALITY.md §3c).
##
## `PlanOutfit`'s header states the fence refuses **zero of 2342 shipped
## entities**. That fact was true of the function and false of this studio: it
## adopted a loaded plan's `hull_id` and left `_deck_grid` on whatever hull the
## app had booted with, so `probe_container_feeder` — 617 entities, every one on
## its own hull — came back with **596 OFF THE HULL — NOT BUILT**. The panel in
## the corner said so, and nobody had asked it to be right.
##
## This asserts the studio agrees with that fact through its OWN load path, on
## every vessel document in the fixtures directory, so the next hull-shaped
## fixture is covered the day it is added rather than the day somebody edits a
## list here.
func _probe_every_fixture_lands_on_its_own_hull(expect: Callable) -> void:
	var wrong_grid := PackedStringArray()
	var refused := PackedStringArray()
	var loaded := 0
	## `STRUCTURES_DIR`, not `_saved_plan_paths()`: this check is about the SHIPPED
	## documents, and the load list now also carries whatever the builder has saved
	## to `SAVED_PLANS_DIR`. A gate check whose universe a player can edit is a
	## gate check that stops meaning what it says.
	for path_variant in _shipped_plan_paths():
		var path := str(path_variant)
		## Deliberately NOT reset between fixtures: loading a 150 m feeder over a
		## 28 m trawler is exactly the sequence that produced 596 phantom
		## refusals, and it is also half the work of resetting each time.
		_load_plan(path)
		if _context != "vessel" or _plan.hull_id.is_empty():
			continue
		loaded += 1
		var want := HullRegistry.make_grid(_plan.hull_id)
		if _deck_grid.width != want.width or _deck_grid.length != want.length:
			wrong_grid.append("%s: %dx%d, its hull %s is %dx%d" % [
				path.get_file(), _deck_grid.width, _deck_grid.length,
				_plan.hull_id, want.width, want.length
			])
		if not _off_hull.is_empty():
			refused.append("%s: %d of %d" % [
				path.get_file(), _off_hull.size(), _plan.entity_count()
			])
	expect.call("there are shipped vessel fixtures to load (%d)" % loaded, loaded >= 10)
	expect.call(
		"loading a plan puts the studio on THAT plan's hull grid (%s)"
		% ("all %d" % loaded if wrong_grid.is_empty() else ", ".join(wrong_grid)),
		wrong_grid.is_empty()
	)
	expect.call(
		"and no shipped fixture reports a single entity off its own hull (%s)"
		% ("0 refused" if refused.is_empty() else ", ".join(refused)),
		refused.is_empty()
	)
	## The hull dropdown is part of the answer: a control reading `hull_28x10`
	## over a 150 m feeder is the same lie one panel across.
	expect.call(
		"and the hull dropdown names the hull actually being built on (%s)"
		% _hull_option.get_item_text(_hull_option.selected),
		_hull_option.get_item_text(_hull_option.selected) == _hull_id
	)


## THE CHECK THIS WAVE'S OWN FIRST CAPTURE EARNED.
##
## `_probe_the_checklist_says_where_to_go` asserts that a failed requirement
## carries a sentence naming a fitting and a tool. The first cut of this panel
## satisfied all of that and was still WRONG: `tag_side` fails both when the
## light is on the wrong side and when there is no light, its `current` is 0 in
## both, and the sentence said "FITTED, BUT NOT ALL ON THE PORT SIDE" under a
## boat carrying no lights whatsoever. Nothing here caught it — I saw it in the
## capture (REALITY.md §2: look, do not score).
##
## So the property is not "there is a sentence". It is that the sentence
## DISTINGUISHES THE TWO STATES, and it is asserted from both directions on the
## same rule, which is the only shape that cannot be satisfied by one fixed
## string.
func _probe_the_advice_matches_the_state(expect: Callable) -> void:
	## Runs on the helm-only boat `_probe_the_checklist_says_where_to_go` left
	## standing — rebuilding the vessel costs a host spawn, and this probe needs
	## exactly the state that probe ends in.
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_refresh_panel()
	var dark := _advice_under("PORT LIGHT MOUNTED ON PORT SIDE")
	expect.call(
		"a boat with NO port light is not told its port light is misplaced (%s)" % dark,
		not dark.contains("WRONG SIDE")
	)
	expect.call(
		"it is told there is nothing fitted yet (%s)" % dark,
		dark.contains("NONE FITTED")
	)

	## Now fit one — on the STARBOARD half. Port is −x, and this hull is 20 cells
	## in the beam, so node x = 18 is the wrong side for a port light.
	_probe_click_fitting("lantern_sidelight_port", Vector3i(18, 0, 30))
	_refresh_panel()
	var misplaced := _advice_under("PORT LIGHT MOUNTED ON PORT SIDE")
	expect.call(
		"control: fitting it made the count rule pass",
		not _panel_failed_labels().has("PORT NAVIGATION LIGHT")
	)
	expect.call(
		"and the side rule still fails, because it is on the wrong side",
		_panel_failed_labels().has("PORT LIGHT MOUNTED ON PORT SIDE")
	)
	expect.call(
		"NOW the sentence says the light is on the wrong side (%s)" % misplaced,
		misplaced.contains("WRONG SIDE")
	)
	expect.call(
		"and no longer claims nothing is fitted (%s)" % misplaced,
		not misplaced.contains("NONE FITTED")
	)
	## No reset — the fixture sweep that runs next replaces the plan on its first
	## `_load_plan`, and that is a hull change, which is the case it exists for.


## The advice sentence drawn under a named requirement, read off the labels.
func _advice_under(label: String) -> String:
	var rows := _registration_rows.get_children()
	for index in rows.size():
		var row := rows[index] as Label
		if row == null or not row.text.contains(label):
			continue
		if index + 1 >= rows.size():
			return ""
		var advice := rows[index + 1] as Label
		return advice.text if advice != null else ""
	return ""


## Everything the REGISTRATION panel is currently putting on screen, as one
## string — the verdict line plus every row and every sentence under it.
func _registration_panel_text() -> String:
	var parts := PackedStringArray([_registration_verdict.text])
	for child in _registration_rows.get_children():
		var label := child as Label
		if label != null:
			parts.append(label.text)
	return "\n".join(parts)


## ── THE PROPERTIES DRAWER'S OWN CONTROLS ────────────────────────────────────
##
## The drawer was off the right edge of the viewport until `2ab3eee` — origin at
## x = 1920 on a 1920-wide viewport — so nothing inside it had ever been seen,
## and nothing inside it had ever been checked either. The four probes below are
## the audit: what does each control DO, does anything read what it writes, and
## is it wired to anything at all.
##
## They press the ACTUAL BUTTON NODE, found by its label in the drawer's own
## tree, for the reason `_probe_fitting_palette` gives: a probe that calls the
## method behind a control cannot tell you whether the control reaches it.


## The button a player would press, by the words written on it. Returns null when
## no such button is in the drawer, and the callers treat that as a failure rather
## than skipping — a control that has been RENAMED has moved out of reach of
## whoever was told to press it (REALITY §4's early-return-on-missing-fixture, in
## a UI).
func _probe_drawer_button(text: String) -> Button:
	return _probe_find_button(_drawer, text)


func _probe_find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var hit := _probe_find_button(child, text)
		if hit != null:
			return hit
	return null


## The drawer's colour swatches, in `COLOR_LIBRARY` order. They carry no text —
## the colour IS the label — so they are found by the 32 x 32 they are built at.
func _probe_swatch_buttons() -> Array[Button]:
	var out: Array[Button] = []
	_probe_collect_swatches(_drawer, out)
	return out


func _probe_collect_swatches(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			var button := child as Button
			if button.text.is_empty() and button.custom_minimum_size == Vector2(32, 32):
				out.append(button)
		_probe_collect_swatches(child, out)


## DOES THE INSPECTOR NAME WHAT IS SELECTED? For all six collections, not the
## four the old probe happened to select.
##
## `_refresh_inspector`'s kind ladder tested `piece`, `axis`, `dir` and fell
## through to "deck". An `items[]` fitting and an `edges[]` run have none of those
## keys, so BOTH came out as DECK / PART nnn with a THICKNESS spinner — a control
## that took an undo snapshot, rebaked, and wrote a key `normalize_item` throws
## away. Seventeen catalogue fittings and every swept run, described as a deck
## plate, for as long as the fitting tool has existed.
##
## The property asserted is not "the header string is X". It is: THE INSPECTOR
## NAMES THE COLLECTION THE SELECTION CAME FROM, and it offers no numeric field
## the collection's own normaliser would discard. The second half is what catches
## the spinner, and it is stated against `normalize_item` rather than against a
## list of field names kept here.
func _probe_the_inspector_names_what_is_selected(expect: Callable) -> void:
	_set_context("vessel")
	_place_deck(Vector3(1, 0, 8), Vector3(9, 0, 24))
	_place_wall(Vector3(2, 0, 10), Vector3(8, 0, 10))
	_place_stair(Vector3(3, 0, 14), Vector3(3, 0, 17))
	_set_tool(Tool.PIECE)
	var kit := _kit_ids()
	_select_piece_type(str(kit[0]))
	_place_piece_at(Vector3i(8, 0, 20))
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("bollard_pair", Vector3i(10, 0, 40))
	_probe_add_bulwark()

	var kinds := {
		"wall": _plan.walls[0], "deck": _plan.decks[0], "stair": _plan.stairs[0],
		"piece": _plan.pieces[0], "fitting": _plan.items[0], "edge": _plan.edges[0],
	}
	var mislabelled := PackedStringArray()
	for kind_variant in kinds.keys():
		var kind := str(kind_variant)
		var entity := kinds[kind] as Dictionary
		expect.call(
			"a %s is recognised as a %s, not as a deck plate (got \"%s\")"
			% [kind, kind, _selected_kind(entity)],
			_selected_kind(entity) == kind
		)
		_selected_id = int(entity.get("id", -1))
		_update_selection_visual()
		_refresh_panel()
		var header := _probe_inspector_header()
		## The header must NAME the thing. For a wall/deck/stair the kind is the
		## word; for a piece and a fitting it is the part's own display name, which
		## is stronger — this file holds no piece names and no part names.
		var wanted := kind.to_upper()
		if kind == "piece":
			wanted = PieceKit.display_name(str(entity["piece"])).to_upper()
		elif kind == "fitting":
			wanted = PartCatalog.display_name(str(entity["item_id"])).to_upper()
		elif kind == "edge":
			wanted = str(entity["primitive"]).replace("_", " ").to_upper()
		if not header.begins_with(wanted):
			mislabelled.append("%s -> \"%s\" (wanted \"%s\")" % [kind, header, wanted])
	expect.call(
		"the drawer's header names the selection, for all six collections (%s)"
		% ("all six" if mislabelled.is_empty() else ", ".join(mislabelled)),
		mislabelled.is_empty()
	)

	## THE SPINNER. Select the fitting, drive EVERY numeric control the inspector
	## built for it, and ask whether the item survived unchanged. This is the
	## check that would have been red for the whole life of the fitting tool.
	var fitting := _plan.items[0] as Dictionary
	_selected_id = int(fitting["id"])
	_refresh_panel()
	var before := JSON.stringify(StructurePlan.normalize_item(fitting.duplicate(true)))
	var spins := _probe_inspector_spinboxes()
	for spin in spins:
		spin.value_changed.emit(spin.value + spin.step)
	var after_edit := fitting.duplicate(true)
	var discarded := PackedStringArray()
	for key in after_edit.keys():
		if not StructurePlan.normalize_item(after_edit).has(key):
			discarded.append(str(key))
	expect.call(
		"no control in a fitting's inspector writes a key the plan discards (%s)"
		% ("none" if discarded.is_empty() else ", ".join(discarded)),
		discarded.is_empty()
	)
	expect.call(
		"driving every numeric control in a fitting's inspector leaves the fitting"
		+ " intact (%d spinners)" % spins.size(),
		JSON.stringify(StructurePlan.normalize_item(fitting.duplicate(true))) == before
	)

	## AND THE ROTATE CONTROL IS REAL. `R` has always turned a placed fitting;
	## there was no button for it, so a builder who did not know the shortcut
	## could not turn a bollard after placing it.
	var yaw_before := float(fitting.get("yaw", 0.0))
	var turn := _probe_find_button(_inspector_box, "⟳  [R]")
	expect.call("a placed fitting has a rotate button in the drawer", turn != null)
	if turn != null:
		turn.pressed.emit()
		var step := float(PartCatalog.yaw_step_of(str(fitting["item_id"])))
		var yaw_after := float((_plan.entity_by_id(_selected_id)).get("yaw", 0.0))
		expect.call(
			"pressing it turns the fitting by its part's own step (%.0f -> %.0f, step %.0f)"
			% [yaw_before, yaw_after, step],
			is_equal_approx(yaw_after, fposmod(yaw_before + step, 360.0))
		)
	## And an edge can still be deleted, which is the whole reason `edges[]` is a
	## first-class plan entity — this studio cannot draw one, so if the drawer
	## could not remove one either, a loaded bulwark would be permanent.
	var edge_id := int((_plan.edges[0] as Dictionary)["id"])
	_selected_id = edge_id
	_refresh_panel()
	var drop := _probe_find_button(_inspector_box, "DELETE RUN  [DEL]")
	expect.call("a swept run has a delete button in the drawer", drop != null)
	if drop != null:
		drop.pressed.emit()
		expect.call("and pressing it removes the run", _plan.entity_by_id(edge_id).is_empty())
	_set_context("vessel")


func _probe_inspector_header() -> String:
	if _inspector_box.get_child_count() == 0:
		return ""
	var first := _inspector_box.get_child(0)
	return (first as Label).text if first is Label else ""


func _probe_inspector_spinboxes() -> Array[SpinBox]:
	var out: Array[SpinBox] = []
	_probe_collect_spinboxes(_inspector_box, out)
	return out


func _probe_collect_spinboxes(node: Node, out: Array[SpinBox]) -> void:
	for child in node.get_children():
		if child is SpinBox:
			out.append(child as SpinBox)
		_probe_collect_spinboxes(child, out)


## DOES THE SURFACE LIBRARY PAINT WHAT IT SAYS IT PAINTS?
##
## It had an OUTSIDE / INSIDE toggle. With INSIDE armed a swatch wrote the
## selection's ONE `color` key — the same one OUTSIDE writes — and stored its
## value in `_lib["in"]`, which `_stamp_library_style` never read. So "inside"
## painted the outside and armed nothing. Both halves are asserted here, from the
## buttons, so re-splitting the slot cannot go quiet again.
func _probe_the_library_paints_what_it_says(expect: Callable) -> void:
	_set_context("vessel")
	_place_wall(Vector3(2, 0, 10), Vector3(8, 0, 10))
	var wall := _plan.walls[0] as Dictionary
	_selected_id = int(wall["id"])
	_refresh_panel()
	var swatches := _probe_swatch_buttons()
	expect.call(
		"every library swatch is on the drawer (%d of %d)" % [swatches.size(), COLOR_LIBRARY.size()],
		swatches.size() == COLOR_LIBRARY.size()
	)
	if swatches.is_empty():
		return
	## Pick a swatch the wall is definitely not already wearing.
	var index := 0
	for candidate in COLOR_LIBRARY.size():
		var colour := (COLOR_LIBRARY[candidate] as Array)[1] as Color
		if not is_equal_approx(colour.r, float((wall["color"] as Array)[0])):
			index = candidate
			break
	var wanted_colour := (COLOR_LIBRARY[index] as Array)[1] as Color
	(swatches[index] as Button).pressed.emit()
	expect.call(
		"pressing a swatch paints the selected wall (%s)" % [wall.get("color")],
		is_equal_approx(float((wall["color"] as Array)[0]), wanted_colour.r)
		and is_equal_approx(float((wall["color"] as Array)[2]), wanted_colour.b)
	)
	## THE HALF THAT WAS DEAD: the swatch is also the style the NEXT wall is born
	## with. `_stamp_library_style` read a slot the swatch did not write, so a wall
	## drawn straight after pressing one came out in the previous colour.
	_place_wall(Vector3(2, 0, 14), Vector3(8, 0, 14))
	var fresh := _plan.walls[1] as Dictionary
	expect.call(
		"and the next wall drawn is born in it (%s)" % [fresh.get("color")],
		is_equal_approx(float((fresh["color"] as Array)[0]), wanted_colour.r)
		and is_equal_approx(float((fresh["color"] as Array)[2]), wanted_colour.b)
	)
	var material_button := _probe_drawer_button("WOOD")
	expect.call("the material buttons are on the drawer", material_button != null)
	if material_button != null:
		material_button.pressed.emit()
		expect.call(
			"pressing a material paints the selected wall (%s)" % [wall.get("material")],
			str(wall.get("material", "")) == "wood"
		)
		_place_wall(Vector3(2, 0, 18), Vector3(8, 0, 18))
		expect.call(
			"and the next wall drawn is born in it",
			str((_plan.walls[2] as Dictionary).get("material", "")) == "wood"
		)
	## AND IT DOES NOT CLAIM TO HAVE PAINTED WHAT IT CANNOT REACH. A placement's
	## tint is an `#rrggbb` string off the kit swatches and a fitting's colour
	## belongs to its part; the library writes neither, and used to say "colour
	## set" over both.
	_set_tool(Tool.PIECE)
	_select_piece_type(str(_kit_ids()[0]))
	var placement := _place_piece_at(Vector3i(8, 0, 20))
	_selected_id = int(placement["id"])
	_refresh_panel()
	var tint_before := str(placement.get("color", ""))
	swatches[index].pressed.emit()
	expect.call(
		"a library swatch does not silently repaint a kit placement",
		str(placement.get("color", "")) == tint_before
	)
	expect.call(
		"and it says so rather than reporting success (\"%s\")" % _status,
		_status.contains("PIECE KIT")
	)
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("bollard_pair", Vector3i(10, 0, 40))
	var item := _plan.items[0] as Dictionary
	_selected_id = int(item["id"])
	_refresh_panel()
	swatches[index].pressed.emit()
	expect.call(
		"a library swatch writes no colour key into a fitting (%s)" % [item.keys()],
		not item.has("color") and not item.has("material")
	)
	_set_context("vessel")


## CAN PRESSING SAVE DESTROY SOMEBODY ELSE'S PLAN?
##
## It could, and it did in this container's own measurement: `_save_plan` opened
## `res://resources/data/structures/<name>.json` with `FileAccess.WRITE` and no
## existence check, so a builder typing a name that snake-cases onto a shipped
## fixture replaced it — silently, with the toast reading `SAVED /` exactly as it
## does for a new file, and with no undo (`_undo` restores the PLAN, never the
## file). `to_snake_case` collapses "Demo Workboat", "demo workboat",
## "DemoWorkboat" and "demo-workboat" onto one name, so the collision does not
## need the builder to type the fixture's own name.
##
## The property: PRESSING SAVE JSON CHANGES NO BYTE UNDER `STRUCTURES_DIR`. Not
## "the path string starts with user://" — the bytes, measured before and after,
## over every shipped document, with the save deliberately aimed at one of them.
func _probe_saving_cannot_touch_shipped_data(expect: Callable) -> void:
	var shipped := _shipped_plan_paths()
	expect.call("there are shipped documents to protect (%d)" % shipped.size(), shipped.size() >= 10)
	var before: Dictionary = {}
	for path_variant in shipped:
		before[str(path_variant)] = FileAccess.get_file_as_string(str(path_variant)).md5_text()

	_set_context("vessel")
	_place_wall(Vector3(2, 0, 10), Vector3(8, 0, 10))
	## Aim at a real fixture, by the display spelling a builder would type.
	var victim := str(shipped[0])
	var typed := victim.get_file().get_basename().replace("_", " ").capitalize()
	expect.call(
		"the name a builder types resolves onto the fixture's file name (%s -> %s)"
		% [typed, typed.to_snake_case()],
		typed.to_snake_case() == victim.get_file().get_basename()
	)
	_name_edit.text = typed
	var save_button := _probe_drawer_button("SAVE JSON")
	expect.call("SAVE JSON is a button in the drawer", save_button != null)
	if save_button == null:
		return
	save_button.pressed.emit()

	var damaged := PackedStringArray()
	for path in before.keys():
		if FileAccess.get_file_as_string(str(path)).md5_text() != str(before[path]):
			damaged.append(str(path).get_file())
	expect.call(
		"pressing SAVE JSON changes no shipped document (%s)"
		% ("all %d unchanged" % before.size() if damaged.is_empty() else ", ".join(damaged)),
		damaged.is_empty()
	)
	var written := _plan_save_path(typed)
	expect.call(
		"and the plan really was written, under the builder's own directory (%s)" % written,
		FileAccess.file_exists(written) and written.begins_with(SAVED_PLANS_DIR)
	)
	## Pressing it again over the builder's OWN file must still work — a builder
	## has to be able to re-save — but must say it is replacing rather than
	## creating, which is the only warning this control has.
	save_button.pressed.emit()
	expect.call(
		"saving over your own file says REPLACED, not SAVED (\"%s\")" % _status,
		_status.begins_with("REPLACED")
	)
	## GUARDED. This probe deliberately aims a save at a shipped fixture's name, so
	## its cleanup must never be able to delete one. It could: run this check
	## against the OLD save path and the tidy-up removed
	## `resources/data/structures/critic_barge.json` from the working tree — a
	## probe that repairs the tree it is measuring, in the direction of hiding the
	## damage. The check goes red either way; the deletion was pure collateral.
	_probe_remove_own_save(written)


## Delete a file this probe wrote, and ONLY if it is under the builder's own
## directory. Anything else is somebody's fixture and stays where it is.
func _probe_remove_own_save(path: String) -> void:
	if path.begins_with(SAVED_PLANS_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## SAVE A PLAN AUTHORED IN THE STUDIO, LOAD IT BACK, IS IT THE SAME PLAN?
##
## The existing save/load checks count entities and spot-check two keys, and the
## plan they round-trip has only ever contained walls, decks and stairs — the
## three collections that existed when it was written. It has never carried a
## fitting, a swept run, a painted surface or a kit placement all at once, which
## is three of the six collections and every field the two newest tools write.
##
## So this authors ONE plan through the tools that has something in all six, saves
## it with the drawer's SAVE JSON button, wipes, and loads it back with the
## drawer's LOAD SELECTED button — then compares, key by key, and names every
## difference. A save path that writes a file nothing can load and a load path
## that drops what the save wrote are the same defect from two ends, and neither
## is visible in an entity count.
##
## ── WHAT IS MEASURED WITH, AND WHY IT IS NOT `to_dict()` ────────────────────
##
## The first cut of this check compared `_plan.to_dict()` before against
## `_plan.to_dict()` after, and it MUTATION-PASSED: deleting `"edges"` from
## `StructurePlan.to_dict` left the check green (`PASS (187)`), because both sides
## of the comparison were taken through the very function that had stopped
## emitting the collection. It could not see a field the serialiser drops — which
## is exactly the failure a round-trip check exists to catch, and exactly the
## §4 shape: a check whose instrument is the thing under test.
##
## So the comparison reads the plan's OWN SIX MEMBER ARRAYS on both sides, and a
## third claim is added at the layer where a builder's work actually lives: the
## FILE ON DISK is parsed independently and every collection has to be in it with
## the right count. `to_dict` is now the subject, not the ruler.
func _probe_the_round_trip_is_the_same_plan(expect: Callable) -> void:
	_set_context("vessel")
	_place_deck(Vector3(1, 0, 8), Vector3(9, 0, 24))
	_place_wall(Vector3(2, 0, 10), Vector3(8, 0, 10))
	_place_stair(Vector3(3, 0, 14), Vector3(3, 0, 17))
	## Painted through the library, so `color` and `material` are not defaults.
	_selected_id = int((_plan.walls[0] as Dictionary)["id"])
	_refresh_panel()
	var swatches := _probe_swatch_buttons()
	if not swatches.is_empty():
		swatches[COLOR_LIBRARY.size() - 1].pressed.emit()
	var wood := _probe_drawer_button("WOOD")
	if wood != null:
		wood.pressed.emit()
	## A cut in the wall, a kit placement, and the fittings a registration counts.
	_set_tool(Tool.OPENING)
	((_plan.walls[0] as Dictionary)["openings"] as Array).append(
		{"type": "door", "offset": 1.0, "width": 1.6, "height": 2.2}
	)
	_set_tool(Tool.PIECE)
	_select_piece_type(str(_kit_ids()[0]))
	_place_piece_at(Vector3i(8, 0, 20))
	_set_tool(Tool.FITTING)
	_set_build_level(0.0)
	_probe_click_fitting("helm_console", Vector3i(10, 0, 40))
	for index in 4:
		_probe_click_fitting("bollard_pair", Vector3i(4 + index * 4, 0, 20))
	_probe_click_fitting("lantern_sidelight_port", Vector3i(3, 0, 30))
	## Turned after placing, so `yaw` is not the default either.
	_selected_id = int((_plan.items[0] as Dictionary)["id"])
	_refresh_panel()
	var turn := _probe_find_button(_inspector_box, "⟳  [R]")
	if turn != null:
		turn.pressed.emit()
	## `edges[]` has no tool in this studio — a sheer-following bulwark is the one
	## curve the kit refuses to quantise — so it is added through the plan. Named
	## rather than skipped: this collection is the one a builder can LOAD and
	## cannot DRAW, and the round trip has to carry it either way.
	_probe_add_bulwark()
	_rebake()
	_refresh_panel()

	var before := _probe_collections()
	var filled := PackedStringArray()
	for key in before.keys():
		if (before[key] as Array).is_empty():
			filled.append(str(key))
	expect.call(
		"the round-trip plan has something in all six collections (%s)"
		% ("all six" if filled.is_empty() else "empty: " + ", ".join(filled)),
		filled.is_empty()
	)

	_name_edit.text = "studio round trip probe"
	var save_button := _probe_drawer_button("SAVE JSON")
	var load_button := _probe_drawer_button("LOAD SELECTED")
	expect.call("SAVE JSON and LOAD SELECTED are both in the drawer",
		save_button != null and load_button != null)
	if save_button == null or load_button == null:
		return
	save_button.pressed.emit()
	var path := _plan_save_path(_name_edit.text)

	_set_context("vessel")
	expect.call("the plan really was wiped before loading", _plan.entity_count() == 0)
	_refresh_panel()
	var found := -1
	for index in _load_option.item_count:
		if str(_load_option.get_item_metadata(index)) == path:
			found = index
	expect.call(
		"the saved plan is offered in the LOAD list (%d entries)" % _load_option.item_count,
		found >= 0
	)
	if found >= 0:
		_load_option.select(found)
	load_button.pressed.emit()

	var after := _probe_collections()
	var differences := PackedStringArray()
	_probe_diff_plan("plan", before, after, differences)
	expect.call(
		"SAVE JSON then LOAD SELECTED gives back the SAME PLAN (%s)"
		% ("identical" if differences.is_empty()
			else "%d differences: %s" % [differences.size(), differences[0]]),
		differences.is_empty()
	)
	## AND THE WORK IS IN THE FILE. Read straight off disk, not through the plan
	## object — a serialiser that silently stops emitting a collection writes a
	## file that has lost a builder's bulwark, and BOTH readings above would still
	## agree with each other about it (they did; see the header).
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	expect.call("the saved file parses as JSON", raw is Dictionary)
	if raw is Dictionary:
		var doc := raw as Dictionary
		var missing := PackedStringArray()
		for key in before.keys():
			var wanted := (before[key] as Array).size()
			var got := (doc.get(key, []) as Array).size()
			if got != wanted:
				missing.append("%s: %d in the plan, %d in the file" % [key, wanted, got])
		expect.call(
			"and the FILE on disk carries every collection the plan held (%s)"
			% ("all six" if missing.is_empty() else ", ".join(missing)),
			missing.is_empty()
		)
	## Not a count: the same number of entities with a fitting's yaw reset, or a
	## wall's paint dropped, would pass a count and fail a builder. Stated as the
	## whole document above; these two are the fields the newest tools write, named
	## so a failure says WHICH one moved.
	expect.call(
		"the fitting keeps the yaw it was turned to (%s -> %s)"
		% [(before["items"] as Array)[0].get("yaw"), (after["items"] as Array)[0].get("yaw")],
		float((before["items"] as Array)[0].get("yaw", -1.0))
		== float((after["items"] as Array)[0].get("yaw", -2.0))
	)
	expect.call(
		"the wall keeps the colour it was painted (%s -> %s)"
		% [(before["walls"] as Array)[0].get("color"), (after["walls"] as Array)[0].get("color")],
		str((before["walls"] as Array)[0].get("color"))
		== str((after["walls"] as Array)[0].get("color"))
	)
	_probe_remove_own_save(path)
	_set_context("vessel")


## ── THE CONTROLS THAT THROW A PLAN AWAY ─────────────────────────────────────
##
## THE FIRST THING IN THIS FILE DRIVEN BY A REAL MOUSE EVENT AT A COORDINATE.
## Every other probe here reaches a control by emitting its `pressed` signal,
## which asserts the callback and nothing about the button: a control under
## another panel, outside the viewport, below a scroll fold or behind a
## `MOUSE_FILTER_IGNORE` parent emits `pressed` exactly as well as one a player
## can hit. `_probe_click` pushes an `InputEventMouseButton` through
## `Viewport.push_input`, so the viewport's own hit test decides which control
## receives it — the same code path a mouse takes.
##
## What it holds:
##
##  1. **Clicking the context you are already in destroys nothing.** It used to
##     empty the plan and the undo stack in one click, and the check twenty lines
##     up — "context switch clears the plan" — asserted that as correct
##     behaviour, which is REALITY §4c: green BECAUSE of the defect. That check
##     still stands, because `_set_context` IS the reset; what changed is that a
##     button no longer calls it blind.
##  2. **A switch that does throw the plan away leaves it on the undo stack**,
##     and UNDO — a button already on the top bar — brings it back.
##  3. **Undo brings it back ON ITS OWN HULL.** The plan document carries
##     `hull_id`, so this asserts the grid the studio builds on is the grid of
##     the hull the RESTORED PLAN names, not a number restated here.
func _probe_a_click_cannot_lose_the_plan(expect: Callable) -> void:
	## Containers sort deferred, so a control's rect is meaningless until a frame
	## has passed — a click at `_ready` time would land at the origin and this
	## whole section would test nothing (REALITY §7).
	for _frame in 2:
		await get_tree().process_frame

	_set_context("vessel")
	_set_tool(Tool.SELECT)
	## The stack is CAPPED AT 100 and this probe has already filled it, so a
	## saturated `_undo_stack` absorbs an extra push without changing size — the
	## first cut of the depth check below was blind for exactly that reason, and
	## a mutation that reddened only its neighbour is what found it (REALITY §4).
	_undo_stack.clear()
	_redo_stack.clear()
	_place_wall(Vector3(0, 0, 6), Vector3(6, 0, 6))
	_place_wall(Vector3(1, 0, 8), Vector3(1, 0, 12))
	_place_deck(Vector3(0, 0, 20), Vector3(6, 0, 24))
	var authored := _plan.entity_count()
	var authored_doc := JSON.stringify(_plan.to_dict())
	var authored_hull := _hull_id
	var undo_depth := _undo_stack.size()
	expect.call("three entities authored to click at", authored == 3)
	expect.call(
		"control: the undo stack is below its 100-step cap, so its depth can move (%d)"
		% undo_depth,
		undo_depth > 0 and undo_depth < 100
	)

	## ── The re-click. VESSEL, while already in the vessel context.
	var vessel_button := _context_buttons.get("vessel") as Button
	var building_button := _context_buttons.get("building") as Button
	expect.call(
		"both BUILD CONTEXT buttons are hittable (on screen, unobscured)",
		_probe_hittable(vessel_button) and _probe_hittable(building_button)
	)
	await _probe_click(vessel_button)
	expect.call(
		"clicking the context you are ALREADY in leaves the plan untouched (%d entities)"
		% _plan.entity_count(),
		JSON.stringify(_plan.to_dict()) == authored_doc
	)
	expect.call(
		"and leaves the undo stack untouched (%d steps)" % _undo_stack.size(),
		_undo_stack.size() == undo_depth
	)

	## ── The real switch. It MAY empty the plan; it may not lose it.
	await _probe_click(building_button)
	expect.call(
		"clicking the OTHER context does switch (control: the click landed)",
		_context == "building"
	)
	expect.call("and starts an empty plan", _plan.is_empty())
	var undo_button := _probe_button_with_text(_ui_root.get_node_or_null(^"TopBar"), "UNDO")
	expect.call("UNDO is on the top bar and hittable", _probe_hittable(undo_button))
	await _probe_click(undo_button)
	expect.call(
		"ONE click on UNDO brings the discarded plan back (%d of %d entities)"
		% [_plan.entity_count(), authored],
		JSON.stringify(_plan.to_dict()) == authored_doc
	)
	expect.call("and puts the studio back in the context it was built in", _context == "vessel")

	## ── The hull dropdown. The popup row is chosen through `index_pressed`,
	## which is the signal `OptionButton` itself connects the player's click on a
	## popup row to — but the dropdown BUTTON is opened with a real click first,
	## so the hit target is asserted too.
	expect.call("the hull dropdown is hittable", _probe_hittable(_hull_option))
	await _probe_click(_hull_option)
	expect.call("clicking it opens the hull list", _hull_option.get_popup().visible)
	_hull_option.get_popup().hide()
	var other := -1
	for index in _hull_option.item_count:
		if str(_hull_option.get_item_text(index)) != authored_hull:
			other = index
			break
	expect.call("the list offers a hull other than the one we are on", other >= 0)
	if other < 0:
		return
	var other_hull := str(_hull_option.get_item_text(other))
	_hull_option.get_popup().index_pressed.emit(other)
	expect.call("choosing another hull moves the studio to it", _hull_id == other_hull)
	expect.call("and starts an empty plan for it", _plan.is_empty())
	await _probe_click(undo_button)
	expect.call(
		"ONE click on UNDO brings the plan back after a hull change (%d of %d)"
		% [_plan.entity_count(), authored],
		JSON.stringify(_plan.to_dict()) == authored_doc
	)
	## THE PROPERTY, not the number: whatever hull the restored plan names, that
	## is the hull the studio is drawing and the grid it is building on. Restating
	## "20 x 56" here would pass on a studio that had adopted the wrong hull and a
	## plan that had adopted it too.
	var want := HullRegistry.make_grid(_plan.hull_id)
	expect.call(
		"the studio follows the restored plan's own hull (%s, plan says %s)"
		% [_hull_id, _plan.hull_id],
		_hull_id == _plan.hull_id
	)
	expect.call(
		"and builds on that hull's grid (%d x %d, %s is %d x %d)"
		% [_deck_grid.width, _deck_grid.length, _plan.hull_id, want.width, want.length],
		_deck_grid.width == want.width and _deck_grid.length == want.length
	)
	_set_context("vessel")
	_undo_stack.clear()
	_redo_stack.clear()


## ── CAN A BUILDER REACH WHAT IS BELOW THE FOLD? ─────────────────────────────
##
## The drawer's scroll viewport is 948 px over 1565 px of content, so SAVE JSON
## starts 440 px and LOAD SELECTED 566 px past the bottom of it, and the vertical
## scrollbar `brand_theme.gd` styles for the whole branded UI is **0 px wide** —
## there is no grabber to drag and no visible hint that anything is down there.
##
## The drawer capture reached the bottom by ASSIGNING `scroll_vertical`, which
## proves a ScrollContainer can be moved by an assignment and says nothing about
## whether a player can move it. The open question was whether a wheel notch
## delivered over the drawer scrolls it or is swallowed by the camera zoom in
## `_handle_mouse_button` — and if it were swallowed, SAVE JSON would be
## unreachable by any means, which is a hard defect and not a signposting one.
##
## Measured: it scrolls, and the camera does not move while it does. This holds
## that. It is asserted through `Viewport.push_input` because setting
## `scroll_vertical` here would assert the same nothing the capture did.
##
## Two vacuity guards, because both failure modes are silent:
##   * if the content ever fits the viewport there is nothing below the fold and
##     "everything is reachable" is free, so the overflow is asserted first;
##   * the camera distance is read before and after, because a wheel that
##     reaches the camera INSTEAD is the exact defect this asks about.
func _probe_below_the_fold_is_reachable(expect: Callable) -> void:
	for _frame in 2:
		await get_tree().process_frame
	_set_tool(Tool.FITTING) ## the tallest state of the left palette
	_refresh_panel()
	for _frame in 2:
		await get_tree().process_frame

	for case in [
		{"scroll": _drawer_scroll, "what": "the drawer", "buttons": ["SAVE JSON", "LOAD SELECTED"]},
		{"scroll": _probe_first_scroll(_ui_root.get_node_or_null(^"ToolPalette")),
			"what": "the tool palette", "buttons": []},
	]:
		var scroll := case["scroll"] as ScrollContainer
		var what := str(case["what"])
		if scroll == null:
			expect.call("%s has a scroll container" % what, false)
			continue
		var content := scroll.get_child(0) as Control
		expect.call(
			"control: %s really does overflow (%.0f px of content in %.0f px)"
			% [what, content.size.y, scroll.size.y],
			content.size.y > scroll.size.y + 1.0
		)
		scroll.scroll_vertical = 0
		await get_tree().process_frame
		var at := scroll.get_global_rect().get_center()
		var camera_before := _cam_distance
		await _probe_wheel(at)
		expect.call(
			"one wheel notch over %s scrolls it (%d px)" % [what, scroll.scroll_vertical],
			scroll.scroll_vertical > 0
		)
		expect.call(
			"and the camera behind %s does not move with it (%.3f -> %.3f)"
			% [what, camera_before, _cam_distance],
			is_equal_approx(camera_before, _cam_distance)
		)
		var notches := 1
		while notches < 400:
			var was := scroll.scroll_vertical
			await _probe_wheel(at)
			notches += 1
			if scroll.scroll_vertical == was:
				break
		var travel := int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
		expect.call(
			"the wheel alone reaches the foot of %s in %d notches (%d of %d px)"
			% [what, notches, scroll.scroll_vertical, travel],
			scroll.scroll_vertical >= travel
		)
		var fold := scroll.get_global_rect().end.y
		for text_variant in (case["buttons"] as Array):
			var text := str(text_variant)
			var button := _probe_drawer_button(text)
			expect.call(
				"%s is fully on screen once the wheel has been used (%s)"
				% [text, "" if button == null else str(button.get_global_rect())],
				button != null and button.get_global_rect().end.y <= fold + 1.0
			)
	_set_tool(Tool.SELECT)


## One wheel-down notch at `at`, both halves, through the whole input stack.
func _probe_wheel(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = at
		event.global_position = at
		event.factor = 1.0
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _probe_first_scroll(root: Node) -> ScrollContainer:
	if root == null:
		return null
	if root is ScrollContainer:
		return root as ScrollContainer
	for child in root.get_children():
		var hit := _probe_first_scroll(child)
		if hit != null:
			return hit
	return null


## A control a player could get the pointer onto at all: in the tree, visible,
## not zero-sized, and wholly inside the viewport. It does NOT say the control is
## topmost — nothing here reads the z-order. What settles that is the click
## itself: if another panel covers this one, `_probe_click` lands on that panel
## and the assertion after it fails, which is why every use of this is paired
## with one (a mutation moving the click 400 px reddens four of them).
func _probe_hittable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return false
	if not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(rect):
		return false
	return true


## One left click, delivered where the control IS. `push_input` runs the whole
## stack — `Viewport`'s GUI hit test first, `_unhandled_input` after — so a
## control the viewport does not find never sees this.
func _probe_click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
	await get_tree().process_frame


func _probe_button_with_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var hit := _probe_button_with_text(child, text)
		if hit != null:
			return hit
	return null


## A `from_hull` bulwark on the studio's current hull, WITH the hull's numbers
## restated into the plan.
##
## Without the `hull` block this prints six copies of *"no hull numbers for
## `hull_28x10` — it is not in HullCatalog and the plan carries no `hull` block to
## loft it from"* and resolves to nothing: `hull_28x10` lives in `HullRegistry`,
## not in the JSON catalogue (CONVENTIONS §3a), which is exactly why
## `_write_tug_fixture` restates it and why `StructurePlan.hull` exists. An edge
## that cannot loft would still have served the drawer checks — they are about the
## DOCUMENT — and that is the trap: it would have been a fixture that looked like
## a bulwark and was not one.
func _probe_add_bulwark() -> void:
	_plan.hull = {
		"loa_m": 28.0, "beam_m": 10.0, "depth_m": 5.6, "draft_m": 2.8,
		"displacement_t": 256.0, "form": "fine_entry",
		"bow_taper_fraction": 0.17857142857142858, "station_count": 8,
	}
	_plan.add_hull_edge({
		"side": "loop", "follow_sheer": true, "height": 1.1, "plate_m": 0.1,
		"cap_w": 0.22, "cap_h": 0.06, "material": "painted",
		"plate_color": [0.11, 0.13, 0.16], "cap_color": [0.86, 0.87, 0.88], "solid": true,
	}, _hull_id)


## The plan's six collections, deep-copied, read off the OBJECT'S OWN MEMBERS.
## Deliberately not `to_dict()` — see the round-trip probe's header for the
## mutation that passed when this was measured through the serialiser.
func _probe_collections() -> Dictionary:
	return {
		"walls": _plan.walls.duplicate(true),
		"decks": _plan.decks.duplicate(true),
		"stairs": _plan.stairs.duplicate(true),
		"edges": _plan.edges.duplicate(true),
		"pieces": _plan.pieces.duplicate(true),
		"items": _plan.items.duplicate(true),
	}


## Every place two plan documents disagree, as a path a person can act on.
func _probe_diff_plan(path: String, a: Variant, b: Variant, out: PackedStringArray) -> void:
	if a is Dictionary and b is Dictionary:
		var keys: Dictionary = {}
		for key in (a as Dictionary).keys():
			keys[key] = true
		for key in (b as Dictionary).keys():
			keys[key] = true
		for key in keys.keys():
			if not (a as Dictionary).has(key):
				out.append("%s.%s appeared" % [path, key])
			elif not (b as Dictionary).has(key):
				out.append("%s.%s was LOST (%s)" % [path, key, (a as Dictionary)[key]])
			else:
				_probe_diff_plan("%s.%s" % [path, key],
					(a as Dictionary)[key], (b as Dictionary)[key], out)
	elif a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			out.append("%s: %d -> %d entries" % [path, (a as Array).size(), (b as Array).size()])
			return
		for index in (a as Array).size():
			_probe_diff_plan("%s[%d]" % [path, index], (a as Array)[index], (b as Array)[index], out)
	elif typeof(a) != typeof(b) or str(a) != str(b):
		out.append("%s: %s -> %s" % [path, a, b])


## One palette click plus one viewport click, at a named node. The camera is
## aimed the way a player aims it, so the cursor ray is the thing under test.
func _probe_click_fitting(part_id: String, node: Vector3i) -> void:
	if _fitting_buttons.has(part_id):
		(_fitting_buttons[part_id] as Button).pressed.emit()
	var aim := _plan_offset + _fitting_plan_point(node)
	_camera.position = aim + Vector3(0.0, 16.0, 16.0)
	_camera.look_at(aim, Vector3.UP)
	_on_left_press(_camera.unproject_position(aim))


## The controls themselves: palette, steppers, dropdowns, rotate, tints.
func _probe_piece_controls(expect: Callable) -> void:
	_set_context("vessel")
	var ids := PieceKit.ids()
	expect.call("the kit loads for the palette (%d pieces)" % ids.size(), ids.size() > 0)
	expect.call(
		"the kit loads clean (%s)" % ", ".join(PieceKit.load_errors()),
		PieceKit.load_errors().is_empty()
	)
	_set_tool(Tool.PIECE)
	expect.call("picking up the PIECE tool arms a piece", not _piece_id.is_empty())

	## Every piece in the palette can be picked, arrives at its declared defaults,
	## and its tint survives the Color -> #rrggbb conversion the swatches make. A
	## tint that drifts by one digit is a placement that no longer compares equal
	## to the fixture it was copied from, and nothing else would notice.
	var pickable := 0
	var defaulted := 0
	var exact_tint := 0
	for id_variant in ids:
		var id := str(id_variant)
		_select_piece_type(id)
		if _piece_id != id:
			continue
		pickable += 1
		var declared := PieceKit.params_of(id)
		var armed := _piece_params_for(id)
		var matches := true
		for key in declared.keys():
			if armed.get(str(key)) != (declared[key] as Dictionary)["default"]:
				matches = false
		if matches:
			defaulted += 1
		var declared_color := PieceKit.get_piece(id)["color"] as Color
		var hex := _kit_color_hex(id)
		if Color.html_is_valid(hex) and Color(hex) == declared_color:
			exact_tint += 1
	expect.call("every one of the %d palette pieces is pickable" % ids.size(), pickable == ids.size())
	expect.call("and each arrives at its own declared defaults", defaulted == ids.size())
	expect.call("every piece's tint round-trips Color <-> #rrggbb exactly", exact_tint == ids.size())

	## A stepper walks the DECLARED list by index, both ways, and stops at the
	## ends. Which piece and which parameter are read out of the data file — this
	## probe names neither, so widening a value set cannot invalidate it.
	var stepped := 0
	var refused_off_set := 0
	var clamped_at_ends := 0
	for id_variant in ids:
		var id := str(id_variant)
		_select_piece_type(id)
		for key in PieceKit.params_of(id).keys():
			var name := str(key)
			var spec := PieceKit.params_of(id)[key] as Dictionary
			if not bool(spec["numeric"]):
				continue
			var values := spec["values"] as Array
			## Walk to the bottom of the list, then one more: it must not move.
			for _i in values.size() + 2:
				_step_piece_param(name, -1)
			if _piece_params_for(id).get(name) == values[0]:
				clamped_at_ends += 1
			## One step up must land on the NEXT DECLARED VALUE, not value+1 — the
			## sets are not evenly spaced (span is 1, 2, 3, 4, 6, 8) and arithmetic
			## would ask the kit for a 5.
			if values.size() > 1 and _step_piece_param(name, 1) \
					and _piece_params_for(id).get(name) == values[1]:
				stepped += 1
			## And a value off the set is refused outright, never clamped.
			if not _set_piece_param(name, 99999):
				refused_off_set += 1
	expect.call("a stepper lands on the next DECLARED value (%d parameters)" % stepped, stepped > 0)
	expect.call("a stepper stops at the bottom of its list", clamped_at_ends > 0)
	expect.call("a value off the declared set is refused (%d)" % refused_off_set, refused_off_set > 0)

	## The rotate key walks the kit's four facings and comes back where it started.
	_select_piece_type(str(ids[0]))
	var seen: Dictionary = {}
	var start := _piece_facing
	for _turn in 4:
		_rotate_piece()
		seen[_piece_facing] = true
	expect.call("R reaches all four facings", seen.size() == PieceKit.FACINGS.size())
	expect.call("and four turns come back to where it started", _piece_facing == start)
	_rotate_piece(-1)
	expect.call("and it turns the other way too", _piece_facing != start)
	_rotate_piece(1)

	## Every tint a placement can be painted is a swatch, and every swatch is a
	## colour the kit will accept.
	var tints := _piece_tints()
	var valid := 0
	for tint_variant in tints:
		if Color.html_is_valid(str((tint_variant as Array)[1])):
			valid += 1
	expect.call("all %d piece tints are valid #rrggbb" % tints.size(), valid == tints.size())

	## The refusal a player can actually walk into: two legal values that make an
	## illegal piece. It has to stop them, and it has to leave the piece as it was.
	var glazed := _probe_piece_with_constraint()
	if glazed.is_empty():
		expect.call("a piece declares a cross-parameter constraint", false)
	else:
		_select_piece_type(str(glazed["id"]))
		var before: Dictionary = (_piece_params_for(str(glazed["id"])) as Dictionary).duplicate()
		var took := _set_piece_param(str(glazed["param"]), glazed["value"])
		expect.call(
			"a setting that violates \"%s\" is refused" % str(glazed["expr"]), not took
		)
		expect.call(
			"and the refused setting leaves the piece untouched",
			_piece_params_for(str(glazed["id"])) == before
		)


## The first piece in the kit that declares a constraint, and a value that breaks
## it — found by SEARCH, so this probe names no piece and no parameter.
func _probe_piece_with_constraint() -> Dictionary:
	for id_variant in PieceKit.ids():
		var id := str(id_variant)
		var piece := PieceKit.get_piece(id)
		var constraints := piece.get("constraints", []) as Array
		if constraints.is_empty():
			continue
		var declared := piece["params"] as Dictionary
		for key in declared.keys():
			var spec := declared[key] as Dictionary
			if not bool(spec.get("numeric", false)):
				continue
			for value in spec["values"] as Array:
				var probe := _piece_defaults(id)
				probe[str(key)] = value
				if (PieceKit.resolve_params(id, probe)["errors"] as PackedStringArray).size() > 0:
					return {
						"id": id, "param": str(key), "value": value,
						"expr": str((constraints[0] as Dictionary).get("expr", "")),
					}
	return {}


func _piece_defaults(piece_id: String) -> Dictionary:
	var out: Dictionary = {}
	var declared := PieceKit.params_of(piece_id)
	for key in declared.keys():
		out[str(key)] = (declared[key] as Dictionary)["default"]
	return out


## EVERY LEVEL THE FLEET USES IS REACHABLE FROM THE LEVEL CONTROL.
##
## The one check here that came from a bug rather than from a design: the level
## buttons stepped 1.00 m, so cell y = 5 — the shipped trawler's boat deck, at
## 2.50 m — could not be reached by clicking. The probe did not notice because it
## placed pieces by CELL. This drives the control the way a player does, `+` at a
## time, and asks whether the cursor's node y ever equals each level the fixtures
## actually build on.
func _probe_piece_levels(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.PIECE)
	var wanted: Dictionary = {}
	for path in ["probe_piece_trawler", "probe_piece_house", "probe_piece_tug"]:
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("%s/%s.json" % [STRUCTURES_DIR, path])
		)
		if not (raw is Dictionary):
			continue
		for placement_variant in (raw as Dictionary).get("pieces", []) as Array:
			wanted[StructurePlan.piece_cell(placement_variant as Dictionary).y] = true
	expect.call("the fleet's piece fixtures use %d distinct levels" % wanted.size(), wanted.size() > 1)
	## Walk the "+" button up from zero and collect the cell each press lands on.
	_set_build_level(0.0)
	var reached: Dictionary = {}
	for _press in 64:
		reached[roundi(_active_base / NODE_SNAP)] = true
		_set_build_level(_active_base + NODE_SNAP)
	var missing := PackedStringArray()
	for level in wanted.keys():
		if not reached.has(int(level)):
			missing.append("cell y=%d (%.2f m)" % [int(level), float(level) * NODE_SNAP])
	expect.call(
		"every one of them is reachable by pressing the level control (%d missing%s)"
		% [missing.size(), "" if missing.is_empty() else ": " + ", ".join(missing)],
		missing.is_empty()
	)
	## And the cursor agrees with the control: the node it reports is the level the
	## control is on, not a rounding of it.
	_set_build_level(2.5)
	var aim := _plan_offset + StructurePlan.piece_node_plan(Vector3i(8, 5, 24))
	_camera.position = aim + Vector3(0.0, 14.0, 14.0)
	_camera.look_at(aim, Vector3.UP)
	expect.call(
		"at level 2.50 m the cursor reads cell y = 5",
		_mouse_to_node(_camera.unproject_position(aim)).y == 5
	)
	_set_build_level(0.0)


## THE CURSOR. A grid node under the mouse, a ghost standing on it, and a click
## that puts the piece exactly where the ghost was.
func _probe_piece_mouse(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.PIECE)
	var ids := PieceKit.ids()
	_select_piece_type(str(ids[0]))
	_set_build_level(0.0)

	## Aim at a node the way a player does: point the camera at it and read the
	## cursor. Cell (8, 0, 24) is plan (4.0, 0, 12.0) on the 0.5 m grid.
	var want := Vector3i(8, 0, 24)
	var aim := _plan_offset + StructurePlan.piece_node_plan(want)
	_camera.position = aim + Vector3(0.0, 14.0, 14.0)
	_camera.look_at(aim, Vector3.UP)
	var screen := _camera.unproject_position(aim)
	var node := _mouse_to_node(screen)
	expect.call(
		"the cursor reads grid node (%d, %d, %d) where (%d, %d, %d) was aimed at"
		% [node.x, node.y, node.z, want.x, want.y, want.z],
		node == want
	)
	## Half a cell is the RESOLUTION of the snap, and the claim that separates it
	## from the 1 m draw snap: a cursor half a metre along must read the next node,
	## not the same one. At GRID_SNAP it would round to the same whole metre.
	var neighbour := _plan_offset + StructurePlan.piece_node_plan(want + Vector3i(1, 0, 0))
	expect.call(
		"and a node 0.5 m away reads as the NEXT node",
		_mouse_to_node(_camera.unproject_position(neighbour)) == want + Vector3i(1, 0, 0)
	)

	## The ghost, then the click. The ghost is the real bake of the placement the
	## click will commit, so the two cannot disagree — and this asserts they do not.
	_update_piece_ghost(node)
	expect.call("a ghost is drawn at the node", _piece_ghost != null)
	var ghost_placement := _piece_ghost_placement.duplicate(true)
	var ghost_bounds := _probe_node_bounds(_piece_ghost)
	expect.call("the ghost has a real extent", ghost_bounds.size.length() > 0.1)
	var placed := _place_piece_at(node)
	expect.call("the click places a piece", not placed.is_empty())
	if placed.is_empty():
		return
	var committed := placed.duplicate(true)
	var previewed := ghost_placement.duplicate(true)
	committed.erase("id")
	previewed.erase("id")
	expect.call(
		"THE PIECE COMMITTED IS THE PIECE THE GHOST DREW (%s vs %s)"
		% [JSON.stringify(previewed), JSON.stringify(committed)],
		committed == previewed
	)
	var id := int(placed["id"])
	expect.call("the placed piece is pickable (has bounds)", _entity_bounds.has(id))
	if _entity_bounds.has(id):
		expect.call(
			"and it lands inside the volume the ghost showed",
			ghost_bounds.grow(0.02).encloses((_entity_bounds[id] as AABB))
		)
	## The node is where the piece stands, not half a cell off it. Stated on the
	## PLACEMENT TRANSFORM rather than on a corner: `corner_45`'s plate is a chord
	## ACROSS the node and legitimately has no corner on it, so a corner test would
	## have been a claim about one piece rather than about the grid. Every resolved
	## item's origin is the node, for every piece, or the whole kit is half a cell
	## out — which is exactly what using a cell CENTRE would do.
	var expected_at := StructurePlan.piece_node_plan(node)
	var off_node := 0
	for item_variant in PieceKit.resolve_placement(placed, 1)["items"] as Array:
		if StructurePlan.vec3_of((item_variant as Dictionary).get("at")) != expected_at:
			off_node += 1
	expect.call("every plate of the placed piece is anchored on the node", off_node == 0)
	if _entity_bounds.has(id):
		expect.call(
			"and the node is inside the piece's own bound",
			(_entity_bounds[id] as AABB).grow(1e-4).has_point(expected_at + _plan_offset)
		)


func _probe_node_bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in _probe_geometry(node):
		var gi := child as GeometryInstance3D
		var box := gi.global_transform * gi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _probe_geometry(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_probe_geometry(child))
	return out


## Click a placed piece, read its parameters, change one, turn it, delete it.
func _probe_piece_selection(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.PIECE)
	var ids := PieceKit.ids()
	_select_piece_type(str(ids[0]))
	var placed := _place_piece_at(Vector3i(8, 0, 24))
	if placed.is_empty():
		expect.call("a piece places for the selection leg", false)
		return
	var id := int(placed["id"])
	var bounds := _entity_bounds[id] as AABB
	var centre := bounds.get_center()
	_camera.position = centre + Vector3(6.0, 6.0, 6.0)
	_camera.look_at(centre, Vector3.UP)
	_set_tool(Tool.SELECT)
	expect.call(
		"a cursor ray on the piece picks it",
		_pick_entity(_camera.unproject_position(centre)) == id
	)
	_selected_id = id
	_update_selection_visual()
	_refresh_panel()
	expect.call("selecting it wraps it", _selection_box.visible)
	expect.call("the inspector knows it is a piece", not _selected_piece().is_empty())
	expect.call(
		"the inspector built controls for it", _inspector_box.get_child_count() > 0
	)
	## THE BRIEF'S HARD LINE: no control anywhere in a piece's inspector may take
	## typed input. A SpinBox does, and the wall/deck/stair inspector is full of
	## them, so this is a claim about THIS inspector and it is worth making.
	expect.call(
		"and not one of them is a typed field",
		_probe_count_typed_fields(_inspector_box) == 0
	)
	## ...and the same claim about the palette's own parameter controls.
	_set_tool(Tool.PIECE)
	_refresh_panel()
	expect.call(
		"nor is any control in the kit palette",
		_probe_count_typed_fields(_piece_section) == 0
	)
	## The negative control for that claim: the wall inspector, which SHOULD have
	## typed fields. If `_probe_count_typed_fields` were blind, this would be 0 too.
	_set_tool(Tool.SELECT)
	var wall := _plan.add_wall(Vector3(0, 0, 4), "x", 4.0)
	_rebake()
	_selected_id = int(wall["id"])
	_refresh_panel()
	expect.call(
		"CONTROL: the wall inspector DOES have typed fields (%d), so the count is not blind"
		% _probe_count_typed_fields(_inspector_box),
		_probe_count_typed_fields(_inspector_box) > 0
	)
	_plan.remove_entity(int(wall["id"]))

	_selected_id = id
	_refresh_panel()
	var before_facing := int(placed.get("facing", 0))
	expect.call("R turns the SELECTED piece", _rotate_selected_piece())
	expect.call(
		"and the placement's facing moved", int(placed.get("facing", -1)) != before_facing
	)
	var param := _probe_first_numeric_param(str(placed["piece"]))
	if param.is_empty():
		expect.call("the piece declares a numeric parameter to edit", false)
	else:
		var was: Variant = (placed["params"] as Dictionary).get(param)
		var moved := _step_selected_piece_param(param, 1) or _step_selected_piece_param(param, -1)
		expect.call("a stepper edits the SELECTED piece's \"%s\"" % param, moved)
		expect.call(
			"and the placement carries the new value",
			(placed["params"] as Dictionary).get(param) != was
		)
	var before_count := _plan.pieces.size()
	_delete_selected()
	expect.call("DEL removes the placement", _plan.pieces.size() == before_count - 1)
	_undo()
	expect.call("and undo brings it back", _plan.pieces.size() == before_count)


## Controls a value can be TYPED into, anywhere under a node. `SpinBox` contains
## its own `LineEdit`, so both are counted and the search is recursive.
func _probe_count_typed_fields(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	if root is SpinBox or root is LineEdit or root is TextEdit:
		count += 1
	for child in root.get_children():
		count += _probe_count_typed_fields(child)
	return count


func _probe_first_numeric_param(piece_id: String) -> String:
	var declared := PieceKit.params_of(piece_id)
	for key in declared.keys():
		if bool((declared[key] as Dictionary).get("numeric", false)):
			return str(key)
	return ""


## Place -> save -> load -> bake. Not "the plan has the same number of pieces":
## the same PLATE CORNERS, exactly, and undo/redo through the same path.
func _probe_piece_persistence(expect: Callable) -> void:
	_set_context("vessel")
	_set_tool(Tool.PIECE)
	var ids := PieceKit.ids()
	var placed := 0
	var cell := Vector3i(6, 0, 20)
	for id_variant in ids:
		_select_piece_type(str(id_variant))
		_rotate_piece()
		if not _place_piece_at(cell).is_empty():
			placed += 1
		cell += Vector3i(0, 0, 8)
	expect.call("one of every kit piece places (%d)" % placed, placed == ids.size())

	var before := _probe_plate_corners(_plan)
	expect.call("they resolve to %d plate corners" % before.size(), before.size() > 0)

	var undo_target := _plan.pieces.size()
	_undo()
	_undo()
	expect.call("undo removes placements", _plan.pieces.size() == undo_target - 2)
	_redo()
	_redo()
	expect.call("redo restores them", _plan.pieces.size() == undo_target)
	expect.call(
		"and the geometry is the same after undo/redo", _probe_plate_corners(_plan) == before
	)

	_save_plan("studio_piece_probe_tmp")
	var path := _plan_save_path("studio_piece_probe_tmp")
	_set_context("vessel")
	expect.call("context switch clears the placements", _plan.pieces.is_empty())
	_load_plan(path)
	expect.call("save/load restores all %d placements" % undo_target, _plan.pieces.size() == undo_target)
	var after := _probe_plate_corners(_plan)
	expect.call(
		"AND EVERY PLATE CORNER IS BIT-IDENTICAL after save/load (%d vs %d corners)"
		% [before.size(), after.size()],
		after == before
	)
	## Byte stability through the studio's own writer, not just through the plan.
	var reserialised := JSON.stringify(_plan.to_dict(), "\t")
	var on_disk := FileAccess.get_file_as_string(path)
	expect.call("what the studio wrote is what it would write again", reserialised == on_disk)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## ── Can the TOOL make two entities with one id? ─────────────────────────────
##
## `probe_piece_tug.json` shipped with an `edges[]` entry and a piece placement
## both numbered 34, so `entity_by_id(34)` returned the edge for both and the
## placement was unaddressable. `plan_entity_id_test` catches that in the
## FIXTURES; this asks the question one layer up, where it matters more — can a
## player produce it with a mouse?
##
## The interesting move is not "place things and count". It is DELETE followed by
## a round trip: `StructurePlan.from_dict` re-anchors `_next_id` to the highest id
## it can see, and every undo, redo, save/load and context switch goes through it.
## So the allocator is reset by the editor constantly, against a plan whose
## highest id may have just been removed — which is exactly the shape that hands
## out a number twice if the anchoring is off by one.
##
## The claim is a PROPERTY, not a count: after each of these moves, no two
## entities anywhere in the plan share an id. The walk is guarded against a
## seventh collection being added and silently not walked (`entity_count`).
func _probe_entity_ids(expect: Callable) -> void:
	## Four placements through the real controls, then the other three primitives.
	_probe_build_through_tool(_tug_placements().slice(0, 4))
	_place_wall(Vector3(0, 0, 6), Vector3(6, 0, 6))
	_place_deck(Vector3(0, 0, 20), Vector3(6, 0, 24))
	_place_stair(Vector3(1, 0, 24), Vector3(1, 0, 27))
	var seeded := _plan.entity_count()
	## Guard against the vacuous pass: everything below is trivially true of an
	## empty plan, and an empty plan is what a refused click leaves behind.
	expect.call(
		"ids: the sequence built a plan to check (%d entities, 4 kinds)" % seeded,
		seeded == 7 and _plan.pieces.size() == 4
	)
	var collisions := PackedStringArray()
	var note := func(step: String) -> void:
		var found := _probe_duplicate_ids()
		if not found.is_empty() and collisions.size() < 4:
			collisions.append("%s: %s" % [step, found[0]])
	note.call("after building")

	## Delete the HIGHEST id, which is the one `from_dict` anchors on, then take
	## every round trip the editor offers.
	var highest := 0
	for id_variant in _probe_all_ids():
		highest = maxi(highest, int(id_variant))
	_selected_id = highest
	_delete_selected()
	note.call("after deleting the highest id")
	expect.call("ids: deleting the highest id removed one entity",
		_plan.entity_count() == seeded - 1)
	_undo()
	note.call("after undo")
	_redo()
	note.call("after redo")
	_place_wall(Vector3(0, 0, 9), Vector3(6, 0, 9))
	var reissued := int((_plan.walls[_plan.walls.size() - 1] as Dictionary).get("id", -1))
	note.call("after placing again on the redone plan")
	_save_plan("studio_id_probe_tmp")
	var path := _plan_save_path("studio_id_probe_tmp")
	_load_plan(path)
	note.call("after save/load")
	_place_deck(Vector3(0, 0, 30), Vector3(4, 0, 34))
	note.call("after placing on the reloaded plan")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	expect.call(
		"ids: no tool action ever gave two entities the same id (%d collisions%s)"
		% [collisions.size(), "" if collisions.is_empty() else " — " + collisions[0]],
		collisions.is_empty()
	)
	## COVERAGE, not product behaviour. `from_dict` anchors on the highest id it
	## can SEE, so the wall placed after the delete takes the number the deleted
	## entity had. That is the one case where an off-by-one in the anchoring hands
	## a live id out twice, and this states that the sequence above really walked
	## it — a run where it did not would leave the check above blind (REALITY §8).
	## Ids are therefore unique within a document but NOT permanent across a
	## delete: an editor holding "#7" over a reload can be holding a new entity.
	expect.call(
		"ids: the delete freed #%d and the next placement took it back, so the reset path was covered"
		% highest,
		reissued == highest
	)
	## And the last leg placed onto the RELOADED plan rather than stopping at the
	## save, so `note` covered the load path with a live plan under it.
	expect.call("ids: the reloaded plan was still buildable on (%d entities)"
		% _plan.entity_count(), _plan.entity_count() == seeded + 1)


## Every entity id in the plan, in walk order, with the walk held to
## `entity_count` so a collection added later cannot be silently skipped.
func _probe_all_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for collection in [_plan.walls, _plan.decks, _plan.stairs, _plan.edges, _plan.items, _plan.pieces]:
		for entity in (collection as Array):
			out.append(int((entity as Dictionary).get("id", 0)))
	if out.size() != _plan.entity_count():
		push_error(
			"studio_probe: walked %d ids but the plan holds %d entities — a collection is not being walked"
			% [out.size(), _plan.entity_count()]
		)
	return out


## Ids used by more than one entity, as ["34 x2", …]. Empty is the invariant.
func _probe_duplicate_ids() -> PackedStringArray:
	var counts: Dictionary = {}
	for id in _probe_all_ids():
		counts[id] = int(counts.get(id, 0)) + 1
	var out := PackedStringArray()
	for id in counts.keys():
		if int(counts[id]) > 1:
			out.append("%d x%d" % [int(id), int(counts[id])])
	out.sort()
	return out


## Every plate corner a plan's placements resolve to, in plan metres. Through
## `PieceKit` — the path a capture rig and a spawned vessel take.
func _probe_plate_corners(plan: StructurePlan) -> PackedVector3Array:
	var out := PackedVector3Array()
	for placement_variant in plan.pieces:
		var placement := placement_variant as Dictionary
		var resolved := PieceKit.resolve_placement(placement, 1)
		for step in (resolved["items"] as Array).size():
			out.append_array(PieceKit.placed_corners(placement, step))
	return out


## ── Rebuilding a shipped fixture THROUGH THE TOOL ───────────────────────────
##
## The claim: every placement in a piece-built fixture is reachable by a player
## with a mouse — palette button, rotate key, steppers, tint swatch, click. The
## result is compared placement for placement against the file on disk, and
## anything unreachable is NAMED rather than quietly hand-written.
func _probe_piece_fixture(expect: Callable, path: String, label: String) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		expect.call("%s fixture loads (%s)" % [label, path], false)
		return
	var wanted := (raw as Dictionary).get("pieces", []) as Array
	expect.call("%s fixture carries placements (%d)" % [label, wanted.size()], wanted.size() > 0)
	if wanted.is_empty():
		return
	var report := _probe_build_through_tool(wanted)
	var built := report["built"] as Array
	var unreachable := report["unreachable"] as PackedStringArray
	expect.call(
		"%s: all %d placements are reachable through the tool (%d unreachable%s)"
		% [
			label, wanted.size(), unreachable.size(),
			"" if unreachable.is_empty() else ": " + unreachable[0],
		],
		unreachable.is_empty()
	)
	var mismatched := PackedStringArray()
	for index in mini(built.size(), wanted.size()):
		var want := _probe_placement_signature(wanted[index] as Dictionary)
		var got := _probe_placement_signature(built[index] as Dictionary)
		if want != got:
			if mismatched.size() < 3:
				mismatched.append("#%d want %s got %s" % [index, JSON.stringify(want), JSON.stringify(got)])
	expect.call(
		"%s: the tool reproduces the fixture placement for placement (%d differ%s)"
		% [
			label, mismatched.size(),
			"" if mismatched.is_empty() else " — " + mismatched[0],
		],
		mismatched.is_empty() and built.size() == wanted.size()
	)
	## Geometry, not just bookkeeping: the plan the tool built and the file on disk
	## must resolve to the SAME plate corners, exactly.
	var from_tool := _probe_plate_corners(_plan)
	var from_file := _probe_plate_corners(StructurePlan.from_dict(raw as Dictionary))
	expect.call(
		"%s: and to the same %d plate corners, to the bit" % [label, from_file.size()],
		from_tool == from_file and from_file.size() > 0
	)


## What two placements are compared on.
##
## Not the raw dictionary: a fixture writes only the parameters that DIFFER from
## the piece's defaults, and the tool writes every declared one, so
## `{"span": 1, "height": 5, "rake": 2}` and the same plus `"opening": "none"`
## are the same placement written two ways. Both sides are put through
## `PieceKit.resolve_params`, which fills the defaults in the kit's own words, so
## what is compared is the SETTING — piece, node, facing, tint and the full
## resolved parameter bag. The id and the author's note are dropped: the plan
## hands out the first and the tool has no control for the second.
func _probe_placement_signature(placement: Dictionary) -> Dictionary:
	var out := StructurePlan.normalize_piece(placement).duplicate(true)
	out.erase("id")
	out.erase("_is")
	var resolved := PieceKit.resolve_params(
		str(out.get("piece", "")), out.get("params", {}) as Dictionary
	)
	if (resolved["errors"] as PackedStringArray).is_empty():
		out["params"] = resolved["params"]
	return out


## Drives palette -> rotate -> steppers/dropdowns -> tint -> click for each
## wanted placement, on a fresh plan. Returns {"built", "unreachable"}.
func _probe_build_through_tool(wanted: Array) -> Dictionary:
	_set_context("vessel")
	_set_tool(Tool.PIECE)
	var unreachable := PackedStringArray()
	for entry_variant in wanted:
		var want := StructurePlan.normalize_piece(entry_variant as Dictionary)
		var piece_id := str(want["piece"])
		var where := "%s at %s" % [piece_id, str(want["cell"])]
		_select_piece_type(piece_id)
		if _piece_id != piece_id:
			unreachable.append("%s: not on the palette" % where)
			continue
		var turns := 0
		while _piece_facing != int(want["facing"]) and turns < PieceKit.FACINGS.size():
			_rotate_piece()
			turns += 1
		if _piece_facing != int(want["facing"]):
			unreachable.append("%s: facing %d not reachable" % [where, int(want["facing"])])
			continue
		## EVERY DECLARED PARAMETER, not just the ones the fixture wrote down. A
		## fixture omits what is at its default; the controls do not reset
		## themselves between placements, so a player who has just put a door in one
		## panel has to put the dropdown back to "none" for the next one. Reaching
		## only the written keys silently inherited that door — which is what this
		## check caught the first time it ran.
		var params := PieceKit.resolve_params(
			piece_id, want["params"] as Dictionary
		)["params"] as Dictionary
		## Two passes over them. One is not enough and that is a property of the
		## KIT, not a workaround: a cross-parameter constraint can make a setting
		## illegal until its partner has moved (a glazed panel's coaming cannot grow
		## until its glass band has shrunk). A player hits the same wall and does
		## the same thing — sets the other one first.
		var stuck := PackedStringArray()
		for _pass in 2:
			stuck = PackedStringArray()
			for key in params.keys():
				if not _probe_reach_param(str(key), params[key]):
					stuck.append(str(key))
			if stuck.is_empty():
				break
		if stuck.size() > 0:
			unreachable.append("%s: cannot set %s" % [where, ", ".join(stuck)])
			continue
		if want.has("color"):
			var hex := str(want["color"])
			if not _probe_tint_offered(hex):
				unreachable.append("%s: tint %s is not a swatch" % [where, hex])
				continue
			_set_piece_color(hex)
		var cell := StructurePlan.piece_cell(want)
		if _place_piece_at(cell).is_empty():
			unreachable.append("%s: the click was refused" % where)
	return {"built": _plan.pieces, "unreachable": unreachable}


## Reaches a parameter value the way the controls do: a dropdown pick for a
## choice, and for a numeric one a WALK ALONG THE DECLARED LIST, one step at a
## time. Never a direct write — a direct write would prove nothing about whether
## the stepper can get there.
func _probe_reach_param(name: String, target: Variant) -> bool:
	var declared := PieceKit.params_of(_piece_id)
	if not declared.has(name):
		return false
	var spec := declared[name] as Dictionary
	if not bool(spec.get("numeric", false)):
		return _set_piece_param(name, str(target))
	var values := spec["values"] as Array
	var want_index := values.find(int(target))
	if want_index < 0:
		return false
	for _step in values.size() + 1:
		var at := values.find(_piece_params_for(_piece_id).get(name))
		if at == want_index:
			return true
		if not _step_piece_param(name, 1 if want_index > at else -1):
			return false
	return values.find(_piece_params_for(_piece_id).get(name)) == want_index


func _probe_tint_offered(hex: String) -> bool:
	for tint_variant in _piece_tints():
		if str((tint_variant as Array)[1]) == hex:
			return true
	return false


## ── The tug wheelhouse: something the kit has never made ────────────────────
##
## A harbour tug's pilot house — a low plated casing with a raked front, a tall
## all-round-glazed wheelhouse standing on it with a chamfered corner at each
## turn, a SLOPED VISOR over the windscreen (`roof_slope`, which no vessel in
## this repo used) and a short exhaust casing aft.
##
## The recipe is TEST DATA and lives in the probe, not in the tool: the tool
## above contains no piece name and no parameter value. It is stated as the
## placements a player performs, and `_probe_piece_tug_recipe` requires that
## replaying it through the controls reproduces the shipped fixture exactly.
##
## RAKES ARE IN EIGHTH-CELLS (0.125 m a step). The kit's rake unit was widened
## from quarter-cells to eighth-cells WHILE this tool was being written, and the
## palette and the steppers needed no change for it — they read the sets out of
## the data file. These numbers did: they are the doubled values, so the casing
## front still stands 0.75 m out over its 2.0 m and the windscreen 1.0 m over its
## 2.5 m, which is what the shape was designed at.
const TUG_RECIPE: Array = [
	## Casing ring: x 5..15, z 18..32 cells, 5 cells tall, raked front. It was 4
	## cells (2.00 m) until `wall_panel` learned what a door costs: a 2.00 m panel
	## cannot carry one. The kit's door is 2.05 m of clear head above the panel's
	## foot — 1.80 m of player, the 0.155 m walking surface of the thickest sole
	## the kit can lay at that node, and the collider hang — so it needs a 2.13 m
	## plate and the constraint refuses anything shorter. The casing was also the
	## fixture with 0.06 m of standing headroom inside it; at 5 cells that is
	## 0.56 m.
	["corner_45", 5, 0, 18, 0, {"span": 1, "height": 5, "rake_a": 6, "rake_b": 0}, "#e3e0d4"],
	["wall_panel", 6, 0, 18, 0, {"span": 8, "height": 5, "rake": 6}, "#e3e0d4"],
	["corner_45", 15, 0, 18, 270, {"span": 1, "height": 5, "rake_a": 0, "rake_b": 6}, "#e3e0d4"],
	["wall_panel", 15, 0, 19, 270, {"span": 8, "height": 5, "rake": 0, "opening": "window"}, "#e3e0d4"],
	["wall_panel", 15, 0, 27, 270, {"span": 4, "height": 5, "rake": 0, "opening": "window"}, "#e3e0d4"],
	["corner_45", 15, 0, 32, 180, {"span": 1, "height": 5, "rake_a": 0, "rake_b": 0}, "#e3e0d4"],
	["wall_panel", 14, 0, 32, 180, {"span": 3, "height": 5, "rake": 0, "opening": "scuttle"}, "#e3e0d4"],
	## Three cells, not two: the kit's door is 1.20 m of clear opening (the player
	## capsule is 0.70 m across) and `wall_panel`'s constraint refuses one on a
	## panel under three cells. The aft face is 8 cells, so the scuttle beside it
	## gives one up: 3 + 3 + 2.
	["wall_panel", 11, 0, 32, 180, {"span": 3, "height": 5, "rake": 0, "opening": "door"}, "#e3e0d4"],
	["wall_panel", 8, 0, 32, 180, {"span": 2, "height": 5, "rake": 0, "opening": "scuttle"}, "#e3e0d4"],
	["corner_45", 5, 0, 32, 90, {"span": 1, "height": 5, "rake_a": 0, "rake_b": 0}, "#e3e0d4"],
	["wall_panel", 5, 0, 31, 90, {"span": 8, "height": 5, "rake": 0, "opening": "window"}, "#e3e0d4"],
	["wall_panel", 5, 0, 23, 90, {"span": 4, "height": 5, "rake": 0, "opening": "window"}, "#e3e0d4"],
	## Casing roof, one cell proud all round — the eave the kit's note calls for.
	["deck_tile", 4, 5, 17, 0, {"span": 12, "depth": 16, "gauge": "deck"}, "#4d5257"],
	["trim_band", 4, 5, 17, 0, {"span": 12, "profile": "eave", "offset": 0}, "#e3e0d4"],
	["trim_band", 16, 5, 17, 270, {"span": 16, "profile": "eave", "offset": 0}, "#e3e0d4"],
	["trim_band", 16, 5, 33, 180, {"span": 12, "profile": "eave", "offset": 0}, "#e3e0d4"],
	["trim_band", 4, 5, 33, 90, {"span": 16, "profile": "eave", "offset": 0}, "#e3e0d4"],
	## Wheelhouse: x 7..13, z 20..28, glazed on three sides, door aft.
	["corner_45", 7, 5, 20, 0, {"span": 1, "height": 5, "rake_a": 8, "rake_b": -2}, "#e3e0d4"],
	["wall_glazed", 8, 5, 20, 0, {"span": 4, "height": 5, "rake": 8, "sill": 2, "band": 2, "lights": 3}, "#e3e0d4"],
	["corner_45", 13, 5, 20, 270, {"span": 1, "height": 5, "rake_a": -2, "rake_b": 8}, "#e3e0d4"],
	["wall_glazed", 13, 5, 21, 270, {"span": 6, "height": 5, "rake": -2, "sill": 2, "band": 2, "lights": 4}, "#e3e0d4"],
	["corner_45", 13, 5, 28, 180, {"span": 1, "height": 5, "rake_a": 2, "rake_b": -2}, "#e3e0d4"],
	["wall_panel", 12, 5, 28, 180, {"span": 4, "height": 5, "rake": 2, "opening": "door"}, "#e3e0d4"],
	["corner_45", 7, 5, 28, 90, {"span": 1, "height": 5, "rake_a": -2, "rake_b": 2}, "#e3e0d4"],
	["wall_glazed", 7, 5, 27, 90, {"span": 6, "height": 5, "rake": -2, "sill": 2, "band": 2, "lights": 4}, "#e3e0d4"],
	## Wheelhouse roof and the visor over the windscreen.
	["deck_tile", 6, 10, 19, 0, {"span": 8, "depth": 8, "gauge": "deck"}, "#858a8f"],
	["deck_tile", 6, 10, 27, 0, {"span": 8, "depth": 2, "gauge": "deck"}, "#858a8f"],
	["roof_slope", 6, 9, 17, 0, {"span": 8, "depth": 2, "rise": 1, "gauge": "light"}, "#4d5257"],
	## Exhaust casing aft on the casing roof.
	["wall_panel", 9, 5, 30, 0, {"span": 2, "height": 6, "rake": 0}, "#9e5c1c"],
	["wall_panel", 11, 5, 30, 270, {"span": 3, "height": 6, "rake": 0}, "#9e5c1c"],
	["wall_panel", 11, 5, 33, 180, {"span": 2, "height": 6, "rake": 0}, "#9e5c1c"],
	["wall_panel", 9, 5, 33, 90, {"span": 3, "height": 6, "rake": 0}, "#9e5c1c"],
	["deck_tile", 9, 11, 30, 0, {"span": 2, "depth": 3, "gauge": "heavy"}, "#1c1c1f"],
	## A HEAVY sole aft in the casing, under the door. It is the thickest floor
	## the kit can lay — 0.30 m of tile, centred on its node, so you walk on
	## 0.150 m of it — and it is here so the fixture's doorway is measured over
	## the worst floor a player can put under it rather than over the hull's own
	## plating. `piece_interior_test` reads the floor it makes and the head over
	## it from the physics world.
	##
	## That rationale lived in an `_is` note ON the placement inside the fixture
	## until the file was regenerated, and it is stated here instead because the
	## writer cannot carry one: `to_dict` does not emit `_is` for a placement and
	## the tool has no control that would type it. A note added to the JSON by hand
	## survives exactly until the next `--studio-write-fixtures`, which is the same
	## hand-edit that gave two entities the same id.
	["deck_tile", 6, 0, 20, 0, {"span": 8, "depth": 12, "gauge": "heavy"}, "#4d5257"],
]


func _tug_placements() -> Array:
	var out: Array = []
	for entry_variant in TUG_RECIPE:
		var entry := entry_variant as Array
		out.append({
			"piece": str(entry[0]),
			"cell": [int(entry[1]), int(entry[2]), int(entry[3])],
			"facing": int(entry[4]),
			"params": entry[5],
			"color": str(entry[6]),
		})
	return out


## The recipe, driven through the controls, must be what the shipped tug fixture
## contains. This is what makes "built through the tool" a checked claim rather
## than a sentence in a report: change one step of the recipe and it goes red.
func _probe_piece_tug_recipe(expect: Callable) -> void:
	var report := _probe_build_through_tool(_tug_placements())
	var unreachable := report["unreachable"] as PackedStringArray
	expect.call(
		"tug recipe: every step is reachable through the tool (%d stuck%s)"
		% [unreachable.size(), "" if unreachable.is_empty() else ": " + unreachable[0]],
		unreachable.is_empty()
	)
	var built := _plan.pieces.duplicate(true)
	var path := "%s/probe_piece_tug.json" % STRUCTURES_DIR
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	expect.call("the tug fixture is on disk", raw is Dictionary)
	if not (raw is Dictionary):
		return
	var shipped := (raw as Dictionary).get("pieces", []) as Array
	var differ := PackedStringArray()
	for index in maxi(built.size(), shipped.size()):
		var want: Dictionary = _probe_placement_signature(shipped[index] as Dictionary) if index < shipped.size() else {}
		var got: Dictionary = _probe_placement_signature(built[index] as Dictionary) if index < built.size() else {}
		if want != got and differ.size() < 3:
			differ.append("#%d want %s got %s" % [index, JSON.stringify(want), JSON.stringify(got)])
	expect.call(
		"tug: the recipe driven through the tool IS the shipped fixture (%d differ%s)"
		% [differ.size(), "" if differ.is_empty() else " — " + differ[0]],
		differ.is_empty() and built.size() == shipped.size()
	)


## One-shot writer, off a flag, never in the gate's run. The fixture in the repo
## is the output of the tool, not of a text editor.
func _write_tug_fixture() -> void:
	_probe_build_through_tool(_tug_placements())
	_plan.hull = {
		"_note": "hull_28x10 as FishingTrawlerSmall builds it, restated so the capture rig can hold the derived stations against the hull the game spawns.",
		"loa_m": 28.0, "beam_m": 10.0, "depth_m": 5.6, "draft_m": 2.8,
		"displacement_t": 256.0, "form": "fine_entry",
		"bow_taper_fraction": 0.17857142857142858, "station_count": 8,
	}
	_plan.palette = {"wall": [0.85, 0.86, 0.88], "deck": [0.33, 0.31, 0.29]}
	_plan.add_hull_edge({
		"_is": "bulwark, both sides and the transom, capped — the deck edge of the vessel. NOT piece-authored: a sheer-following bulwark is a swept curve and the kit refuses to quantise it, which is a stated boundary rather than a gap.",
		"side": "loop", "follow_sheer": true, "height": 1.1, "plate_m": 0.1,
		"cap_w": 0.22, "cap_h": 0.06, "material": "painted",
		"plate_color": [0.11, 0.13, 0.16], "cap_color": [0.86, 0.87, 0.88], "solid": true,
	}, "hull_28x10")
	## Written straight to `STRUCTURES_DIR`, NOT through `_save_plan`. This is the
	## maintainer's fixture writer behind `--studio-write-fixtures`, and the
	## fixture is shipped game data; `_save_plan` is the BUILDER'S path and now
	## goes to `SAVED_PLANS_DIR` for the reasons that constant gives. Routing this
	## through the builder's path would have written the fixture to `user://` and
	## then re-stamped the stale shipped copy with a note.
	##
	## The `_note` is added here because `StructurePlan.to_dict` does not carry one
	## — it never has, for any fixture — so a plan that is loaded and re-saved
	## loses it. Stated rather than quietly worked around.
	var path := "%s/probe_piece_tug.json" % STRUCTURES_DIR
	var doc := _plan.to_dict()
	doc["_note"] = TUG_NOTE
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(doc, "\t"))
		file.close()
	print("[structure-studio] wrote probe_piece_tug.json — %d placements" % _plan.pieces.size())


const TUG_NOTE := """BUILT THROUGH THE STUDIO'S PIECE TOOL. Every one of the 34 placements below was made by
picking a piece off the kit palette, turning it with R, setting its parameters on steppers and
dropdowns over the piece's own declared value sets, picking a tint off a swatch, and clicking a
grid node. Not one number in this file was typed; there is no control in that tool a number CAN
be typed into.

That claim is checked rather than asserted. `structure_studio.gd`'s `--studio-probe` self-check
carries the same 34 actions as data and requires that replaying them through the controls
reproduces this file placement for placement and plate corner for plate corner — so changing one
step of the recipe, or breaking the rotate key, or letting a stepper walk off its declared set,
turns the gate red.

WHAT IT IS. A harbour tug's pilot house: a plated casing 2.50 m tall with a raked front and
windows in its sides, a tall all-round-glazed wheelhouse standing on it, chamfered at every
corner by a `corner_45` facet, a sloped VISOR over the windscreen — `roof_slope`, which no vessel
in this repo had used — an exhaust casing standing clear above the wheelhouse roof, and a HEAVY
sole in the casing under the door: the thickest floor the kit can lay, which is what the door
head is sized against.

EVERY ID IN THIS FILE IS ALLOCATED BY `StructurePlan`, and that is load-bearing rather than
cosmetic. The 34 placements take 1..34 in the order the recipe places them and the bulwark edge
takes 35, because it is added after them. A hand-edit that appends a placement and types its own
id is how this file once carried TWO entities numbered 34 — an `edges[]` entry and a piece — and
`entity_by_id(34)` silently returned the edge for both. Regenerate it; do not type into it.

WHAT IS NOT PIECE-AUTHORED, and it is the kit's own stated boundary rather than a gap: the
sheer-following bulwark. That is a swept curve, and quantising it to the 0.5 m grid would step
the one curve the fleet was rebuilt to draw, so it is an `edges[]` entry as it is on every other
vessel. The studio has no tool for it either — see the wave report.

Rakes are in EIGHTH-CELLS (0.125 m a step), the kit's unit as of this file's writing."""


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

## Preloaded rather than named, for the reason `plan_outfit.gd`'s own header
## gives: a script that names a global the class cache has not caught up with
## fails to COMPILE, and this app is a lane C gate unit.
const PlanOutfitScript := preload("res://scripts/ship/plan_outfit.gd")

var _deck_grid: DeckGrid
## Entities of `_plan` that `PlanOutfit` will refuse to build — read STRAIGHT OFF
## the compliance report, never computed here. See `_recompute_compliance`.
var _off_hull: Array = []
## The whole registration verdict for the working plan, exactly as
## `DeckFitout.apply_plan` will compute it at spawn. `{}` in the building
## context, where there is no vessel to register.
var _compliance: Dictionary = {}
## The licence the plan is being built to. `""` is a legal state and the panel
## says so — an unregistered plan is refused at spawn with "Choose a vessel
## registration before building", and the builder should read that here first.
var _registration_id := "general_vessel"


## START A NEW, EMPTY PLAN IN `context`. This is the RESET, not the button —
## `_choose_context` and `_choose_hull` are what a click reaches, and they guard
## the two things this function cannot: that the click changed anything at all,
## and that the plan it is about to throw away can be got back.
##
## It used to `_undo_stack.clear()`, and that made this the worst one-click
## work-loss in the app: the two BUILD CONTEXT buttons and every row of the hull
## dropdown emptied the plan AND the undo stack with no confirmation and no
## recovery. Measured by PRESSING every one of the studio's **119 click targets**
## — 83 buttons and 36 dropdown rows, collected with each of the seven tools
## armed in turn — those eleven were the only ones that touched either
## (`tests/_studio_discard_survey.gd`); nothing else in the app clears undo at
## all, so this was the single recovery hole in the surface. The wipe
## itself is correct (a vessel plan is not a building plan, and a plan drawn for
## one hull is not a plan for another); losing the way back was not.
##
## Now the outgoing plan is snapshotted, so UNDO — a button already on the top
## bar, and Ctrl+Z — brings it back, on its own hull, because `_undo` adopts the
## restored plan's frame through `_apply_plan_frame`.
func _set_context(context: String) -> void:
	## A snapshot of nothing is junk on the stack; boot goes through here too.
	var discarded := _plan.entity_count()
	if not _plan.is_empty():
		_snapshot()
	_plan = StructurePlan.new()
	_plan.context = context
	if context == "vessel":
		_plan.hull_id = _hull_id
	_selected_id = -1
	## The ghost is baked at the CURRENT `_plan_offset`, so a hull change leaves a
	## preview standing where the old hull was. Its cache key is the placement, not
	## the offset, so it would not have rebuilt itself.
	_hide_piece_ghost()
	_hide_fitting_ghost()
	_apply_plan_frame()
	_cam_focus = Vector3.ZERO
	_rebake()
	if discarded > 0:
		## The builder has to be told a plan just went away and where it went.
		_set_status("NEW %s PLAN — %d ENTITIES ON UNDO" % [context.to_upper(), discarded])
	_refresh_panel()


## THE GRID, THE DRAWN HULL AND THE CONTEXT, DERIVED FROM `_plan` AND NOTHING
## ELSE — one derivation, shared by `_set_context`, `_load_plan`, `_undo` and
## `_redo` (REALITY §3b).
##
## Each of those four used to carry its own partial version, and the gaps were
## real: `_undo` carried none at all, so undoing a load that changed the hull left
## a 28 m trawler's plan standing on a 150 m feeder's grid with the feeder drawn
## under it — measured before this existed, `hull_id=hull_150x32 grid=64x300`
## against `plan.hull_id=hull_28x10`. That is the same lie `_apply_hull_grid`'s
## header records at 596 of 617 entities, one control over. `_load_plan` carried
## the vessel half and no building half, so loading a building plan kept the
## hull's grid under a plot.
func _apply_plan_frame() -> void:
	_context = _plan.context
	if _context == "vessel":
		if not _plan.hull_id.is_empty():
			_hull_id = _plan.hull_id
		_apply_hull_grid()
		if _hull_option != null:
			_hull_option.selected = _hull_option_index_for(_hull_id)
	else:
		_deck_grid = null
		## CELLS, not metres — a 24 x 24 m plot on the same 0.5 m grid the vessel
		## context builds on. They were 24 and 24 and were read as metres by
		## `_plan_offset` and as cells by `_build_grid_lines`, so the drawn grid was
		## half the size of the plot and sat in a corner of it.
		_grid_width = int(round(24.0 / DeckGrid.CELL_M))
		_grid_length = int(round(24.0 / DeckGrid.CELL_M))
		_plan_offset = Vector3(
			-float(_grid_width) * DeckGrid.CELL_M * 0.5,
			0.0,
			-float(_grid_length) * DeckGrid.CELL_M * 0.5
		)
	_rebuild_host_visual()


## WHAT THE BUILD CONTEXT BUTTONS ACTUALLY CALL.
##
## A click on the context you are already in must not be able to destroy
## anything. It did: pressing VESSEL while in the vessel context took a 3-entity
## plan with a 4-deep undo stack to 0 and 0 (`tests/_studio_discard_survey.gd`),
## and the lane C probe asserted that wipe as correct behaviour — REALITY §4c,
## a check green *because* of the defect.
func _choose_context(context: String) -> void:
	if context == _context:
		_set_status("ALREADY BUILDING A %s — NOTHING CHANGED" % context.to_upper())
		_refresh_panel()
		return
	_set_context(context)


## What the hull dropdown calls. Godot's own `OptionButton` does not re-emit
## `item_selected` for the row already selected — measured, not assumed
## (`_studio_discard_survey.gd`, "chose the same row -> plan 3 entities") — but
## this file must not depend on that to keep a plan, and picking a hull from the
## building context is a real change even when the id matches.
func _choose_hull(hull_id: String) -> void:
	if hull_id == _hull_id and _context == "vessel":
		_set_status("ALREADY ON %s — NOTHING CHANGED" % hull_id.to_upper())
		_refresh_panel()
		return
	_hull_id = hull_id
	_set_context("vessel")


## True when `_plan` was drawn for a different boat than the one on screen. The
## only case undo/redo has to pay `_apply_plan_frame` for — spawning the host
## vessel is the single most expensive call in this file and Ctrl+Z is held down.
func _plan_frame_differs() -> bool:
	if _plan.context != _context:
		return true
	if _plan.context != "vessel":
		return false
	return not _plan.hull_id.is_empty() and _plan.hull_id != _hull_id


## THE GRID THE STUDIO IS BUILDING ON, DERIVED FROM `_hull_id` AND NOTHING ELSE.
##
## Extracted because `_set_context` was the ONLY place it happened, and
## `_load_plan` — which adopts the loaded document's `hull_id` — never rebuilt
## it. Measured before this existed (`tests/_studio_rebake_cost.gd`): loading
## `probe_container_feeder` (hull_150x32, 617 entities) into a studio that had
## booted on hull_28x10 left `_deck_grid` at the trawler's **20 x 56 cells**
## while `_hull_id` read `hull_150x32`, and **596 of 617 entities came back
## "OFF THE HULL — NOT BUILT"** on a fixture that is entirely on its own hull.
##
## That was survivable while the only consumer was one count in a corner of the
## palette. It is not survivable with a registration checklist beside it: every
## rule that locates a fitting (`tag_side`, `white_above_sidelights`) and every
## rule that counts one reads the partition this grid decides, so the panel would
## have been confidently, precisely wrong about somebody else's boat — a lie with
## a UI, which is the one thing this surface must never be.
func _apply_hull_grid() -> void:
	_deck_grid = HullRegistry.make_grid(_hull_id)
	_grid_width = _deck_grid.width
	_grid_length = _deck_grid.length
	_plan_offset = Vector3(-_deck_grid.half_beam, 0.0, -_deck_grid.half_loa)


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
		slab_mesh.size = Vector3(
			float(_grid_width) * DeckGrid.CELL_M + 8.0,
			1.0,
			float(_grid_length) * DeckGrid.CELL_M + 8.0
		)
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
	## `_grid_width` / `_grid_length` are CELL COUNTS and these are PLAN METRES —
	## the same units mistake `_build_grid_lines` carries a note about and
	## `_mouse_to_grid` used to make. On `hull_28x10` (20 x 56 cells, 10 x 28 m)
	## it put STARBOARD 21.6 m out from a hull 10 m wide and STERN 57 m aft of a
	## 28 m one, so all four markings were painted on open water off the grid.
	var beam := float(_grid_width) * DeckGrid.CELL_M
	var loa := float(_grid_length) * DeckGrid.CELL_M
	var markers := [
		["BOW", Vector3(beam * 0.5, 0.06, -1.4), 0.0, BrandTokens.BRASS],
		["STERN", Vector3(beam * 0.5, 0.06, loa + 1.4), 180.0, BrandTokens.INK_INVERSE_DIM],
		["PORT", Vector3(-1.6, 0.06, loa * 0.5), 90.0, BrandTokens.ALERT],
		["STARBOARD", Vector3(beam + 1.6, 0.06, loa * 0.5), 270.0, BrandTokens.OK_LIGHT],
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
	## Same units bug as the orientation markings, and this one mattered more: the
	## STUDIO'S OWN 1.8 m scale reference was standing at plan z = 53 m on a 28 m
	## hull, i.e. 25 m astern of the transom, hanging over open water. It rendered
	## perfectly and was never on the boat — the fourth variant of the failure
	## CONVENTIONS §3a records three of. `_grid_length` is CELLS; this is METRES.
	var spot := Vector3(2.0, 0.0, float(_grid_length) * DeckGrid.CELL_M - 3.0)
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
	_restore_frame_after_history()


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_plan.to_dict())
	_plan = StructurePlan.from_dict(_redo_stack.pop_back())
	_restore_frame_after_history()


## Shared tail of undo and redo. Since a context switch and a hull change are
## both undoable, a step on either stack may be a plan for a different boat —
## so the grid and the drawn hull follow the plan, and only when they have to.
func _restore_frame_after_history() -> void:
	_selected_id = -1
	if _plan_frame_differs():
		_hide_piece_ghost()
		_hide_fitting_ghost()
		_apply_plan_frame()
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
	_recompute_compliance()


## THE WHOLE VERDICT, ONCE PER REBAKE — what will not be built, and whether what
## is left is a legal vessel. Both answers come out of ONE call to the function
## `DeckFitout.apply_plan` calls at spawn, so the checklist on screen and the
## checklist the boat is judged by cannot be two different measurements
## (REALITY.md §3b; `_probe_panel_and_spawn_agree` holds it to that).
##
## THIS IS THE HALF THAT REACHES A PERSON. `PlanOutfit` has computed an off-deck
## warning for slot fittings since it was written and **nothing anywhere read it**
## — not this studio, which is the one place a plan is authored, and not
## `DeckFitout.apply_plan`, which reads `errors` only and pushes them to the
## engine console. The brick side had the identical defect one layer up:
## `shipyard_brick_editor` computed a whole error chain and discarded it one line
## before the Label (STATE.md 2c). The registration verdict was the same shape
## one level up again: computed correctly at spawn, and the builder who has to
## act on it never saw it until the boat was in the water.
##
## ── THE COST, AND WHY IT IS NOT A CACHE ─────────────────────────────────────
##
## `compliance` re-resolves the plan and takes its own hull fence, so adding it
## BESIDE the `off_hull_entities` call this function used to make would have paid
## for that fence twice. Measured on the 617-entity `probe_container_feeder`
## (`tests/_compliance_cost.gd`, quiet tree, 5 reps):
##
##     fence alone, which is what this function used to cost      99.88 ms
##     compliance(), which contains that same fence              120.11 ms
##     the two of them separately — the naive panel              219.98 ms
##
## The verdict half is **~20 ms**: a fifth of the fence, and the fence is a
## fifth of nothing next to the two full bakes `_rebake` already does above.
## So the answer is not to cache it, debounce it, or hide it behind a CHECK
## button — it is to stop taking the fence twice. `compliance` now publishes the
## partition it already holds and this function reads it. Measured at the level
## that matters, a whole rebake of that plan (`tests/_studio_rebake_cost.gd`,
## one process, 9 reps, two runs):
##
##     BEFORE  fence only, no verdict         321.7 / 342.2 ms
##     AFTER   this shared pass               342.4 / 365.4 ms   +6.4 % / +6.8 %
##     NAIVE   fence AND its own compliance   427.4 / 460.0 ms  +32.9 % / +34.4 %
##
## A cache would also have been the worse answer on correctness, not only on
## speed: a stale checklist is a panel that says CERTIFIED about a plan that is
## not, which is the one thing this surface must never do.
##
## Taken here, once per rebake, and never in `_refresh_panel`, which runs on
## every button press and only READS `_compliance`.
func _recompute_compliance() -> void:
	_off_hull = []
	_compliance = {}
	if _context != "vessel" or _deck_grid == null:
		return
	_compliance = PlanOutfitScript.compliance(
		_plan, _hull_id, _registration_id, _deck_grid
	)
	_off_hull = (_compliance.get("off_hull", []) as Array)
	if _off_hull.is_empty():
		return
	_set_status(str((_off_hull[0] as Dictionary)["message"]).to_upper(), false)


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
	## ITEMS, which had no bound at all until the fitting tool landed — so a
	## fitting in a loaded plan could be neither clicked, focused, moved nor
	## deleted, and one placed here would have been write-only. The extent comes
	## from `PlanOutfit.item_world_points`, which is the project's ONE derivation
	## of what an item occupies (REALITY.md §3b): the baker's own geometry for a
	## raw primitive, the catalogue's resolved box for a part. Bounding it any
	## other way here would be the second formula that always drifts.
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var item_id := int(item.get("id", -1))
		var origin := _plan.item_transform(item).origin
		_entity_base_y[item_id] = origin.y
		var points := PlanOutfitScript.item_world_points(_plan, item)
		if points.is_empty():
			## An item the baker draws nothing for still has a position, and a
			## zero-size bound at it is honest: it can be picked and deleted.
			_grow_point_bounds(item_id, origin + _plan_offset)
			continue
		for point in points:
			_grow_point_bounds(item_id, point + _plan_offset)


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
		KEY_I:
			_set_tool(Tool.FITTING)
		KEY_R:
			## Turns whatever is in hand: the selected entity if there is one,
			## otherwise the thing the armed tool is about to place. A fitting and
			## a placement are asked in that order because only one of them can
			## answer — `_rotate_selected_*` returns false unless the selection is
			## its own kind.
			if _rotate_selected_fitting():
				pass
			elif _rotate_selected_piece():
				pass
			elif _tool == Tool.FITTING:
				_rotate_fitting()
			else:
				_rotate_piece()
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_F:
			if _selected_id >= 0 and _entity_bounds.has(_selected_id):
				_cam_focus = (_entity_bounds[_selected_id] as AABB).get_center()
		KEY_PAGEUP:
			_set_build_level(_active_base + NODE_SNAP)
		KEY_PAGEDOWN:
			_set_build_level(_active_base - NODE_SNAP)


## The build level moves a CELL at a time, not a metre.
##
## It stepped 1.0 m, and that quietly made half the kit unreachable with a mouse:
## a placement's level is a whole cell, and the shipped trawler's boat deck is at
## cell y = 5, which is 2.50 m. From 0.00 in whole metres you can reach 2.00 and
## 3.00 and never 2.50, so a player could not stand a piece on that tier at all —
## while the probe, which called `_place_piece_at` with a cell, passed. That is
## exactly the shape of REALITY.md §5 and it is why `_probe_piece_levels` now
## drives this control rather than setting `_active_base`.
func _set_build_level(level: float) -> void:
	_active_base = maxf(roundf(level / NODE_SNAP) * NODE_SNAP, 0.0)
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
	if _tool == Tool.FITTING:
		## One click, one fitting, at the node the ghost is standing on. No drag:
		## a fitting's size is the part's own parameter, not something swept out
		## with the mouse.
		_place_fitting_at(_mouse_to_node(screen_pos))
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
	if tool != Tool.FITTING:
		_hide_fitting_ghost()
	elif _fitting_id.is_empty():
		## Same rule as the piece tool: arm the catalogue's first part so the tool
		## works the moment it is picked up, and let the data file say which.
		var part_ids := _catalogue_ids()
		if part_ids.size() > 0:
			_select_fitting_type(str(part_ids[0]))
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
## Read off the kit's own build expressions, which are the only authority: a
## `quarter_cells` step multiplies by 0.25 and an `eighth_cells` step by 0.125.
## (The names are the kit's and they are looser than they look — a "quarter cell"
## is 0.25 m, which is half of the 0.5 m cell.) `eighth_cells` arrived while this
## tool was being written and the controls needed no change for it, which is the
## point of reading the sets out of the data file; only this readout did.
const PIECE_UNIT_METRES := {
	"cells": WorldUnits.DECK_CELL_M,
	"quarter_cells": WorldUnits.DECK_CELL_M * 0.5,
	"eighth_cells": WorldUnits.DECK_CELL_M * 0.25,
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


# ── The fitting tool ─────────────────────────────────────────────────────────

## The catalogue's part ids, in the catalogue's own order. Empty when the data
## file failed to load — a state the palette shows rather than crashes on.
func _catalogue_ids() -> PackedStringArray:
	return PartCatalog.ids()


## Picking a fitting off the palette.
func _select_fitting_type(part_id: String) -> void:
	if not PartCatalog.has(part_id):
		_set_status("no fitting \"%s\" in the catalogue" % part_id, false)
		return
	_fitting_id = part_id
	## Snap the armed yaw onto the new part's own step, so switching from a
	## 15° part to a 45° one cannot leave a yaw the part does not offer.
	_fitting_yaw = _snap_fitting_yaw(_fitting_yaw)
	_fitting_ghost_key = ""
	_set_status("%s selected" % PartCatalog.display_name(part_id))
	_refresh_panel()


func _snap_fitting_yaw(yaw: float) -> float:
	if _fitting_id.is_empty():
		return 0.0
	var step := float(PartCatalog.yaw_step_of(_fitting_id))
	return fposmod(roundf(yaw / step) * step, 360.0)


## One step of the ARMED part's own declared `yaw_step`. Not a number chosen
## here: a bollard pair turns in 15° and a nav light in whatever its entry says,
## and the catalogue is the only authority on which.
func _rotate_fitting(steps := 1) -> void:
	if _fitting_id.is_empty():
		return
	var step := float(PartCatalog.yaw_step_of(_fitting_id))
	_fitting_yaw = fposmod(_fitting_yaw + step * float(steps), 360.0)
	_fitting_ghost_key = ""
	_set_status("yaw %d°" % roundi(_fitting_yaw))
	_refresh_panel()


## Where the tool would stand the fitting, in PLAN metres. A node index times the
## node snap — the same conversion the piece tool's ghost and commit share, so
## the preview and the placement cannot land in different places.
func _fitting_plan_point(cell: Vector3i) -> Vector3:
	return Vector3(float(cell.x) * NODE_SNAP, float(cell.y) * NODE_SNAP, float(cell.z) * NODE_SNAP)


## The item the tool would commit at this node, with no id yet. ONE function,
## used by the ghost and by the commit.
func _fitting_item_at(cell: Vector3i) -> Dictionary:
	var at := _fitting_plan_point(cell)
	return StructurePlan.normalize_item({
		"item_id": _fitting_id,
		"at": [at.x, at.y, at.z],
		"yaw": _fitting_yaw,
	})


## The ghost is the REAL BAKE of the item about to be committed, drawn through
## `StructureBaker` exactly as the committed one will be.
func _update_fitting_ghost(cell: Vector3i) -> void:
	if _fitting_id.is_empty() or cell == NO_NODE:
		_hide_fitting_ghost()
		return
	var item := _fitting_item_at(cell)
	var key := JSON.stringify(item)
	if key == _fitting_ghost_key and _fitting_ghost != null and is_instance_valid(_fitting_ghost):
		_fitting_ghost.visible = true
		return
	_hide_fitting_ghost()
	var probe := StructurePlan.new()
	probe.context = _context
	probe.hull_id = _hull_id
	probe.items = [item]
	_fitting_ghost = StructureBaker.bake(probe, _plan_offset, true)
	add_child(_fitting_ghost)
	_fitting_ghost_key = key
	_fitting_ghost_item = item


func _hide_fitting_ghost() -> void:
	if _fitting_ghost != null and is_instance_valid(_fitting_ghost):
		_fitting_ghost.queue_free()
	_fitting_ghost = null
	_fitting_ghost_key = ""
	_fitting_ghost_item = {}


## Stands the armed fitting on a grid node. Returns the item, or {} when nothing
## was armed or the cursor was off the grid.
func _place_fitting_at(cell: Vector3i) -> Dictionary:
	if _fitting_id.is_empty():
		_set_status("pick a fitting first", false)
		return {}
	if cell == NO_NODE:
		return {}
	var at := _fitting_plan_point(cell)
	_snapshot()
	var placed := _plan.add_item(_fitting_id, at, _fitting_yaw)
	_set_status("%s at (%.1f, %.1f, %.1f) m yaw %d°" % [
		PartCatalog.display_name(_fitting_id), at.x, at.y, at.z, roundi(_fitting_yaw),
	])
	_rebake()
	_refresh_panel()
	return placed


## The selected entity, if it is a fitting. An item is the only plan entity with
## an `item_id` key.
func _selected_fitting() -> Dictionary:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.is_empty() or not entity.has("item_id"):
		return {}
	return entity


## Turning a PLACED fitting, by its own part's step. Returns false when the
## selection is not a fitting, so `R` can fall through to the piece tool's.
func _rotate_selected_fitting(steps := 1) -> bool:
	var item := _selected_fitting()
	if item.is_empty():
		return false
	var part_id := str(item.get("item_id", ""))
	if not PartCatalog.has(part_id):
		return false
	var step := float(PartCatalog.yaw_step_of(part_id))
	_snapshot()
	StructurePlan.set_item_rotation(
		item, fposmod(float(item.get("yaw", 0.0)) + step * float(steps), 360.0)
	)
	_rebake()
	_refresh_panel()
	return true


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

## The file a given name saves to. ONE derivation, so the probe's temp files and
## the SAVE JSON button cannot disagree about where a plan went (REALITY §3b) —
## they did, and the probes were reaching into `STRUCTURES_DIR` by hand.
func _plan_save_path(plan_name: String) -> String:
	var trimmed := plan_name.strip_edges().to_snake_case()
	if trimmed.is_empty():
		return ""
	return "%s/%s.json" % [SAVED_PLANS_DIR, trimmed]


func _save_plan(plan_name: String) -> void:
	var path := _plan_save_path(plan_name)
	if path.is_empty():
		_set_status("NAME THE STRUCTURE FIRST", false)
		_refresh_panel()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVED_PLANS_DIR))
	## REPLACING, not creating, is a different sentence. The toast said `SAVED /`
	## either way and the builder had no other signal — no dialog, no backup, and
	## `_undo` restores the plan in memory, never the file that was overwritten.
	var replacing := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("SAVE FAILED / %s" % path, false)
	else:
		file.store_string(JSON.stringify(_plan.to_dict(), "\t"))
		file.close()
		_set_status("%s / %s" % ["REPLACED" if replacing else "SAVED", path.get_file()])
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
	_selected_id = -1
	_hide_piece_ghost() ## same reason as `_set_context`: the offset may have moved
	_hide_fitting_ghost()
	## The grid has to follow the hull the document declares. See `_apply_hull_grid`
	## for the 596-of-617 measurement this closes, and for why a checklist makes it
	## load-bearing rather than cosmetic.
	_apply_plan_frame()
	_set_status("LOADED / %s" % path.get_file())
	_rebake()
	_refresh_panel()


## Which entry of the hull dropdown names `hull_id`, or the current selection if
## the registry has no such hull. Keeps the control agreeing with the state the
## rest of this file builds against — a dropdown reading `hull_28x10` over a
## 150 m feeder is the same class of lie as a wrong checklist, one control over.
func _hull_option_index_for(hull_id: String) -> int:
	for index in _hull_option.item_count:
		if str(_hull_option.get_item_text(index)) == hull_id:
			return index
	return _hull_option.selected


## Everything the LOAD list may offer: the builder's own saves first, then the
## shipped worked examples. Two directories, one list — see `SAVED_PLANS_DIR`.
func _saved_plan_paths() -> PackedStringArray:
	var out := _plan_paths_in(SAVED_PLANS_DIR)
	out.append_array(_shipped_plan_paths())
	return out


## The shipped worked examples alone. Kept separate from the line above because a
## check about the FIXTURES must not widen the moment a builder saves a plan.
func _shipped_plan_paths() -> PackedStringArray:
	return _plan_paths_in(STRUCTURES_DIR)


func _plan_paths_in(directory: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	var names := PackedStringArray()
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		out.append("%s/%s" % [directory, file_name])
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
		if _fitting_ghost != null and is_instance_valid(_fitting_ghost):
			_fitting_ghost.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
	_opening_ghost.visible = false
	_hover_box.visible = false
	_start_marker.visible = false
	if _tool != Tool.PIECE and _piece_ghost != null and is_instance_valid(_piece_ghost):
		_piece_ghost.visible = false
	if _tool != Tool.FITTING and _fitting_ghost != null and is_instance_valid(_fitting_ghost):
		_fitting_ghost.visible = false
	match _tool:
		Tool.PIECE:
			var node := _mouse_to_node(mouse)
			_update_piece_ghost(node)
			if node != NO_NODE:
				_start_marker.position = _plan_offset + StructurePlan.piece_node_plan(node)
				_start_marker.visible = true
		Tool.FITTING:
			var fitting_node := _mouse_to_node(mouse)
			_update_fitting_ghost(fitting_node)
			if fitting_node != NO_NODE:
				_start_marker.position = _plan_offset + _fitting_plan_point(fitting_node)
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
## The surface library: every swatch or material click paints the selection AND
## defines the style every NEWLY drawn wall/deck/stair is born with.
##
## ── THE "INSIDE" SLOT WAS TWO DEFECTS IN ONE CONTROL, AND IS GONE ───────────
##
## This was `{"out": …, "in": …}` behind an OUTSIDE / INSIDE toggle. Driven
## through the buttons (`tests/_studio_drawer_drive.gd`, section 3):
##
##   * with INSIDE armed, clicking a swatch wrote the SELECTION'S ONE `color`
##     key — the same key OUTSIDE writes — so "inside" painted the outside, and
##     the toast said `inside colour set` while it did it. `_library_keys_for_selection`
##     admitted as much in its own comment: "walls, plates and stairs carry a
##     single surface — both slots address it";
##   * and the value it stored in `_lib["in"]` was read by NOTHING. `_stamp_library_style`
##     reads `_lib["out"]` alone, so a wall drawn with INSIDE armed came out in
##     the OUTSIDE colour. Measured: INSIDE + hull red, then draw → `[0.9, 0.86, 0.76]`.
##     That is REALITY §3d exactly — a value with no consumer.
##
## There is nothing for it to mean. `structure_plan_v1` gives a wall, a plate and
## a stair ONE `color` and ONE `material`; an inside surface is not a control this
## studio was missing, it is a field the format does not have. So the slot row is
## deleted rather than wired, and the day the format carries a second surface the
## control comes back pointing at it.
var _lib: Dictionary = {"color": [0.82, 0.84, 0.86], "material": "painted"}
var _lib_material_buttons: Dictionary = {}
var _drawer: PanelContainer
var _drawer_scroll: ScrollContainer
var _drawer_info: Label
var _inspector_box: VBoxContainer
var _load_option: OptionButton
var _name_edit: LineEdit
var _hull_option: OptionButton
var _hull_row: VBoxContainer
var _entities_label: Label
var _toast_timer: Timer
## The registration checklist — see `_build_registration_section`.
var _registration_section: VBoxContainer
var _registration_option: OptionButton
var _registration_verdict: Label
var _registration_rows: VBoxContainer
## The lines currently ON SCREEN, so a refresh that would draw the same thing
## draws nothing. See `_render_registration_rows` for the 184x measurement.
var _registration_rendered: PackedStringArray = PackedStringArray()

const TOOL_HINTS := {
	Tool.PIECE: "Piece: pick one off the kit palette, R turns it, click a grid node to stand it there. Every setting is a stepper over the piece's own list — nothing is typed.",
	Tool.FITTING: "Fitting: pick one off the catalogue palette, R turns it by its own step, click a grid node to stand it there. Bollards, helm, navigation lights — the gear a registration counts.",
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
		[Tool.FITTING, "FITTING"],
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
	palette.offset_bottom = -STRIP_HEIGHT
	_ui_root.add_child(palette)
	## SCROLLED. The kit's parameter sets grew from four names to seven while this
	## panel was being built, and the capture showed the result immediately: RAKE
	## was cut off by the bottom of the window and OPENING and the tint swatches
	## were below the fold, which means a player could not reach them at all. A
	## palette whose contents are decided by a data file cannot assume a height.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	scroll.add_child(box)

	box.add_child(BrandComponents.section_header("BUILD CONTEXT"))
	var context_row := HBoxContainer.new()
	context_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	box.add_child(context_row)
	for context in ["vessel", "building"]:
		var button := BrandComponents.tool_button(context.to_upper(), 0.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _choose_context(context))
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
		_choose_hull(str((hulls[index] as Dictionary).get("id", _hull_id)))
	)
	box.add_child(_hull_option)

	box.add_child(BrandComponents.separator())
	box.add_child(BrandComponents.section_header("ACTIVE LEVEL"))
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var level_down := BrandComponents.compact_button("−", BrandTokens.MIN_HIT_TARGET)
	level_down.pressed.connect(func() -> void: _set_build_level(_active_base - NODE_SNAP))
	level_row.add_child(level_down)
	_level_label = BrandLabel.new("", BrandLabel.Role.DATA)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_row.add_child(_level_label)
	var level_up := BrandComponents.compact_button("+", BrandTokens.MIN_HIT_TARGET)
	level_up.pressed.connect(func() -> void: _set_build_level(_active_base + NODE_SNAP))
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
	_build_fitting_section(box)


## The catalogue palette. Same shape as the kit palette above and driven the same
## way — one button per `PartCatalog.ids()` entry, the part's own description as
## the tooltip, and its own `yaw_step` on the turn buttons. No part id appears in
## this file.
func _build_fitting_section(box: VBoxContainer) -> void:
	_fitting_section = VBoxContainer.new()
	_fitting_section.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	_fitting_section.add_child(BrandComponents.section_header("FITTINGS"))

	var catalogue_errors := PartCatalog.load_errors()
	if catalogue_errors.size() > 0:
		var broken := BrandLabel.new(
			"CATALOGUE FAILED TO LOAD\n%s" % "\n".join(catalogue_errors),
			BrandLabel.Role.MICRO_DATA
		)
		broken.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		broken.add_theme_color_override(&"font_color", BrandTokens.ALERT)
		_fitting_section.add_child(broken)

	var flow := VBoxContainer.new()
	flow.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	for id_variant in _catalogue_ids():
		var id := str(id_variant)
		var button := BrandComponents.tool_button(PartCatalog.display_name(id).to_upper(), 0.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(PartCatalog.get_entry(id).get("description", ""))
		button.pressed.connect(func() -> void: _select_fitting_type(id))
		flow.add_child(button)
		_fitting_buttons[id] = button
	_fitting_section.add_child(flow)

	var yaw_row := HBoxContainer.new()
	yaw_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var turn_back := BrandComponents.compact_button("⟲", BrandTokens.MIN_HIT_TARGET)
	turn_back.pressed.connect(func() -> void:
		if not _rotate_selected_fitting(-1):
			_rotate_fitting(-1)
	)
	yaw_row.add_child(turn_back)
	_fitting_yaw_label = BrandLabel.new("", BrandLabel.Role.DATA)
	_fitting_yaw_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fitting_yaw_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fitting_yaw_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	yaw_row.add_child(_fitting_yaw_label)
	var turn_on := BrandComponents.compact_button("⟳", BrandTokens.MIN_HIT_TARGET)
	turn_on.pressed.connect(func() -> void:
		if not _rotate_selected_fitting(1):
			_rotate_fitting(1)
	)
	yaw_row.add_child(turn_on)
	_fitting_section.add_child(yaw_row)
	box.add_child(_fitting_section)


func _refresh_fitting_section() -> void:
	if _fitting_section == null:
		return
	_fitting_section.visible = _tool == Tool.FITTING
	for id in _fitting_buttons.keys():
		(_fitting_buttons[id] as Button).set_pressed_no_signal(str(id) == _fitting_id)
	if _fitting_yaw_label != null:
		var step := PartCatalog.yaw_step_of(_fitting_id) if not _fitting_id.is_empty() else 0
		_fitting_yaw_label.text = "YAW %d°  (STEP %d°)" % [roundi(_fitting_yaw), step]


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
	_drawer = BrandComponents.panel(Vector2(DRAWER_WIDTH, 0), BrandPanel.Variant.PAPER)
	_drawer.name = "PropertiesDrawer"
	_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_top = 60.0
	_drawer.offset_bottom = -STRIP_HEIGHT
	## See `_build_context_strip`: without this the whole drawer stands off the
	## right edge of the viewport.
	_drawer.offset_left = -DRAWER_WIDTH
	_drawer.offset_right = 0.0
	_ui_root.add_child(_drawer)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	_drawer.add_child(root_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(scroll)
	## Held so a capture can photograph the part of the drawer below the fold.
	## Measured on the default boat: the scroll viewport is 948 px and its content
	## is 1628, so PROPERTIES, the whole inspector and the entire STRUCTURE FILE
	## block — name field, SAVE JSON, LOAD SELECTED — start 240 to 630 px past the
	## bottom of it. See `_shoot_properties_drawer`.
	_drawer_scroll = scroll

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	scroll.add_child(box)

	_build_registration_section(box)
	box.add_child(BrandComponents.separator())
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

	## INSIDE the scroll, not pinned under it. Pinned, this block reserved ~200 px
	## of a 984 px drawer and the registration checklist's last two requirements
	## fell behind it — on the very boat whose mooring shortfall was one of them.
	## The file controls are the least urgent thing in this drawer; they scroll
	## like everything else.
	box.add_child(BrandComponents.separator())
	box.add_child(BrandComponents.section_header("STRUCTURE FILE"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Structure name"
	_name_edit.max_length = 32
	box.add_child(_name_edit)
	var save_btn := BrandComponents.primary_button("SAVE JSON", Vector2(0, BrandTokens.MIN_HIT_TARGET))
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func() -> void: _save_plan(_name_edit.text))
	box.add_child(save_btn)
	_load_option = OptionButton.new()
	_load_option.focus_mode = Control.FOCUS_ALL
	_load_option.custom_minimum_size = Vector2(0, BrandTokens.MIN_HIT_TARGET)
	box.add_child(_load_option)
	var load_btn := BrandComponents.compact_button("LOAD SELECTED", 0.0)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(func() -> void:
		var index := _load_option.selected
		if index >= 0:
			_load_plan(str(_load_option.get_item_metadata(index)))
	)
	box.add_child(load_btn)


## ── THE REGISTRATION CHECKLIST ─────────────────────────────────────────────
##
## The last open step of the loop STATE.md 2e/2f closed. A plan-built vessel can
## be certified and the fittings can be placed with a mouse — and until this
## panel existed the studio never TOLD the builder whether the plan certifies.
## The verdict was computed correctly, at spawn, by `DeckFitout.apply_plan`, and
## the one person who has to act on it found out when the boat hit the water.
## REALITY.md §3d, one level up from the off-hull line right beside it.
##
## THREE RULES THIS SURFACE IS BUILT TO:
##
##  1. **It cannot say something the spawn will contradict.** Every row below is
##     rendered out of `_compliance`, which is one call to `PlanOutfit.compliance`
##     — the same function, with the same arguments, that `apply_plan` makes.
##     There is no second evaluator here, no re-count of items, no "looks
##     complete" shortcut. `_probe_panel_and_spawn_agree` authors a plan through
##     the tool's own click path, reads the TEXT off these labels, spawns the
##     same plan through `VesselSpawn` -> `apply_plan`, and fails if the two
##     disagree about the verdict or about which requirements failed.
##
##  2. **A rule id is not an instruction.** "FAILS 3" and `white_light_height`
##     are things a person who wrote the rules can read. So each failing row
##     carries a sentence naming WHAT is missing and WHERE the tool for it is —
##     and the part names in it come out of `PartCatalog`, by the same address
##     the rule uses (tag, outfit slot, compliance numeric), never out of a list
##     kept here. A part that declares `nav_port` tomorrow is named by this panel
##     tomorrow, with no edit in this file.
##
##  3. **Where it does not know, it says so.** An unrecognised rule kind reads as
##     unrecognised rather than as a hint that would waste an afternoon. A
##     cheerful guess here is the same defect as a green test.
##
##     This clause used to name `has_cabin` as its example — "a requirement of a
##     kind this studio has no tool for, which no plan primitive declares since
##     the room was deleted". That was true of the code and WRONG about the
##     studio: `PlanOutfit.has_cabin` returned false for every plan, so the panel
##     told the builder to pick another licence for something the WALL, DECK and
##     OPENING tools between them could already draw. It is measured off geometry
##     now (`PlanOutfit.enclosure`) and `_capability_advice` says which of the
##     two ways the drawing falls short — nothing closed, or closed with no way
##     in — off `cabin_area_m2`, which is the measurement rather than a sentence
##     about it. **A panel that says "you cannot" is a
##     claim like any other, and it goes stale the moment the thing it is about
##     gets built** — which is what happened here, in the one place a player
##     reads.
##
## `_registration_id` is the studio's own state and is NOT saved into the plan:
## `structure_plan_v1` has no registration field, and inventing one here would be
## this file changing a format four other units parse. The consequence is named
## rather than hidden — the licence is a studio setting, and the spawn path takes
## it from the caller or from the boat's `registration_id` meta.
const RegistrationCatalog := preload("res://scripts/ship/vessel_registration_catalog.gd")

## Which tool a builder reaches for, per rule kind. This is the ONE table in this
## file that is not read out of data, because it maps somebody else's vocabulary
## onto THIS studio's tools, and only this file knows those.
const FITTING_TOOL := "FITTING TOOL"


func _build_registration_section(box: VBoxContainer) -> void:
	_registration_section = VBoxContainer.new()
	_registration_section.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	_registration_section.add_child(BrandComponents.section_header("REGISTRATION"))

	_registration_option = OptionButton.new()
	_registration_option.focus_mode = Control.FOCUS_ALL
	_registration_option.custom_minimum_size = Vector2(0, BrandTokens.MIN_HIT_TARGET)
	var ids := RegistrationCatalog.ids()
	## "NONE" is a real choice and it is first, because it is the state a plan is
	## in before anybody picks — and the panel has to be able to say what that
	## costs rather than defaulting quietly to a licence the builder never chose.
	_registration_option.add_item("NONE — NOT REGISTERED", 0)
	_registration_option.set_item_metadata(0, "")
	for index in ids.size():
		var id := str(ids[index])
		_registration_option.add_item(RegistrationCatalog.display_name(id).to_upper(), index + 1)
		_registration_option.set_item_metadata(index + 1, id)
		if id == _registration_id:
			_registration_option.select(index + 1)
	_registration_option.item_selected.connect(func(index: int) -> void:
		_registration_id = str(_registration_option.get_item_metadata(index))
		## The verdict depends on the licence, so it has to be retaken — this is
		## the only control in the studio that recomputes without a rebake.
		_recompute_compliance()
		_refresh_panel()
	)
	_registration_section.add_child(_registration_option)

	_registration_verdict = BrandLabel.new("", BrandLabel.Role.DATA)
	_registration_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_registration_section.add_child(_registration_verdict)

	_registration_rows = VBoxContainer.new()
	_registration_rows.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	_registration_section.add_child(_registration_rows)
	box.add_child(_registration_section)


## COMPUTE THE WORDS, THEN REBUILD ONLY IF THEY CHANGED.
##
## The first cut of this function tore down and rebuilt every row on every call,
## and `_refresh_panel` runs on every button press, every placement and twice per
## frame during a drag. Measured on the default boat with `_studio_refresh_cost2`:
##
##     _refresh_panel, before this panel existed     0.179 ms
##     _refresh_panel, rebuilding rows every time   32.904 ms
##
## **184x**, on the function that runs when you click anything. A `BrandLabel`
## sets `theme` in its constructor, so sixteen of them is sixteen theme
## propagations through a live tree, and none of that work was ever needed: the
## checklist changes when the PLAN or the LICENCE changes, not when a tool button
## is pressed. So the text is derived first — pure string work — and the nodes are
## rebuilt only when it differs from what is already on screen.
##
## This is the cheap half of the same argument `_recompute_compliance` makes
## about the fence: do the work once, for the thing that actually changed.
func _refresh_registration_section() -> void:
	if _registration_section == null:
		return
	_registration_section.visible = _context == "vessel"
	if _context != "vessel":
		_render_registration_rows(PackedStringArray())
		return
	var checklist: Array = _compliance.get("checklist", []) as Array
	if _registration_id.strip_edges().is_empty():
		_set_verdict("NOT REGISTERED — THIS PLAN CANNOT BE SPAWNED", BrandTokens.ALERT)
		_render_registration_rows(PackedStringArray([
			"!PICK A LICENCE ABOVE. A PLAN WITH NO REGISTRATION IS REFUSED AT SPAWN,"
			+ " WHATEVER IS FITTED TO IT."
		]))
		return
	var met := 0
	for raw in checklist:
		if bool((raw as Dictionary).get("ok", false)):
			met += 1
	var certified := bool(_compliance.get("registration_ok", false))
	## The word a builder is looking for, and the count behind it. Not the count
	## alone: "5 OF 8" is a score, and a score is what this panel exists to stop
	## being the whole answer (REALITY.md §1).
	_set_verdict(
		"%s — %d OF %d REQUIREMENTS MET" % [
			"CERTIFIED" if certified else "NOT CERTIFIED", met, checklist.size()
		],
		BrandTokens.OK_LIGHT if certified else BrandTokens.ALERT
	)
	_render_registration_rows(_registration_row_texts(checklist))


## Every line the checklist wants on screen, in order, each tagged by its first
## character: `+` met, `-` failed, `!` an advice sentence. One string array so
## "has anything changed" is one comparison.
func _registration_row_texts(checklist: Array) -> PackedStringArray:
	var rules: Array = (
		RegistrationCatalog.resolved_registration(_registration_id).get("rules", []) as Array
	)
	## WHAT IS STILL WRONG COMES FIRST. The met requirements need no action, and
	## the first cut of this panel put them in rule order, which pushed "at least
	## four mooring points" — the thing the builder in the capture was two short
	## of — below the fold behind two requirements they had already satisfied.
	## The failures also carry a sentence each, so they are the tall rows; ordering
	## by verdict is what keeps the actionable half above the fold on a 320 px
	## drawer, and it costs nothing on a plan that certifies (nothing is failing).
	var ordered: Array = []
	for index in checklist.size():
		var item := checklist[index] as Dictionary
		## Zipped by index AND checked by id: `compliance` walks the resolved
		## rules in order to build the checklist, so index is the correspondence
		## — but an id mismatch would mean this panel is describing a different
		## requirement from the one it just marked failed, so it refuses to guess.
		var rule: Dictionary = {}
		if index < rules.size() and (rules[index] is Dictionary):
			var candidate := rules[index] as Dictionary
			if str(candidate.get("id", "")) == str(item.get("id", "")):
				rule = candidate
		ordered.append({"item": item, "rule": rule})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (
			not bool((a["item"] as Dictionary).get("ok", false))
			and bool((b["item"] as Dictionary).get("ok", false))
		)
	)
	var out := PackedStringArray()
	for pair_variant in ordered:
		var pair := pair_variant as Dictionary
		var item := pair["item"] as Dictionary
		var ok := bool(item.get("ok", false))
		out.append("%s%s  %s" % [
			"+" if ok else "-", "✓" if ok else "✗", str(item.get("label", "")).to_upper()
		])
		if ok:
			continue
		out.append(
			"!" + _registration_advice(pair["rule"] as Dictionary, item, checklist, rules)
		)
	return out


## Puts `lines` on screen, and does nothing at all when they are already there.
func _render_registration_rows(lines: PackedStringArray) -> void:
	if lines == _registration_rendered and _registration_rows.get_child_count() > 0:
		return
	if lines.is_empty() and _registration_rows.get_child_count() == 0:
		_registration_rendered = lines
		return
	## Removed AND freed, for the reason `_refresh_inspector` gives: `queue_free`
	## alone leaves the old rows in the tree, counted and drawn, until the end of
	## the frame — and this can run twice in one frame on a placement.
	for child in _registration_rows.get_children():
		_registration_rows.remove_child(child)
		child.queue_free()
	for line in lines:
		var body := line.substr(1)
		if line.begins_with("!"):
			_registration_rows.add_child(_advice_label(body))
			continue
		var row := BrandLabel.new(body, BrandLabel.Role.DATA)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_color_override(
			&"font_color",
			BrandTokens.OK_LIGHT if line.begins_with("+") else BrandTokens.ALERT
		)
		_registration_rows.add_child(row)
	_registration_rendered = lines


func _set_verdict(text: String, color: Color) -> void:
	_registration_verdict.text = text
	_registration_verdict.add_theme_color_override(&"font_color", color)


func _advice_label(text: String) -> Label:
	var label := BrandLabel.new(text, BrandLabel.Role.MICRO_DATA)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", BrandTokens.WARN)
	return label


## WHAT IS MISSING AND WHERE TO GET IT, for one failed requirement.
##
## Every part name in the returned sentence is looked up in `PartCatalog` by the
## address the RULE uses — its tag, its outfit slot, its compliance numeric — so
## the catalogue is the source of the answer and this function only decides which
## question to ask it. That is what makes a new lantern show up in this text the
## day it is added and not the day somebody remembers this file exists.
## `rules` is the resolved rule array the caller already holds. Passed in rather
## than re-resolved: `VesselRegistrationCatalog.resolved_registration` deep-copies
## the whole catalogue on every call, and this runs inside a loop that runs on
## every button press.
func _registration_advice(
	rule: Dictionary, item: Dictionary, checklist: Array = [], rules: Array = []
) -> String:
	if rule.is_empty():
		return (
			"THIS REQUIREMENT FAILED AND THIS PANEL COULD NOT MATCH IT TO A RULE"
			+ " — REPORT IT. THE VESSEL WILL BE REFUSED AT SPAWN."
		)
	var kind := str(rule.get("kind", ""))
	var have := int(item.get("current", 0)) if not (item.get("current") is String) else 0
	match kind:
		"slot_count":
			return _fit_advice(
				_parts_for_slot(str(rule.get("slot", ""))), rule, have, "FITTED"
			)
		"tag_count":
			return _fit_advice(
				_parts_with_tag(str(rule.get("tag", ""))), rule, have, "FITTED"
			)
		"capacity":
			return _fit_advice(
				_parts_with_numeric(str(rule.get("field", ""))), rule, have, "PROVIDED"
			)
		"cargo_cells":
			return _fit_advice(
				_parts_with_any_tag(PlanOutfitScript.CARGO_TAGS), rule, have, "DECK CELLS OF HOLD"
			)
		"tag_side":
			## THE SENTENCE THAT WAS WRONG IN THE FIRST CAPTURE. `tag_side` fails
			## two ways — the light is on the wrong side, or there is no light —
			## and the rule's `current` is 0 in both, so "FITTED, BUT NOT ALL ON
			## THE PORT SIDE" was printed under a boat carrying no lights at all.
			## A confident wrong instruction is the failure mode this panel exists
			## to avoid, so which sentence to print is settled by asking the SAME
			## report how many of that tag it counted, not by a second census of
			## the plan that could disagree with the fence.
			var tag := str(rule.get("tag", ""))
			var side := str(rule.get("side", "")).to_upper()
			var names := _parts_with_tag(tag)
			var named := "/".join(names) if not names.is_empty() else "IT"
			var counted := _counted_for_tag(checklist, rules, tag)
			if counted < 0:
				## No rule in this registration counts that tag, so the panel does
				## not know which of the two it is. Say the law, not a guess.
				return "EVERY %s MUST STAND %s OF THE CENTRELINE." % [named, side]
			if counted == 0:
				return "NONE FITTED — FIT ONE FIRST, THEN STAND IT %s OF THE CENTRELINE." % side
			return (
				"ON THE WRONG SIDE — SELECT TOOL, DRAG THE %s ACROSS TO %s (THE HALF"
				% [named, side]
				+ " MARKED %s ON THE GRID)." % side
			)
		"white_above_sidelights":
			var whites := _parts_with_tag("nav_white")
			return (
				"MUST STAND HIGHER THAN THE SIDE LIGHTS — PGUP RAISES THE BUILD LEVEL,"
				+ " THEN %s ▸ %s." % [
					FITTING_TOOL,
					"/".join(whites) if not whites.is_empty() else "A WHITE LANTERN"
				]
			)
		"metric_range":
			return _metric_advice(str(rule.get("metric", "")), rule, have)
		"capability":
			return _capability_advice(str(rule.get("capability", "")))
		"equipment_rating_max":
			var rated := _parts_with_tag(str(rule.get("tag", "")))
			return (
				"SOMETHING FITTED IS RATED %d AND THIS LICENCE ALLOWS %d. SELECT TOOL ▸"
				% [have, int(rule.get("max_rating", 0))]
				+ " CLICK THE %s ▸ DEL, OR CHOOSE A LICENCE THAT CARRIES IT."
				% ["/".join(rated) if not rated.is_empty() else "FITTING"]
			)
	return (
		"THIS STUDIO HAS NO GUIDANCE FOR A \"%s\" REQUIREMENT YET — IT DOES NOT KNOW"
		% kind
		+ " WHICH TOOL TO SEND YOU TO."
	)


## The shape every countable requirement shares: how short you are, and which
## catalogue fittings carry the thing you are short of.
func _fit_advice(
	names: PackedStringArray, rule: Dictionary, have: int, noun: String
) -> String:
	if rule.has("max") and have > int(rule["max"]):
		return (
			"%d %s AND THIS LICENCE ALLOWS %d. SELECT TOOL ▸ CLICK ONE ▸ DEL."
			% [have, noun, int(rule["max"])]
		)
	var want := int(rule.get("min", 0))
	var short := "NONE %s" % noun if have <= 0 else "%d OF %d %s" % [have, want, noun]
	if names.is_empty():
		return (
			"%s, AND NOTHING IN THE FITTINGS CATALOGUE CARRIES IT YET — THIS LICENCE"
			% short
			+ " CANNOT BE MET IN THIS STUDIO."
		)
	return "%s — %s ▸ %s." % [short, FITTING_TOOL, " OR ".join(names)]


## How many fittings the report counted for a tag, taken out of the report's own
## checklist rather than re-counted here. Returns -1 when this registration has
## no rule that counts that tag, so a caller can say something true in both cases
## instead of guessing.
func _counted_for_tag(checklist: Array, rules: Array, tag: String) -> int:
	for index in checklist.size():
		if index >= rules.size() or not (rules[index] is Dictionary):
			continue
		var rule := rules[index] as Dictionary
		if str(rule.get("kind", "")) != "tag_count" or str(rule.get("tag", "")) != tag:
			continue
		var current: Variant = (checklist[index] as Dictionary).get("current", 0)
		return int(current) if not (current is String) else -1
	return -1


## Metrics are not fittings, so each one gets sent to the control that actually
## moves it — and `exposed_deck_cells` is a HULL property, not something the DECK
## tool can change, which is why it points at the hull dropdown. Sending a
## builder to drag a bigger deck for it would be a confident wrong answer.
func _metric_advice(metric: String, rule: Dictionary, have: int) -> String:
	match metric:
		"doors":
			return (
				"NO DOOR CUT YET. OPENING TOOL ▸ DOOR, THEN CLICK THE WALL YOU WANT"
				+ " IT IN — OR FIT A CATALOGUE DOOR WITH THE %s." % FITTING_TOOL
			)
		"exposed_deck_cells":
			return (
				"THIS HULL HAS %d EXPOSED DECK CELLS AND THE LICENCE WANTS %d. THAT IS A"
				% [have, int(rule.get("min", 0))]
				+ " PROPERTY OF THE HULL, NOT OF WHAT YOU HAVE DRAWN — PICK A LARGER ONE"
				+ " IN THE HULL DROPDOWN, TOP LEFT."
			)
	return (
		"MEASURED \"%s\" IS %d AND THE LICENCE WANTS %s. THIS STUDIO DOES NOT KNOW"
		% [metric, have, str(rule.get("min", "?"))]
		+ " WHICH CONTROL MOVES THAT YET."
	)


## `has_cabin` is the one capability with a tool behind it, and until 2026-08-16
## this said the opposite: *"NO PLAN PRIMITIVE DECLARES ENCLOSURE SINCE THE ROOM
## TOOL WAS REMOVED, SO THIS STUDIO CANNOT SATISFY THIS REQUIREMENT AT ALL …
## PICK ANOTHER LICENCE."* `PlanOutfit.has_cabin` returned false for every plan,
## so the sentence was true of the code and it sent the builder away from a
## licence they could have earned with one deck plate.
##
## It is measured now, and so is the reason a plan FAILS: `cabin_area_m2` and
## `cabin_why` come off the same report and the same partition this panel shows
## the rest of, so the advice cannot disagree with the verdict beside it. The two
## failures want opposite instructions — nothing is closed (draw walls, roof
## them) against something IS closed and has no way in (cut a door) — and which
## one is printed is decided on the AREA, not on the wording of the reason. It
## was decided on the wording for about an hour, and that branch was already dead
## when it was read back, because the reason string had changed underneath it.
func _capability_advice(capability: String) -> String:
	if capability == "has_cabin":
		var caps: Dictionary = _compliance.get("capabilities", {})
		## WHICH SENTENCE, DECIDED ON A NUMBER AND NOT ON A SENTENCE. The first cut
		## matched `cabin_why` for the words "no door or window", and by the time
		## it was read back that string said "no door opens onto it" — the branch
		## was dead the moment the reading stopped counting a window as a way in.
		## `cabin_area_m2` is the measurement itself: enclosed floor was found, or
		## it was not, and the two failures need opposite instructions.
		var enclosed := float(caps.get("cabin_area_m2", 0.0))
		var why := str(caps.get("cabin_why", "")).to_upper()
		## `cabin_area_m2` is the largest enclosed pocket, and `enclosure` publishes
		## it whether or not a door opens onto it — so it is ALSO non-zero on a
		## plan that HAS a cabin, and the branch below then told a builder with a
		## certified 30.7 m² cabin that they had drawn a space with no way into it.
		## Latent, because the only caller asks for advice on requirements that
		## FAILED and this one cannot fail while `has_cabin` is true; kept out
		## anyway, because the next caller does not inherit that guarantee and this
		## panel's whole job is not to say a confident wrong thing (see `tag_side`
		## above, which learned it the same way).
		if bool(caps.get("has_cabin", false)):
			return (
				"THIS PLAN ALREADY REPORTS %.1f M2 OF CABIN. IF THIS REQUIREMENT IS"
				% enclosed
				+ " SHOWN AS FAILED, THE PANEL AND THE VERDICT DISAGREE — REPORT IT."
			)
		if enclosed > 0.0:
			return (
				"YOU HAVE DRAWN %.1f M2 OF ENCLOSED SPACE WITH NO WAY INTO IT." % enclosed
				+ " OPENING TOOL ▸ DOOR, THEN CLICK THE WALL YOU WANT IT IN."
				+ " A WINDOW WILL NOT DO IT — A CABIN IS SOMEWHERE YOU CAN GET."
			)
		return (
			"A CABIN IS A SPACE THE WEATHER CANNOT GET INTO: WALLS ALL ROUND, A DECK"
			+ " PLATE OVER THEM, %.1f M OF HEADROOM AND A DOOR." % PlanOutfitScript.CABIN_MIN_HEADROOM_M
			+ " CLOSE THE RING WITH THE WALL TOOL, ROOF IT WITH THE DECK TOOL, THEN"
			+ " CUT A DOOR WITH THE OPENING TOOL."
			+ ("  MEASURED: %s." % why if not why.is_empty() else "")
		)
	return (
		"THE VESSEL MUST REPORT \"%s\" AND DOES NOT. THIS STUDIO DOES NOT KNOW WHICH"
		% capability
		+ " TOOL PROVIDES IT."
	)


## ── Catalogue lookups: the answers come from the data, not from a list here ──
##
## MEMOISED, and the distinction matters. This does NOT cache a verdict — a stale
## verdict is the lie this whole panel exists to prevent, and `_compliance` is
## recomputed on every rebake. It caches which CATALOGUE FITTINGS carry a tag,
## which is a property of `resources/data/parts/catalog.json` and cannot change
## while the app is running.
##
## Why it needs caching at all: `PartCatalog.get_entry` returns
## `_entries[id].duplicate(true)`, so `display_name`, `has_tag` and
## `compliance_of` each deep-copy a part — `build` array and all — per call. The
## advice for one failed requirement walks all 17 parts, and a checklist with
## seven failures walks them seven times, on a function that runs on every button
## press. Measured contribution to `_refresh_panel`: ~2.9 ms of 3.1 ms.
var _part_name_cache: Dictionary = {}


func _parts_for_slot(slot: String) -> PackedStringArray:
	var key := "slot:%s" % slot
	if _part_name_cache.has(key):
		return _part_name_cache[key] as PackedStringArray
	var out := PackedStringArray()
	for id_variant in PartCatalog.ids():
		var id := str(id_variant)
		if PartCatalog.outfit_slot_of(id) == slot:
			out.append(PartCatalog.display_name(id).to_upper())
	_part_name_cache[key] = out
	return out


func _parts_with_tag(tag: String) -> PackedStringArray:
	var out := PackedStringArray()
	if tag.is_empty():
		return out
	var key := "tag:%s" % tag
	if _part_name_cache.has(key):
		return _part_name_cache[key] as PackedStringArray
	for id_variant in PartCatalog.ids():
		var id := str(id_variant)
		if PartCatalog.has_tag(id, tag):
			out.append(PartCatalog.display_name(id).to_upper())
	_part_name_cache[key] = out
	return out


func _parts_with_any_tag(tags: Array) -> PackedStringArray:
	var key := "tags:%s" % ",".join(PackedStringArray(tags))
	if _part_name_cache.has(key):
		return _part_name_cache[key] as PackedStringArray
	var out := PackedStringArray()
	for id_variant in PartCatalog.ids():
		var id := str(id_variant)
		for tag in tags:
			if PartCatalog.has_tag(id, str(tag)):
				out.append(PartCatalog.display_name(id).to_upper())
				break
	_part_name_cache[key] = out
	return out


## Fittings that contribute a compliance NUMERIC (seats, and whatever joins it),
## with what each one contributes — because "fit more seats" without "three each"
## leaves a builder counting benches.
func _parts_with_numeric(field: String) -> PackedStringArray:
	var out := PackedStringArray()
	if field.is_empty():
		return out
	var key := "num:%s" % field
	if _part_name_cache.has(key):
		return _part_name_cache[key] as PackedStringArray
	for id_variant in PartCatalog.ids():
		var id := str(id_variant)
		var value := int(PartCatalog.compliance_of(id).get(field, 0))
		if value > 0:
			out.append("%s (%d EACH)" % [PartCatalog.display_name(id).to_upper(), value])
	_part_name_cache[key] = out
	return out


## ── THE TWO PANELS THAT WERE NEVER ON SCREEN ───────────────────────────────
##
## `PRESET_BOTTOM_WIDE` anchors top AND bottom to 1.0 and leaves both offsets at
## zero, so the strip's ORIGIN is the bottom edge and its minimum height grows it
## DOWNWARD, off the viewport. Same shape on the right drawer
## (`PRESET_RIGHT_WIDE`, origin at the right edge, width grown rightward).
## Measured with `tests/_studio_ui_rects.gd` against the project's 1920 x 1080
## logical viewport, before the two offsets below existed:
##
##     TopBar            (0, 0)      1920 x 67    on screen
##     ToolPalette       (0, 60)      286 x 984   on screen
##     PropertiesDrawer  (1920, 60)   320 x 984   ENTIRELY OFF THE RIGHT EDGE
##     ContextStrip      (0, 1080)   1920 x 40    ENTIRELY OFF THE BOTTOM EDGE
##
## So the inspector, the surface library, SAVE JSON, LOAD SELECTED, the tool
## hint, the metrics line and `_set_status`'s toast have never been visible to
## anybody — including the off-hull refusal STATE.md 2f reports as delivered,
## whose probe asserted the `_status` STRING and not the pixel. A panel a player
## cannot see is REALITY.md §3d at the last layer, and it is why
## `_probe_panels_are_on_screen` now asserts the rects rather than the text.
const STRIP_HEIGHT := 36.0
const DRAWER_WIDTH := 320.0


func _build_context_strip() -> void:
	var strip := BrandComponents.panel(Vector2.ZERO, BrandPanel.Variant.BAND)
	strip.name = "ContextStrip"
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.custom_minimum_size = Vector2(0, STRIP_HEIGHT)
	strip.offset_top = -STRIP_HEIGHT
	strip.offset_bottom = 0.0
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

	## The strip's own minimum height, not a second copy of it: the BAND variant
	## adds its own padding, so the constant above under-states the band by 4 px
	## and the bottom row of text falls off the screen by exactly that much.
	## One derivation (REALITY.md §3b) — ask the panel how tall it is.
	strip.offset_top = -maxf(STRIP_HEIGHT, strip.get_combined_minimum_size().y)


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
	_refresh_fitting_section()
	for opening_type in _opening_buttons.keys():
		(_opening_buttons[opening_type] as Button).set_pressed_no_signal(opening_type == _opening_type)
	_level_label.text = "%.2f M · CELL %d" % [_active_base, roundi(_active_base / NODE_SNAP)]
	_ghost_button.set_pressed_no_signal(_ghost_levels)
	var armed_material := str(_lib["material"])
	for material_name in _lib_material_buttons.keys():
		(_lib_material_buttons[material_name] as Button).set_pressed_no_signal(material_name == armed_material)
	_entities_label.text = "STRUCTURE\n%d PARTS\n%d KIT PIECES\n%d FITTINGS\n%d UNDO STEPS" % [
		_plan.entity_count(), _plan.pieces.size(), _plan.items.size(), _undo_stack.size()
	]
	## Persistent, not a toast: a builder who dismissed the message still has to
	## be able to see that part of their ship will not be built.
	if not _off_hull.is_empty():
		_entities_label.text += "\n%d OFF THE HULL — NOT BUILT" % _off_hull.size()
	_hull_option.visible = _context == "vessel"
	_context_label.text = (
		"VESSEL / %s" % _hull_id.to_upper() if _context == "vessel" else "LAND BUILDING"
	)
	_metrics_label.text = _studio_metrics_text()
	_hint_label.text = str(TOOL_HINTS.get(_tool, "")).to_upper()
	_refresh_registration_section()
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
		## The list draws from two directories now, so the same base name can
		## appear twice. Saying which is which is not decoration: picking the
		## wrong one and pressing LOAD SELECTED replaces the plan on screen.
		var label := paths[index].get_file()
		if paths[index].begins_with(STRUCTURES_DIR):
			label += "   (shipped)"
		_load_option.add_item(label, index)
		_load_option.set_item_metadata(index, paths[index])
	if previous >= 0 and previous < _load_option.item_count:
		_load_option.select(previous)


## WHICH OF THE SIX COLLECTIONS THE SELECTION CAME FROM, BY WHAT IT DECLARES.
##
## `StructurePlan` keeps six collections in ONE id space, so a selection is just
## a dictionary and the inspector has to recognise it. It used to test three keys
## and fall through:
##
##     piece -> "piece" · axis -> "wall" · dir -> "stair" · anything else -> "deck"
##
## An ITEM is `{id, item_id, at, yaw}` and an EDGE is `{id, primitive, path|from_hull, …}`.
## Neither has `axis`, `dir` or `piece`, so BOTH landed on "deck" — measured with
## `tests/_studio_inspector_kinds.gd`: selecting a placed navigation light drew
##
##     DECK / PART 006 · THICKNESS 0.500 · Surface: Painted · DELETE PART
##
## and selecting `probe_sheer_bulwark`'s hull bulwark drew the same thing. The
## THICKNESS spinner was live: driving it wrote `thickness` into the item, took an
## undo snapshot and rebaked, and `normalize_item` threw the key away on the next
## save. So all seventeen catalogue fittings and every swept run were described as
## a deck plate and offered a control that costs an undo step and does nothing.
##
## That is exactly the trap the comment on the `piece` branch warned about, one
## collection later: the fitting tool and `edges[]` both arrived after this ladder
## was written, and nothing pointed a check at it because the probe only ever
## selected walls, decks, stairs and placements (REALITY §4b).
##
## Tested in declaration order, most specific first, and each key is the one that
## collection's own writer guarantees: `add_piece` always writes `piece`, `add_item`
## always writes `item_id`, `add_edge`/`add_hull_edge` always write `primitive`.
func _selected_kind(entity: Dictionary) -> String:
	if entity.has("piece"):
		return "piece"
	if entity.has("item_id"):
		return "fitting"
	if entity.has("primitive"):
		return "edge"
	if entity.has("axis"):
		return "wall"
	if entity.has("dir"):
		return "stair"
	return "deck"


## Inspector for a PLACED FITTING. The rotate control is the one the `R` key has
## always driven (`_rotate_selected_fitting`, by the part's own declared step) —
## it simply had no button, so a builder who did not know the shortcut could not
## turn a bollard after placing it. No sizing row: a part's `params` are a
## continuous range, and inventing a step here is the thing `_fitting_id`'s header
## refuses to do.
func _refresh_fitting_inspector(item: Dictionary) -> void:
	var part_id := str(item.get("item_id", ""))
	var known := PartCatalog.has(part_id)
	_drawer_info.text = (
		str(PartCatalog.get_entry(part_id).get("description", "")) if known
		else "No part \"%s\" in the catalogue — this fitting draws nothing." % part_id
	)
	var header := BrandLabel.new(
		"%s / PART %03d" % [
			(PartCatalog.display_name(part_id) if known else part_id).to_upper(), _selected_id
		],
		BrandLabel.Role.DATA
	)
	header.add_theme_color_override(&"font_color", BrandTokens.BRASS_DEEP)
	_inspector_box.add_child(header)
	var at := StructurePlan.vec3_of(item.get("at"))
	_inspector_box.add_child(BrandComponents.key_value_row(
		"At", "%.1f, %.1f, %.1f m" % [at.x, at.y, at.z]
	))
	var step := PartCatalog.yaw_step_of(part_id) if known else 0
	var yaw_row := HBoxContainer.new()
	yaw_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var back := BrandComponents.compact_button("⟲", BrandTokens.MIN_HIT_TARGET)
	back.pressed.connect(func() -> void: _rotate_selected_fitting(-1))
	yaw_row.add_child(back)
	var yaw_label := BrandLabel.new(
		"YAW %d°  (STEP %d°)" % [roundi(float(item.get("yaw", 0.0))), step],
		BrandLabel.Role.DATA
	)
	yaw_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yaw_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yaw_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	yaw_row.add_child(yaw_label)
	var forward := BrandComponents.compact_button("⟳  [R]", BrandTokens.MIN_HIT_TARGET)
	forward.pressed.connect(func() -> void: _rotate_selected_fitting(1))
	yaw_row.add_child(forward)
	_inspector_box.add_child(yaw_row)
	_inspector_box.add_child(BrandComponents.separator())
	var delete_btn := BrandButton.new("DELETE FITTING  [DEL]", BrandButton.Variant.DANGER)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.pressed.connect(func() -> void: _delete_selected())
	_inspector_box.add_child(delete_btn)


## Inspector for a SWEPT RUN. This studio has no tool that draws one — a
## sheer-following bulwark is the one curve the piece kit deliberately refuses to
## quantise — so every edge on screen arrived from the plan file. The panel says
## that rather than offering fields that would only ever be typed numbers
## (REALITY §5), and it can still be selected, found and deleted, which is the
## reason `edges[]` is a first-class plan entity at all.
func _refresh_edge_inspector(edge: Dictionary) -> void:
	var primitive := str(edge.get("primitive", "?"))
	_drawer_info.text = (
		"%s. Authored in the plan file — this studio has no tool that draws a"
		+ " swept run, so its shape is not editable here. Select and DELETE work."
	) % str(edge.get("_is", primitive.replace("_", " ").capitalize()))
	var header := BrandLabel.new(
		"%s / PART %03d" % [primitive.replace("_", " ").to_upper(), _selected_id],
		BrandLabel.Role.DATA
	)
	header.add_theme_color_override(&"font_color", BrandTokens.BRASS_DEEP)
	_inspector_box.add_child(header)
	_inspector_box.add_child(BrandComponents.key_value_row(
		"Path", "from the hull" if edge.has("from_hull") else "%d points" % (
			(edge.get("path", []) as Array).size()
		)
	))
	if edge.has("height"):
		_inspector_box.add_child(BrandComponents.key_value_row(
			"Height", "%.2f m" % float(edge.get("height", 0.0))
		))
	_inspector_box.add_child(BrandComponents.key_value_row(
		"Surface", str(edge.get("material", "painted")).capitalize()
	))
	_inspector_box.add_child(BrandComponents.separator())
	var delete_btn := BrandButton.new("DELETE RUN  [DEL]", BrandButton.Variant.DANGER)
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_btn.pressed.connect(func() -> void: _delete_selected())
	_inspector_box.add_child(delete_btn)


func _refresh_inspector() -> void:
	## REMOVED, then freed. `queue_free` alone is deferred to the end of the frame,
	## so the old controls stay in the tree — and stay counted, and stay drawn —
	## until then. Two refreshes in one frame (selecting a piece right after a
	## wall) left the wall's SpinBoxes sitting under the piece's steppers.
	for child in _inspector_box.get_children():
		_inspector_box.remove_child(child)
		child.queue_free()
	var entity := _plan.entity_by_id(_selected_id)
	if _selected_id < 0 or entity.is_empty():
		## Names all five things a click can pick, not the three that existed when
		## this string was written: a builder who has just placed a kit piece or a
		## fitting was being told, by the panel, that it was not selectable.
		_drawer_info.text = (
			"Nothing selected. Use Select / Move and click a wall, deck plate,"
			+ " stair, kit piece or fitting."
		)
		return
	var kind := _selected_kind(entity)
	if kind == "piece":
		_refresh_piece_inspector(entity)
		return
	if kind == "fitting":
		_refresh_fitting_inspector(entity)
		return
	if kind == "edge":
		_refresh_edge_inspector(entity)
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


## The standing right-hand surface library: a material or a swatch paints the
## current selection AND becomes the style everything drawn next is born with.
## No Outside/Inside slots — see `_lib` for what they did and why they are gone.
func _build_library_section(box: VBoxContainer) -> void:
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
	## A fitting's colour belongs to its PART (`PartCatalog.color_of`), and an
	## `items[]` entry has no `color` or `material` key at all — `normalize_item`
	## drops both. Writing them would have been the same shape as the placement
	## case above: a key no reader accepts.
	if entity.has("item_id"):
		return {}
	## Walls, plates and stairs carry ONE surface, and that is what the library
	## paints.
	return {"entity": entity, "color": "color", "material": "material"}


## What the toast should say when the library cannot reach the selection. Saying
## "colour set" over a placement it did not touch is the small version of a
## checklist that reads CERTIFIED over a boat the spawn refuses.
func _library_refusal() -> String:
	var entity := _plan.entity_by_id(_selected_id)
	if entity.has("piece"):
		return "a placement's tint comes off the PIECE KIT swatches, not this library"
	if entity.has("item_id"):
		return "a fitting is painted by its part, not by this library"
	return ""


func _apply_library_color(rgb: Array) -> void:
	_lib["color"] = rgb.duplicate()
	var keys := _library_keys_for_selection()
	if not keys.is_empty():
		_snapshot()
		(keys["entity"] as Dictionary)[str(keys["color"])] = rgb.duplicate()
		_rebake()
	var refusal := _library_refusal()
	if refusal.is_empty():
		_set_status("surface colour set")
	else:
		_set_status("armed for the next surface — %s" % refusal, false)
	_refresh_panel()


func _apply_library_material(material_name: String) -> void:
	_lib["material"] = material_name
	var keys := _library_keys_for_selection()
	if not keys.is_empty():
		_snapshot()
		(keys["entity"] as Dictionary)[str(keys["material"])] = material_name
		_rebake()
	var refusal := _library_refusal()
	if refusal.is_empty():
		_set_status("surface material: %s" % material_name)
	else:
		_set_status("armed %s for the next surface — %s" % [material_name, refusal], false)
	_refresh_panel()


## Style every new entity with the armed library so drawing is paint-first.
func _stamp_library_style(entity: Dictionary) -> void:
	entity["color"] = (_lib["color"] as Array).duplicate()
	entity["material"] = str(_lib["material"])


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
