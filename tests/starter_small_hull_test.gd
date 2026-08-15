extends Node

## Lane B — it drives `VesselSpawn` and `BoatBody`, which name autoloads, and it
## needs a real physics space.
##
## THE CLAIM THIS UNIT HOLDS
##
## Until 2026-08-15 the whole fleet stood on two hulls, `hull_28x10` (28 m) and
## `hull_45x16_cat` (45 m), and every legacy alias collapsed onto one of them.
## The owner's three reference vessels are ~22 m, ~22 m and ~15 m, so **the
## game's smallest boat was larger than every boat it was modelled on** and a
## beginner's first vessel was a 28 m coastal trader. `hull_15x5` exists to close
## that, and this unit exists so that closing cannot silently re-open.
##
## WHY IT IS WRITTEN AGAINST "THE SMALLEST REGISTERED HULL" AND NOT AGAINST AN ID
##
## REALITY.md §4a: assert the property, not the number. The property a beginner
## cares about is "the catalogue offers me a hull my size", which is a statement
## about `HullRegistry.catalog()` as a whole. Pinning the id would let someone
## delete every other small hull, or add a smaller broken one, without moving a
## check. So SUBJECT is resolved by measurement — the shortest `loa_m` in the
## registry — and every later section then interrogates whatever that turned out
## to be. The one place an id appears is the comparison against `hull_28x10`,
## because "smaller than the floor that used to exist" is literally the claim.
##
## WHY IT GOES THROUGH THE WORLD AND NOT THROUGH THE PROFILE
##
## REALITY.md §3: assert against the path that can break. A hull's declared
## `draft_m` is a field; whether it FLOATS there is the output of strip-theory
## integration, a mass ledger, a rigid body and a water surface, and those four
## can disagree with the field without anybody noticing. Likewise "a player can
## stand on it" is answered by `PhysicsServer3D` against the body
## `VesselSpawn -> apply_plan -> _ensure_walk_deck` actually built, never by the
## deck-grid dictionary — the dictionary is right in every failure mode that
## matters.
##
## AND WHY §4 IS HERE AT ALL
##
## `HullPhysicsProfile.make_stations()` now CLAMPS a profile `validate()` has
## rejected instead of returning null. That guard is correct and it is also a
## trap for an author: a hull with an impossible draft or an impossible
## displacement still builds, still floats, and still renders — on numbers it was
## never given. §4 therefore asserts the profile is clean AND that
## `stations_geometry()` did not clamp, so a hull that only works because the
## rescue caught it fails here rather than shipping.

const TestReport := preload("res://tests/support/test_report.gd")

## The design target: the smallest of the owner's three reference vessels is
## ~15 m, so a starter hull has to reach that end of the range. The bound is
## slack (a 16 m or 14 m redesign passes); what it forbids is the state this
## unit was written in, where the floor was 28 m.
const BEGINNER_LOA_CEILING_M := 16.0
const OLD_FLOOR_HULL := "hull_28x10"

## Settling tolerance. The declared draft is the number every other system
## consumes; a hull that swims a decimetre off it is mis-declared, not noisy.
const DRAFT_TOLERANCE_M := 0.05
const SETTLE_FRAMES := 480
## `HullStations.from_form` warns above 1 %; `hull_form_geometry_test` uses 1.5 %.
const VOLUME_TOLERANCE := 0.01

## scenes/shared/player.tscn — CapsuleShape3D radius 0.35, height 1.8.
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.8
## Dropped from clear air this far above the deck, so `cast_motion` can never be
## answering "began inside something" (REALITY §3's cast_motion trap).
const DROP_START_M := 3.0
const DROP_LENGTH_M := 6.0
## A foot landing this far from the build plane is not standing on the deck.
const FOOT_TOLERANCE_M := 0.40

var _t := TestReport.new("starter_small_hull_test")
var _hull_id := ""


func _ready() -> void:
	WaveSurface.fft_system = null
	WaveSurface.clear_sample_cache()
	if _check_registry():
		await _check_floats_where_declared()
		await _check_a_player_can_stand_on_it()
	_t.finish(get_tree())


# ── 1 · it is in the registry, and it is the small one ──────────────────────

