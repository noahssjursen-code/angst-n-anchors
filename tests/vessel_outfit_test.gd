extends Node

var _failures := PackedStringArray()


func _ready() -> void:
	_test_budget_for_trawler_hull()
	_test_fishing_slot_cap()
	_test_hidden_cargo_rejected()
	_test_official_trawler_passes()
	if _failures.is_empty():
		print("VesselOutfit: budget, anti-exploit, and official SKU checks passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("VesselOutfit: " + failure)
		get_tree().quit(1)


func _test_budget_for_trawler_hull() -> void:
	var budget := VesselOutfit.budget_for_hull("hull_28x10")
	_check(int(budget.get("fishing", 0)) == 1, "fishing budget is 1")
	_check(int(budget.get("helm", 0)) == 1, "helm budget is 1")
	_check(int(budget.get("cargo_cells", 0)) > 0, "cargo cell budget is positive")
	_check(int(budget.get("crane", -1)) == 0, "crane slots closed until gameplay exists")
	_check(int(budget.get("tow", -1)) == 0, "tow slots closed until gameplay exists")


func _test_fishing_slot_cap() -> void:
	var grid := HullRegistry.make_grid("hull_28x10")
	var layout := BrickLayout.new()
	layout.hull_id = "hull_28x10"
	_check(
		layout.place_footprint(Vector3i(2, 0, 18), "trommel_small", 0, grid),
		"first trommel places",
	)
	_check(
		layout.place_footprint(Vector3i(5, 0, 18), "trommel_small", 0, grid),
		"second trommel places",
	)
	var report := VesselOutfit.validate(layout, "hull_28x10", grid)
	_check(not bool(report.get("ok", true)), "two trommels fail outfit validate")
	var accepted: Dictionary = report.get("accepted_slots", {})
	var fishing: Array = accepted.get("fishing", [])
	_check(fishing.size() == 1, "only one fishing slot is accepted for mount")


func _test_hidden_cargo_rejected() -> void:
	var grid := HullRegistry.make_grid("hull_28x10")
	var layout := BrickLayout.new()
	layout.hull_id = "hull_28x10"
	layout.cargo_zones = [{
		"a": [2, 1, 10],
		"b": [4, 1, 12],
	}]
	var report := VesselOutfit.validate(layout, "hull_28x10", grid)
	_check(not bool(report.get("ok", true)), "layered cargo at y=1 fails validate")
	var accepted: Dictionary = report.get("accepted_slots", {})
	_check(
		(accepted.get("cargo_zone_indices", []) as Array).is_empty(),
		"hidden cargo zones are not accepted for mount",
	)


func _test_official_trawler_passes() -> void:
	var found := false
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != "fishing_trawler":
			continue
		found = true
		var layout := BrickLayout.from_dict(entry.get("prebuilt_layout", {}) as Dictionary)
		var report := VesselOutfit.validate(
			layout,
			"hull_28x10",
			HullRegistry.make_grid("hull_28x10"),
		)
		_check(bool(report.get("ok", false)), "official fishing_trawler passes outfit validate")
		_check(bool(report.get("capabilities", {}).get("has_fishing", false)), "trawler has live fishing")
		break
	_check(found, "fishing_trawler appears in prebuilt catalog")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
