extends Node
## No meshes, physics, player saves, network server or scene-owned inventory.
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const VESSELS = preload("res://scripts/port/state/custom_port_vessel_projection.gd")
var failures: Array[String] = []
var checks := 0
var sequence := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Custom port tests require --shipyard-playtest isolation.")
		get_tree().quit(1)
		return
	_test_validation()
	_test_wire_precision()
	_test_projection_cache()
	_test_docking_and_cargo()
	_test_unit_capacity()
	_test_crane_handling()
	_test_vessel_projections()
	_test_bulk_compartments()
	_test_attached_stores()
	_test_survey_expansion()
	_test_store_configuration()
	_test_plots_and_construction()
	_test_replay()
	check(checks >= 100, "all test scenarios reached their assertions")
	print("CUSTOM PORT DATA %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_wire_precision() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19737
	var numbers: Array = []
	var drifting := 0.0
	for index in 2048:
		var number := rng.randf_range(-40000.0, 40000.0) * rng.randf()
		var parsed: float = JSON.parse_string(JSON.stringify(number, "", true, true))
		numbers.append(number)
		if JSON.stringify(number) != JSON.stringify(parsed): drifting = number
	check(drifting != 0, "precision fixture reproduces a computed double whose JSON roundtrip changed the old receipt hash")
	var original := {"samples": numbers, "attributes": {"precise_value": drifting, "name": "Keep me unchanged", "enabled": true}, "negative_zero": -0.0}
	var canonical: Dictionary = STATE._canonical(original)
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(canonical, "", true, true))
	check(canonical == decoded and canonical == STATE._canonical(canonical), "full-precision numeric wire normalization is stable across coastal-scale samples")
	check(canonical.attributes.name == original.attributes.name and canonical.attributes.enabled == true, "numeric normalization preserves custom strings and booleans")
	var state := _fresh()
	var base := state.to_dict()
	var command := {"command_id": "precision-placement", "expected_revision": state.revision(), "actor_company_id": "company-a", "kind": "place_asset", "payload": {
		"placement": _placement("precision-lamp", "lamp", 0, 8, {"custom_value": drifting, "support_depth_m": absf(drifting) / 20.0 + 1.0})}}
	var applied := state.apply(command)
	check(applied.ok, "computed custom attributes can be placed through authority")
	if not applied.ok: return
	var save: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true))
	var restored := _fresh(save)
	check(restored.to_dict() == state.to_dict(), "full snapshot equals its save/load reconstruction exactly")
	var retry: Dictionary = JSON.parse_string(JSON.stringify(command, "", true, true))
	check(restored.apply(retry).code == "already_applied", "computed numeric command retries remain idempotent after JSON transport and save")
	var replica := _fresh(base)
	var event: Dictionary = JSON.parse_string(JSON.stringify(applied.events[0], "", true, true))
	check(replica.replay_event(event).ok and replica.to_dict() == state.to_dict(), "JSON event replay reconstructs identical computed attributes")