func _check_registry() -> bool:
	var entries := HullRegistry.catalog()
	if not _t.check("HullRegistry.catalog() returns hulls", not entries.is_empty()):
		return false

	var smallest := {}
	for entry in entries:
		if smallest.is_empty() or float(entry.get("loa_m", 1e9)) < float(smallest.get("loa_m", 1e9)):
			smallest = entry
	_hull_id = str(smallest.get("id", ""))
	var loa := float(smallest.get("loa_m", 0.0))

	## THE claim: a beginner is offered a hull at the small end of the reference
	## range. Fails the moment the small hull leaves the catalogue, because the
	## next-shortest is then 28 m.
	_t.check(
		"the registry offers a beginner-sized hull — shortest is %s at %.1f m, must be <= %.1f m"
		% [_hull_id, loa, BEGINNER_LOA_CEILING_M],
		loa <= BEGINNER_LOA_CEILING_M,
	)
	var old_floor := HullRegistry.get_by_id(OLD_FLOOR_HULL)
	_t.check(
		"the fleet floor moved — %s (%.1f m) is shorter than %s (%.1f m)"
		% [_hull_id, loa, OLD_FLOOR_HULL, float(old_floor.get("loa_m", 0.0))],
		loa < float(old_floor.get("loa_m", 0.0)),
	)
	## It must be REACHABLE the way the game reaches hulls, not merely present in
	## the array: id resolution, grid construction and hull building are the three
	## entry points every consumer of `HullRegistry` goes through.
	_t.equal(
		"the id round-trips through network resolution",
		HullRegistry.resolve_network_hull_id(_hull_id),
		_hull_id,
	)
	_t.check("HullRegistry.is_known_hull agrees", HullRegistry.is_known_hull(_hull_id))
	return not _hull_id.is_empty()


# ── 2, 3, 4 · it floats where it says it does, on the tonnage it declares ────

func _check_floats_where_declared() -> void:
	var boat := HullRegistry.build_hull(_hull_id)
	if not _t.check("the small hull builds: %s" % _hull_id, boat != null):
		return
	boat.name = "StarterHullFloat"
	boat.automatic_physics_lod = false
	add_child(boat)

	var profile: HullPhysicsProfile = boat.physics_profile
	if not _t.check("the built hull carries a physics profile", profile != null):
		boat.free()
		return

	## §4 · CLEAN, not clamp-rescued. Both halves are needed: `validate()` empty
	## is the contract, and `clamped == false` is the proof that
	## `make_stations()` took the authored numbers rather than the guard's.
	var errors := profile.validate()
	_t.check(
		"the profile validates cleanly (%s)"
		% ("no errors" if errors.is_empty() else "; ".join(errors)),
		errors.is_empty(),
	)
	_t.check(
		"the stations are built from AUTHORED geometry, not the invalid-profile clamp",
		not bool(profile.stations_geometry().get("clamped", true)),
	)

	var stations: HullStations = boat.hull_stations
	if not _t.check("the hull has stations", stations != null and not stations.stations.is_empty()):
		boat.free()
		return

	## Displacement consistency: the buoyancy volume the strip integrator will
	## actually use at the declared draft, against the declared tonnage.
	var rho := profile.water_density
	var tonnes_below_design := stations.volume_below(boat.draft_m) * rho / 1000.0
	var volume_error := absf(tonnes_below_design - boat.displacement_t) / boat.displacement_t
	_t.check(
		"buoyancy volume below the declared draft weighs the declared displacement (%.3f t vs %.3f t, %.4f%%)"
		% [tonnes_below_design, boat.displacement_t, volume_error * 100.0],
		volume_error < VOLUME_TOLERANCE,
	)
	_t.near(
		"the rigid body's mass is the declared displacement",
		boat.mass, boat.displacement_t * 1000.0, 1.0,
	)

	## And now the part no field can answer: put it in the water and look.
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	for _frame in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	var settled_draft := WaveSurface.WATER_LEVEL - (boat.global_position.y + stations.keel_y)
	_t.check(
		"it settles at the draft it declares (%.4f m settled vs %.4f m declared, delta %+.4f m)"
		% [settled_draft, boat.draft_m, settled_draft - boat.draft_m],
		absf(settled_draft - boat.draft_m) < DRAFT_TOLERANCE_M,
	)
	_t.check(
		"it settles upright (heel %.3f deg, trim %.3f deg)"
		% [rad_to_deg(boat.rotation.z), rad_to_deg(boat.rotation.x)],
		absf(rad_to_deg(boat.rotation.z)) < 1.0 and absf(rad_to_deg(boat.rotation.x)) < 1.0,
	)
	## Not "it did not sink" — "it came to rest". A hull that is still moving
	## after eight seconds of flat water has not floated, it is on its way
	## somewhere.
	_t.check(
		"it comes to rest rather than drifting up or down (|v| %.4f m/s)"
		% boat.linear_velocity.length(),
		boat.linear_velocity.length() < 0.05,
	)
	boat.free()
	await get_tree().process_frame


