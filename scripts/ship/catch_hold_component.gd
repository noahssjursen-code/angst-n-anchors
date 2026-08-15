@tool
class_name CatchHoldComponent
extends Node3D

## Insulated fish hold. Catch inventory is data; this node renders coarse fill stages.
##
## GEOMETRY IS DECLARED, NOT SCALED — 2026-08-15.
##
## This node used to draw one fixed hold (a 5.76 x 4.34 m coaming with a manifold
## reaching 0.42 m further outboard) and let `DeckFitout` stretch the whole node
## with `scale = Vector3(1.10, 1.0, 2.10)`. That constant was hull-independent, so
## the same 6.80 m of drawn width landed on a 10 m beam and on a 5 m one: on
## `hull_15x5` the pump flange stood 1.130 m outboard of the deck edge, over open
## water, and the coaming overhung the bow by 0.157 m as well.
##
## The scale is gone. `footprint_m` is the OUTER extent of everything this node
## draws — manifold included — and every internal dimension is derived from it,
## so what a caller declares is what appears. `DeckFitout._mount_fishing` derives
## that footprint from the hull's own clear deck; anything constructing this class
## directly gets the small-boat default below.
##
## `capacity_kg` is NOT derived from `footprint_m` and never has been. Nothing in
## the fishing, landing or persistence path reads the drawn size — `FishingSystem`,
## `FishLandingPump` and `GameState` all read `state.capacity_kg`, which is the
## number `configure()` is handed. Resizing the drawing moves no game balance.

signal fill_changed(state: CatchHoldState)

## Wall/liner thicknesses and coaming height are absolute: a coaming is
## shin-high on a 15 m boat and on a 90 m one, and steel plate does not get
## thicker because the deck is wider. Only the footprint follows the hull.
const COAMING_HEIGHT_M := 0.26
const COAMING_WALL_M := 0.12
## Inset from the coaming's outer face to the insulated liner's outer face.
const COAMING_TO_LINER_M := 0.17
const LINER_WALL_M := 0.08
const PIT_FLOOR_M := 0.08
## How far the capped discharge manifold reaches outboard of the coaming. It is
## part of the declared footprint, so the coaming is inset by it rather than the
## hold quietly growing by 0.42 m on the starboard side.
const MANIFOLD_REACH_M := 0.42
const MANIFOLD_FLANGE_R := 0.18

## THE HATCH IS CLOSED, AND WHAT CLOSES IT IS DRAWN — 2026-08-15.
##
## Until today this node drew a 1.16 m pit and NOTHING it drew collided: not one
## CollisionShape3D, not one CollisionObject3D, on any vessel. What carried a
## player over the aperture was `BoatBody`'s WalkDeck slab, a 5.00 x 0.14 x
## 15.00 m box spanning the whole hull — so a deckhand walked over an open hatch
## on a surface the hold does not draw. Measured on the granted starter
## (`tests/_hold_walk_probe.gd`, `hull_15x5`): all 50 capsule stations over the
## footprint stood on that slab at boat-local y 2.750, and a capsule dropped
## down the middle of the hatch stopped there too, 1.09 m above the drawn pit
## floor and 0.09 m above the drawn surface of its own chilled water.
##
## A fish hold IS a hole in the deck, so "close it" is a choice and not the only
## one. It is the one this drawing can honour, because the other two need the
## HULL cut open and this node cannot do that:
##
##   • the same WalkDeck also carries a hull box (5.00 x 2.21 x 15.00 m) whose
##     top stands 0.51 m BELOW the deck plane. An aperture that were merely
##     opened would drop a player 0.51 m onto invisible steel with 0.65 m of
##     drawn pit still beneath their feet — the same "standing on nothing"
##     defect, one storey down;
##   • the hull's own deck plate mesh spans the aperture as well, so an open
##     hold needs three separate holes cut — slab, hull box, plate — every one
##     of them in `BoatBody` / the hull loft, on every vessel in the game;
##   • the player capsule steps 0.45 m and jumps 0.90 m. This coaming is 0.26 m,
##     so it is not a barrier a player would notice, and a 1.16 m pit with
##     vertical sides is not climbable. Falling in would be a trap, not a
##     hazard, until somebody draws a ladder.
##
## So the hold gets hatch boards, dropped into the coaming so the rim still
## stands proud of them, and they are what a player's feet are on — 0.20 m above
## the deck, against a 0.45 m step height. Opening them is a gameplay action
## nothing in the game can perform yet; when it can, the thing it opens exists.
const HATCH_COVER_M := 0.06
## Target board width. The count is derived from the hatch so a 2 m hold gets
## boards a person could lift, not one slab and not twenty battens.
const HATCH_BOARD_M := 0.62
## How far each board laps into its neighbour and into the coaming.
##
## MEASURED, not styled. Butted flush, two boards share a face exactly, and a
## downward ray on that plane passes between both boxes and reports the deck
## 0.250 m below: 7 of 63 stations on `hull_150x32`, whose 19.0 m hatch takes 30
## boards, all of them on the seam row. A capsule cannot fall through a
## zero-width seam, but an interaction ray can, and a hold that answers "the
## deck" to "what is under the cursor" is the same lie one layer thinner. A lap
## removes the degeneracy; 4 mm is invisible beside a 0.06 m board.
const HATCH_LAP_M := 0.004

