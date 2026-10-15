extends Node
## Pure coast-parcel conversion: no purchase, world registration or invented stock.
const PLAN := preload("res://scripts/port/building/custom_port_site_plan.gd")
const INDEX := preload("res://scripts/port/coastal_plot_index.gd")
const STATE := preload("res://scripts/port/state/custom_port_state.gd")
const WORLD := {"seed": 7, "generation_version": 12, "checksum": "site-plan-fixture"}
var checks := 0
var cases := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	var index := _fixture()
	var plot: Dictionary = index.plot_at(Vector2(50, 50))
	_check(not plot.is_empty(), "Synthetic coastline supplies the selected parcel")
	var plot_id := String(plot.get("id", ""))
	_success(index, plot_id, WORLD.duplicate(true), [100.0, 0.5, 100.0], "Test harbour", "Test harbour", "Canonical world")
	_success(index, plot_id, index.world_identity, [100.0, 0.5, 100.0], "", "New harbour", "Index checksum alias and world size")
	var both_aliases := WORLD.duplicate(true)
	both_aliases.layout_checksum = WORLD.checksum
	_success(index, plot_id, both_aliases, [100.0, 0.5, 100.0], " \t\n ", "New harbour", "Matching aliases and whitespace name")
	var wire_world: Dictionary = JSON.parse_string(JSON.stringify(WORLD))
	_success(index, plot_id, wire_world, [100.0, 0.5, 100.0], "Wire harbour", "Wire harbour", "JSON-decoded world identity")
	var negative: Dictionary = index.plot_at(Vector2(-50, -50))
	_success(index, String(negative.id), WORLD.duplicate(true), [-100.0, 0.5, -100.0], "Negative harbour", "Negative harbour", "Negative 200 m parcel")
	var alternate := _fixture(250.0)
	var negative_alternate: Dictionary = alternate.plot_at(Vector2(-350, -50))
	_success(alternate, String(negative_alternate.id), WORLD.duplicate(true), [-376.0, 0.5, -124.0], "Alternate harbour", "Alternate harbour", "Negative 250 m parcel snaps its centre without changing boundaries")
	var positive_alternate: Dictionary = alternate.plot_at(Vector2(350, 50))
	_success(alternate, String(positive_alternate.id), WORLD.duplicate(true), [376.0, 0.5, 124.0], "Alternate harbour", "Alternate harbour", "Positive 250 m parcel snaps its centre without changing boundaries")
	_failure(null, plot_id, WORLD.duplicate(true), "invalid_plot_index", "Null index")
	_failure(INDEX.new(), plot_id, WORLD.duplicate(true), "invalid_plot_index", "Unbuilt index")
	_failure(index, "unknown-plot", WORLD.duplicate(true), "unknown_plot", "Unknown plot")
	_failure(index, "", WORLD.duplicate(true), "unknown_plot", "Empty plot ID")
	_failure(index, String(negative_alternate.id), WORLD.duplicate(true), "unknown_plot", "Plot ID from another parcel size")
	for empty_identity in ["", " \t\n "]:
		_failure(index, plot_id, WORLD.duplicate(true), "invalid_identity", "Blank port ID", empty_identity, "company-a")
		_failure(index, plot_id, WORLD.duplicate(true), "invalid_identity", "Blank owner ID", "port-a", empty_identity)
	_failure(index, plot_id, {}, "invalid_world", "Missing world")
	for key in ["seed", "generation_version", "checksum"]:
		var missing := WORLD.duplicate(true)
		missing.erase(key)
		_failure(index, plot_id, missing, "invalid_world", "Missing world " + key)
		var mismatch := WORLD.duplicate(true)
		mismatch[key] = "different-checksum" if key == "checksum" else int(mismatch[key]) + 1
		_failure(index, plot_id, mismatch, "world_mismatch", "Mismatched world " + key)
	for key in ["seed", "generation_version"]:
		for invalid_number in ["7", true, 1.25, INF, NAN]:
			var invalid := WORLD.duplicate(true)
			invalid[key] = invalid_number
			_failure(index, plot_id, invalid, "invalid_world", "Invalid numeric world " + key + ": " + str(invalid_number))
	for checksum in ["", " \t\n ", 42, null]:
		var invalid := WORLD.duplicate(true)
		invalid.checksum = checksum
		_failure(index, plot_id, invalid, "invalid_world", "Invalid checksum: " + str(checksum))
	var conflict := WORLD.duplicate(true)
	conflict.layout_checksum = "another-checksum"
	_failure(index, plot_id, conflict, "invalid_world", "Conflicting checksum aliases")
	for size in [2500.0, "2000", INF]:
		var wrong_size := WORLD.duplicate(true)
		wrong_size.world_size_m = size
		_failure(index, plot_id, wrong_size, "world_mismatch", "Mismatched or malformed optional world size: " + str(size))
	var foreign_index := _fixture(200.0, "another-checksum")
	_failure(foreign_index, String(foreign_index.plot_at(Vector2(50, 50)).id), WORLD.duplicate(true), "world_mismatch", "Selected plot from a foreign index")
	for failure in failures: push_error(failure)
	print("CUSTOM PORT SITE PLAN ", "PASS" if failures.is_empty() else "FAIL", " cases=", cases, " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _fixture(size_m := 200.0, checksum := "site-plan-fixture") -> CoastalPlotIndex:
	var index := INDEX.new()
	var contours: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-750, -50), Vector2(750, -50)]),
		PackedVector2Array([Vector2(-750, 50), Vector2(750, 50)]),
	]
	index._build(contours, {"seed": 7, "generation_version": 12,
		"layout_checksum": checksum, "world_size_m": 2000.0},
		Rect2(-1000, -1000, 2000, 2000), size_m)
	return index