func _test_projection_cache() -> void:
	var state := _fresh()
	var initial := state.to_dict()
	var expected := state.derived_berths()
	var exposed := state.construction_edges()
	check(expected == CustomPortBerths.derive(initial, _catalog()), "cached berth projection equals fresh geometry")
	check(exposed == CustomPortBerths.construction_edges(initial, _catalog()), "construction edge cache uses identical validated boundaries")
	var borrowed := state.derived_berths()
	borrowed[0].max_length_m = 99999
	var borrowed_edges := state.construction_edges()
	borrowed_edges[0].length = 99999
	check(state.derived_berths() == expected and state.construction_edges() == exposed, "mutable projection copies cannot corrupt authority caches")
	var dock := _command(state, "dock", {"vessel_id": "ship-a", "berth_id": expected[0].id})
	check(dock.ok, "cache fixture docks")
	var invalid := state.preview_asset(_placement("break-occupied-berth", "bollard", -20, -19), "company-a")
	check(not invalid.ok and state.derived_berths() == expected, "invalid speculative berth split cannot overwrite committed projection")
	var removed := _command(state, "remove_asset", {"placement_id": "bollard-c"})
	check(removed.ok and state.derived_berths().size() == 1, "construction revision replaces cached berths")
	var replay := _fresh(initial)
	check(replay.replay_event(dock.events[0]).ok and replay.replay_event(removed.events[0]).ok and replay.derived_berths() == state.derived_berths(), "event reconstruction updates cached projection with the same revision")
	for action in [["reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"coal-lot","quantity":400,"reservation_id":"cached-trip"}],
		["load_cargo",{"reservation_id":"cached-trip"}],["unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"coal-lot","quantity":400}],
		["undock",{"vessel_id":"ship-a"}]]:
		var response:=_command(state,action[0],action[1])
		check(response.ok,"Cargo remains valid after a rejected structural preview and accepted berth edit")
		if not response.ok:continue
		var cold:=_fresh(state.to_dict())
		check(cold.validation_errors.is_empty() and cold.to_dict()==state.to_dict(),"Cached command equals an uncached full document validation")
		check(cold.derived_berths()==state.derived_berths() and cold.construction_edges()==state.construction_edges(),"Cargo-only revisions preserve exactly the freshly derived construction")
		check(replay.replay_event(response.events[0]).ok and replay.to_dict()==state.to_dict(),"Cached cargo event reconstruction remains identical")
	# The current cache cannot excuse malformed geometry in an imported document.
	var broken:=state.to_dict()
	broken.placements[0].position_m[1]=1
	check(not _fresh(broken).validation_errors.is_empty(),"Fresh import still rejects a platform above the common plane")
	broken=state.to_dict();broken.water_regions[0].depth_m=.1
	var shallow:=_fresh(broken)
	check(shallow.validation_errors.is_empty() and not CustomPortBerths.fit(shallow.derived_berths()[0],broken.vessels[0]).ok,"Fresh shallow-water survey never inherits an older safe berth")


func _catalog() -> Dictionary:
	return {
		"quay": {"footprint_m": [100, 40], "kind": "platform", "berth_edge": true, "placement_layer": "platform", "placement_kind": "platform"},
		"bollard": {"footprint_m": [1, 1], "kind": "bollard", "mooring": true, "placement_layer": "equipment", "requires_support": true},
		"crane": {"footprint_m": [4, 4], "kind": "crane", "placement_layer": "equipment", "requires_support": true,
			"reach_max_m": 55, "reach_min_m": 3, "crane_offset_m": [0, 0], "cargo_types": ["container", "bulk", "catch", "general"]},
		"yard": {"footprint_m": [20, 14], "placement_layer": "equipment", "requires_support": true},
		"paving": {"footprint_m": [4, 4], "kind": "platform", "placement_layer": "platform", "placement_kind": "platform"},
		"lamp": {"footprint_m": [1, 1], "placement_layer": "equipment", "requires_support": true}}


func _placement(id: String, asset: String, x: float, z: float, attributes: Dictionary = {}) -> Dictionary:
	return {"id": id, "asset_id": asset, "position_m": [x, 0, z], "yaw_degrees": 0, "attributes": attributes}


func _vessel(id: String, length: float = 18, draft: float = 2, capacity: float = 6000, owner: String = "company-a") -> Dictionary:
	return {"id": id, "owner_company_id": owner, "length_m": length, "beam_m": 5,
		"draft_m": draft, "capacity_kg": capacity, "lots": [], "berth_id": ""}


func _fixture() -> Dictionary:
	return {"schema_version": 1, "id": "port-a", "name": "Data Harbour", "owner_company_id": "company-a",
		"world": {"seed": 44, "generation_version": 7, "checksum": "test-coast"},
		"origin_m": [1000, 0, 2000], "deck_height_above_sea_m": 2,
		"plots": [{"id": "plot-a", "rect_m": [-100, -100, 200, 200], "owner_company_id": "company-a"}],
		"placements": [_placement("quay-1", "quay", 0, 0), _placement("bollard-a", "bollard", -40, -19),
			_placement("bollard-b", "bollard", 0, -19), _placement("bollard-c", "bollard", 40, -19),
			_placement("crane-1", "crane", -20, -8, {"store_ids": ["yard"]}),
			_placement("crane-2", "crane", 20, -8, {"store_ids": ["yard"]}), _placement("pad-1", "yard", -20, 5)],
		"water_regions": [{"rect_m": [-100, -160, 200, 140], "depth_m": 8}],
		"stores": [{"id": "yard", "placement_id": "pad-1", "capacity_kg": 20000,
			"accepted_commodities": ["coal", "steel"], "public_loading": true, "public_unloading": true,
			"lots": [{"id": "coal-lot", "commodity_id": "coal", "quantity": 10000, "unit_mass_kg": 1,
				"attributes": {"quality": 0.9, "origin_port_id": "mine", "value_nok_per_unit": 6}}]}],
		"vessels": [_vessel("ship-a"), _vessel("ship-b", 18, 2, 6000, "company-b"),
			_vessel("too-long", 80), _vessel("too-deep", 18, 10), _vessel("tiny-hold", 18, 2, 1000)],
		"reservations": []}


func _fresh(value: Dictionary = {}) -> CustomPortState:
	var fixture := _fixture() if value.is_empty() else value
	return STATE.from_dict(fixture, fixture.world, _catalog())


func _command(state: CustomPortState, kind: String, payload: Dictionary, actor: String = "company-a", context: Dictionary = {}) -> Dictionary:
	sequence += 1
	var result := state.apply({"command_id": "command-%d" % sequence,
		"expected_revision": state.to_dict().revision, "actor_company_id": actor, "kind": kind, "payload": payload}, context)
	return result


func _reject_unchanged(state: CustomPortState, kind: String, payload: Dictionary, code: String, actor: String = "company-a", context: Dictionary = {}) -> Dictionary:
	var before := state.to_dict()
	var result := _command(state, kind, payload, actor, context)
	check(not result.ok and result.code == code, "%s rejected as %s (got %s: %s)" % [kind, code, result.code, result.get("details", {})])
	check(before == state.to_dict(), "%s failure is atomic" % kind)
	check(result.events.is_empty() and result.account_changes.is_empty(), "%s failure publishes nothing" % kind)
	return result


func _test_validation() -> void:
	var state := _fresh()
	check(state.validation_errors.is_empty(), "valid document: %s" % [state.validation_errors])
	var document := state.to_dict()
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(document))
	check(_fresh(round_trip).validation_errors.is_empty(), "JSON round trip validates")
	check(_fresh(round_trip).to_dict() == document, "JSON preserves complete document")
	document.placements[0].position_m[0] = 9999
	check(state.to_dict().placements[0].position_m[0] == 0, "snapshots cannot mutate source state")
	var bad := _fixture()
	bad.stores[0].lots[0].quantity = -1
	check(not _fresh(bad).validation_errors.is_empty(), "negative stock is invalid")
	bad = _fixture()
	bad.stores[0].lots[0].quantity = 30000
	check(not _fresh(bad).validation_errors.is_empty(), "over-capacity initial stock is invalid")
	bad = _fixture()
	bad.placements.append(bad.placements[0].duplicate(true))
	check(not _fresh(bad).validation_errors.is_empty(), "duplicate placement identity is invalid")
	bad = _fixture()
	bad.placements[0].position_m[0] = NAN
	check(not _fresh(bad).validation_errors.is_empty(), "non-finite coordinates are invalid")
	bad = _fixture()
	bad.placements[0].position_m = Vector3.ZERO
	check(not _fresh(bad).validation_errors.is_empty(), "native Vector3 cannot enter a JSON document")
	check(not STATE.from_dict(_fixture(), {"seed": 99}, _catalog()).validation_errors.is_empty(), "wrong world cannot be injected")
	bad = _fixture()
	bad.plots = [{"id": "left", "rect_m": [-100, -100, 80, 200], "owner_company_id": "company-a"},
		{"id": "right", "rect_m": [20, -100, 80, 200], "owner_company_id": "company-a"}]
	check(not _fresh(bad).validation_errors.is_empty(), "placement cannot span an unowned gap despite owned corners")
	for key in ["kind", "footprint_m", "reach_max_m", "requires_support"]:
		bad = _fixture()
		bad.placements[4].attributes[key] = false if key == "requires_support" else 99999
		check(not _fresh(bad).validation_errors.is_empty(), "placement cannot override trusted catalogue %s" % key)
	bad = _fixture()
	bad.stores[0].public_loading = "false"
	check(not _fresh(bad).validation_errors.is_empty(), "string false cannot grant public loading")
	bad = _fixture()
	bad.water_regions = "deep enough"
	check(not _fresh(bad).validation_errors.is_empty(), "malformed bathymetry rejected")
	bad = _fixture()
	bad.placements[4].attributes.store_ids = true
	check(not _fresh(bad).validation_errors.is_empty(), "malformed store link rejected before geometry")


func _test_docking_and_cargo() -> void:
	var state := _fresh()
	var berths := state.derived_berths()
	check(berths.size() == 2, "three edge bollards produce two independent berths: %s" % [berths])
	if berths.size() != 2:
		return
	var berth_a := str(berths[0].id)
	var berth_b := str(berths[1].id)
	check("yard" in berths[0].store_ids, "crane links reachable yard to berth")
	_reject_unchanged(state, "dock", {"vessel_id": "ship-b", "berth_id": berth_a}, "not_vessel_owner")
	_reject_unchanged(state, "dock", {"vessel_id": "too-long", "berth_id": berth_a}, "vessel_does_not_fit")
	_reject_unchanged(state, "dock", {"vessel_id": "too-deep", "berth_id": berth_a}, "vessel_does_not_fit")
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth_a}).ok, "18 m vessel docks")
	var malformed := _placement("bad-node", "bollard", 10, 0)
	malformed.yaw_degrees = {"bad": true}
	_reject_unchanged(state, "place_asset", {"placement": malformed}, "invalid_result")
	_reject_unchanged(state, "dock", {"vessel_id": "ship-b", "berth_id": berth_a}, "vessel_does_not_fit", "company-b")
	check(_command(state, "dock", {"vessel_id": "ship-b", "berth_id": berth_b}, "company-b").ok, "second company independently docks second berth")
	_reject_unchanged(state, "remove_asset", {"placement_id": "bollard-a"}, "berth_in_use")
	_reject_unchanged(state, "remove_asset", {"placement_id": "pad-1"}, "placement_has_store")
	var shortage := _reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 12000}, "insufficient_stock")
	check(shortage.details.get("available") == 10000, "shortage reports actual available stock, never manufactures it")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 7000}, "vessel_capacity_exceeded")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": -100}, "invalid_quantity")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 6000, "reservation_id": "booking-a"}).ok, "reserve finite stock and ship capacity")
	_reject_unchanged(state, "edit_assets", {"operations": [
		{"kind": "remove_asset", "payload": {"placement_id": "crane-1"}},
		{"kind": "remove_asset", "payload": {"placement_id": "crane-2"}}]}, "invalid_result")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "coal-lot", "quantity": 5000}, "insufficient_stock", "company-b")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "coal-lot", "quantity": 4000, "reservation_id": "booking-b"}, "company-b").ok, "remaining stock can be reserved by second company")
	_reject_unchanged(state, "undock", {"vessel_id": "ship-a"}, "cargo_reserved")
	_reject_unchanged(state, "load_cargo", {"reservation_id": "booking-a"}, "not_reservation_owner", "company-c")
	check(_command(state, "load_cargo", {"reservation_id": "booking-a"}).ok, "load reserved cargo")
	check(_command(state, "load_cargo", {"reservation_id": "booking-b"}, "company-b").ok, "load remainder exactly once")
	var loaded := state.to_dict()
	check(loaded.stores[0].lots.is_empty(), "empty source lot removed")
	check(loaded.vessels[0].lots[0].quantity == 6000 and loaded.vessels[1].lots[0].quantity == 4000, "no lost or duplicated cargo")
	check(loaded.vessels[0].lots[0].attributes.quality == 0.9, "cargo metadata survives transfer")
	_reject_unchanged(state, "load_cargo", {"reservation_id": "booking-a"}, "reservation_not_found")
	_reject_unchanged(state, "unload_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 6001}, "insufficient_cargo")
	check(_command(state, "unload_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 6000}).ok, "unload back into finite stock")
	check(_command(state, "unload_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "coal-lot", "quantity": 4000}, "company-b").ok, "combine same lot without changing its identity")
	check(state.to_dict().stores[0].lots[0].quantity == 10000, "round voyage conserves every unit")
	check(_command(state, "undock", {"vessel_id": "ship-a"}).ok, "empty vessel leaves berth")
	check(_command(state, "undock", {"vessel_id": "ship-b"}, "company-b").ok, "second vessel leaves berth")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 1}, "not_docked")
	var dry := _fixture()
	dry.erase("water_regions")
	var unsafe := _fresh(dry)
	var unverified := unsafe.derived_berths()
	check(not unverified.is_empty(), "unknown bathymetry keeps berth visible for inspection")
	if not unverified.is_empty():
		_reject_unchanged(unsafe, "dock", {"vessel_id": "ship-a", "berth_id": unverified[0].id}, "vessel_does_not_fit")


func _test_unit_capacity() -> void:
	var fixture := _fixture()
	fixture.stores[0].lots = [{"id": "boxes", "commodity_id": "steel", "quantity": 6, "unit_mass_kg": 1000,
		"attributes": {"whole_units": true, "container_type": "20ft", "slots_per_unit": 1}}]
	fixture.stores[0].capacity_units = 6
	fixture.vessels[0].capacity_units = 2
	var state := _fresh(fixture)
	check(state.validation_errors.is_empty(), "container-slot fixture valid")
	var berths := state.derived_berths()
	if berths.is_empty():
		return
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berths[0].id}).ok, "two-slot ship docks")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 3}, "vessel_slots_exceeded")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 0.5}, "invalid_quantity")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 1, "reservation_id": "first-slot"}).ok, "reserve first physical slot")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 2}, "vessel_slots_exceeded")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 1, "reservation_id": "second-slot"}).ok, "reserve second physical slot")
	check(_command(state, "load_cargo", {"reservation_id": "first-slot"}).ok, "reserved slot becomes physical cargo")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 1}, "vessel_slots_exceeded")
	check(_command(state, "cancel_reservation", {"reservation_id": "second-slot"}).ok, "cancelled booking releases reserved slot")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 1, "reservation_id": "replacement"}).ok, "released slot can be reserved again")
	check(_command(state, "load_cargo", {"reservation_id": "replacement"}).ok, "fill exactly two slots")
	check(state.to_dict().vessels[0].lots[0].quantity == 2, "two slots contain two boxes despite spare weight capacity")
	var full_destination := fixture.duplicate(true)
	full_destination.vessels[0].lots = [{"id": "arriving", "commodity_id": "steel", "quantity": 1, "unit_mass_kg": 1000,
		"attributes": {"whole_units": true, "container_type": "20ft"}}]
	var arrivals := _fresh(full_destination)
	check(_command(arrivals, "dock", {"vessel_id": "ship-a", "berth_id": berths[0].id}).ok, "loaded vessel arrives at full yard")
	_reject_unchanged(arrivals, "unload_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "arriving", "quantity": 1}, "store_slots_exceeded")
	var forty := fixture.duplicate(true)
	forty.stores[0].lots[0].quantity = 3
	forty.stores[0].lots[0].attributes.slots_per_unit = 2
	forty.stores[0].lots[0].attributes.container_type = "40ft"
	var long_boxes := _fresh(forty)
	check(_command(long_boxes, "dock", {"vessel_id": "ship-a", "berth_id": berths[0].id}).ok, "40ft scenario docks")
	check(_command(long_boxes, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 1}).ok, "one 40ft box consumes two configured slot units")
	_reject_unchanged(long_boxes, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "boxes", "quantity": 1}, "vessel_slots_exceeded")
	for marker in [{"indivisible": true}, {"container_type": "20ft"}]:
		var fractional := fixture.duplicate(true)
		fractional.stores[0].lots[0].attributes = marker
		fractional.stores[0].lots[0].quantity = 0.5
		check(not STATE.from_dict(fractional, fractional.world, _catalog()).validation_errors.is_empty(), "indivisible/container markers independently require whole quantity")
	for marker in [{"indivisible": "false"}, {"container_type": 20}]:
		var invalid := fixture.duplicate(true)
		invalid.stores[0].lots[0].attributes = marker
		check(not STATE.from_dict(invalid, invalid.world, _catalog()).validation_errors.is_empty(), "invalid cargo classification types rejected")
	for marker in [{"container_type": "20ft", "slots_per_unit": 0}, {"container_type": "40ft", "slots_per_unit": 1}, {"container_type": "unknown"}]:
		var spoofed := fixture.duplicate(true)
		spoofed.stores[0].lots[0].attributes = marker
		check(not _fresh(spoofed).validation_errors.is_empty(), "physical container classification cannot undercount or bypass slot capacity")
	forty.stores[0].lots[0].attributes.erase("slots_per_unit")
	check(STATE._lot_slots(forty.stores[0].lots[0]) == 2 and _fresh(forty).validation_errors.is_empty(), "40ft cargo derives two slots without a client-provided override")


