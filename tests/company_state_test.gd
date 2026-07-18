extends Node

const CompanyServiceScript := preload("res://scripts/company/company_service.gd")
const FreightServiceScript := preload("res://scripts/cargo/freight_service.gd")


class FakeSession:
	extends Node
	var data := PlayerData.new()

	func get_marks() -> int:
		return data.marks

	func earn_marks(amount: int) -> void:
		data.marks += maxi(amount, 0)

	func spend_marks(amount: int) -> bool:
		if amount > data.marks:
			return false
		data.marks -= maxi(amount, 0)
		return true

	func _request_save() -> void:
		pass


func _ready() -> void:
	_test_save_round_trip()
	_test_company_normalization_and_wages()
	_test_company_contract_is_separate_from_player_journal()
	_test_cargo_manifest_survives_save_and_clears_after_delivery()
	_test_abstract_departure_builds_deterministic_cargo()
	_test_local_physics_suspends_timestamp_arrival()
	_test_preparation_departure_and_offline_arrival()
	_test_payroll_holds_without_debt()
	_test_stop_after_leg_settles_offline_and_holds()
	print("Company state tests: all checks passed")
	get_tree().quit()


func _test_save_round_trip() -> void:
	var source := PlayerData.new()
	source.company_state = {
		"schema_version": 1,
		"name": "North Sea Coastal",
		"employees": [{"id": "crew-1", "name": "Astrid Berg", "wage_per_hour": 30}],
		"fleet": {"vessel-1": {
			"status": "underway", "leg_ends_unix": 9000,
			"crew_ids": PackedStringArray(["crew-1"]),
			"route": {"origin_port_id": "a", "destination_port_id": "b"},
		}},
		"last_simulated_unix": 8000,
	}
	var restored := PlayerData.from_dict(source.to_dict())
	assert(PlayerData.json_equivalent(source.company_state, restored.company_state),
		"company authority state must survive PlayerData serialization")
	var json_data := JSON.parse_string(JSON.stringify(source.to_dict())) as Dictionary
	var from_json := PlayerData.from_dict(json_data)
	var service := CompanyServiceScript.new()
	var normalized := service.call("_normalize", from_json.company_state) as Dictionary
	var fleet_row := (normalized.get("fleet", {}) as Dictionary).get("vessel-1", {}) as Dictionary
	assert(fleet_row.get("crew_ids") is PackedStringArray,
		"JSON crew arrays must normalize back to PackedStringArray")
	service.free()
	assert(PlayerSaveStore.SAVE_VERSION == 6)


func _test_company_normalization_and_wages() -> void:
	var service := CompanyServiceScript.new()
	var normalized := service.call("_normalize", {"name": "Test Co"}) as Dictionary
	assert(str(normalized.get("name", "")) == "Test Co")
	assert(normalized.get("employees") is Array)
	assert(normalized.get("fleet") is Dictionary)
	service.set("_state", {
		"employees": [
			{"id": "a", "wage_per_hour": 30},
			{"id": "b", "wage_per_hour": 18},
		],
		"fleet": {},
	})
	var wage := int(service.call("_leg_wage", {"crew_ids": PackedStringArray(["a", "b"])}, 1800))
	assert(wage == 24, "half-hour payroll should be deterministic and prepaid")
	var voyage_duration := float(service.call("_voyage_duration_s", 4000.0))
	assert(voyage_duration > 4000.0 / 7.2,
		"berth crab and harbour manoeuvres must be slower than passage speed")
	assert(is_equal_approx(float(service.call(
		"_voyage_distance_at_elapsed", 4000.0, voyage_duration)), 4000.0))
	service.free()


func _test_company_contract_is_separate_from_player_journal() -> void:
	var freight := FreightServiceScript.new()
	add_child(freight)
	var contract := {
		"id": "company-test-contract",
		"origin_port_id": "a",
		"destination_port_id": "b",
		"commodity_id": "provisions",
		"handling_mode": "general",
		"quantity": 2,
		"pay_marks": 20,
	}
	assert(freight.register_company_contract(contract))
	assert(freight.active_contracts().is_empty(),
		"company freight must not appear in the player's active contract journal")
	assert(not freight.company_contract("company-test-contract").is_empty())
	assert(freight.cancel_company_contract("company-test-contract"))
	assert(freight.company_contract("company-test-contract").is_empty())
	freight.queue_free()


