extends Node

## Lane B — it drives `VesselSpawn`, `FishingSystem` and `FishLandingPump`, all
## of which name autoloads.
##
## Sections 1-6 are the hold as DATA: lots, capacity, FIFO, landing value, the
## mass it contributes to its vessel, and the shore transfer.
##
## Section 7 is the hold as a THING ON A BOAT, added 2026-08-15, and it is the
## one with a defect behind it. `DeckFitout` used to mount the hold at a
## hull-independent size and position — `scale = Vector3(1.10, 1.0, 2.10)` and
## `gear_local + inward_z * 6.1` — so the same drawing landed on every hull that
## carried a trawl winch. On `hull_15x5` (half-beam 2.50 m) the pump flange stood
## **1.130 m outboard of the deck edge, over open water**, the coaming overhung
## the bow by 0.157 m, and on BOTH shipped fishing vessels the hatch sat under
## the wheelhouse. It was photographed before it was measured
## (`screenshots/vessels/starter/starter__bow_on_ortho.png`).
##
## The check is deliberately not "the footprint equals 3.0 x 2.0" — that would
## restate the derivation and go green on the next hull (REALITY §4a). It states
## the property: **every corner of every mesh the hold draws stands over a cell
## this hull calls FULL deck**, which is one sentence that covers the beam, the
## bow taper and both deck ends, on a hull nobody has authored yet. A second
## states that no built brick column stands inside the hatch, which is the
## "inside the wheelhouse" half.
##
## It runs over every prebuilt vessel AND over a synthetic fishing layout on
## every hull in `HullRegistry.catalog()`, because the two that were broken were
## not the one being worked on (REALITY §3c).

const TestReport := preload("res://tests/support/test_report.gd")

var _t := TestReport.new("catch_hold_test")


func _ready() -> void:
	_test_lot_round_trip()
	_test_capacity_and_overflow()
	_test_fifo_withdrawal()
	_test_landing_quote()
	_test_component_mass_and_discovery()
	await _test_shore_rsw_transfer_and_capacity()
	await _test_official_trawler_runtime()
	await _test_the_hold_fits_the_boat()
	_t.finish(get_tree())


func _test_lot_round_trip() -> void:
	var lot := CatchLot.create({
		"lot_id": "haul-1",
		"mass_kg": 275.0,
		"caught_game_hours": 42.5,
		"caught_position": [120.0, -88.0],
		"ground_tier": "rich",
		"price_multiplier": 1.75,
		"vessel_id": "vessel-1",
	})
	var restored := CatchLot.from_dict(lot.to_dict())
	_t.check("lot id survives serialization", restored.lot_id == "haul-1")
	_t.check("lot mass survives serialization", is_equal_approx(restored.mass_kg, 275.0))
	_t.check(
		"catch position survives serialization",
		restored.caught_position == Vector2(120.0, -88.0),
	)


func _test_capacity_and_overflow() -> void:
	var state := CatchHoldState.new()
	state.hold_id = "hold-a"
	state.capacity_kg = 500.0
	var overflow := state.accept_lot(CatchLot.create({"lot_id": "a", "mass_kg": 650.0}))
	_t.check("hold clamps accepted catch to capacity", is_equal_approx(state.total_mass_kg(), 500.0))
	_t.check("hold returns exact overflow", is_equal_approx(overflow.mass_kg, 150.0))
	var restored := CatchHoldState.from_dict(state.to_dict())
	_t.check("hold inventory survives serialization", is_equal_approx(restored.total_mass_kg(), 500.0))


func _test_fifo_withdrawal() -> void:
	var state := CatchHoldState.new()
	state.capacity_kg = 1000.0
	state.accept_lot(CatchLot.create({"lot_id": "old", "mass_kg": 300.0, "caught_game_hours": 1.0}))
	state.accept_lot(CatchLot.create({"lot_id": "new", "mass_kg": 400.0, "caught_game_hours": 3.0}))
	var taken := state.withdraw_oldest(450.0)
	_t.check("withdrawal spans lots when requested", taken.size() == 2)
	_t.check("oldest catch leaves first", taken[0].lot_id == "old")
	_t.check("withdrawal removes requested mass", is_equal_approx(state.total_mass_kg(), 250.0))