func _test_crane_handling() -> void:
	var fixture := _fixture()
	fixture.stores[0].lots = [{"id": "boxes", "commodity_id": "steel", "quantity": 2, "unit_mass_kg": 1000, "attributes": {"container_type": "20ft"}}]
	var catalog := _catalog()
	catalog.crane.cargo_types = ["bulk"]
	var state := STATE.from_dict(fixture, fixture.world, catalog)
	var berth := str(state.derived_berths()[0].id)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "bulk-only crane does not prevent compatible mooring")
	_reject_unchanged(state, "reserve_cargo", {"vessel_id": "ship-a", "store_id": "yard", "lot_id": "boxes", "quantity": 1}, "crane_handling_not_supported")
	fixture.vessels[0].lots = [{"id": "arriving-box", "commodity_id": "steel", "quantity": 1, "unit_mass_kg": 1000, "attributes": {"container_type": "20ft"}}]
	state = STATE.from_dict(fixture, fixture.world, catalog)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "loaded container vessel can moor by bulk crane")
	_reject_unchanged(state, "unload_cargo", {"vessel_id": "ship-a", "store_id": "yard", "lot_id": "arriving-box", "quantity": 1}, "crane_handling_not_supported")
	catalog.container_crane = catalog.crane.duplicate(true)
	catalog.container_crane.cargo_types = ["container"]
	fixture.placements[5].asset_id = "container_crane"
	state = STATE.from_dict(fixture, fixture.world, catalog)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "mixed handling harbour admits container vessel")
	check(_command(state, "reserve_cargo", {"vessel_id": "ship-a", "store_id": "yard", "lot_id": "boxes", "quantity": 1, "reservation_id": "correct-crane"}).ok, "compatible second crane grants cargo access")
	_reject_unchanged(state, "remove_asset", {"placement_id": "crane-2"}, "invalid_result")
	var only_bulk := catalog.duplicate(true)
	only_bulk.container_crane.cargo_types = ["bulk"]
	check(not STATE.from_dict(state.to_dict(), fixture.world, only_bulk).validation_errors.is_empty(), "restored reservation requires a physically compatible handling service")
	var loaded := _command(state, "load_cargo", {"reservation_id": "correct-crane"})
	check(loaded.ok and loaded.result.get("crane_id") == "crane-2" and loaded.events[0].receipt.result.get("store_id") == "yard", "authority transfer event selects compatible crane for presentation")
	var unloaded := _command(state, "unload_cargo", {"vessel_id": "ship-a", "store_id": "yard", "lot_id": "boxes", "quantity": 1})
	check(unloaded.ok and unloaded.result.get("crane_id") == "crane-2", "unloading event carries the actual compatible crane")
	# Imported state cannot exceed the same limits applied to a newly placed yard.
	fixture = _fixture()
	catalog = _catalog()
	catalog.yard.attached_store = {"capacity_kg": 20000, "accepted_handling_modes": ["bulk"], "accepted_commodities": ["coal", "steel"]}
	fixture.stores[0].accepted_handling_modes = ["bulk"]
	check(STATE.from_dict(fixture, fixture.world, catalog).validation_errors.is_empty(), "catalog-bounded imported store validates")
	for change in [{"capacity_kg": 30000}, {"accepted_handling_modes": ["container"]}, {"accepted_handling_modes": []}, {"accepted_commodities": []}]:
		var tampered := fixture.duplicate(true)
		tampered.stores[0].merge(change, true)
		check(not STATE.from_dict(tampered, fixture.world, catalog).validation_errors.is_empty(), "snapshot cannot expand installed storage limits: " + str(change))
	var duplicated := fixture.duplicate(true)
	var second: Dictionary = duplicated.stores[0].duplicate(true)
	second.id = "same-pad-again"
	duplicated.stores.append(second)
	check(not STATE.from_dict(duplicated, fixture.world, catalog).validation_errors.is_empty(), "duplicate store records cannot multiply a single installed yard capacity")
	var excluded := fixture.duplicate(true)
	excluded.stores[0].accepted_commodities = ["steel"]
	check(not STATE.from_dict(excluded, fixture.world, catalog).validation_errors.is_empty(), "imported storage cannot contain goods excluded by its commodity filter")