@export var hold_id: String = "catch_hold"
@export var capacity_kg: float = 4000.0
## Outer drawn extent in local metres: x across, y BELOW the deck plane
## (y = 0 is the deck; the coaming stands COAMING_HEIGHT_M above it), z fore-aft.
@export var footprint_m := Vector3(3.00, 1.16, 2.40)

var state := CatchHoldState.new()
## Every box `_build_visual` drew as STRUCTURE, in hold-local metres, appended
## by the same statement that built the mesh. `DeckFitout` registers exactly
## these on the vessel's WalkDeck, so the collider is not a second derivation of
## the drawing that can drift away from it (REALITY §3b).
var _solid: Array[Dictionary] = []
var _fill_root: Node3D
var _boat: BoatBody
var _pump_connection: Node3D
var _hose_drop: Node3D


func _ready() -> void:
	_boat = _find_boat()
	state.hold_id = hold_id
	state.capacity_kg = maxf(capacity_kg, 0.0)
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_build_visual()
	_sync_payload_mass()


func configure(id_in: String, capacity_kg_in: float) -> void:
	hold_id = id_in.strip_edges()
	if hold_id.is_empty():
		hold_id = "catch_hold"
	capacity_kg = maxf(capacity_kg_in, 0.0)
	state.hold_id = hold_id
	state.capacity_kg = capacity_kg


## Declare the drawn footprint. Separate from `configure` on purpose: capacity is
## a gameplay number and this is a drawing, and the two must stay unable to move
## each other. Rebuilds the meshes when the node is already in the tree.
func configure_footprint(size_m: Vector3) -> void:
	footprint_m = Vector3(
		maxf(size_m.x, 2.0 * (COAMING_TO_LINER_M + LINER_WALL_M) + 0.20),
		maxf(size_m.y, PIT_FLOOR_M + 0.10),
		maxf(size_m.z, 2.0 * (COAMING_TO_LINER_M + LINER_WALL_M) + 0.20),
	)
	if is_inside_tree():
		_build_visual()


func get_state() -> CatchHoldState:
	return state


func get_pump_connection_world() -> Vector3:
	if _pump_connection != null and is_instance_valid(_pump_connection):
		return _pump_connection.global_position
	return global_position


func get_hose_drop_world() -> Vector3:
	if _hose_drop != null and is_instance_valid(_hose_drop):
		return _hose_drop.global_position
	return global_position


func apply_state(data: Dictionary) -> void:
	state = CatchHoldState.from_dict(data)
	state.hold_id = hold_id
	state.capacity_kg = capacity_kg
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_on_state_changed(state)