# ── 5 · a 1.8 m player can stand on it, per PhysicsServer3D ──────────────────

func _check_a_player_can_stand_on_it() -> void:
	var boat: BoatBody = VesselSpawn.instantiate(_hull_id, {}, "")
	if not _t.check("VesselSpawn builds the small hull", boat != null):
		return
	boat.name = "StarterHullStand"
	boat.automatic_physics_lod = false
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	## One frame for the deferred WalkDeck re-parent / collision enable, one for
	## the physics server to be holding the shapes.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if not _t.check("the hull has a WalkDeck body", walk != null):
		boat.free()
		return
	_t.check(
		"the WalkDeck carries shapes in PhysicsServer3D (%d)"
		% PhysicsServer3D.body_get_shape_count(walk.get_rid()),
		PhysicsServer3D.body_get_shape_count(walk.get_rid()) > 0,
	)

	var space := walk.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	var grid := HullRegistry.make_grid(_hull_id)
	_t.check(
		"the deck grid is buildable (%d x %d cells, %d-cell 45-degree bow)"
		% [grid.width, grid.length, grid.bow_taper_cells],
		grid.width >= 4 and grid.length >= 8
			and grid.bow_taper_cells == int(grid.width / 2),
	)
	var deck_y_world := boat.to_global(Vector3(0.0, grid.deck_y, 0.0)).y

	## The control comes FIRST and is asserted, because a query that says "solid"
	## everywhere proves nothing: over open water, 40 m off the beam, the same
	## capsule on the same mask must fall the whole way.
	_t.near(
		"the same drop over open water finds nothing (the query can say no)",
		_drop(space, capsule, boat.to_global(Vector3(-40.0, grid.deck_y + DROP_START_M, 0.0))),
		1.0, 0.001,
	)

	var samples := 0
	var landed := 0
	var worst := 0.0
	for iz in [1, grid.length / 4, grid.length / 2, (grid.length * 3) / 4, grid.length - 2]:
		for ix in [0, grid.width / 2, grid.width - 1]:
			if grid.cell_shape(int(ix), int(iz)) != DeckGrid.CellShape.FULL:
				continue
			samples += 1
			var cell := grid.cell_center_local(Vector3i(int(ix), 0, int(iz)))
			var from := boat.to_global(
				Vector3(cell.x, grid.deck_y + DROP_START_M, cell.z)
			)
			var fraction := _drop(space, capsule, from)
			if fraction >= 0.999:
				continue
			var foot_y := from.y + PLAYER_HEIGHT * 0.5 - fraction * DROP_LENGTH_M - PLAYER_HEIGHT * 0.5
			if absf(foot_y - deck_y_world) <= FOOT_TOLERANCE_M:
				landed += 1
			worst = maxf(worst, absf(foot_y - deck_y_world))
	_t.check("the sweep sampled deck cells (%d)" % samples, samples >= 8)
	_t.equal(
		"a 1.8 m capsule dropped on every sampled deck cell lands on the deck (worst offset %.3f m)"
		% worst,
		landed, samples,
	)

	## Standing on that surface must not be standing INSIDE it.
	var stand := boat.to_global(
		Vector3(0.0, grid.deck_y + 0.25 + PLAYER_HEIGHT * 0.5, 0.0)
	)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, stand)
	params.collision_mask = BoatBody.LAYER_BOAT_WALK
	_t.equal(
		"a player standing on the build plane is not embedded in it",
		space.intersect_shape(params, 4).size(), 0,
	)
	boat.free()
	await get_tree().process_frame


## Fraction of DROP_LENGTH_M a player capsule falls from `from` (its CENTRE)
## before the walk layer stops it. 1.0 means nothing stopped it.
## Returns 1.0 without querying if the capsule starts overlapping — a
## `cast_motion` from inside a body returns a clean 1.0 and would be scored as
## "walked straight through" (REALITY §3).
func _drop(
	space: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, from: Vector3
) -> float:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, from + Vector3(0.0, PLAYER_HEIGHT * 0.5, 0.0))
	params.collision_mask = BoatBody.LAYER_BOAT_WALK
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if not space.intersect_shape(params, 1).is_empty():
		_t.check("drop start at %v is clear air, not inside a body" % from, false)
		return 1.0
	params.motion = Vector3(0.0, -DROP_LENGTH_M, 0.0)
	return space.cast_motion(params)[0]