func _test_vessel_projections() -> void:
	var fisher := VESSELS.from_prebuilt("fishing_hook_line", "ship-a", "company-a")
	var crabber := VESSELS.from_prebuilt("fishing_crab", "crabber", "company-a")
	var trader := VESSELS.from_prebuilt("28_10_m", "ship-a", "company-a", "Cargo", 48000)
	var bulk := VESSELS.from_prebuilt("coastal_coaster", "ship-a", "company-a")
	var feeder := VESSELS.from_prebuilt("container_feeder_40", "feeder", "company-a", "Feeder", 400000)
	check(not fisher.is_empty() and not trader.is_empty() and not bulk.is_empty() and not feeder.is_empty(), "real prebuilt projections load")
	if fisher.is_empty() or trader.is_empty() or bulk.is_empty() or feeder.is_empty():
		return
	check(fisher.length_m == 14 and fisher.beam_m == 5 and fisher.draft_m == 1.6, "fishing dimensions derive from actual hull catalog")
	check(fisher.capacity_kg == 600 and fisher.capacity_units == 0 and fisher.accepted_handling_modes == ["catch"], "one fish tank is 600kg catch storage and zero container beds")
	check(crabber.capacity_kg == 1200 and crabber.cargo_holds.size() == 2 and crabber.capacity_units == 0, "crabber has two catch tanks, not container slots")
	check(trader.length_m == 24 and trader.beam_m == 8 and trader.container_beds.size() == 2, "Harbour Cargo uses actual 24x8 hull and two authored beds")
	check(trader.accepted_container_types == ["20ft"] and trader.handling_capacity_kg.container == 48000, "20ft bed types and explicit scenario mass ceiling preserved")
	check(bulk.length_m == 32 and bulk.capacity_kg == 120000 and bulk.capacity_units == 0 and bulk.accepted_handling_modes == ["bulk"], "coaster has one 120t bulk hold and no container beds")
	check(feeder.length_m == 88 and feeder.container_beds.size() == 40, "feeder exposes all forty supported bed positions")
	var small := VESSELS.from_prebuilt("bulk_small", "bulk-small", "company-a")
	check(small.capacity_kg == 80000 and small.cargo_holds.size() == 2, "small bulk ship contains two existing 40t hold limits")
	check(VESSELS.from_prebuilt("../28_10_m", "x", "x").is_empty(), "prebuilt lookup rejects path traversal")
	var draft: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/28_10_m.json")).brick_layout
	var changed := draft.duplicate(true)
	for part in changed.parts:
		if part.asset_id == "container_bed_20ft": part.position[1] += 2
	check(VESSELS.from_layout("raised", "company-a", "hull_24x8", changed, 48000).capacity_units == 0, "floating authoring beds do not manufacture capacity")
	changed = draft.duplicate(true)
	for part in changed.parts:
		if part.asset_id == "container_bed_20ft": part.yaw_degrees = 90
	check(VESSELS.from_layout("rotated", "company-a", "hull_24x8", changed, 48000).capacity_units == 0, "unsupported rotated beds do not manufacture capacity")
	changed = draft.duplicate(true)
	changed.parts = changed.parts.filter(func(part: Dictionary) -> bool: return part.asset_id != "cargo_deck_5x8")
	check(VESSELS.from_layout("unsupported", "company-a", "hull_24x8", changed, 48000).capacity_units == 0, "ISO beds need their installed structural load deck")
	for vessel in [fisher, trader, bulk, feeder]:
		var fixture := _fixture()
		fixture.vessels = [vessel]
		var state := _fresh(JSON.parse_string(JSON.stringify(fixture)))
		check(state.validation_errors.is_empty(), "typed vessel projection survives JSON save")
	var fixture := _fixture()
	fixture.vessels = [fisher]
	var state := _fresh(fixture)
	var berth := str(state.derived_berths()[0].id)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "fishing boat can moor at general quay")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 1}, "handling_not_supported")
	fixture.vessels = [trader]
	fixture.stores[0].lots = [{"id": "box", "commodity_id": "steel", "quantity": 1, "unit_mass_kg": 1000, "attributes": {"container_type": "40ft", "slots_per_unit": 2}}]
	state = _fresh(fixture)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "actual cargo ship can moor")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "box", "quantity": 1}, "container_does_not_fit")
	fixture.stores[0].lots[0].attributes.container_type = "20ft"
	fixture.stores[0].lots[0].attributes.slots_per_unit = 1
	fixture.vessels = [fisher]
	state = _fresh(fixture)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "fishing boat docks near container stock")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "box", "quantity": 1}, "handling_not_supported")
	# A hypothetical mixed vessel proves holds cannot borrow each other's space.
	fixture.vessels[0].accepted_handling_modes = ["catch", "bulk"]
	fixture.vessels[0].handling_capacity_kg = {"catch": 600, "bulk": 600}
	fixture.vessels[0].capacity_kg = 1200
	fixture.stores[0].lots = [{"id": "fish", "commodity_id": "fresh_groundfish", "quantity": 1000, "unit_mass_kg": 1, "attributes": {}}]
	fixture.stores[0].accepted_commodities = []
	state = _fresh(fixture)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "mixed-capacity scenario docks")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "fish", "quantity": 500, "reservation_id": "catch-reserve"}).ok, "catch uses tank mass without consuming ISO slots")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "fish", "quantity": 101}, "handling_capacity_exceeded")
	check(_command(state, "load_cargo", {"reservation_id": "catch-reserve"}).ok, "typed catch reservation transfers to hold")
	check(state.to_dict().vessels[0].lots[0].quantity == 500, "physical fish mass represented in loaded manifest")
	fixture.vessels[0].accepted_handling_modes = true
	check(not _fresh(fixture).validation_errors.is_empty(), "malformed handling capability rejects without parser/runtime error")