func _test_landing_quote() -> void:
	var state := CatchHoldState.new()
	state.capacity_kg = 2000.0
	state.accept_lot(CatchLot.create({
		"lot_id": "market",
		"mass_kg": 1000.0,
		"quality": 0.8,
		"price_multiplier": 1.5,
	}))
	var quote := FishingLandingService.quote([state])
	_t.check("landing quote weighs catch", is_equal_approx(float(quote.get("mass_kg", 0.0)), 1000.0))
	_t.check("landing quote applies quality and ground value", int(quote.get("value_marks", 0)) == 288)


func _test_component_mass_and_discovery() -> void:
	var boat := BoatBody.new()
	boat.name = "TestBoat"
	boat.displacement_t = 20.0
	add_child(boat)
	var hold := CatchHoldComponent.new()
	hold.name = "CatchHold"
	hold.configure("primary", 1000.0)
	boat.add_child(hold)
	var before := boat.get_total_mass_kg()
	hold.accept_lot(CatchLot.create({"lot_id": "mass", "mass_kg": 600.0}))
	_t.check("boat discovers its catch hold", boat.get_catch_holds().size() == 1)
	_t.check("catch contributes to vessel payload mass", boat.get_total_mass_kg() >= before + 599.0)
	var fishing := FishingSystem.new()
	fishing.name = "FishingSystem"
	boat.add_child(fishing)
	fishing.set("_haul_zone", {"tier_id": "normal", "tier_label": "Normal", "price_mul": 1.0})
	var completed := bool(fishing.call("_complete_one_haul_crate"))
	_t.check("trawl haul deposits into the dedicated catch hold", completed)
	_t.check(
		"trawl adds weighed catch rather than containers",
		is_equal_approx(hold.state.total_mass_kg(), 850.0),
	)
	boat.remove_child(fishing)
	fishing.free()
	boat.remove_child(hold)
	hold.free()
	remove_child(boat)
	boat.free()


func _test_shore_rsw_transfer_and_capacity() -> void:
	var boat := BoatBody.new()
	boat.name = "LandingTestBoat"
	boat.freeze = true
	add_child(boat)
	var hold := CatchHoldComponent.new()
	hold.name = "CatchHold"
	hold.configure("landing-hold", 1000.0)
	boat.add_child(hold)
	hold.accept_lot(CatchLot.create({
		"lot_id": "landing-lot",
		"species_id": "herring",
		"mass_kg": 800.0,
		"quality": 0.9,
	}))

	var bank := ShoreRswTankBank.new()
	bank.name = "TestShoreRswBank"
	bank.capacity_kg = 600.0
	add_child(bank)
	var pump := FishLandingPump.new()
	pump.name = "TestFishLandingPump"
	pump.connect_seconds = 0.01
	pump.flush_seconds = 0.01
	pump.pump_rate_kg_s = 1000.0
	add_child(pump)
	pump.bind_receiver(bank)
	await get_tree().process_frame
	_t.check("landing pump accepts a trawler with catch", pump.start_unload(boat))
	var hose := pump.get_node_or_null("FlexibleSuctionHose") as Node3D
	_t.check("landing hose deploys when unloading starts", hose != null and hose.visible)
	pump.stop()
	_t.check("manual stop retracts the landing hose", hose != null and not hose.visible)
	_t.check("landing pump can restart after a manual stop", pump.start_unload(boat))
	pump.set_process(false)
	for i in range(20):
		pump.call("_process", 0.1)
		if pump.state_label() == FishLandingPump.STATE_COMPLETE:
			break
	_t.check(
		"shore RSW bank receives catch up to capacity",
		is_equal_approx(bank.total_mass_kg(), 600.0),
	)
	_t.check(
		"catch beyond shore capacity remains aboard",
		is_equal_approx(hold.state.total_mass_kg(), 200.0),
	)
	_t.check(
		"pump finishes cleanly when shore tanks fill",
		pump.state_label() == FishLandingPump.STATE_COMPLETE,
	)
	_t.check("completed unloading retracts the landing hose", hose != null and not hose.visible)
	var stored := bank.withdraw_oldest(600.0)
	_t.check(
		"shore storage preserves catch lot identity",
		stored.size() == 1 and stored[0].lot_id == "landing-lot",
	)

	remove_child(pump)
	pump.free()
	remove_child(bank)
	bank.free()
	boat.remove_child(hold)
	hold.free()
	remove_child(boat)
	boat.free()


