extends Node

var _failures := PackedStringArray()


func _ready() -> void:
	_test_catalog_and_inheritance()
	_test_official_fishing_registration()
	_test_fishing_berth_deployment_filter()
	_test_official_starter_catalog()
	_test_stricter_registration_budget()
	_test_nav_light_placement()
	_test_seeded_registration_types()
	_test_deployment_gate()
	if _failures.is_empty():
		print("Vessel registration: legal code, checklists, and lifecycle gates passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("Vessel registration: " + failure)
		get_tree().quit(1)


func _test_catalog_and_inheritance() -> void:
	var ids := VesselRegistrationCatalog.ids()
	for required in [
		"general_vessel", "fishing_vessel", "cargo_vessel", "passenger_vessel"
	]:
		_check(ids.has(required), required + " exists")
	var general := VesselRegistrationCatalog.resolved_registration("general_vessel")
	var fishing := VesselRegistrationCatalog.resolved_registration("fishing_vessel")
	_check(
		(fishing.get("rules", []) as Array).size() > (general.get("rules", []) as Array).size(),
		"fishing inherits general-vessel legal code",
	)
	_check(
		HarbourDeploy.terminal_families_for_registration("fishing_vessel") \
				== PackedStringArray(["fishing"]),
		"fishing vessels deploy only at fishing berths",
	)


func _official_trawler() -> Dictionary:
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			return entry
	return {}


func _test_official_fishing_registration() -> void:
	var entry := _official_trawler()
	_check(not entry.is_empty(), "official trawler survives catalog compliance gate")
	if entry.is_empty():
		return
	_check(not bool(entry.get("is_draft", true)), "certified trawler is not a draft")
	var hull_id := str(entry.get("hull_id", ""))
	var report := VesselCompliance.validate(
		BrickLayout.from_dict(entry.get("prebuilt_layout", {}) as Dictionary),
		hull_id,
		str(entry.get("registration_id", "")),
		HullRegistry.make_grid(hull_id),
	)
	_check(bool(report.get("ok", false)), "official trawler is certified fishing vessel")
	_check((report.get("checklist", []) as Array).size() >= 10, "inherited checklist is visible")
	var bollard_item := {}
	for raw in report.get("checklist", []) as Array:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == "mooring_points":
			bollard_item = raw
			break
	_check(not bollard_item.is_empty(), "general code requires mooring points")
	_check(bool(bollard_item.get("ok", false)), "official trawler meets the four-mooring minimum")
	_check(BrickCatalog.has("railing_mooring"), "railing with mooring bit exists")
	_check(
		BrickCatalog.has_tag("railing_mooring", "railing")
		and BrickCatalog.has_tag("railing_mooring", "mooring"),
		"railing_mooring is both railing and mooring gear",
	)


func _test_fishing_berth_deployment_filter() -> void:
	var record := _official_trawler()
	if record.is_empty():
		return
	var harbour := HarbourController.new()
	harbour.setup("test-port")
	var cargo := QuayBerthSlot.new()
	cargo.setup("berth:cargo", "cargo", "general", PackedStringArray(["provisions"]), 100.0, 20.0)
	var fishing := QuayBerthSlot.new()
	fishing.setup("berth:fishing", "fishing", "fishing", PackedStringArray(["fresh_groundfish"]), 100.0, 20.0)
	harbour.register_berth(cargo)
	harbour.register_berth(fishing)
	var slots := HarbourDeploy.free_slots_for(harbour, record)
	_check(slots.size() == 1, "trawler has exactly one compatible berth")
	_check(not slots.is_empty() and slots[0] == fishing, "trawler rejects a general-cargo quay")
	harbour.unregister_all()
	cargo.free()
	fishing.free()
	harbour.free()

func _test_official_starter_catalog() -> void:
	var found_starter := false
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != "28_10_m":
			continue
		found_starter = true
		_check(not bool(entry.get("is_draft", true)), "28×10 m cargo starter is certified")
		_check(bool(entry.get("compliance_ok", false)), "28×10 m cargo starter passes compliance")
		_check(not entry.get("prebuilt_layout", {}).is_empty(), "starter keeps its brick layout")
		break
	_check(found_starter, "28×10 m starter stays in the authoring catalog")
	for sale in PrebuiltVesselCatalog.for_sale_entries():
		_check(
			not bool(sale.get("is_draft", false)),
			"Shipwright sale list excludes drafts",
		)
		_check(
			bool(sale.get("compliance_ok", false)),
			"Shipwright sale list is compliance-certified",
		)


func _test_stricter_registration_budget() -> void:
	var hull_budget := VesselOutfit.budget_for_hull("hull_90x24")
	var registration := VesselRegistrationCatalog.resolved_registration("cargo_vessel")
	var effective := VesselOutfit.budget_for_hull(
		"hull_90x24", registration.get("budget_caps", {}) as Dictionary
	)
	_check(
		int(effective.get("cargo_cells", 0)) == 600
			and int(hull_budget.get("cargo_cells", 0)) > int(effective.get("cargo_cells", 0)),
		"registration cargo maximum tightens a larger physical hull",
	)
	_check(int(effective.get("fishing", -1)) == 0, "cargo registration forbids fishing gear")
	_check(
		not VesselCompliance.brick_allowed_for_registration(
			"cargo_vessel", "hull_90x24", "trommel_small"
		),
		"trommel is not placeable on a cargo vessel",
	)
	_check(
		VesselCompliance.brick_allowed_for_registration(
			"fishing_vessel", "hull_90x24", "trommel_small"
		),
		"trommel remains placeable on a fishing vessel",
	)


func _test_nav_light_placement() -> void:
	var entry := _official_trawler()
	if entry.is_empty():
		return
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var cells := layout_dict.get("cells", {}) as Dictionary
	for key in cells.keys():
		var item := cells[key] as Dictionary
		var light_id := str(item.get("light_id", ""))
		if light_id == "light_nav_port":
			item["light_id"] = "light_nav_stbd"
		elif light_id == "light_nav_stbd":
			item["light_id"] = "light_nav_port"
	var report := VesselCompliance.validate(
		BrickLayout.from_dict(layout_dict),
		str(entry.get("hull_id", "")),
		"fishing_vessel",
		HullRegistry.make_grid(str(entry.get("hull_id", ""))),
	)
	_check(not bool(report.get("ok", true)), "swapped port/starboard lights fail registration")


func _test_seeded_registration_types() -> void:
	var entry := _official_trawler()
	if entry.is_empty():
		return
	var hull_id := str(entry.get("hull_id", ""))
	var original := entry.get("prebuilt_layout", {}) as Dictionary
	for registration_id in ["general_vessel", "cargo_vessel"]:
		var report := VesselCompliance.validate(
			BrickLayout.from_dict(original), hull_id, registration_id, HullRegistry.make_grid(hull_id)
		)
		_check(
			not bool(report.get("ok", true)),
			registration_id + " rejects fishing gear on a trawler layout",
		)
	var passenger := BrickLayout.from_dict(original)
	passenger.container_pads.clear()
	var fishing_cells: Array[Vector3i] = []
	for item in passenger.iter_primary_cells():
		var brick_id := str(item.get("brick_id", ""))
		if VesselCompliance.outfit_slot_for_brick(brick_id) == "fishing":
			fishing_cells.append(item["cell"] as Vector3i)
	for cell in fishing_cells:
		passenger.erase_footprint_at(cell)
	for i in range(4):
		passenger.set_brick(Vector3i(2 + i, 2, 10), "passenger_seat", 0)
	var passenger_report := VesselCompliance.validate(
		passenger, hull_id, "passenger_vessel", HullRegistry.make_grid(hull_id)
	)
	_check(bool(passenger_report.get("ok", false)), "passenger registration uses explicit seat capacity")


func _test_deployment_gate() -> void:
	var entry := _official_trawler()
	if entry.is_empty():
		return
	var record := {
		"uid": "registration_test",
		"hull_id": entry.get("hull_id", ""),
		"registration_id": entry.get("registration_id", ""),
		"brick_layout": entry.get("prebuilt_layout", {}),
	}
	_check(
		not VesselSpawn.resolve_deployable_record(record).is_empty(),
		"certified vessel is deployable",
	)
	record["registration_id"] = "review_required"
	_check(
		VesselSpawn.resolve_deployable_record(record).is_empty(),
		"legacy review-required vessel is blocked from deployment",
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