func _success(index: CoastalPlotIndex, plot_id: String, world: Dictionary, expected_origin: Array,
		name: String, expected_name: String, label: String) -> void:
	cases += 1
	var world_before := var_to_bytes(world)
	var index_before := _index_bytes(index)
	var result: Dictionary = PLAN.plan(plot_id, index, world, "port-a", "company-a", name)
	_check(result.get("ok") == true and result.get("code") == "planned", label + ": successful plan")
	_check(var_to_bytes(world) == world_before and _index_bytes(index) == index_before, label + ": inputs unchanged")
	if result.get("ok") != true: return
	var snapshot: Dictionary = result.get("snapshot", {})
	var source: Dictionary = index.get_plot(plot_id)
	_check(result.get("plot") == source, label + ": exact indexed plot returned")
	_check(snapshot.get("id") == "port-a" and snapshot.get("owner_company_id") == "company-a", label + ": requested identity")
	_check(snapshot.get("name") == expected_name, label + ": requested or default name")
	_check(snapshot.get("schema_version") == 1 and snapshot.get("revision") == 0, label + ": initial document version")
	_check(snapshot.get("world") == {"seed": 7.0, "generation_version": 12.0, "checksum": "site-plan-fixture"}, label + ": canonical three-key world identity")
	_check(snapshot.get("origin_m") == expected_origin, label + ": expected snapped centre and fixed Y")
	_check(snapshot.get("deck_height_above_sea_m") == 2.0 and snapshot.origin_m[1] == WaveSurface.WATER_LEVEL + 2.0, label + ": fixed sea-referenced deck plane")
	_check(fmod(float(snapshot.origin_m[0]), 4.0) == 0.0 and fmod(float(snapshot.origin_m[2]), 4.0) == 0.0, label + ": origin on 4 m grid")
	var plots: Array = snapshot.get("plots", [])
	_check(plots.size() == 1, label + ": exactly the selected plot")
	if plots.size() == 1:
		_check(plots[0].get("id") == plot_id and plots[0].get("owner_company_id") == "company-a", label + ": plot identity and owner")
		var rect: Array = plots[0].get("rect_m", [])
		_check(rect.size() == 4, label + ": local rectangle shape")
		if rect.size() == 4:
			var reconstructed := [float(rect[0]) + float(snapshot.origin_m[0]),
				float(rect[1]) + float(snapshot.origin_m[2]), float(rect[2]), float(rect[3])]
			var bounds: Dictionary = source.bounds
			_check(reconstructed == [float(bounds.x), float(bounds.z), float(bounds.size_m), float(bounds.size_m)], label + ": exact world boundaries survive local translation")
	for key in ["placements", "stores", "vessels", "reservations", "water_regions"]:
		_check(snapshot.get(key) is Array and snapshot[key].is_empty(), label + ": blank " + key)
	_check(snapshot.get("receipts") is Dictionary and snapshot.receipts.is_empty(), label + ": no command receipts")
	_check(result.get("shore_anchor_m") == [float(source.shore_anchor[0]), 0.5, float(source.shore_anchor[1])], label + ": shoreline camera hint")
	_check(not snapshot.has("shore_anchor_m") and not snapshot.has("spawn_m") and not snapshot.has("spawn"), label + ": camera hint does not create an authoritative spawn")
	var state := STATE.from_dict(snapshot, snapshot.world)
	_check(state.validation_errors.is_empty(), label + ": valid blank authority document: " + str(state.validation_errors))
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot, "", true, true))
	var restored := STATE.from_dict(decoded, snapshot.world)
	_check(restored.validation_errors.is_empty(), label + ": JSON round-trip remains valid")
	_check(JSON.stringify(restored.to_dict(), "", true, true) == JSON.stringify(snapshot, "", true, true), label + ": JSON round-trip preserves the complete snapshot")
	var expected := result.duplicate(true)
	_poison(result)
	_check(var_to_bytes(world) == world_before and _index_bytes(index) == index_before, label + ": returned nested data is independent of inputs")
	_check(PLAN.plan(plot_id, index, world, "port-a", "company-a", name) == expected, label + ": fresh deterministic result after consumer mutation")

func _failure(index: CoastalPlotIndex, plot_id: String, world: Dictionary, code: String,
		label: String, port_id := "port-a", owner := "company-a") -> void:
	cases += 1
	var world_before := var_to_bytes(world)
	var index_before := _index_bytes(index)
	var result: Dictionary = PLAN.plan(plot_id, index, world, port_id, owner, "Test harbour")
	_check(result.get("ok") == false and result.get("code") == code, label + ": expected rejection " + code)
	_check(result.get("errors") is Array and not result.errors.is_empty(), label + ": explanatory errors")
	_check(not result.has("snapshot"), label + ": failure does not issue a document")
	_check(var_to_bytes(world) == world_before and _index_bytes(index) == index_before, label + ": rejected inputs unchanged")
	var expected := result.duplicate(true)
	_poison(result)
	_check(var_to_bytes(world) == world_before and _index_bytes(index) == index_before, label + ": returned errors are independent of inputs")
	_check(PLAN.plan(plot_id, index, world, port_id, owner, "Test harbour") == expected, label + ": fresh rejection after consumer mutation")

func _index_bytes(index: CoastalPlotIndex) -> PackedByteArray:
	if index == null: return PackedByteArray()
	return var_to_bytes([index.world_identity, index.world_bounds, index.cell_size_m,
		index.plot_ids(), index.plots_in_rect(index.world_bounds)])

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