func accept_lot(lot: CatchLot) -> CatchLot:
	var before := state.total_mass_kg()
	var overflow := state.accept_lot(lot)
	if not is_equal_approx(before, state.total_mass_kg()):
		fill_changed.emit(state)
	return overflow


func withdraw_oldest(max_mass_kg: float) -> Array[CatchLot]:
	var before := state.total_mass_kg()
	var lots := state.withdraw_oldest(max_mass_kg)
	if not is_equal_approx(before, state.total_mass_kg()):
		fill_changed.emit(state)
	return lots


static func get_all_for_ship(boat: Node) -> Array[CatchHoldComponent]:
	var out: Array[CatchHoldComponent] = []
	if boat == null:
		return out
	for child in boat.find_children("*", "CatchHoldComponent", true, false):
		var hold := child as CatchHoldComponent
		if hold != null:
			out.append(hold)
	return out


static func first_for_ship(boat: Node) -> CatchHoldComponent:
	var holds := get_all_for_ship(boat)
	return holds[0] if not holds.is_empty() else null


func _on_state_changed(_state: CatchHoldState) -> void:
	_sync_payload_mass()
	_update_fill_visual()


func _sync_payload_mass() -> void:
	if _boat == null:
		_boat = _find_boat()
	if _boat == null:
		return
	_boat.set_mass_entry(
		"catch:%s" % hold_id,
		state.total_mass_kg(),
		_boat.to_local(global_position) + Vector3(0.0, -0.8, 0.0),
		"cargo",
	)


func _find_boat() -> BoatBody:
	var node: Node = self
	while node != null:
		if node is BoatBody:
			return node as BoatBody
		node = node.get_parent()
	return null


## Half-extent of the coaming's outer face, inboard of the manifold that shares
## the declared footprint with it. One derivation: the mesh builder below, the
## fill visual and the pump connection all read these, so none of them can drift
## outside `footprint_m` on its own.
func _manifold_reach() -> float:
	return minf(MANIFOLD_REACH_M, footprint_m.x * 0.25)


func _coaming_half() -> Vector2:
	return Vector2(footprint_m.x * 0.5 - _manifold_reach(), footprint_m.z * 0.5)


func _liner_half() -> Vector2:
	var c := _coaming_half()
	return Vector2(
		maxf(c.x - COAMING_TO_LINER_M, LINER_WALL_M),
		maxf(c.y - COAMING_TO_LINER_M, LINER_WALL_M),
	)


## Draws a box AND records it as one of this hold's solid boxes. The two happen
## in one statement on purpose: a collider derived a second time from the same
## constants is a second derivation, and this project has fixed that drift three
## times (REALITY §3b).
func _add_solid(
	parent: Node3D,
	pos: Vector3,
	size: Vector3,
	color: Color,
	roughness: float,
	metallic: float,
) -> void:
	var mesh := MeshBuilder.box(size, color, roughness, metallic)
	mesh.position = pos
	parent.add_child(mesh)
	_solid.append({"pos": pos, "size": size})


## Same, for an athwartships pipe. Its solid box is the cylinder's own bounding
## box — a box around a round thing, which is what every collider in this
## project is; the corners it adds are 0.09 m of steel on a 0.36 m flange.
func _add_solid_pipe(
	parent: Node3D,
	pos: Vector3,
	radius: float,
	length: float,
	color: Color,
	roughness: float,
	metallic: float,
) -> void:
	var mesh := MeshBuilder.cylinder(radius, length, color, roughness, metallic)
	mesh.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	mesh.position = pos
	parent.add_child(mesh)
	_solid.append({"pos": pos, "size": Vector3(length, radius * 2.0, radius * 2.0)})


