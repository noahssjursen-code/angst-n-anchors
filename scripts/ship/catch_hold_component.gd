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
## Emitted after the boards have moved and the colliders have followed them.
signal hatch_changed(open: bool)

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

## THE HATCH OPENS, AND WHAT IT OPENS INTO IS NOT A HOLE A PERSON FITS THROUGH
## — 2026-08-15.
##
## History, because the shape of the answer comes from it. This node used to draw
## a 1.16 m pit and NOTHING it drew collided: not one CollisionShape3D, not one
## CollisionObject3D, on any vessel. What carried a player over the aperture was
## `BoatBody`'s WalkDeck slab, a 5.00 x 0.14 x 15.00 m box spanning the whole
## hull, so a deckhand walked over an open hatch on a surface the hold does not
## draw — 50 of 50 capsule stations at boat-local y 2.750, 1.09 m above the drawn
## pit floor. `bd548bc` closed it with solid boards and said the price out loud:
## a player could no longer see their catch.
##
## THE ARGUMENT FOR HOW IT OPENS. A fish hold is a hole in the deck, and the
## honest way to open one is to let a player climb down it. Measured, this hull
## cannot offer that:
##
##   • the WalkDeck's hull box (5.00 x 2.21 x 15.00 m) tops out 0.51 m BELOW the
##     deck plane, and the drawn pit floor is 0.55 m below THAT. Opening the
##     aperture drops a player onto invisible steel with 0.65 m of drawn pit
##     still under their feet — the same defect one storey down;
##   • and the way back out does not exist. `scripts/player/player.gd` has
##     `max_step_height 0.45` and `jump_peak_height 0.9`, and NO climb path of
##     any kind — grep for it. The pit floor stands 1.06 m below the deck plane
##     on `hull_15x5`, so a player who got in could not get out. A hazard needs
##     an exit or it is a trap, and the exit would be a ladder the controller
##     cannot use or a stair 1.2 m long in a 2.0 m hold.
##
## So the aperture opens to LOOK, not to enter, and the property that makes that
## true is measured rather than asserted: **the player capsule is 0.70 m across**
## (`scenes/shared/player.tscn`: radius 0.35) **and no clear opening this hatch
## ever presents is wider than 0.62 m.** The hatch boards slide, alternate boards
## lifting onto their neighbours, so what is open is a run of slots each one
## board wide — which is how pound boards are actually worked, and which scales:
## a 19 m hatch on `hull_150x32` opens into 15 slots, not into one 19 m hole.
##
## Because nothing a player controls can pass the deck plane, the two colliders
## below it — the WalkDeck slab and the hull box — are left whole. Cutting a hole
## in a vessel's player-blocking hull volume to serve a space nothing can reach
## would be risk with no payoff. The third hole IS cut, because it is a drawing
## and not a collider: `BoatBody.add_deck_plate_aperture` re-meshes
## `HullVisual/Deck` around the liner, without which an open hatch shows the deck
## plate where the catch should be at every fill below brimful.
const HATCH_COVER_M := 0.06
## Target board width. The count is derived from the hatch so a 2 m hold gets
## boards a person could lift, not one slab and not twenty battens.
const HATCH_BOARD_M := 0.62
## The player capsule's diameter — `scenes/shared/player.tscn`, radius 0.35.
## An open slot narrower than this is a slot a player cannot fall through, and
## that is the whole safety argument for opening the hatch at all.
const PLAYER_CAPSULE_DIAMETER_M := 0.70
## How much narrower than the player an open slot is held. Small on purpose: the
## board pitch that already shipped (0.62) clears it, so the margin does not move
## any hatch that exists, it states why 0.62 is allowed to.
const HATCH_SLOT_MARGIN_M := 0.08
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
var _hatch_open := false
## The WalkDeck shapes `DeckFitout` built from `_solid`, in the same order, handed
## back so the boards can MOVE when the hatch is worked. Not re-derived here: the
## consumer that put them on the body is the one that knows where the hold sits
## on it, and a second derivation of that is exactly the drift REALITY §3b is
## about. Empty on a hold with no vessel (the showcase), which is why every user
## of this list tolerates it being empty rather than requiring it.
var _colliders: Array[CollisionShape3D] = []
var _collider_origin := Vector3.ZERO


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
		_sync_colliders()


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


## PERSISTENCE DOES NOT EXIST YET, AND THAT IS WHY `_hatch_open` IS NOT SAVED
## — surveyed 2026-08-16, when the hatch became a precondition on landing.
##
## The question asked was "if landing depends on the hatch, does the hatch have
## to survive a reload?" The answer is that NOTHING about this hold survives a
## reload. Grepped: this function and `BoatBody.get_catch_hold_states()` — the
## two halves of a save/restore pair — have **zero callers outside this file and
## `boat_body.gd`**, in `scripts/` and in `tests/` alike; `SAVE_FORMAT.md` does
## not mention a hold or a catch; and nothing in `scripts/state/` or
## `scripts/network/` reads either. So a reloaded vessel comes back with an empty
## hold, and persisting the lid of a box whose contents evaporate would be
## cosmetic in the exact sense the question was asking about (REALITY §3d — a
## value with no consumer is not delivered; here it is a whole seam).
##
## When catch persistence is built, `_hatch_open` belongs in the same dictionary
## as the lots, for a reason worth writing down now: a hold that reloads SHUT
## with catch in it is a boat that silently refuses to land, and the refusal
## points at a hatch the player never closed.
func apply_state(data: Dictionary) -> void:
	state = CatchHoldState.from_dict(data)
	state.hold_id = hold_id
	state.capacity_kg = capacity_kg
	if not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)
	_on_state_changed(state)