func _test_bulk_compartments() -> void:
	var vessel := VESSELS.from_prebuilt("coastal_coaster", "ship-a", "company-a")
	var fixture := _fixture()
	fixture.vessels = [vessel]
	fixture.stores[0].accepted_commodities = []
	var first: Dictionary = fixture.stores[0].lots[0].duplicate(true)
	first.quantity = 1000
	var second := first.duplicate(true)
	second.id = "second-shipment"
	second.quantity = 2000
	fixture.stores[0].lots = [first, second]
	var aboard := first.duplicate(true)
	vessel.lots = [aboard]
	var state := _fresh(fixture)
	check(state.validation_errors.is_empty(), "one consignment fits the actual 120t hold")
	var berth := str(state.derived_berths()[0].id)
	check(_command(state, "dock", {"vessel_id":"ship-a", "berth_id":berth}).ok, "bulk compartment fixture docks")
	_reject_unchanged(state, "reserve_cargo", {"vessel_id":"ship-a", "store_id":"yard", "lot_id":"second-shipment", "quantity":1000}, "bulk_compartments_exceeded")
	check(_command(state, "reserve_cargo", {"vessel_id":"ship-a", "store_id":"yard", "lot_id":"coal-lot", "quantity":500, "reservation_id":"same-lot"}).ok, "same consignment can use remaining hold capacity")
	check(_command(state, "load_cargo", {"reservation_id":"same-lot"}).ok, "ordinary single-lot loading remains valid")
	var plan := STATE._bulk_plan(state.to_dict().vessels[0], state.to_dict().vessels[0].lots)
	check(plan.ok and is_equal_approx(plan.hold_states[0].filled_tonnes_t, 1.5), "accepted mass exactly reconstructs in the installed compartment")
	var invalid := fixture.duplicate(true)
	invalid.vessels[0].lots.append(second.duplicate(true))
	check(not _fresh(invalid).validation_errors.is_empty(), "import rejects same commodity with two consignments in one hold")
	invalid.vessels[0].lots[1].commodity_id = "iron_ore"
	invalid.stores[0].lots[1].commodity_id = "iron_ore"
	check(not _fresh(invalid).validation_errors.is_empty(), "import rejects mixed commodities in one hold")
	invalid = fixture.duplicate(true)
	invalid.stores[0].lots[1].commodity_id = "iron_ore"
	state = _fresh(invalid)
	check(_command(state, "dock", {"vessel_id":"ship-a", "berth_id":berth}).ok, "different-commodity fixture docks")
	_reject_unchanged(state, "reserve_cargo", {"vessel_id":"ship-a", "store_id":"yard", "lot_id":"second-shipment", "quantity":1000}, "bulk_compartments_exceeded")
	# Reservations occupy compartments as well as kilograms, before either loads.
	fixture.vessels[0].lots = []
	state = _fresh(fixture)
	check(_command(state, "dock", {"vessel_id":"ship-a", "berth_id":berth}).ok, "empty bulk vessel docks")
	check(_command(state, "reserve_cargo", {"vessel_id":"ship-a", "store_id":"yard", "lot_id":"coal-lot", "quantity":500, "reservation_id":"first"}).ok, "first reservation claims the single bulk compartment")
	_reject_unchanged(state, "reserve_cargo", {"vessel_id":"ship-a", "store_id":"yard", "lot_id":"second-shipment", "quantity":500}, "bulk_compartments_exceeded")
	invalid = state.to_dict()
	var conflict: Dictionary = invalid.reservations[0].duplicate(true)
	conflict.id = "conflicting-reservation"
	conflict.lot_id = "second-shipment"
	invalid.reservations.append(conflict)
	check(not _fresh(invalid).validation_errors.is_empty(), "import rejects over-reserved compartments despite spare aggregate mass")
	# The existing rules allow separate lots belonging to one explicit shipment.
	for lot in fixture.stores[0].lots: lot.attributes.consignment_id = "shared-voyage"
	fixture.vessels[0].lots = fixture.stores[0].lots.duplicate(true)
	state = _fresh(fixture)
	plan = STATE._bulk_plan(state.to_dict().vessels[0], state.to_dict().vessels[0].lots)
	check(state.validation_errors.is_empty() and plan.ok and is_equal_approx(plan.hold_states[0].filled_tonnes_t, 3), "two same-commodity lots with an explicit shared consignment fit one hold")
	# Real two-compartment fitout, including loading its reservations in reverse.
	fixture.vessels = [VESSELS.from_prebuilt("bulk_small", "ship-a", "company-a")]
	for lot in fixture.stores[0].lots: lot.attributes.erase("consignment_id")
	fixture.stores[0].lots[1].commodity_id = "iron_ore"
	state = _fresh(fixture)
	check(state.validation_errors.is_empty() and state.to_dict().vessels[0].cargo_holds.size()==2, "actual small bulk vessel exposes two separate holds")
	check(_command(state, "dock", {"vessel_id":"ship-a", "berth_id":berth}).ok, "two-compartment vessel docks")
	for lot in fixture.stores[0].lots:
		check(_command(state, "reserve_cargo", {"vessel_id":"ship-a", "store_id":"yard", "lot_id":lot.id, "quantity":lot.quantity, "reservation_id":lot.id}).ok, "separate hold accepts reservation for "+str(lot.commodity_id))
	check(_command(state, "load_cargo", {"reservation_id":"second-shipment"}).ok and _command(state, "load_cargo", {"reservation_id":"coal-lot"}).ok, "both dissimilar reservations can be loaded without losing either shipment")
	plan = STATE._bulk_plan(state.to_dict().vessels[0], state.to_dict().vessels[0].lots)
	check(plan.ok and plan.hold_states.size()==2 and is_equal_approx(plan.hold_states[0].filled_tonnes_t+plan.hold_states[1].filled_tonnes_t,3), "accepted manifest has both commodities in real separate compartments")
	check(_fresh(JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true))).validation_errors.is_empty(), "accepted mixed manifest and hold metadata survive JSON reconstruction")
	var separate_shipments := [first.duplicate(true), second.duplicate(true)]
	plan = VESSELS.bulk_hold_plan(fixture.vessels[0], separate_shipments)
	check(plan.ok and plan.hold_states[0].consignment_id != plan.hold_states[1].consignment_id, "two holds also separate same-commodity distinct consignments")
	separate_shipments[0].quantity = 60000
	plan = VESSELS.bulk_hold_plan(fixture.vessels[0], [separate_shipments[0]])
	check(plan.ok and is_equal_approx(plan.hold_states[0].filled_tonnes_t,40) and is_equal_approx(plan.hold_states[1].filled_tonnes_t,20), "one large shipment may span the two actual holds")
	check(not VESSELS.bulk_hold_plan(fixture.vessels[0], separate_shipments).ok, "20t aggregate free space is unavailable to another consignment when both compartments are occupied")
	var tiny := first.duplicate(true)
	tiny.quantity = 5
	check(not VESSELS.bulk_hold_plan(vessel, [tiny]).ok, "physical component epsilon cannot silently discard an accepted tiny manifest")
	for bad_holds in [true, [{}], [{"id":"bad", "handling_mode":"bulk", "capacity_kg":-1}], [vessel.cargo_holds[0],vessel.cargo_holds[0]]]:
		invalid = fixture.duplicate(true)
		invalid.vessels[0].cargo_holds = bad_holds
		check(not _fresh(invalid).validation_errors.is_empty(), "malformed physical hold metadata is rejected safely")
	invalid = fixture.duplicate(true)
	invalid.vessels[0].cargo_holds = []
	invalid.vessels[0].lots = [first.duplicate(true)]
	check(not _fresh(invalid).validation_errors.is_empty(), "explicitly missing physical bulk holds cannot claim aggregate capacity")