## The boxes this node draws as structure, in hold-local metres. `DeckFitout`
## puts exactly these on the vessel's WalkDeck; nothing else may invent one.
##
## The pit floor and the insulated liner are NOT here, and that is a decision
## rather than an oversight: the boards close the only way in, and the WalkDeck's
## hull box already fills the drawn pit from 0.51 m below the deck plane
## downwards, so a liner collider would be a box inside a bigger box that a
## player can never touch. If the hatch is ever made to open, they belong here
## and the hull box needs a hole — see the header.
func solid_boxes() -> Array[Dictionary]:
	## A hold configured but never yet in a tree has not drawn anything, and a
	## caller asking what it draws would get an empty answer and register no
	## colliders at all. Building here rather than reporting nothing keeps the
	## list and the meshes the same object in every construction order.
	if _solid.is_empty():
		_build_visual()
	var out: Array[Dictionary] = []
	for box in _solid:
		out.append((box as Dictionary).duplicate())
	return out


func _build_visual() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_solid.clear()
	var hold := Node3D.new()
	hold.name = "OpenRswFishHold"
	add_child(hold)
	var steel := Color(0.34, 0.39, 0.42)
	var inner := Color(0.025, 0.045, 0.055)
	var coam := _coaming_half()
	var liner := _liner_half()
	var depth := footprint_m.y
	## Deep false floor and dark liner make this read as a volume below deck,
	## matching the open bulk-hold language used elsewhere on vessels.
	var pit := MeshBuilder.box(
		Vector3(liner.x * 2.0, PIT_FLOOR_M, liner.y * 2.0), inner, 0.96, 0.03
	)
	pit.position = Vector3(0.0, -depth + PIT_FLOOR_M * 0.5, 0.0)
	hold.add_child(pit)
	var wall_h := depth - PIT_FLOOR_M
	var wall_y := -wall_h * 0.5
	for wall in [
		[
			Vector3(-liner.x + LINER_WALL_M * 0.5, wall_y, 0.0),
			Vector3(LINER_WALL_M, wall_h, liner.y * 2.0),
		],
		[
			Vector3(liner.x - LINER_WALL_M * 0.5, wall_y, 0.0),
			Vector3(LINER_WALL_M, wall_h, liner.y * 2.0),
		],
		[
			Vector3(0.0, wall_y, -liner.y + LINER_WALL_M * 0.5),
			Vector3(liner.x * 2.0, wall_h, LINER_WALL_M),
		],
		[
			Vector3(0.0, wall_y, liner.y - LINER_WALL_M * 0.5),
			Vector3(liner.x * 2.0, wall_h, LINER_WALL_M),
		],
	]:
		var skin := MeshBuilder.box(wall[1], inner, 0.92, 0.04)
		skin.position = wall[0]
		hold.add_child(skin)
	## Low stainless coaming around the hatch. SOLID: it is the curb a deckhand
	## steps over, and the drawing was the only thing here that ever existed.
	var coam_y := COAMING_HEIGHT_M * 0.5
	for wall in [
		[
			Vector3(-coam.x + COAMING_WALL_M * 0.5, coam_y, 0.0),
			Vector3(COAMING_WALL_M, COAMING_HEIGHT_M, coam.y * 2.0),
		],
		[
			Vector3(coam.x - COAMING_WALL_M * 0.5, coam_y, 0.0),
			Vector3(COAMING_WALL_M, COAMING_HEIGHT_M, coam.y * 2.0),
		],
		[
			Vector3(0.0, coam_y, -coam.y + COAMING_WALL_M * 0.5),
			Vector3(coam.x * 2.0, COAMING_HEIGHT_M, COAMING_WALL_M),
		],
		[
			Vector3(0.0, coam_y, coam.y - COAMING_WALL_M * 0.5),
			Vector3(coam.x * 2.0, COAMING_HEIGHT_M, COAMING_WALL_M),
		],
	]:
		_add_solid(hold, wall[0], wall[1], steel, 0.7, 0.15)
	## Hatch boards, spanning the coaming's clear opening and dropped into it — so
	## the assembly reads as a hatch a person steps up onto, and the step is
	## 0.20 m against a 0.45 m step height.
	##
	## CONTIGUOUS AND LAPPED, deliberately. Each board is registered as the box it
	## draws, so a gap between two boards is a gap in the COLLIDER: a foot, or a
	## downward ray, would find the deck 0.26 m below through it — and butted
	## flush is not enough, see HATCH_LAP_M. The seams are drawn by alternating
	## the board shade instead, which is free in the solid bake.
	var open := Vector2(
		maxf(coam.x - COAMING_WALL_M, 0.05), maxf(coam.y - COAMING_WALL_M, 0.05)
	)
	var boards := maxi(2, int(round(open.y * 2.0 / HATCH_BOARD_M)))
	var board_z := open.y * 2.0 / float(boards)
	## RECESSED one board thickness, not flush. Flush was tried and photographed
	## first (`screenshots/vessels/hold/hold__after__quarter.png` at that
	## version): the boards and the coaming top formed one continuous grey
	## surface, so the hatch read as a plain slab dropped on the deck with no
	## rim, no shadow line and nothing to say it was a hold. Dropped into the
	## coaming it reads as a hatch again — the coaming stands 0.06 m proud all
	## round and casts a line onto the boards (REALITY §1: look, then say what
	## you changed and why).
	var board_y := COAMING_HEIGHT_M - HATCH_COVER_M * 1.5
	for i in range(boards):
		_add_solid(
			hold,
			Vector3(0.0, board_y, -open.y + (float(i) + 0.5) * board_z),
			Vector3(
				open.x * 2.0 + HATCH_LAP_M * 2.0,
				HATCH_COVER_M,
				board_z + HATCH_LAP_M * 2.0,
			),
			steel.lerp(Color(0.20, 0.24, 0.26), 0.42 if i % 2 == 1 else 0.14),
			0.62,
			0.30,
		)
	## Capped discharge manifold for the fish-landing pump hose. Its outer face is
	## the starboard edge of `footprint_m`. The cap is a CYLINDER, so its own
	## half-thickness and its radius both reach past the point it is positioned
	## at — which is how the old drawing ended up 0.42 m wider than anything in
	## `DeckFitout` accounted for. Every term below is measured to the outer face.
	## SOLID as well, and its box is its own bounding box: a capped pipe standing
	## proud of the deck is something a deckhand walks into, and leaving it as
	## the one drawn thing with no collider would have left the property this
	## component now holds ("what the hold draws is what you stand on") with an
	## exception in it — which is how exceptions become the next bug.
	var reach := _manifold_reach()
	var flange_r := minf(MANIFOLD_FLANGE_R, reach * 0.42)
	## Clamped, because the flange is a CYLINDER: its radius bulges in z as well
	## as in y, and on a short hatch 0.68 of the coaming plus a radius reaches
	## past the declared end. Same class of miss as the 0.42 m it used to make
	## sideways.
	var manifold_z := minf(coam.y * 0.68, footprint_m.z * 0.5 - flange_r)
	var pipe_len := maxf(reach - flange_r * 0.44, 0.06)
	_add_solid_pipe(
		hold,
		Vector3(coam.x + pipe_len * 0.5, coam_y, manifold_z),
		flange_r * 0.56,
		pipe_len,
		steel,
		0.42,
		0.72,
	)
	_add_solid_pipe(
		hold,
		Vector3(footprint_m.x * 0.5 - flange_r * 0.22, coam_y, manifold_z),
		flange_r,
		flange_r * 0.44,
		Color(0.12, 0.16, 0.18),
		0.5,
		0.55,
	)
	_pump_connection = Node3D.new()
	_pump_connection.name = "PumpConnection"
	_pump_connection.position = Vector3(footprint_m.x * 0.5, coam_y, manifold_z)
	hold.add_child(_pump_connection)
	## Loose fish is landed through the open hatch. The hose hangs above this
	## point and drops into the RSW water rather than piercing the hull side.
	_hose_drop = Node3D.new()
	_hose_drop.name = "HoseDrop"
	_hose_drop.position = Vector3(0.0, -depth * 0.33, 0.0)
	hold.add_child(_hose_drop)
	_fill_root = Node3D.new()
	_fill_root.name = "FishAndChilledWater"
	add_child(_fill_root)
	_update_fill_visual()


