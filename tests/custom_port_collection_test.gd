extends Node
## Collection invariants remain separate from per-document authority validation.
const COLLECTION := preload("res://scripts/port/state/custom_port_collection.gd")
const STATE := preload("res://scripts/port/state/custom_port_state.gd")
const WORLD := {"seed": 424242, "generation_version": 12, "checksum": "collection-fixture"}
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	var a := _fixture("port-a", "plot-a", [0, 0, 4, 4])
	_expect([], true, "", "Empty collection")
	_expect([a], true, "", "Single valid port")
	_expect([a, a.duplicate(true)], false, "duplicate_port_id", "Identical document cannot be registered twice")
	var duplicate_id := _fixture("port-a", "plot-b", [12, 0, 4, 4])
	_expect([a, duplicate_id], false, "duplicate_port_id", "Different documents cannot share a port ID")
	_expect([a, _fixture("port-b", "plot-a", [0, 0, 4, 4])], false, "duplicate_plot_id", "Plot ID reused at identical world rectangle")
	_expect([a, _fixture("port-b", "plot-a", [12, 0, 4, 4])], false, "plot_bounds_conflict", "Plot ID reused with changed world bounds")
	_expect([a, _fixture("port-b", "plot-b", [3, 0, 4, 4])], false, "plot_overlap", "Same company cannot own overlapping records")
	_expect([a, _fixture("port-b", "plot-b", [3, 0, 4, 4], [0, 0, 0], "company-b")], false, "plot_overlap", "Different companies cannot own overlapping records")
	_expect([a, _fixture("port-b", "plot-b", [4, 0, 4, 4])], true, "", "Shared edge has zero area")
	_expect([a, _fixture("port-b", "plot-b", [4, 4, 4, 4])], true, "", "Shared corner has zero area")
	_expect([a, _fixture("port-b", "plot-b", [5, 5, 4, 4])], true, "", "Disjoint rectangles")
	_expect([a, _fixture("port-b", "plot-b", [0, 0, 4, 4], [20, 0, -20])], true, "", "Same local coordinates are disjoint at different origins")
	_expect([a, _fixture("port-b", "plot-b", [20, -20, 4, 4], [-20, 0, 20])], false, "plot_overlap", "Different local coordinates resolve to the same world rectangle")
	_expect([a, _fixture("port-b", "plot-a", [20, -20, 4, 4], [-20, 0, 20])], false, "duplicate_plot_id", "Plot identity compares translated world geometry")
	_expect([a, _fixture("port-b", "plot-b", [1, 1, 1, 1])], false, "plot_overlap", "Nested rectangle is positive-area overlap")
	_expect([
		_fixture("negative-a", "negative-plot-a", [-6, -8, 4, 4], [-100, 0, -200]),
		_fixture("negative-b", "negative-plot-b", [-4, -6, 4, 4], [-100, 0, -200])
	], false, "plot_overlap", "Negative local and world coordinates preserve overlap")
	_expect([
		_fixture("negative-a", "negative-plot-a", [-6, -8, 4, 4], [-100, 0, -200]),
		_fixture("negative-b", "negative-plot-b", [-2, -8, 4, 4], [-100, 0, -200])
	], true, "", "Negative-coordinate shared edge remains allowed")
	# Arrays preserve scalar double coordinates; Vector2 would round this away.
	var distant := _fixture("far-a", "far-plot-a", [0, 0, 4, 4], [80000.0, 0, -80000.0])
	_expect([distant, _fixture("far-b", "far-plot-b", [0, 0, 4, 4], [80003.9999, 0, -80000.0])], false, "plot_overlap", "0.0001 m positive overlap at 80000 m remains an overlap")
	_expect([distant, _fixture("far-b", "far-plot-b", [0, 0, 4, 4], [80004.0, 0, -80000.0])], true, "", "Exact edge at 80000 m remains allowed")
	_expect([distant, _fixture("far-b", "far-plot-b", [0, 0, 4, 4], [80004.0001, 0, -80000.0])], true, "", "0.0001 m gap at 80000 m remains disjoint")
	var other_world := _fixture("other-world", "other-plot", [20, 20, 4, 4])
	other_world.world.seed += 1
	_check(STATE.from_dict(other_world).validation_errors.is_empty(), "Different-world fixture is individually valid")
	_expect([a, other_world], false, "world_mismatch", "Collection cannot mix world identities")
	var malformed := a.duplicate(true)
	malformed.erase("id")
	_expect([malformed], false, "invalid_record", "Missing record identity")
	_expect(["not-a-record"], false, "invalid_record", "Non-dictionary record")
	malformed = a.duplicate(true)
	malformed.origin_m = [0, 0]
	_expect([malformed], false, "invalid_record", "Invalid origin shape")
	malformed = a.duplicate(true)
	malformed.plots = ["not-a-plot"]
	_expect([malformed], false, "invalid_plot", "Non-dictionary plot")
	malformed = a.duplicate(true)
	malformed.plots[0].rect_m = [0, 0, -1, 4]
	_expect([malformed], false, "invalid_plot", "Invalid plot extent")
	malformed = a.duplicate(true)
	malformed.plots[0].rect_m = [0, 0, 4]
	_expect([malformed], false, "invalid_plot", "Invalid plot rectangle shape")
	for failure in failures: push_error(failure)
	print("CUSTOM PORT COLLECTION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _fixture(port_id: String, plot_id: String, rect: Array, origin: Array = [0, 0, 0], company := "company-a") -> Dictionary:
	var record := {"schema_version": 1, "id": port_id, "name": port_id,
		"owner_company_id": company, "world": WORLD.duplicate(true),
		"origin_m": origin.duplicate(), "deck_height_above_sea_m": 2.0,
		"plots": [{"id": plot_id, "rect_m": rect.duplicate(), "owner_company_id": company}],
		"placements": [], "stores": [], "vessels": [], "reservations": [],
		"water_regions": [], "revision": 0, "receipts": {}}
	var errors := STATE.from_dict(record, WORLD).validation_errors
	_check(errors.is_empty(), "Individually valid empty authority fixture " + port_id + ": " + str(errors))
	return record

func _expect(records: Array, expected_ok: bool, expected_error: String, label: String) -> void:
	var before := var_to_bytes(records)
	var response: Dictionary = COLLECTION.validate(records)
	_check(response.get("ok") == expected_ok, label + ": success status")
	_check(response.get("code") == ("valid_collection" if expected_ok else "invalid_collection"), label + ": result code")
	_check(response.get("errors") is Array, label + ": structured errors")
	var errors: Array = response.get("errors", [])
	_check(errors.is_empty() if expected_ok else _has_code(errors, expected_error), label + ": expected error code " + expected_error)
	_check(var_to_bytes(records) == before, label + ": validation does not mutate inputs")
	var response_before := response.duplicate(true)
	_poison(response)
	_check(var_to_bytes(records) == before, label + ": returned errors do not alias input documents")
	_check(COLLECTION.validate(records) == response_before, label + ": returned errors do not alias later results")

func _has_code(errors: Array, code: String) -> bool:
	for error in errors:
		if error is Dictionary and error.get("code") == code: return true
	return false

func _poison(value: Variant) -> void:
	if value is Dictionary:
		for key in value.keys(): _poison(value[key])
		value["mutated_by_consumer"] = true
	elif value is Array:
		for item in value: _poison(item)
		value.append({"mutated_by_consumer": true})

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