## THE BOARDS ARE A PRECONDITION, NOT A DECORATION — 2026-08-16.
##
## `29e5e2a` made the hatch openable and wired it to the player and to nothing
## else, and said so in its own commit message. Surveyed: SEVEN decision points
## in four production systems move catch or decide whether catch can be moved,
## and NOT ONE of them asked whether the boards were up —
## `FishingSystem._try_start_haul` and `_complete_one_haul_crate`,
## `FishLandingPump.start_unload`, `_transfer_mass` and `_ship_connection_world`,
## and `FishLandingEquipmentJob.can_serve` and `serve_hint`. The pump's is the
## sharpest: it hangs its hose on `get_hose_drop_world()`, a point 0.38 m INSIDE
## the pit, and pumped four tonnes through solid steel while reporting success.
##
## THE GATE LIVES HERE, at the one seam every mover goes through, and the callers
## ASK FIRST with `is_hatch_open()` so they can say something a player can act
## on. That is not two derivations: `is_hatch_open()` is this node's own answer in
## both places (REALITY §3b). What is here is the BACKSTOP — it makes a caller
## that forgets to ask loud instead of silent, which is the whole complaint
## against the behaviour it replaces.
##
## IT REFUSES. It does not auto-open and it does not queue.
##   • Auto-opening moves the deck. A lifted board is drawn one pitch aft and one
##     thickness up and IT KEEPS ITS COLLIDER (`_sync_colliders`), so opening the
##     hatch moves a surface a deckhand may be standing on. Nothing but the
##     player may do that to the deck under the player.
##   • Queueing leaves the trawl streaming into a hold that is not taking fish,
##     which is the silent success this replaces wearing the other face.
## A silent refusal would be no better, so every caller pairs its refusal with a
## line naming the lever: `FishingSystem` toasts it, `FishLandingEquipmentJob`
## publishes it as a serve hint, and `ShipHud`'s FISH HOLD cell stands it up as a
## standing blocker.
func accept_lot(lot: CatchLot) -> CatchLot:
	if not _hatch_open:
		push_warning(
			"CatchHoldComponent '%s': refusing catch through a SHUT hatch. " % hold_id
			+ "Ask is_hatch_open() before offering a lot; the lot is returned whole."
		)
		return lot if lot != null else CatchLot.new()
	var before := state.total_mass_kg()
	var overflow := state.accept_lot(lot)
	if not is_equal_approx(before, state.total_mass_kg()):
		fill_changed.emit(state)
	return overflow


## Same gate, same aperture. The landing hose comes down through the boards; a
## shut hatch stops fish leaving exactly as it stops fish arriving.
func withdraw_oldest(max_mass_kg: float) -> Array[CatchLot]:
	if not _hatch_open:
		push_warning(
			"CatchHoldComponent '%s': refusing to discharge through a SHUT hatch. " % hold_id
			+ "Ask is_hatch_open() before withdrawing; nothing was removed."
		)
		return [] as Array[CatchLot]
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


## Half-extent of the coaming's CLEAR opening — the rectangle the boards span.
func _hatch_opening_half() -> Vector2:
	var c := _coaming_half()
	return Vector2(maxf(c.x - COAMING_WALL_M, 0.05), maxf(c.y - COAMING_WALL_M, 0.05))


## The widest a board — and therefore the widest an OPEN SLOT — may be.
## Stated against the player rather than against taste: `HATCH_BOARD_M` is what
## a board should look like, and the capsule term is what it may not exceed.
func _hatch_board_pitch_max() -> float:
	return minf(HATCH_BOARD_M, PLAYER_CAPSULE_DIAMETER_M - HATCH_SLOT_MARGIN_M)


## How many boards span this hatch. CEIL, not round: rounding lets a hatch just
## under 1.5 boards long take two boards of 0.775 m each, which is wider than the
## player and would open a slot a person falls through.
func hatch_board_count() -> int:
	return maxi(2, ceili(_hatch_opening_half().y * 2.0 / _hatch_board_pitch_max()))


## Clear fore-and-aft width of one open slot, in metres. The number the safety
## argument turns on; `catch_hold_test` reads it back off PhysicsServer3D rather
## than off this function.
func hatch_slot_width_m() -> float:
	return _hatch_opening_half().y * 2.0 / float(hatch_board_count())