func _test_official_trawler_runtime() -> void:
	var record: Dictionary = {}
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			record = entry
			break
	_t.check("official fishing trawler exists", not record.is_empty())
	if record.is_empty():
		return
	var vessel_name := str(record.get("prebuilt_name", record.get("display", "Fishing trawler")))
	var owned_record := VesselSpawn.normalize_record({
		"uid": VesselSpawn.new_vessel_uid(str(record.get("hull_id", VesselSpawn.TRAWLER_SMALL_ID))),
		"hull_id": str(record.get("hull_id", VesselSpawn.TRAWLER_SMALL_ID)),
		"registration_id": str(record.get("registration_id", "fishing_vessel")),
		"name": vessel_name,
		"display": vessel_name,
		"shaft_power_kw": float(record.get("shaft_power_kw", 1871.0)),
		"brick_layout": (record.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
	})
	var boat := VesselSpawn.instantiate_from_record(owned_record)
	_t.check("official fishing trawler record is deployable", boat != null)
	if boat == null:
		return
	add_child(boat)
	await get_tree().process_frame
	await get_tree().process_frame
	var systems := boat.get_fishing_systems()
	var holds := boat.get_catch_holds()
	_t.check("official trawler mounts one live fishing system", systems.size() == 1)
	_t.check("official trawler mounts one insulated catch hold", holds.size() == 1)
	if systems.size() == 1 and holds.size() == 1:
		var system: FishingSystem = systems[0]
		boat.freeze = true
		system.catch_interval_seconds = 0.01
		system.apply_trawl_desired(true)
		system.call("_physics_process", 0.02)
		system.call("_physics_process", 0.01)
		_t.check("official trawler reports active fishing", system.get_activity_status() == "ACTIVE")
		_t.check(
			"official trawler receives catch data",
			is_equal_approx(holds[0].state.total_mass_kg(), 250.0),
		)
	remove_child(boat)
	boat.free()


# ── 7 · the hold fits the boat it is mounted on ─────────────────────────────

## Clearance a corner of drawn hold geometry is allowed to sit outside the deck
## cell it stands over. Zero would be the honest bound; this absorbs the float
## noise of a transform chain and nothing else. The defect it replaced was
## 1.130 m, three orders of magnitude out.
const OVERHANG_EPSILON_M := 0.005


func _test_the_hold_fits_the_boat() -> void:
	var surveyed := 0
	for entry_raw in PrebuiltVesselCatalog.catalog_entries():
		var entry := entry_raw as Dictionary
		var layout := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
		surveyed += await _hold_geometry_on(
			str(entry.get("prebuilt_id", "?")),
			str(entry.get("hull_id", "")),
			str(entry.get("registration_id", "fishing_vessel")),
			layout,
			true,
		)
	## Then a hull nobody has built a preset for. Every hull in the registry gets
	## the painted starter deck plus a winch — the shape a player produces on a
	## hull the fleet does not ship — because the two vessels that were broken
	## were not the one being worked on (REALITY §3c).
	for hull_raw in HullRegistry.catalog():
		var hull_id := str((hull_raw as Dictionary).get("id", ""))
		var grid := HullRegistry.make_grid(hull_id)
		if grid == null:
			continue
		var synthetic := _synthetic_fishing_layout(hull_id, grid)
		if synthetic.is_empty():
			continue
		var seen := await _hold_geometry_on(
			"synthetic:%s" % hull_id, hull_id, "fishing_vessel", synthetic, false
		)
		## Asserted, not counted: a synthetic vessel that mounts NO hold makes
		## every geometry check above it a loop over nothing (REALITY §4).
		_t.check(
			"synthetic:%s: a placed trawl winch mounts a catch hold" % hull_id,
			seen >= 1,
		)
		surveyed += seen
	## The survey has to have found holds at all, or every check above it is a
	## loop over nothing reporting success (REALITY §4).
	_t.check(
		"the fit survey actually measured catch holds (%d)" % surveyed, surveyed >= 2
	)


## Spawns one vessel and measures every hold it mounts. Returns how many it saw.
##
## `owned` picks the entry point. A shipped preset goes through
## `instantiate_from_record`, which is what onboarding and the ledger call and
## which REFUSES a record that is not compliance-ok. A synthetic deck is not a
## legal registration — no nav lights, no mooring points — so it goes through
## `VesselSpawn.instantiate`, one layer below that gate and the same call
## `starter_small_hull_test` uses. Both reach `DeckFitout.apply` and the same
## `_mount_fishing`, which is the code under test; neither is a test-only path.
func _hold_geometry_on(
	label: String,
	hull_id: String,
	registration_id: String,
	layout: Dictionary,
	owned: bool,
) -> int:
	if hull_id.is_empty() or layout.is_empty():
		return 0
	var boat: BoatBody = null
	if owned:
		boat = VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({
			"uid": VesselSpawn.new_vessel_uid(hull_id),
			"hull_id": hull_id,
			"registration_id": registration_id,
			"name": label,
			"display": label,
			"brick_layout": layout,
		}))
	else:
		boat = VesselSpawn.instantiate(hull_id, layout, registration_id)
	if boat == null:
		return 0
	boat.freeze = true
	boat.automatic_physics_lod = false
	add_child(boat)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := HullRegistry.make_grid(hull_id)
	var holds := CatchHoldComponent.get_all_for_ship(boat)
	var built := BrickLayout.from_dict(layout)
	var seen := 0
	for hold in holds:
		seen += 1
		_check_one_hold(label, hold, boat, grid, built)
	remove_child(boat)
	boat.free()
	await get_tree().process_frame
	return seen


