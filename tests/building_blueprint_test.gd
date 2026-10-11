extends Node

const ARCHIVE := "res://resources/data/buildings/archive/"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Old layouts remain recoverable without reviving the removed block library.
	assert(not BrickCatalog.has("block"))
	for blueprint_id in ["harbouroffice", "warehouse"]:
		assert(not BuildingBlueprintCatalog.ids().has(blueprint_id))
		assert(BuildingBlueprintCatalog.by_id(blueprint_id) == null)
		assert(BuildingBlueprintCatalog.build(blueprint_id) == null)
		assert(BuildingBlueprintCatalog.by_id("archive/" + blueprint_id) == null)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			ARCHIVE + blueprint_id + ".json"))
		var archived := BuildingLayout.from_dict(raw)
		assert(not archived.cells.is_empty())
		assert(archived.to_dict()["cells"] == raw["cells"], "archive round-trip must retain placements")
		var report := BuildingRules.validate(archived)
		assert(not report.ok, "retired layouts must still fail explicit validation")
		assert(report.errors.size() < 20, "report asset types, not thousands of cells")

	assert(BuildingBlueprintCatalog.by_id("missing_building") == null)
	assert(BuildingBlueprintCatalog.by_id("  ") == null)
	for specimen in PerfShowcase.SPECIMENS:
		assert(specimen.id not in ["harbouroffice", "warehouse"], "retired buildings cannot be preview choices")
	for blueprint_id in BuildingBlueprintCatalog.ids():
		var loaded := BuildingBlueprintCatalog.by_id(blueprint_id)
		assert(loaded != null and loaded.blueprint_id == blueprint_id)

	# Repeated bad placements stay invalid, with one counted diagnostic per type.
	var invalid := BuildingLayout.new()
	for index in range(100):
		invalid.cells[BuildingLayout.cell_key(Vector3i(index, 0, 0))] = {
			"brick_id": "missing_test_brick", "yaw": 0,
		}
	var report := BuildingRules.validate(invalid)
	assert(not report.ok and report.errors.size() == 1)
	assert(report.errors[0] == "Unknown brick 'missing_test_brick' (100 placements).")
	invalid.cells = {"0,0,0": {"brick_id": "cabin_wall_straight", "yaw": 0}}
	report = BuildingRules.validate(invalid)
	assert(not report.ok and report.errors.size() == 1)
	assert(report.errors[0].begins_with("Ship-only brick"))

	# Exercise the exact failing runtime path: rebuilding harbour apron pads.
	var graph := PortLayoutGraph.new()
	graph.initial_attributes = {"land_plan": {"apron_pads": {"pads": [
		{"id": "office", "role": "harbour_office", "pad_template_id": "pad_2x3",
			"origin": [0.0, 0.0], "size_m": [20.0, 30.0]},
		{"id": "warehouse", "role": "general_warehouse", "pad_template_id": "pad_2x2",
			"origin": [30.0, 0.0], "size_m": [20.0, 20.0]},
	]}}}
	var original := graph.initial_attributes.duplicate(true)
	var visual := PortLayoutGraphVisualizer.new()
	add_child(visual)
	for rebuild in range(3):
		visual.configure(graph)
		assert(visual.get_node("ApronPads").get_child_count() == 2)
		for site_name in ["office", "warehouse"]:
			var site := visual.get_node("ApronPads/" + site_name)
			assert(site.has_node("PadSlab") and site.has_node("PadMass"))
			assert(not site.has_node("BuildingLod"))
	assert(graph.initial_attributes == original, "presentation must not alter saved port data")
	visual.free()
	print("building_blueprint_test: PASS (archived layouts, strict validation, repeated port rebuilds)")
	get_tree().quit(0)