func _test_attached_stores() -> void:
	var catalog := _catalog()
	catalog.bundle = catalog.crane.duplicate(true)
	catalog.bundle.storage_rect_m = [-10, 6, 20, 8]
	catalog.bundle.attached_store = {"name": "New bulk yard", "capacity_kg": 5000, "accepted_handling_modes": ["bulk"],
		"accepted_commodities": ["coal"], "public_loading": false}
	var fixture := _fixture()
	fixture.vessels[0].lots = [{"id": "arriving-coal", "commodity_id": "coal", "quantity": 500, "unit_mass_kg": 1, "attributes": {}}]
	var state := STATE.from_dict(fixture, fixture.world, catalog)
	check(state.validation_errors.is_empty(), "attached-store scenario validates")
	var berth := str(state.derived_berths()[0].id)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "loaded visitor docks before player installs terminal")
	check(_command(state, "remove_asset", {"placement_id": "crane-1"}).ok, "old crane removed while other crane keeps existing yard served")
	var build := {"command_id": "new-terminal", "expected_revision": state.revision(), "actor_company_id": "company-a",
		"kind": "place_asset", "payload": {"placement": _placement("new-terminal", "bundle", -20, -8)}}
	var placed := state.apply(build)
	check(placed.ok, "placing a crane atomically creates its attached yard")
	if not placed.ok:
		return
	var stores: Array = state.to_dict().stores
	var created: Dictionary = stores.back()
	check(created.id == "store:new-terminal" and created.lots.is_empty() and created.capacity_kg == 5000, "new yard is finite, stable and contains no free stock")
	check(not created.public_loading and not created.public_unloading and created.accepted_handling_modes == ["bulk"], "new yard uses catalog handling and private company access")
	_reject_unchanged(state, "configure_store", {"store_id": created.id, "changes": {"accepted_commodities": ["steel"]}}, "unsupported_commodity_filter")
	check(state.apply(build).replayed and state.to_dict().stores.size() == stores.size(), "build retry cannot duplicate attached yard")
	check(_command(state, "unload_cargo", {"store_id": created.id, "vessel_id": "ship-a", "lot_id": "arriving-coal", "quantity": 100}).ok, "new player-built yard participates in cargo transfer")
	_reject_unchanged(state, "remove_asset", {"placement_id": "new-terminal"}, "placement_has_store")
	check(_command(state, "reserve_cargo", {"store_id": created.id, "vessel_id": "ship-a", "lot_id": "arriving-coal", "quantity": 100, "reservation_id": "recover-coal"}).ok, "new yard stock can be reserved")
	_reject_unchanged(state, "remove_asset", {"placement_id": "new-terminal"}, "placement_has_store")
	check(_command(state, "load_cargo", {"reservation_id": "recover-coal"}).ok, "withdraw all goods before dismantling terminal")
	check(_command(state, "remove_asset", {"placement_id": "new-terminal"}).ok and state.to_dict().stores.size() == stores.size() - 1, "empty terminal and attached yard are removed atomically")
	check(state.to_dict().vessels[0].lots[0].quantity == 500, "building and removal never create or delete cargo")
	var fake := created.duplicate(true)
	fake.lots = [{"id": "free-goods", "commodity_id": "coal", "quantity": 10, "unit_mass_kg": 1, "attributes": {}}]
	_reject_unchanged(state, "place_asset", {"placement": _placement("new-terminal", "bundle", -20, -8), "restore_empty_stores": [fake]}, "cannot_restore_stock")
	fake = created.duplicate(true)
	fake.capacity_kg = 999999
	_reject_unchanged(state, "place_asset", {"placement": _placement("new-terminal", "bundle", -20, -8), "restore_empty_stores": [fake]}, "invalid_attached_store_capacity")
	for depth in [-1, 0, 4096.1, "4", true]:
		var bad := _fixture()
		bad.placements[0].attributes.support_depth_m = depth
		check(not _fresh(bad).validation_errors.is_empty(), "invalid foundation support depth rejects: %s" % str(depth))
	var valid := _fixture()
	valid.placements[0].attributes.support_depth_m = 25.0
	check(_fresh(valid).validation_errors.is_empty(), "positive bounded seabed-derived foundation depth accepted")