func _check_one_hold(
	label: String,
	hold: CatchHoldComponent,
	boat: BoatBody,
	grid: DeckGrid,
	layout: BrickLayout,
) -> void:
	## Filled FIRST, because the chilled water and the fish scatter are drawn only
	## when there is catch aboard — an empty hold hides a third of its own
	## geometry from any measurement, and a scatter sized for a 28 m trawler
	## hanging through a 15 m boat's liner is the same bug one scale down.
	hold.accept_lot(CatchLot.create({"lot_id": "fit-check", "mass_kg": 3900.0}))

	## THE property. Every corner of every mesh the hold COMMITTED, in boat-local
	## metres, has to stand over a cell this hull calls FULL deck. Read off the
	## MeshInstance3Ds rather than off `footprint_m`, because the bug was
	## geometry escaping its own declared size: the pump flange reached 0.42 m
	## further outboard than anything in `DeckFitout` accounted for.
	var corners := _drawn_corners(hold, boat)
	if not _t.check(
		"%s: the mounted hold draws geometry (%d corners)" % [label, corners.size()],
		corners.size() >= 8,
	):
		return
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var off_deck := 0
	for corner in corners:
		var cell := grid.local_to_cell(Vector3(corner.x, grid.deck_y, corner.z))
		if grid.cell_shape(cell.x, cell.z) == DeckGrid.CellShape.FULL:
			continue
		## How far outside the deck it reached, so the failure carries a number
		## rather than a count. Measured against this hull's own half-beam and
		## half-length, which is what makes the check survive a new hull.
		var out := maxf(
			absf(corner.x) - grid.half_beam, absf(corner.z) - grid.half_loa
		)
		if out > worst:
			worst = out
			worst_at = corner
		off_deck += 1
	_t.check(
		(
			"%s: no corner of the hold hangs off the deck"
			+ " (%d of %d corners off, worst %.3f m at %v, half-beam %.3f)"
		) % [label, off_deck, corners.size(), worst, worst_at, grid.half_beam],
		off_deck == 0 or worst <= OVERHANG_EPSILON_M,
	)

	## The guarantee the component's own header makes — "`footprint_m` is the
	## OUTER extent of everything this node draws" — held to (REALITY §3c). This
	## is not the same statement as the one above and it is not implied by it:
	## the derivation leaves a 0.50 m walkway on every side, so geometry can
	## escape its declared size by up to that much and still stand on real deck.
	## Reinstating the old manifold, which reached 0.42 m past where `DeckFitout`
	## thought the hold ended, is invisible to the off-deck check and RED here.
	var box := _drawn_bounds(_drawn_corners(hold, hold))
	var declared := hold.footprint_m
	_t.check(
		(
			"%s: the drawn hold stays inside its declared footprint"
			+ " (x %.3f..%.3f in +-%.3f, z %.3f..%.3f in +-%.3f)"
		) % [
			label, box.position.x, box.end.x, declared.x * 0.5,
			box.position.z, box.end.z, declared.z * 0.5,
		],
		box.position.x >= -declared.x * 0.5 - OVERHANG_EPSILON_M
			and box.end.x <= declared.x * 0.5 + OVERHANG_EPSILON_M
			and box.position.z >= -declared.z * 0.5 - OVERHANG_EPSILON_M
			and box.end.z <= declared.z * 0.5 + OVERHANG_EPSILON_M,
	)

	## The other half of "it fits": the hatch has to be on OPEN deck. A hold
	## whose coaming is buried in the wheelhouse is not reachable, and both
	## shipped fishing vessels were in exactly that state.
	var deck_box := _drawn_bounds(corners)
	var intruders := PackedStringArray()
	for key in layout.cells:
		var cell := BrickLayout.parse_key(str(key))
		var centre := grid.cell_center_local(Vector3i(cell.x, 0, cell.z))
		if centre.x < deck_box.position.x or centre.x > deck_box.end.x:
			continue
		if centre.z < deck_box.position.z or centre.z > deck_box.end.z:
			continue
		var brick_id := str((layout.cells[key] as Dictionary).get("brick_id", "?"))
		if not intruders.has(brick_id):
			intruders.append(brick_id)
	_t.check(
		"%s: nothing is built inside the hold's hatch (%s)"
		% [label, "clear" if intruders.is_empty() else " ".join(intruders)],
		intruders.is_empty(),
	)

	## And a 1.8 m deckhand can stand at the hatch side to work it — through
	## PhysicsServer3D on the body the fit-out actually built, not through the
	## grid dictionary (REALITY §3).
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk == null:
		_t.check("%s: the vessel has a WalkDeck to stand on" % label, false)
		return
	var space := walk.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var clear_sides := 0
	var sides := [
		Vector3(deck_box.position.x - 0.55, 0.0, (deck_box.position.z + deck_box.end.z) * 0.5),
		Vector3(deck_box.end.x + 0.55, 0.0, (deck_box.position.z + deck_box.end.z) * 0.5),
		Vector3((deck_box.position.x + deck_box.end.x) * 0.5, 0.0, deck_box.position.z - 0.55),
		Vector3((deck_box.position.x + deck_box.end.x) * 0.5, 0.0, deck_box.end.z + 0.55),
	]
	for at in sides:
		var cell := grid.local_to_cell(Vector3(at.x, grid.deck_y, at.z))
		if grid.cell_shape(cell.x, cell.z) != DeckGrid.CellShape.FULL:
			continue
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = capsule
		params.transform = Transform3D(
			Basis.IDENTITY,
			boat.to_global(Vector3(at.x, grid.deck_y + 0.25 + 0.9, at.z)),
		)
		params.collision_mask = BoatBody.LAYER_BOAT_WALK
		if space.intersect_shape(params, 1).is_empty():
			clear_sides += 1
	_t.check(
		"%s: a 1.8 m deckhand can stand at the hatch (%d of 4 sides clear)"
		% [label, clear_sides],
		clear_sides >= 1,
	)


