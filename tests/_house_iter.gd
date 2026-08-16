extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## THE WHEELHOUSE ITERATION RIG. Builds candidate deckhouses on `hull_15x5`
## through the real `BrickLayout` API, validates each against
## `VesselCompliance`, spawns it through `VesselSpawn.instantiate_from_record`
## (which REFUSES a non-compliant record, so a candidate that breaks
## certification photographs nothing rather than photographing a lie), and
## writes a render series to `screenshots/vessels/iter_house/`.
##
## Camera rig, sky, sea, shadows and the two-pass figure count are lifted from
## `tests/_starter_shot.gd` unchanged, so an iteration frame is comparable with
## the baseline frames in `screenshots/vessels/starter/`.
##
## `VARIANT` selects which candidate to draw; pass it as the first user arg.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_house_iter.tscn -- v1
##
## ── REPRODUCIBILITY, 2026-08-16 ────────────────────────────────────────────
##
## This rig used to produce different pixels on every run. The cause is written
## up in full at the top of `tests/_starter_shot.gd`, and in one line it is:
## `WorldClock` runs a 24-REAL-MINUTE day off the Unix clock and
## `ShipLighting` rescales every light on the vessel from it, so two runs a few
## real minutes apart are a few GAME HOURS apart. The subject does not move —
## the boat's transform, meshes and materials are bit-identical across
## processes — the light does. Two fixes, both mechanical: the clock is pinned
## at noon, and each frame is grabbed after `frame_post_draw` rather than after
## a bare `process_frame` count.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const OUT_DIR := "res://screenshots/vessels/iter_house"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5
const SMALL := "hull_15x5"

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _variant := "v0"
var _refusals := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_variant = str(arg).strip_edges()
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f (noon) — the HOUR is fixed; see this file's header for what that closes"
		% CaptureClock.pin(get_tree()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()

	var grid := HullRegistry.make_grid(SMALL)
	var layout := _build(_variant, grid)
	if layout == null:
		print("UNKNOWN VARIANT '%s'" % _variant)
		get_tree().quit(1)
		return

	var report := VesselCompliance.validate(layout, SMALL, "fishing_vessel", grid)
	print("\n=== %s  cells=%d primaries=%d ===" % [
		_variant, layout.count(), layout.iter_primary_cells().size(),
	])
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		print("    %-24s %s  current=%s" % [
			str(item.get("id", "")),
			"ok " if bool(item.get("ok", false)) else "RED",
			str(item.get("current", "")),
		])
	for e in report.get("errors", PackedStringArray()):
		print("    ERR " + str(e))
	for r in _refusals:
		print("    OFF-DECK " + str(r))
	print("    COMPLIANCE ok=%s  off_deck_refusals=%d" % [
		str(bool(report.get("ok", false))), _refusals.size(),
	])

	var record := {
		"uid": "iter_%s" % _variant,
		"hull_id": SMALL,
		"name": "Coastal sjark",
		"display": "Coastal sjark",
		"shaft_power_kw": 280.0,
		"registration_id": "fishing_vessel",
		"brick_layout": layout.to_dict(),
	}
	var boat := _place(record, Vector3.ZERO)
	if boat == null:
		print("SHOT ABORTED — the record would not spawn (compliance refused it)")
		get_tree().quit(1)
		return

	_report_house_geometry(boat)

	await _ortho("%s__profile_port_ortho" % _variant,
		Vector3(-60.0, WL + 2.6, 0.0), Vector3(0.0, WL + 2.6, 0.0), 21.0)
	## Tight on the house alone, so a 0.5 m change is legible.
	await _ortho("%s__house_profile_ortho" % _variant,
		Vector3(-60.0, WL + 4.2, -1.2), Vector3(0.0, WL + 4.2, -1.2), 8.0)
	await _ortho("%s__bow_on_ortho" % _variant,
		Vector3(0.0, WL + 3.4, -60.0), Vector3(0.0, WL + 3.4, 0.0), 8.0)
	await _persp("%s__bow_quarter" % _variant,
		Vector3(-16.0, 6.6, -19.0), Vector3(0.0, WL + 1.4, -1.0))
	await _persp("%s__house_quarter" % _variant,
		Vector3(-9.2, 6.2, -11.0), Vector3(0.0, WL + 3.6, -1.4))
	await _persp("%s__on_deck" % _variant,
		Vector3(1.6, WL + 3.4, 7.4), Vector3(0.0, WL + 2.0, -2.0))
	print("SHOT DONE %s" % _variant)
	get_tree().quit(0)


# ── house geometry, measured off the SPAWNED boat ───────────────────────────

## The drawn extent of everything the fitout put above the deck, so "the roof is
## flat" is a measurement rather than an impression. Reads the scene the spawn
## path actually produced, not the layout dictionary that fed it.
func _report_house_geometry(boat: BoatBody) -> void:
	var fitout := boat.get_node_or_null("DeckFitout")
	if fitout == null:
		print("    NO DeckFitout NODE — nothing was built")
		return
	var deck_y: float = boat.hull_stations.deck_y
	var lo := INF
	var hi := -INF
	var n := 0
	for mi in _meshes(fitout):
		var a := mi.get_aabb()
		var xf := boat.global_transform.affine_inverse() * mi.global_transform
		var box := xf * a
		if box.end.y <= deck_y + 0.05:
			continue
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
		n += 1
	if n == 0:
		print("    NO ABOVE-DECK GEOMETRY")
		return
	print("    above-deck meshes=%d  y from %.3f to %.3f (deck_y=%.3f, top is %.2f m over deck)" % [
		n, lo, hi, deck_y, hi - deck_y,
	])


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


# ── candidates ──────────────────────────────────────────────────────────────

func _build(variant: String, grid: DeckGrid) -> BrickLayout:
	_refusals = PackedStringArray()
	var layout := _base(grid)
	_add_mooring(layout, grid)
	var house := {}
	match variant:
		"v0":
			house = _house_v0(layout, grid)
		"v1":
			house = _house_v1(layout, grid)
		"v2":
			house = _house_v2(layout, grid)
		"v3":
			house = _house_v3(layout, grid)
		"v6":
			house = _house_v6(layout, grid)
		"v7":
			house = _house_v7(layout, grid)
		"v8":
			house = _house_v8(layout, grid)
		"v9":
			house = _house_v9(layout, grid)
		"v10":
			house = _house_v10(layout, grid)
		_:
			return null
	_add_helm(layout, grid, house)
	var mast_top := _add_mast(layout, grid, int(house["mast_z"]), int(house["mast_y"]))
	_add_nav_lights(layout, house, mast_top)
	_add_trommel(layout, grid, int(house["z1"]) + 3)
	return layout


## v0 — THE SHIPPED HOUSE, re-authored here verbatim from `_add_deckhouse`, so
## every later variant is measured against the same rig rather than against a
## screenshot taken by a different one.
func _house_v0(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var x0 := 2
	var x1 := 7
	var z0 := 9
	var z1 := 16
	var door_cells := {}
	for dx in range(2):
		for dy in range(3):
			door_cells[Vector3i(x0 + 2 + dx, dy, z1)] = true
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			if not (x == x0 or x == x1 or z == z0 or z == z1):
				continue
			for y in range(5):
				var c := Vector3i(x, y, z)
				if door_cells.has(c):
					continue
				var glazed := (y == 2 or y == 3) and (
					z == z0 or (x == x0 or x == x1) and z <= z0 + 2
				)
				_set_on_deck(layout, grid, c, "block_window" if glazed else "block")
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			_set_on_deck(layout, grid, Vector3i(x, 5, z), "roof_flat")
	if not layout.place_footprint(Vector3i(x0 + 2, 0, z1), "block_door", 0, grid):
		_refuse("door at %v" % Vector3i(x0 + 2, 0, z1))
	return {
		"x0": x0, "x1": x1, "z0": z0, "z1": z1, "roof_y": 5,
		"port_wall": Vector3i(x0, 2, z0 + 2), "stbd_wall": Vector3i(x1, 2, z0 + 2),
		"helm_z": z0 + 2, "mast_z": z0 + 2, "mast_y": 6,
	}


## v1 — the three things the bar names, each with the brick the catalogue
## already carries for it and nobody used:
##   RAKE   the front wall steps 0.5 m forward between level 1 and level 2, and
##          `ledge_45` (yaw 0 — high edge at −Z, MEASURED in _wedge_yaw_probe)
##          fills the step into one raked plane.
##   ROOF   a hipped cap: `roof_slope` all round the perimeter falling outboard,
##          `roof_corner` mitring the four corners, `roof_flat` only inside.
##   GLASS  `block_windshield` (3 cells, ONE 1.34 m pane, perimeter frame only)
##          instead of six 0.34 m panes in six frames.
## Plus `block_45` chamfering all four plan corners on every wall level, which
## is the brick equivalent of the piece kit's `corner_45`.
func _house_v1(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var x0 := 2
	var x1 := 7
	var z_low := 10 ## front wall foot, levels 0-1
	var z0 := 9 ## front wall head, levels 2-4
	var z1 := 16
	var door_cells := {}
	for dx in range(2):
		for dy in range(3):
			door_cells[Vector3i(x0 + 2 + dx, dy, z1)] = true

	for y in range(5):
		var zf := z_low if y <= 1 else z0
		for x in range(x0, x1 + 1):
			for z in range(zf, z1 + 1):
				if not (x == x0 or x == x1 or z == zf or z == z1):
					continue
				var c := Vector3i(x, y, z)
				if door_cells.has(c):
					continue
				## Plan corners are chamfered, not square.
				var corner_yaw := _corner_yaw(x, z, x0, x1, zf, z1)
				if corner_yaw >= 0:
					_set_on_deck(layout, grid, c, "block_45", corner_yaw)
					continue
				_set_on_deck(layout, grid, c, "block")
	## The rake: fill the notch left forward of the level-1 wall.
	for x in range(x0, x1 + 1):
		_set_on_deck(layout, grid, Vector3i(x, 1, z0), "ledge_45", 0)

	_glaze_band(layout, grid, x0, x1, z0, [2, 3])
	_roof_cap(layout, grid, x0, x1, z0, z1, 5)

	if not layout.place_footprint(Vector3i(x0 + 2, 0, z1), "block_door", 0, grid):
		_refuse("door at %v" % Vector3i(x0 + 2, 0, z1))
	return {
		"x0": x0, "x1": x1, "z0": z0, "z1": z1, "roof_y": 5,
		"port_wall": Vector3i(x0, 2, z0 + 4), "stbd_wall": Vector3i(x1, 2, z0 + 4),
		"helm_z": z0 + 2, "mast_z": z0 + 3, "mast_y": 6,
	}


## v2 — v1 with its two authoring bugs fixed, both of which the RENDER found and
## no check would have:
##   • the front windshield was anchored at x1-1, and a 3-cell footprint from
##     there runs x1-1, x1, x1+1 — one cell PAST the house, out over the side
##     deck. `place_footprint` was right to accept it; the house was the thing
##     that ended.
##   • the rake wedges were written with `set_brick`, which OVERWRITES, so the
##     level-1 corner chamfers were replaced by wedges and the front-port corner
##     came out as a notch with a loose grey block in it.
## The rake also moves: instead of stepping the FOOT of the wall aft (which
## leaves the roof eave hanging a metre proud of the wall in profile), the top
## level and the roof step FORWARD over the window band — a brow. The base of
## the house stays where the deck plan puts it.
func _house_v2(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, false)


## v3 — v2 plus the plan chamfer on every wall level (`block_45`, the brick the
## piece kit calls `corner_45`). The front window band drops from six cells to
## the four straight ones between the chamfers, so this trades the full-width
## windscreen for a chamfered corner: that is the choice, and it is made by
## looking at v2 and v3 side by side, not by argument.
func _house_v3(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, true)


## v6 — brow only, no chamfer, no eave. The three bar items and nothing else:
## a front that steps forward at the top, a hipped roof, a windshield band.
func _house_v6(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, false, true, false)


## v7 — v6 plus the plan chamfer on every wall level (`block_45` — the brick the
## piece kit calls `corner_45`). It costs the full-width windscreen: the straight
## front run drops from six cells to four, which is not a whole number of 3-cell
## windshields, so the band becomes `block_window_45` corners and four small
## panes. That trade is the thing to LOOK at.
func _house_v7(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, true, true, false)


## v8 — v6 plus a one-cell eave on the sides and the after end.
func _house_v8(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, false, true, true)


## v9 — v8 plus two aft-facing windows flanking the door. The after face is the
## one a captain stands in front of on the working deck (`__on_deck`), and in
## v0-v8 it is 3.0 x 2.5 m of unbroken white with a door in it.
func _house_v9(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, false, true, true, true)


## v10 — THE PICK. v9 with the eave taken off again.
##
## The eave was the right idea and the wrong brick. `roof_slope` fills its whole
## cell, so an eave presents a 0.5 m grey band across the wall top in profile —
## a third of the house becomes roof — and its underside lands EXACTLY on the
## wall top plane, which z-fights: `v9__house_profile_ortho` carries a jagged
## white sawtooth the full length of the house and `v6__house_profile_ortho`
## carries none. `roof_flat` never had that problem because it draws a 0.18 m
## slab at the TOP of its cell and never touches the wall.
##
## So: brow, hipped cap, full-width windscreen, aft windows, no eave.
func _house_v10(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return _house_raked(layout, grid, false, true, false, true)


func _house_raked(
	layout: BrickLayout,
	grid: DeckGrid,
	chamfer: bool,
	brow: bool = true,
	eave: bool = false,
	aft_glass: bool = false,
) -> Dictionary:
	var x0 := 2
	var x1 := 7
	var z0 := 9 ## the house front, unchanged from the shipped preset
	var z_brow := z0 - 1 if brow else z0
	var z1 := 16
	var roof_y := 5
	var door_cells := {}
	for dx in range(2):
		for dy in range(3):
			door_cells[Vector3i(x0 + 2 + dx, dy, z1)] = true

	## Walls — the shipped footprint, five levels, hollow.
	for y in range(5):
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				if not (x == x0 or x == x1 or z == z0 or z == z1):
					continue
				var c := Vector3i(x, y, z)
				if door_cells.has(c):
					continue
				var corner_yaw := _corner_yaw(x, z, x0, x1, z0, z1) if chamfer else -1
				if corner_yaw >= 0:
					_set_on_deck(layout, grid, c, "block_45", corner_yaw)
				else:
					_set_on_deck(layout, grid, c, "block")

	## THE BROW — the top level's front ROW only, cantilevered one cell proud of
	## the window band, with the roof carried out over it. That is how the front
	## of a wheelhouse rakes, and it is the shape v1-v5 kept failing to make with
	## `ledge_45`: a 45° wedge is a RAMP, widest at its base whichever way it is
	## turned (measured — yaw 0 and yaw 180 both read `bot` full, `top` a line),
	## so it can flare a foot but it cannot soffit an overhang. v4 put a wedge
	## there anyway and the front came out a Z.
	if brow:
		for x in range(x0, x1 + 1):
			var corner_yaw := -1
			if chamfer and x == x0:
				corner_yaw = 180
			elif chamfer and x == x1:
				corner_yaw = 90
			if corner_yaw >= 0:
				_set_on_deck(layout, grid, Vector3i(x, 4, z_brow), "block_45", corner_yaw)
			else:
				_set_on_deck(layout, grid, Vector3i(x, 4, z_brow), "block")

	_glaze(layout, grid, x0, x1, z0, chamfer)
	## Two aft-facing windows either side of the door — glass on the brick's local
	## −Z face, so yaw 180 aims it aft.
	if aft_glass:
		for y in [2, 3]:
			for x in [x0 + 1, x1 - 1]:
				layout.erase_cell(Vector3i(x, y, z1))
				_set_on_deck(layout, grid, Vector3i(x, y, z1), "block_window", 180)
	## The roof follows the brow forward. An eave adds one cell to the SIDES and
	## the after end only: carried out forward as well (v4) the cap projects on
	## every face at once and the house reads as a mushroom.
	if eave:
		_roof_cap(layout, grid, x0 - 1, x1 + 1, z_brow, z1 + 1, roof_y)
	else:
		_roof_cap(layout, grid, x0, x1, z_brow, z1, roof_y)

	if not layout.place_footprint(Vector3i(x0 + 2, 0, z1), "block_door", 0, grid):
		_refuse("door at %v" % Vector3i(x0 + 2, 0, z1))
	return {
		"x0": x0, "x1": x1, "z0": z_brow, "z1": z1, "roof_y": roof_y,
		"port_wall": Vector3i(x0, 2, z0 + 4), "stbd_wall": Vector3i(x1, 2, z0 + 4),
		"helm_z": z0 + 2, "mast_z": z0 + 3, "mast_y": roof_y + 1,
	}


## The window band. `block_windshield` is three cells of ONE 1.34 m pane behind a
## perimeter frame; `block_window` is a 0.34 m pane in a frame of its own, and
## six of them in a row is the grid of punched squares the shipped house has.
## Where a straight run is a whole number of windshields it gets windshields.
func _glaze(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, chamfer: bool
) -> void:
	var fx0 := x0 + 1 if chamfer else x0
	var fx1 := x1 - 1 if chamfer else x1
	for y in [2, 3]:
		## Front face.
		var x := fx0
		while x <= fx1:
			if fx1 - x + 1 >= 3:
				for dx in range(3):
					layout.erase_cell(Vector3i(x + dx, y, z0))
				if layout.place_footprint(
					Vector3i(x, y, z0), "block_windshield", 0, grid
				):
					x += 3
					continue
				_refuse("front windshield at %v" % Vector3i(x, y, z0))
			layout.erase_cell(Vector3i(x, y, z0))
			_set_on_deck(layout, grid, Vector3i(x, y, z0), "block_window", 0)
			x += 1
		if chamfer:
			## Carry the band round the chamfer so it reads as one run.
			for corner in [[x0, 180], [x1, 90]]:
				var cx: int = corner[0]
				layout.erase_cell(Vector3i(cx, y, z0))
				_set_on_deck(layout, grid, Vector3i(cx, y, z0), "block_window_45", corner[1])
		## Sides — the forward three cells, exactly one windshield, aimed
		## outboard (glass is on local −Z; yaw 90 puts it on −X = port).
		for side in [[x0, 90], [x1, 270]]:
			var sx: int = side[0]
			var yaw: int = side[1]
			for dz in range(3):
				layout.erase_cell(Vector3i(sx, y, z0 + 1 + dz))
			if not layout.place_footprint(
				Vector3i(sx, y, z0 + 1), "block_windshield", yaw, grid
			):
				_refuse("side windshield at %v yaw %d" % [Vector3i(sx, y, z0 + 1), yaw])
				for dz in range(3):
					_set_on_deck(
						layout, grid, Vector3i(sx, y, z0 + 1 + dz), "block_window", yaw
					)


## -1 when (x,z) is not a plan corner; otherwise the `block_45` yaw that removes
## THAT corner. The four values are the probe's, not the rotation convention's:
##   yaw   0 removes (+X,+Z)   yaw  90 removes (+X,−Z)
##   yaw 180 removes (−X,−Z)   yaw 270 removes (−X,+Z)
func _corner_yaw(x: int, z: int, x0: int, x1: int, z0: int, z1: int) -> int:
	if x == x0 and z == z0:
		return 180
	if x == x1 and z == z0:
		return 90
	if x == x1 and z == z1:
		return 0
	if x == x0 and z == z1:
		return 270
	return -1


## A continuous window band: one `block_windshield` per three cells across the
## front, one down each side's forward three cells. Glass is on the brick's
## local −Z face, so yaw aims it outboard — 0 forward, 90 to port, 270 to
## starboard (measured).
func _glaze_band(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, levels: Array
) -> void:
	for y in levels:
		## Front: the two chamfered corners are already placed, so the straight
		## run is x0+1 .. x1-1 — four cells, which is not a whole number of
		## 3-cell windshields. One windshield plus one window keeps every pane
		## on the same sill and head line.
		for c in [Vector3i(x0 + 1, y, z0), Vector3i(x1 - 1, y, z0)]:
			layout.erase_cell(c)
		if not layout.place_footprint(Vector3i(x0 + 1, y, z0), "block_windshield", 0, grid):
			_refuse("front windshield at %v" % Vector3i(x0 + 1, y, z0))
		for x in range(x0 + 1, x1):
			if not layout.has_cell(Vector3i(x, y, z0)):
				_set_on_deck(layout, grid, Vector3i(x, y, z0), "block_window", 0)
		## Sides: forward three cells, aimed outboard.
		for side in [[x0, 90], [x1, 270]]:
			var x: int = side[0]
			var yaw: int = side[1]
			for dz in range(3):
				layout.erase_cell(Vector3i(x, y, z0 + 1 + dz))
			if not layout.place_footprint(
				Vector3i(x, y, z0 + 1), "block_windshield", yaw, grid
			):
				_refuse("side windshield at %v yaw %d" % [Vector3i(x, y, z0 + 1), yaw])
				for dz in range(3):
					_set_on_deck(layout, grid, Vector3i(x, y, z0 + 1 + dz), "block_window", yaw)


## A hipped roof cap instead of a flat slab: the perimeter falls outboard on
## `roof_slope`, the corners are mitred with `roof_corner`, and `roof_flat`
## fills only what is left. Yaws are the probe's measured values — a
## `roof_slope`'s HIGH edge is at local −Z at yaw 0.
func _roof_cap(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int, roof_y: int
) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var c := Vector3i(x, roof_y, z)
			var on_x := x == x0 or x == x1
			var on_z := z == z0 or z == z1
			if on_x and on_z:
				## Hip corner — peak INBOARD.
				var yaw := 0
				if x == x0 and z == z0:
					yaw = 180
				elif x == x1 and z == z0:
					yaw = 90
				elif x == x1 and z == z1:
					yaw = 0
				else:
					yaw = 270
				_set_on_deck(layout, grid, c, "roof_corner", yaw)
			elif on_z:
				## Falls forward at z0 (high edge aft = yaw 180), aft at z1.
				_set_on_deck(layout, grid, c, "roof_slope", 180 if z == z0 else 0)
			elif on_x:
				## Falls outboard: high edge inboard.
				_set_on_deck(layout, grid, c, "roof_slope", 270 if x == x0 else 90)
			else:
				_set_on_deck(layout, grid, c, "roof_flat")


# ── shared hull furniture, copied from tests/_prebuilt_gen.gd ───────────────

func _refuse(what: String) -> void:
	_refusals.append(what)


## `_on_deck` used to live here too, copied from `_prebuilt_gen.gd`. Both copies
## are deleted: `BrickLayout.set_brick` takes the grid and returns false, so the
## rule is asked once, in the setter (REALITY.md §3b).
func _set_on_deck(
	layout: BrickLayout, grid: DeckGrid, cell: Vector3i, brick_id: String, yaw: int = 0
) -> void:
	if not layout.set_brick(grid, cell, brick_id, yaw):
		_refuse(BrickLayout.off_grid_reason(grid, cell, brick_id))


func _railing_yaw(grid: DeckGrid, ix: int, iz: int) -> int:
	if grid.cell_shape(ix - 1, iz) != DeckGrid.CellShape.FULL:
		return 90
	if grid.cell_shape(ix + 1, iz) != DeckGrid.CellShape.FULL:
		return 270
	if grid.cell_shape(ix, iz - 1) != DeckGrid.CellShape.FULL:
		return 0
	return 180


func _base(grid: DeckGrid) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = SMALL
	for z in range(grid.length):
		for x in range(grid.width):
			if grid.cell_shape(x, z) != DeckGrid.CellShape.FULL:
				continue
			var edge := (
				grid.cell_shape(x - 1, z) != DeckGrid.CellShape.FULL
				or grid.cell_shape(x + 1, z) != DeckGrid.CellShape.FULL
				or grid.cell_shape(x, z - 1) != DeckGrid.CellShape.FULL
				or grid.cell_shape(x, z + 1) != DeckGrid.CellShape.FULL
			)
			if edge:
				_set_on_deck(layout, grid, Vector3i(x, 0, z), "railing", _railing_yaw(grid, x, z))
	return layout


func _add_mooring(layout: BrickLayout, grid: DeckGrid) -> void:
	var zs := [
		grid.bow_taper_cells + 1,
		grid.length - 2,
	]
	for z in zs:
		for x in [0, grid.width - 1]:
			layout.erase_cell(Vector3i(x, 0, z))
			_set_on_deck(
				layout, grid, Vector3i(x, 0, z), "railing_mooring", _railing_yaw(grid, x, z)
			)


func _add_nav_lights(layout: BrickLayout, house: Dictionary, mast_top: Vector3i) -> void:
	if not layout.attach_light(house["port_wall"] as Vector3i, "light_nav_port", 270):
		_refuse("port sidelight has no wall at %v" % house["port_wall"])
	if not layout.attach_light(house["stbd_wall"] as Vector3i, "light_nav_stbd", 90):
		_refuse("starboard sidelight has no wall at %v" % house["stbd_wall"])
	if not layout.attach_light(mast_top, "light_mast_white", 0):
		_refuse("masthead light has no mast at %v" % mast_top)


func _add_mast(layout: BrickLayout, grid: DeckGrid, z: int, y0: int) -> Vector3i:
	var x := (grid.width - 2) / 2
	if not layout.place_footprint(Vector3i(x, y0, z), "mast_base", 0, grid):
		_refuse("mast base at %v" % Vector3i(x, y0, z))
	for y in range(y0 + 1, y0 + 4):
		if not layout.place_footprint(Vector3i(x, y, z), "mast_pole", 0, grid):
			_refuse("mast pole at %v" % Vector3i(x, y, z))
	return Vector3i(x, y0 + 3, z)


func _add_helm(layout: BrickLayout, grid: DeckGrid, house: Dictionary) -> void:
	_set_on_deck(
		layout, grid, Vector3i((grid.width - 2) / 2, 0, int(house["helm_z"])), "helm"
	)


func _add_trommel(layout: BrickLayout, grid: DeckGrid, z0: int) -> void:
	var fp := BrickCatalog.footprint_of("trommel_small")
	var x := (grid.width - fp.x) / 2
	var z := mini(z0, grid.length - fp.z - 1)
	if not layout.place_footprint(Vector3i(x, 0, z), "trommel_small", 0, grid):
		_refuse("trommel at %v" % Vector3i(x, 0, z))


# ── stage / camera, lifted from tests/_starter_shot.gd ──────────────────────

func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(_viewport)

	_world = Node3D.new()
	_viewport.add_child(_world)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.70, 0.78)
	env.ambient_light_energy = 0.85
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 138.0, 0.0)
	fill.light_energy = 0.45
	_world.add_child(fill)

	var sea := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(600.0, 40.0, 600.0)
	sea.mesh = box
	sea.position = Vector3(0.0, WL - 20.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sea.material_override = mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(sea)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.near = 0.05
	_camera.far = 800.0
	_world.add_child(_camera)


func _place(record: Dictionary, at: Vector3) -> BoatBody:
	var boat := VesselSpawn.instantiate_from_record(record)
	if boat == null:
		return null
	boat.freeze = true
	boat.automatic_physics_lod = false
	_world.add_child(boat)
	boat.position = Vector3(at.x, WL - boat.draft_m - boat.hull_stations.keel_y, at.z)
	var figures: Array[Node3D] = []
	var aft := _make_figure()
	aft.position = Vector3(
		boat.beam_m * 0.20, boat.hull_stations.deck_y + 0.12, boat.length_m * 0.18
	)
	boat.add_child(aft)
	figures.append(aft)
	var fwd := _make_figure()
	fwd.position = Vector3(
		-boat.beam_m * 0.30, boat.hull_stations.deck_y + 0.12, -boat.length_m * 0.24
	)
	boat.add_child(fwd)
	figures.append(fwd)
	boat.set_meta("scale_figures", figures)
	return boat


func _make_figure() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.radius = 0.22
	caps.height = 1.62
	body.mesh = caps
	body.position = Vector3(0.0, 0.81, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.05)
	body.material_override = mat
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.115
	sphere.height = 0.23
	head.mesh = sphere
	head.position = Vector3(0.0, 1.69, 0.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.95, 0.92, 0.82)
	head.material_override = hmat
	root.add_child(head)
	return root


func _figures() -> Array:
	var out: Array = []
	for child in _world.get_children():
		if child is BoatBody and child.has_meta("scale_figures"):
			out.append_array(child.get_meta("scale_figures") as Array)
	return out


func _ortho(case: String, from: Vector3, look_at: Vector3, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case, "ortho %.1f m across" % width_m)


func _persp(case: String, from: Vector3, look_at: Vector3) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 40.0
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case, "persp 40 deg")


func _save(case: String, lens: String) -> void:
	var figures := _figures()
	for f in figures:
		f.visible = false
	await CaptureClock.settle(get_tree(), 4)
	var without := _viewport.get_texture().get_image()
	for f in figures:
		f.visible = true
	await CaptureClock.settle(get_tree(), 4)
	var with := _viewport.get_texture().get_image()
	var figure_px := 0
	for y in with.get_height():
		for x in with.get_width():
			if with.get_pixel(x, y) != without.get_pixel(x, y):
				figure_px += 1
	var path := "%s/%s.png" % [OUT_DIR, case]
	with.save_png(ProjectSettings.globalize_path(path))
	print("    %-38s %-20s figure_px=%d%s" % [
		case, lens, figure_px, "   *** FIGURE INVISIBLE ***" if figure_px == 0 else "",
	])