func _update_fill_visual() -> void:
	if _fill_root == null:
		return
	for child in _fill_root.get_children():
		child.queue_free()
	var ratio := state.fill_ratio()
	if ratio <= CatchLot.MASS_EPS_KG:
		return
	var liner := _liner_half()
	var inner := Vector2(
		maxf(liner.x - LINER_WALL_M, 0.05), maxf(liner.y - LINER_WALL_M, 0.05)
	)
	## Empty surface sits just above the pit floor; brimful sits just below the
	## deck plane. Both ends are read off the same depth the walls were built to.
	var surface_y := lerpf(-footprint_m.y + PIT_FLOOR_M + 0.04, -0.08, ratio)
	var water := MeshBuilder.box(
		Vector3(inner.x * 2.0, 0.045, inner.y * 2.0),
		Color(0.16, 0.42, 0.48, 0.86),
		0.22,
		0.06,
	)
	water.position = Vector3(0.0, surface_y, 0.0)
	_fill_root.add_child(water)
	## A deterministic surface scatter reads as loose fish in chilled seawater
	## without creating one scene object per kilogram of catch. Lane and row
	## counts follow the hatch the hull gave us, so a small boat's hold is not
	## paved with overlapping fish.
	## A fish is 0.36 m nose to tail at full size. On a hatch too small to carry
	## that it shrinks rather than hanging through the liner: a scatter that
	## pierces its own hold is the overhang bug one scale down.
	var fish := clampf(minf(inner.x, inner.y) * 0.34, 0.09, 0.18)
	var margin := fish * 1.6
	var lanes := clampi(int(floor((inner.x * 2.0 - margin * 2.0) / (fish * 3.4))), 2, 8)
	var rows := clampi(int(floor((inner.y * 2.0 - margin * 2.0) / (fish * 4.2))), 2, 5)
	var lane_step := (inner.x * 2.0 - margin * 2.0) / float(maxi(lanes - 1, 1))
	var row_step := (inner.y * 2.0 - margin * 2.0) / float(maxi(rows - 1, 1))
	var fish_count := maxi(4, ceili(ratio * float(lanes * rows)))
	for i in range(fish_count):
		var lane := i % lanes
		var row := (i / lanes) % rows
		var jitter_x := sin(float(i * 17 + 3)) * minf(fish * 0.56, lane_step * 0.16)
		var jitter_z := cos(float(i * 11 + 5)) * minf(fish * 0.50, row_step * 0.12)
		var fish_root := Node3D.new()
		fish_root.name = "Fish_%02d" % i
		fish_root.position = Vector3(
			-(inner.x - margin) + float(lane) * lane_step + jitter_x,
			surface_y + fish * 0.39 + float(i % 3) * 0.012,
			-(inner.y - margin) + float(row) * row_step + jitter_z,
		)
		fish_root.rotation_degrees.y = float((i * 47) % 170) - 85.0
		_fill_root.add_child(fish_root)
		var fish_color := Color(0.56, 0.64, 0.66) if i % 3 else Color(0.32, 0.42, 0.46)
		var body := MeshBuilder.sphere(fish, fish_color, 0.32, 0.18)
		body.scale = Vector3(1.0, 0.28, 0.42)
		fish_root.add_child(body)
		var tail := MeshBuilder.prism(
			Vector3(fish * 0.78, fish * 0.33, fish * 0.67), fish_color, 0.38, 0.12
		)
		tail.position = Vector3(fish * 1.17, 0.0, 0.0)
		tail.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		fish_root.add_child(tail)