## Every corner of every visible mesh under the hold, expressed in `frame`'s
## local metres — the boat for the deck checks, the hold itself for the
## declared-footprint check.
func _drawn_corners(hold: CatchHoldComponent, frame: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var to_boat := frame.global_transform.affine_inverse()
	for node in hold.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var local := mi.get_aabb()
		var xf := to_boat * mi.global_transform
		for i in range(8):
			out.append(xf * local.get_endpoint(i))
	return out


func _drawn_bounds(corners: Array[Vector3]) -> AABB:
	var out := AABB(corners[0], Vector3.ZERO)
	for corner in corners:
		out = out.expand(corner)
	return out


## The painted starter deck plus a helm and a trawl winch, on any hull. This is
## what a player who buys a bare hull and places fishing gear ends up with, and
## it is the only way to put a hold on a hull the fleet ships no preset for.
func _synthetic_fishing_layout(hull_id: String, grid: DeckGrid) -> Dictionary:
	var layout := BrickLayout.starter_cargo(hull_id, grid)
	var helm_at := _first_clear(layout, grid, "helm", grid.length / 2, -1)
	if helm_at.x >= 0:
		layout.place_footprint(helm_at, "helm", 0, grid)
	var winch_at := _first_clear(layout, grid, "trommel_small", grid.length / 2, 1)
	if winch_at.x < 0:
		return {}
	if not layout.place_footprint(winch_at, "trommel_small", 0, grid):
		return {}
	return layout.to_dict()


## First cell from `z_start`, walking in `step`, where `brick_id`'s footprint
## fits on the centreline with nothing already on it.
func _first_clear(
	layout: BrickLayout, grid: DeckGrid, brick_id: String, z_start: int, step: int
) -> Vector3i:
	var fp := BrickCatalog.footprint_of(brick_id)
	var x := maxi((grid.width - fp.x) / 2, 0)
	var iz := z_start
	while iz >= 0 and iz + fp.z <= grid.length:
		var ok := true
		for c in grid.footprint_cells(Vector3i(x, 0, iz), fp, 0):
			if not grid.in_bounds(c) or layout.has_cell(c):
				ok = false
				break
		if ok:
			return Vector3i(x, 0, iz)
		iz += step
	return Vector3i(-1, -1, -1)
