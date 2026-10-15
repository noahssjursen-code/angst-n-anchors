extends Node

## Read-only diagnostic: full actual harbour, current supported equipment and
## finite stock. The synthetic depth rectangles are explicit performance data.
var report: Dictionary = {}
var failures: Array[String] = []
var catalog: Dictionary

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()

func _run() -> void:
	catalog = CustomPortCatalog.definitions()
	for fish in [false, true]:
		var snapshot := _fixture(fish)
		var state := CustomPortState.from_dict(snapshot, snapshot.world, catalog)
		_check(state.validation_errors.is_empty(), "Service fixture validates: " + str(state.validation_errors))
		if not state.validation_errors.is_empty(): continue
		var id := "container-terminal"
		var store_id := "fish-receiver" if fish else "container-yard"
		var vessel_id := "nordlys" if fish else "trader"
		var lot_id := "morning-catch" if fish else "parts-for-shipyard"
		var label := "fish_plant" if fish else "container_crane"
		report[label] = {"placements": snapshot.placements.size(), "water_cells": snapshot.water_regions.size()}
		for phase in ["idle", "docked", "reserved"]:
			if phase == "docked":
				var vessel := _find(state.to_dict().vessels, vessel_id)
				var selected := ""
				for berth in state.derived_berths():
					if store_id in CustomPortBerths.services_for_vessel(berth, vessel, "catch" if fish else "container").store_ids:
						selected = str(berth.id); break
				_check(not selected.is_empty(), label + ": real equipment reaches the selected installed vessel")
				if selected.is_empty(): break
				var dock := state.apply({"command_id":"probe-dock", "expected_revision":state.revision(), "actor_company_id":str(vessel.owner_company_id),
					"kind":"dock", "payload":{"vessel_id":vessel_id, "berth_id":selected}})
				_check(dock.ok, label + ": docking is accepted")
				if not dock.ok: break
			elif phase == "reserved":
				var vessel := _find(state.to_dict().vessels, vessel_id)
				var reserve := state.apply({"command_id":"probe-reserve", "expected_revision":state.revision(), "actor_company_id":str(vessel.owner_company_id),
					"kind":"reserve_cargo", "payload":{"vessel_id":vessel_id, "store_id":store_id, "lot_id":lot_id, "quantity":100 if fish else 1}})
				_check(reserve.ok, label + ": finite stock reservation is accepted")
				if not reserve.ok: break
			report[label][phase] = _profile(state, id, fish)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--service-preview-output="):
			var file := FileAccess.open(argument.trim_prefix("--service-preview-output="), FileAccess.WRITE)
			_check(file != null, "Diagnostic output opens")
			if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("SERVICE_PREVIEW_PROFILE ", JSON.stringify(report, "", true, true))
	for failure in failures: push_error(failure)
	print("CUSTOM PORT SERVICE PREVIEW PROBE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _profile(state: CustomPortState, id: String, fish: bool) -> Dictionary:
	var editor := CustomPortEditor.new()
	editor.configure(state, catalog, CustomPortExample.OWNER)
	var before := state.to_dict()
	var original := _find(before.placements, id)
	var origin := CustomPortCatalog.vector3(original.position_m)
	var samples: Array = []
	for delta in [Vector3(4,0,0),Vector3(8,0,0),Vector3(12,0,0),Vector3(16,0,0),Vector3(0,0,4),Vector3(0,0,8),Vector3(72,0,12),Vector3(-80,0,0),Vector3(0,0,-32)]:
		var started := Time.get_ticks_usec()
		var proposal := editor.preview_transform(id, origin + delta, 0)
		var full_ms := _elapsed(started)
		var payload := {"placement_id":id, "expected_placement":proposal.expected_placement,
			"position_m":proposal.placement.position_m, "yaw_degrees":proposal.placement.yaw_degrees}
		started = Time.get_ticks_usec()
		var candidate := state.to_dict()
		var clone_ms := _elapsed(started)
		started = Time.get_ticks_usec()
		var preflight := state._execute(candidate, "transform_asset", CustomPortExample.OWNER, CustomPortState._canonical(payload), {}, "diagnostic")
		var execute_ms := _elapsed(started)
		var validate_ms := 0.0
		var errors: Array = []
		if preflight.ok:
			started = Time.get_ticks_usec()
			errors = state._validate(candidate)
			validate_ms = _elapsed(started)
		_check(proposal.ok == (preflight.ok and errors.is_empty()), "Editor and full authority preview agree")
		started = Time.get_ticks_usec()
		# Measurement only, NOT offered as a permission decision. This local
		# helper deliberately omits service/reservation authority preflight.
		var local_only := editor._preview_local_transform(original, proposal.placement, CustomPortPlacementRules.definition(original, catalog))
		var local_ms := _elapsed(started)
		samples.append({"position":proposal.placement.position_m, "ok":proposal.ok, "errors":proposal.errors,
			"full_preview_ms":full_ms, "clone_ms":clone_ms, "existing_command_preflight_ms":execute_ms,
			"full_candidate_validation_ms":validate_ms, "geometry_only_ms":local_ms,
			"geometry_only_ok":local_only.ok, "preflight_code":preflight.get("code", "")})
	_check(state.to_dict() == before, "Diagnostic did not mutate authority, stock, reservation or receipts")
	var summary: Dictionary = {"samples":samples}
	for field in ["full_preview_ms", "clone_ms", "existing_command_preflight_ms", "full_candidate_validation_ms", "geometry_only_ms"]:
		var values: Array[float] = []
		for sample in samples: values.append(float(sample[field]))
		values.sort()
		var total := 0.0
		for value in values: total += value
		summary[field] = {"mean":total/values.size(), "max":values.back()}
	return summary

func _fixture(fish: bool) -> Dictionary:
	var world := {"seed":73119,"generation_version":1,"checksum":"service-preview-performance-fixture"}
	var plots: Array = [{"id":"plot","rect_m":[-200,-200,400,400],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot := CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	for z in range(-96,0,8):
		for x in range(-88,88,8): snapshot.water_regions.append({"rect_m":[x,z,8,8],"depth_m":12})
	if fish:
		for index in snapshot.placements.size():
			if snapshot.placements[index].id == "container-terminal":
				snapshot.placements[index] = CustomPortCatalog.placement("container-terminal", "fish_landing_plant", Vector3(-4,0,12))
		var store: Dictionary = catalog.fish_landing_plant.attached_store.duplicate(true)
		store.merge({"id":"fish-receiver","placement_id":"container-terminal","public_loading":true,"public_unloading":true,
			"lots":[{"id":"morning-catch","commodity_id":"fresh_groundfish","quantity":420,"unit_mass_kg":1,
				"attributes":{"species_id":"cod","quality":.94,"specimen":false}}]},true)
		snapshot.stores[0] = store
	return snapshot

func _find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.id) == id: return row
	return {}

func _elapsed(started: int) -> float:
	return float(Time.get_ticks_usec() - started)/1000.0

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