func _test_survey_expansion() -> void:
	var fixture := _fixture()
	var source_regions: Array = fixture.water_regions.duplicate(true)
	fixture.erase("water_regions")
	var state := _fresh(fixture)
	var replica := _fresh(fixture)
	var context := {"water_survey": {"port_id": fixture.id, "world": fixture.world,
		"for_revision": state.revision(), "regions": source_regions}}
	_reject_unchanged(state, "refresh_water_survey", {}, "trusted_survey_required")
	_reject_unchanged(state, "refresh_water_survey", {"regions": source_regions}, "survey_payload_not_allowed", "company-a", context)
	_reject_unchanged(state, "refresh_water_survey", {}, "not_port_owner", "company-b", context)
	var bad := context.duplicate(true)
	bad.water_survey.port_id = "another-port"
	_reject_unchanged(state, "refresh_water_survey", {}, "survey_port_mismatch", "company-a", bad)
	bad = context.duplicate(true)
	bad.water_survey.world.seed = 99
	_reject_unchanged(state, "refresh_water_survey", {}, "survey_world_mismatch", "company-a", bad)
	bad = context.duplicate(true)
	bad.water_survey.for_revision = 20
	_reject_unchanged(state, "refresh_water_survey", {}, "survey_revision_mismatch", "company-a", bad)
	bad = context.duplicate(true)
	bad.water_survey.regions = true
	_reject_unchanged(state, "refresh_water_survey", {}, "invalid_survey_regions", "company-a", bad)
	var command := {"command_id": "initial-survey", "kind": "refresh_water_survey", "expected_revision": state.revision(),
		"actor_company_id": "company-a", "payload": {}}
	var surveyed := state.apply(command, context)
	check(surveyed.ok and surveyed.result.regions_added == 1, "trusted survey enables previously unsurveyed shore")
	if not surveyed.ok:
		return
	check(replica.replay_event(JSON.parse_string(JSON.stringify(surveyed.events[0]))).ok and replica.to_dict() == state.to_dict(), "survey event rebuilds identical bathymetry on receiver")
	check(state.apply(command, context).replayed and state.to_dict().water_regions.size() == 1, "survey retry does not duplicate water coverage")
	var berth := str(state.derived_berths()[0].id)
	check(_command(state, "dock", {"vessel_id": "ship-a", "berth_id": berth}).ok, "surveyed water admits fitting ship")
	context.water_survey.for_revision = state.revision()
	context.water_survey.regions = [{"rect_m": [100,-160,100,140], "depth_m": 9}]
	var grown := _command(state, "refresh_water_survey", {}, "company-a", context)
	check(grown.ok and grown.result.regions_added == 1 and state.to_dict().water_regions.size() == 2, "new coastal plot survey appends coverage")
	check(state.to_dict().water_regions[0] == surveyed.snapshot.water_regions[0] and state.to_dict().vessels[0].berth_id == berth, "extension preserves old survey and occupied berth")
	context.water_survey.for_revision = state.revision()
	context.water_survey.regions = source_regions
	var duplicate := _command(state, "refresh_water_survey", {}, "company-a", context)
	check(duplicate.ok and duplicate.result.regions_added == 0, "full-region resurvey safely deduplicates identical cells")
	context.water_survey.for_revision = state.revision()
	context.water_survey.regions[0].depth_m = 1
	_reject_unchanged(state, "refresh_water_survey", {}, "survey_depth_conflict", "company-a", context)
	context.water_survey.regions = [{"rect_m": [50,-160,100,140], "depth_m": 9}]
	_reject_unchanged(state, "refresh_water_survey", {}, "survey_overlap", "company-a", context)
	context.water_survey.regions = [{"rect_m": [200,-160,100,140], "depth_m": -1}]
	_reject_unchanged(state, "refresh_water_survey", {}, "invalid_survey_regions", "company-a", context)
	var wrong_kind: Dictionary = surveyed.events[0].duplicate(true)
	wrong_kind.kind = "place_asset"
	check(_fresh(fixture).replay_event(wrong_kind).code == "invalid_event_field", "ordinary event cannot carry depth changes")
	var erase_survey: Dictionary = grown.events[0].duplicate(true)
	erase_survey.changes.water_regions = []
	var prior := _fresh(grown.snapshot)
	# Give a new contiguous event identity so the replay must examine its content.
	erase_survey.command_id = "bad-survey"
	erase_survey.revision = prior.revision() + 1
	erase_survey.receipt.applied_revision = erase_survey.revision
	check(prior.replay_event(erase_survey).code == "invalid_survey_event", "survey replay cannot erase prior surveyed regions")