func _test_cargo_manifest_survives_save_and_clears_after_delivery() -> void:
	var service := CompanyServiceScript.new()
	add_child(service)
	var session := FakeSession.new()
	add_child(session)
	service.set("_session", session)
	service.set("_state", _simulation_state(100))
	var manifest := {
		"kind": "units",
		"contract": {"id": "company-freight:vessel-1:0", "quantity": 1},
		"units": [{"id": "unit-1", "commodity_id": "provisions"}],
	}
	assert(service.set_cargo_manifest("vessel-1", manifest))
	var encoded := JSON.stringify(service.get("_state"))
	var decoded := JSON.parse_string(encoded) as Dictionary
	var restored_manifest := (((decoded.get("fleet", {}) as Dictionary).get(
		"vessel-1", {}) as Dictionary).get("cargo_manifest", {}) as Dictionary)
	assert(str(restored_manifest.get("kind", "")) == "units")
	var row := (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	row["arrival_pending_settlement"] = true
	row["pending_revenue_marks"] = 10
	assert(service.confirm_arrival_unloaded("vessel-1"))
	row = (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert((row.get("cargo_manifest", {}) as Dictionary).is_empty(),
		"delivered authority cargo must be cleared only after unload settlement")
	service.free()
	session.queue_free()


func _test_abstract_departure_builds_deterministic_cargo() -> void:
	var service := CompanyServiceScript.new()
	add_child(service)
	var session := FakeSession.new()
	add_child(session)
	session.data.owned_vessels = [{
		"uid": "vessel-1",
		"brick_layout": {
			"hull_id": "hull-test",
			"container_pads": [{"a": [0, 0, 0], "b": [7, 0, 7]}],
		},
	}]
	service.set("_session", session)
	var row := {
		"commodity_id": "provisions",
		"leg_origin_port_id": "port-a",
		"leg_destination_port_id": "port-b",
		"leg_origin_berth_id": "port-a/general",
		"completed_legs": 2,
		"route": {"pay_marks": 80},
	}
	service.call("_ensure_abstract_cargo", row, "vessel-1")
	var manifest := row.get("cargo_manifest", {}) as Dictionary
	var units := manifest.get("units", []) as Array
	assert(str(manifest.get("kind", "")) == "units")
	assert(units.size() == 4, "abstract cargo must respect the vessel's 4x4 deck slots")
	var first := units[0] as Dictionary
	assert(str(first.get("id", "")) == "company-freight:vessel-1:2:unit:0",
		"abstract container identities must be deterministic across reconnects")
	service.free()
	session.queue_free()


func _test_local_physics_suspends_timestamp_arrival() -> void:
	var service := CompanyServiceScript.new()
	add_child(service)
	var session := FakeSession.new()
	add_child(session)
	session.data.marks = 1000
	service.set("_session", session)
	service.set("_state", _simulation_state(100))
	service.advance_to(101)
	var row := (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	var arrival := int(row.get("leg_ends_unix", 0))
	service.set_local_voyage_simulation("vessel-1", true)
	service.advance_to(arrival + 100)
	row = (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(str(row.get("status", "")) == "underway",
		"timestamp authority must not complete a vessel while real physics owns it")
	service.suspend_local_voyage("vessel-1", 400.0, 1000.0)
	row = (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(int(row.get("leg_ends_unix", 0)) > int(Time.get_unix_time_from_system()),
		"leaving physics interest must restart dormant time projection from real progress")
	service.set_local_voyage_simulation("vessel-1", true)
	assert(service.complete_local_voyage(
		"vessel-1", "port-b/general", 0.2, Vector3(10.0, 0.0, 20.0)))
	row = (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(str(row.get("status", "")) == "turnaround")
	assert(str(row.get("current_berth_id", "")) == "port-b/general")
	service.free()
	session.queue_free()


func _test_preparation_departure_and_offline_arrival() -> void:
	var service := CompanyServiceScript.new()
	add_child(service)
	var session := FakeSession.new()
	add_child(session)
	session.data.marks = 1000
	service.set("_session", session)
	service.set("_state", _simulation_state(100))
	service.advance_to(101)
	var row := (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(str(row.get("status", "")) == "underway")
	assert(not bool(row.get("cargo_ready", true)))
	var arrival := int(row.get("leg_ends_unix", 0))
	service.advance_to(arrival)
	row = (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(str(row.get("status", "")) == "turnaround")
	assert(int(row.get("completed_legs", 0)) == 0,
		"arrival alone must not settle freight before unloading")
	assert(str(row.get("current_port_id", "")) == "port-b")
	assert(service.confirm_arrival_unloaded("vessel-1"))
	row = (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(int(row.get("completed_legs", 0)) == 1)
	assert(int(row.get("revenue_marks", 0)) == 80)
	service.free()
	session.queue_free()


func _test_payroll_holds_without_debt() -> void:
	var service := CompanyServiceScript.new()
	add_child(service)
	var session := FakeSession.new()
	add_child(session)
	session.data.marks = 0
	service.set("_session", session)
	service.set("_state", _simulation_state(100))
	service.advance_to(101)
	var row := (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(str(row.get("status", "")) == "unpaid")
	assert(session.data.marks == 0, "company payroll must never create debt")
	service.free()
	session.queue_free()


func _test_stop_after_leg_settles_offline_and_holds() -> void:
	var service := CompanyServiceScript.new()
	add_child(service)
	var session := FakeSession.new()
	add_child(session)
	session.data.marks = 1000
	service.set("_session", session)
	service.set("_state", _simulation_state(100))
	service.advance_to(101)
	assert(service.stop_after_current_leg("vessel-1"))
	service.advance_to(1000)
	var row := (service.get("_state") as Dictionary)["fleet"]["vessel-1"] as Dictionary
	assert(str(row.get("status", "")) == "inactive")
	assert(int(row.get("completed_legs", 0)) == 1)
	assert(int(row.get("revenue_marks", 0)) == 80)
	assert(not bool(row.get("arrival_pending_settlement", true)))
	service.free()
	session.queue_free()


func _simulation_state(turnaround_ends: int) -> Dictionary:
	return {
		"name": "Simulation Co",
		"employees": [{"id": "crew-1", "name": "A", "wage_per_hour": 30}],
		"fleet": {
			"vessel-1": {
				"vessel_uid": "vessel-1",
				"route": {
					"origin_port_id": "port-a",
					"destination_port_id": "port-b",
					"duration_seconds": 120,
					"pay_marks": 80,
					"outbound_commodity_id": "provisions",
					"return_commodity_id": "provisions",
				},
				"crew_ids": PackedStringArray(["crew-1"]),
				"status": "preparing",
				"current_port_id": "port-a",
				"leg_origin_port_id": "port-a",
				"leg_destination_port_id": "port-b",
				"commodity_id": "provisions",
				"cargo_ready": false,
				"turnaround_ends_unix": turnaround_ends,
				"completed_legs": 0,
			},
		},
		"ledger": [],
		"last_simulated_unix": 90,
	}