## The rectangle of DECK this hold needs cut out of the hull's plate, in
## hold-local XZ metres. It is the liner's outer face, so the plate's cut edge
## and the liner's outer skin are the same line — no ledge to see, no gap.
func hatch_aperture_m() -> Rect2:
	var l := _liner_half()
	return Rect2(-l.x, -l.y, l.x * 2.0, l.y * 2.0)


## Which boards come up when the hatch is worked: every other one. That is what
## keeps an open slot ONE board wide however long the hatch is — no two slots are
## ever adjacent, so the 19 m hatch on `hull_150x32` opens into 15 separate
## 0.61 m slots rather than into a hole.
func _board_is_lifted(i: int) -> bool:
	return i % 2 == 1


func is_hatch_open() -> bool:
	return _hatch_open


func toggle_hatch() -> void:
	set_hatch_open(not _hatch_open)


## Work the hatch. The boards are REDRAWN in their new places and the shapes on
## the vessel follow them in the same call, so there is no frame in which what a
## player stands on and what a player sees disagree.
func set_hatch_open(open: bool) -> void:
	if open == _hatch_open:
		return
	_hatch_open = open
	if is_inside_tree():
		_build_visual()
		_sync_colliders()
	hatch_changed.emit(_hatch_open)


## Take ownership of the WalkDeck shapes built from `_solid`, in `_solid` order.
## `boat_local_origin` is where this hold sits on the vessel — the offset
## `DeckFitout` already applied when it placed them.
func adopt_colliders(shapes: Array, boat_local_origin: Vector3) -> void:
	_colliders.clear()
	for shape in shapes:
		var cs := shape as CollisionShape3D
		if cs != null:
			_colliders.append(cs)
	_collider_origin = boat_local_origin


## Re-point every adopted shape at the box its mesh was just drawn from. The
## count and the order are invariant across hatch states BY CONSTRUCTION — a
## board that is lifted is drawn somewhere else, never dropped — so this is a
## positional update and not a rebuild, and a count mismatch is a defect worth
## refusing loudly rather than papering over.
func _sync_colliders() -> void:
	if _colliders.is_empty():
		return
	if _boat == null or not is_instance_valid(_boat):
		_boat = _find_boat()
	if _boat == null:
		return
	if _colliders.size() != _solid.size():
		push_warning(
			"CatchHoldComponent: %d adopted colliders against %d drawn boxes — the "
			% [_colliders.size(), _solid.size()]
			+ "hatch will not be what you stand on. Refusing to move them."
		)
		return
	for i in _solid.size():
		var cs := _colliders[i]
		if cs == null or not is_instance_valid(cs):
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		box.size = _solid[i]["size"] as Vector3
		cs.position = _boat.boat_to_walk_deck_local(
			_collider_origin + (_solid[i]["pos"] as Vector3)
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


## Names of the roots this function owns. Everything else parented to the hold —
## the `HoldHatch` that works it, the state binding under that — is somebody
## else's and MUST survive a rebuild.
##
## This is not tidiness. `_ready` calls `_build_visual` and `_ready` fires when
## the hold's parent enters the tree, which is AFTER `DeckFitout` has attached
## the hatch during a deferred fit-out — so a blanket `for child in
## get_children(): free()` deleted the hatch on every vessel whose fit-out ran
## before the boat was in the tree. Measured: 11 of 11 holds carried no hatch.
const OWNED_ROOTS := ["OpenRswFishHold", "FishAndChilledWater"]


func _build_visual() -> void:
	for child in get_children():
		if not OWNED_ROOTS.has(str(child.name)):
			continue
		remove_child(child)
		child.queue_free()
	_solid.clear()
	var hold := Node3D.new()
	hold.name = "OpenRswFishHold"
	add_child(hold)
	var steel := Color(0.34, 0.39, 0.42)
	## PALE, and that changed today. The liner used to be (0.025, 0.045, 0.055) —
	## near black — chosen when nothing could ever see it, to "read as a volume
	## below deck" from a cutaway. Now that the hatch opens, that colour is what a
	## player looks at: photographed through an open slot at 25% fill the hold was
	## a black hole with nothing in it, because the chilled water is 0.8 m down
	## and no light reaches a narrow slot at a quarter angle. A real insulated
	## fish hold is white for hygiene; a white one is also legible.
	var inner := Color(0.80, 0.82, 0.80)
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
	var open := _hatch_opening_half()
	var boards := hatch_board_count()
	var board_z := hatch_slot_width_m()
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
		var laid := Vector3(0.0, board_y, -open.y + (float(i) + 0.5) * board_z)
		var at := laid
		if _hatch_open and _board_is_lifted(i):
			## Lifted and laid ON the board it slides over: one pitch back, one
			## thickness up, which puts the stowed board's top flush with the
			## coaming rim rather than proud of it. It is still drawn and still
			## solid — a stowed board is a thing on the deck, and a cover that
			## simply vanished would be the "collides with nothing" defect
			## wearing the other face.
			at = Vector3(0.0, board_y + HATCH_COVER_M, laid.z - board_z)
		_add_solid(
			hold,
			at,
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