func _test_store_configuration() -> void:
	var fixture := _fixture()
	fixture.stores[0].public_loading = false
	fixture.stores[0].public_unloading = false
	fixture.vessels[1].lots = [{"id": "visitor-coal", "commodity_id": "coal", "quantity": 500, "unit_mass_kg": 1, "attributes": {}}]
	var state := _fresh(fixture)
	var berth := str(state.derived_berths()[1].id)
	check(_command(state, "dock", {"vessel_id": "ship-b", "berth_id": berth}, "company-b").ok, "visitor can dock before gaining storage access")
	_reject_unchanged(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "coal-lot", "quantity": 100}, "store_access_denied", "company-b")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"public_loading": true}}, "not_port_owner", "company-b")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"capacity_kg": 999999}}, "store_field_not_editable")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"accepted_handling_modes": ["catch"]}}, "store_field_not_editable")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"public_loading": "true"}}, "invalid_store_access")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"name": " \n "}}, "invalid_store_name")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"accepted_commodities": [true]}}, "invalid_commodity_filter")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"accepted_commodities": ["imaginary_unregistered_material"]}}, "unknown_commodity")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"accepted_commodities": ["steel"]}}, "store_contains_excluded_goods")
	var before := state.to_dict()
	var command := {"command_id": "open-yard", "expected_revision": state.revision(), "actor_company_id": "company-a", "kind": "configure_store",
		"payload": {"store_id": "yard", "changes": {"name": " North coal yard ", "public_loading": true, "accepted_commodities": ["coal"]}}}
	var opened := state.apply(command)
	check(opened.ok and state.to_dict().stores[0].name == "North coal yard", "owner opens and names terminal through one data command")
	check(state.apply(command).replayed, "configuration retry does not apply twice")
	var reconstructed := _fresh(before)
	check(reconstructed.replay_event(JSON.parse_string(JSON.stringify(opened.events[0]))).ok and reconstructed.to_dict() == state.to_dict(), "configuration event persists and reconstructs same store settings")
	check(_fresh(JSON.parse_string(JSON.stringify(state.to_dict()))).to_dict() == state.to_dict(), "configured terminal survives save/load")
	check(_command(state, "reserve_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "coal-lot", "quantity": 100, "reservation_id": "visitor-booking"}, "company-b").ok, "visitor can reserve once owner permits public loading")
	_reject_unchanged(state, "configure_store", {"store_id": "yard", "changes": {"public_loading": false}}, "store_has_visitor_reservation")
	check(_command(state, "cancel_reservation", {"reservation_id": "visitor-booking"}, "company-b").ok, "visitor releases reservation")
	check(_command(state, "configure_store", {"store_id": "yard", "changes": {"public_loading": false}}).ok, "terminal can close after reservations finish")
	_reject_unchanged(state, "unload_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "visitor-coal", "quantity": 100}, "store_access_denied", "company-b")
	check(_command(state, "configure_store", {"store_id": "yard", "changes": {"public_unloading": true}}).ok, "owner separately permits inbound deliveries")
	check(_command(state, "unload_cargo", {"store_id": "yard", "vessel_id": "ship-b", "lot_id": "visitor-coal", "quantity": 100}, "company-b").ok, "visitor can deliver to newly public receiving yard")
	check(_command(state, "configure_store", {"store_id": "yard", "changes": {"accepted_commodities": ["coal", "future_material"]}}, "company-a", {"commodity_ids": ["future_material"]}).ok, "authority commodity catalog can extend beyond built-in current goods")


func _test_plots_and_construction() -> void:
	var state := _fresh()
	var fixture := _fixture()
	var context := {"accounts": {"company-a": {"balance_nok": 5000}}, "plot_offers": {
		"plot-b": {"rect_m": [100, -100, 200, 200], "world": fixture.world, "price_nok": 3000, "available": true},
		"far": {"rect_m": [500, -100, 200, 200], "world": fixture.world, "price_nok": 3000, "available": true},
		"corner": {"rect_m": [100, 100, 200, 200], "world": fixture.world, "price_nok": 3000, "available": true}}}
	_reject_unchanged(state, "buy_plot", {"plot_id": "far"}, "plot_not_adjacent", "company-a", context)
	_reject_unchanged(state, "buy_plot", {"plot_id": "corner"}, "plot_not_adjacent", "company-a", context)
	_reject_unchanged(state, "buy_plot", {"plot_id": "plot-b"}, "not_port_owner", "company-b", context)
	var poor := context.duplicate(true)
	poor.accounts["company-a"].balance_nok = 100
	_reject_unchanged(state, "buy_plot", {"plot_id": "plot-b"}, "insufficient_funds", "company-a", poor)
	_reject_unchanged(state, "place_asset", {"placement": _placement("extra-pad", "paving", 120, 0)}, "invalid_result")
	var purchase := _command(state, "buy_plot", {"plot_id": "plot-b"}, "company-a", context)
	check(purchase.ok and purchase.account_changes[0].balance_nok == 2000, "adjoining plot bought at authority price")
	check(context.accounts["company-a"].balance_nok == 5000, "simulation never mutates supplied company account")
	check(state.to_dict().plots.size() == 2, "expanded plot persists in port record")
	check(_command(state, "place_asset", {"placement": _placement("extra-pad", "paving", 120, 0)}).ok, "build on purchased extension")
	_reject_unchanged(state, "place_asset", {"placement": _placement("alien", "unknown-asset", 120, 0)}, "invalid_result")
	check(_command(state, "place_asset", {"placement": _placement("extra-lamp", "lamp", 120, 0)}).ok, "add supported equipment through data command")
	check(_command(state, "remove_asset", {"placement_id": "extra-lamp"}).ok, "remove equipment by stable identity")
	check(_command(state, "remove_asset", {"placement_id": "extra-pad"}).ok, "remove now-unoccupied platform")
	var buyer := _fresh()
	var purchase_command := {"command_id": "buy-once", "expected_revision": 0,
		"actor_company_id": "company-a", "kind": "buy_plot", "payload": {"plot_id": "plot-b", "price_nok": 0}}
	var charged := buyer.apply(purchase_command, context)
	check(charged.ok and charged.account_changes[0].delta_nok == -3000, "client-supplied price cannot override authority offer")
	var again := _fresh(JSON.parse_string(JSON.stringify(buyer.to_dict()))).apply(purchase_command, context)
	check(again.ok and again.replayed and again.account_changes.is_empty(), "purchase retry after reload cannot charge account twice")
	var bad_offer := context.duplicate(true)
	bad_offer.plot_offers["plot-b"].available = "false"
	_reject_unchanged(_fresh(), "buy_plot", {"plot_id": "plot-b"}, "invalid_plot_offer", "company-a", bad_offer)


func _test_replay() -> void:
	var initial := _fixture()
	var source := _fresh(initial)
	var target := _fresh(initial)
	var berth := source.derived_berths()
	if berth.is_empty():
		return
	var command := {"command_id": "durable-id", "expected_revision": 0, "actor_company_id": "company-a", "kind": "dock", "payload": {"vessel_id": "ship-a", "berth_id": berth[0].id}}
	var accepted := source.apply(command)
	check(accepted.ok and accepted.events.size() == 1, "one successful command emits one revisioned event")
	if not accepted.ok:
		return
	var replay := source.apply(command)
	check(replay.ok and replay.replayed and replay.events.is_empty(), "network retry does not duplicate changes/events")
	var reloaded := _fresh(JSON.parse_string(JSON.stringify(source.to_dict())))
	check(reloaded.apply(command).code == "already_applied", "idempotency survives save/load")
	check(reloaded.apply(JSON.parse_string(JSON.stringify(command))).code == "already_applied", "idempotency survives integer-to-JSON-float conversion")
	var conflict := command.duplicate(true)
	conflict.payload.vessel_id = "too-long"
	check(source.apply(conflict).code == "command_id_conflict", "same id cannot be reused for different action")
	conflict = command.duplicate(true)
	conflict.command_id = "stale"
	check(source.apply(conflict).code == "revision_conflict", "concurrent stale writer rejected")
	var event: Dictionary = JSON.parse_string(JSON.stringify(accepted.events[0]))
	var forged := event.duplicate(true)
	forged.changes.world = {"seed": 99, "generation_version": 1, "checksum": "different"}
	check(target.replay_event(forged).code == "invalid_event_field", "event cannot rewrite world identity")
	forged = event.duplicate(true)
	forged.changes.water_regions = [{"rect_m": [-100, -100, 200, 200], "depth_m": 100}]
	check(target.replay_event(forged).code == "invalid_event_field", "event cannot forge surveyed depth")
	check(target.replay_event(event).ok, "JSON event reconstructs receiving client state")
	check(target.to_dict() == source.to_dict(), "receiver exactly matches authority snapshot")
	check(target.replay_event(event).code == "already_applied", "duplicate event harmless")
	var events: Array = []
	for action in [["reserve_cargo", {"store_id": "yard", "vessel_id": "ship-a", "lot_id": "coal-lot", "quantity": 3500, "reservation_id": "voyage"}],
		["load_cargo", {"reservation_id": "voyage"}], ["undock", {"vessel_id": "ship-a"}]]:
		var response := _command(source, action[0], action[1])
		check(response.ok, "data voyage action %s" % action[0])
		events.append_array(response.events)
	if events.size() != 3:
		return
	check(target.replay_event(events[1]).code == "event_gap", "out-of-order delivery waits for missing event")
	for next in events:
		check(target.replay_event(JSON.parse_string(JSON.stringify(next))).ok, "ordered event applied")
	check(target.to_dict() == source.to_dict(), "entire dock/load/depart sequence reconstructs from data")
	var artifact_events: Array = accepted.events.duplicate(true)
	artifact_events.append_array(events)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port-data-output="):
			var destination := argument.trim_prefix("--port-data-output=")
			var file := FileAccess.open(destination, FileAccess.WRITE)
			check(file != null, "simulation evidence file opens")
			if file != null:
				file.store_string(JSON.stringify({"format_version": 1, "scenario": "Dock, reserve 3500 kg coal, load, depart",
					"catalog": _catalog(), "initial": initial, "events": artifact_events, "final": source.to_dict()}, "\t"))
