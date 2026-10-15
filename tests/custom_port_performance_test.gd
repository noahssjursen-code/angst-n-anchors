extends Node
## Bounded repeatable measurements of the actual large data/editor fixture.
var measurements: Dictionary = {}
var failures: Array[String] = []
var state: CustomPortState
var editor: CustomPortEditor
var catalog: Dictionary


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Port performance review requires isolated playtest mode.")
		get_tree().quit(1)
		return
	catalog = CustomPortCatalog.definitions()
	var world := {"seed": 73119, "generation_version": 1, "checksum": "performance-coast"}
	var plots: Array = [{"id": "plot", "rect_m": [-200, -200, 400, 400], "owner_company_id": CustomPortExample.OWNER}]
	var record := CustomPortExample.build(Vector3.ZERO, plots, world)
	record.erase("_site_yaw")
	for z in range(-400, 0, 8):
		for x in range(-200, 200, 8):
			record.water_regions.append({"rect_m": [x, z, 8, 8], "depth_m": 12})
	var started := Time.get_ticks_usec()
	state = CustomPortState.from_dict(record, world, catalog)
	measurements.reconstruct_ms = _elapsed(started)
	_check(state.validation_errors.is_empty(), "Large actual fixture must validate: " + str(state.validation_errors))
	if not state.validation_errors.is_empty(): _finish(); return
	measurements.placements = record.placements.size()
	measurements.water_cells = record.water_regions.size()
	_measure("state_canonicalization", 3, func(): return CustomPortState._canonical(record))
	_measure("state_validation", 3, func(): return state.validate())
	_measure("placement_rules_validation", 3, func(): return CustomPortPlacementRules.validate(record, catalog))
	_measure("berths_geometry_derivation", 3, func(): return CustomPortBerths.derive(record, catalog))
	_measure("snapshot_copy", 10, func(): return state.to_dict())
	_measure("derived_berths_repeated", 8, func(): return state.derived_berths())
	editor = CustomPortEditor.new()
	started = Time.get_ticks_usec()
	editor.configure(state, catalog, CustomPortExample.OWNER)
	measurements.editor_configure_ms = _elapsed(started)
	var samples := {
		"empty_platform": ["foundation", Vector3(100, 0, 120)],
		"overlapping_platform": ["foundation", Vector3(2, 0, 6)],
		"outside_plot": ["foundation", Vector3(300, 0, 120)],
		"supported_prop": ["pallet_stack", Vector3(8, 0, 48)],
		"edge_fitting": ["quay_ladder", Vector3(8, 0, 0)],
	}
	for label in samples:
		var asset: String = samples[label][0]
		var cursor: Vector3 = samples[label][1]
		started = Time.get_ticks_usec()
		var proposal := editor.preview(asset, cursor)
		measurements[label + "_first_ms"] = _elapsed(started)
		measurements[label + "_ok"] = proposal.ok
		var before := editor.previews_evaluated
		_measure(label + "_cached", 200, func(): return editor.preview(asset, cursor))
		_check(editor.previews_evaluated == before, "Same-cell hover must not reevaluate " + label)
	var index := [0]
	_measure("empty_platform_new_cells", 16, func():
		index[0] += 1
		return editor.preview("foundation", Vector3(100 + index[0] * 4, 0, 120)))
	# A ship alongside exposes the expensive full-candidate preview path.
	var berths := state.derived_berths()
	var dock := state.apply({"command_id": "performance-dock", "kind": "dock", "expected_revision": state.revision(), "actor_company_id": CustomPortExample.OWNER,
		"payload": {"vessel_id": "nordlys", "berth_id": berths[0].id}})
	_check(dock.ok, "Docked-vessel preview scenario must be valid")
	started = Time.get_ticks_usec()
	editor.preview("pallet_stack", Vector3(8, 0, 48))
	measurements.docked_first_prop_with_revision_refresh_ms = _elapsed(started)
	index[0] = 0
	_measure("docked_supported_prop_new_cells", 5, func():
		index[0] += 1
		return editor.preview("pallet_stack", Vector3(8, 0, 48 + index[0])))
	var proposed := editor.preview("foundation", Vector3(100, 0, 120))
	started = Time.get_ticks_usec()
	var placed := editor.place(proposed)
	measurements.construction_command_ms = _elapsed(started)
	_check(placed.ok, "Measured construction command must succeed")
	_measure("derived_berths_after_build", 8, func(): return state.derived_berths())
	_finish()


func _measure(label: String, count: int, callback: Callable) -> void:
	var values: Array[float] = []
	var total := 0.0
	for index in count:
		var started := Time.get_ticks_usec()
		callback.call()
		var elapsed := _elapsed(started)
		values.append(elapsed)
		total += elapsed
	values.sort()
	measurements[label] = {"iterations": count, "mean_ms": total / count, "p95_ms": values[mini(count - 1, floori(count * 0.95))], "max_ms": values.back()}


func _elapsed(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)


func _finish() -> void:
	print("PORT_PERFORMANCE ", JSON.stringify(measurements, "", true, true))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port-performance-output="):
			var path := argument.trim_prefix("--port-performance-output=")
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(measurements, "\t", true, true))
	for failure in failures: push_error(failure)
	print("CUSTOM PORT PERFORMANCE ", "PASS" if failures.is_empty() else "FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
