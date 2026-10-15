extends Node

const LIBRARY = preload("res://scripts/port/building/custom_port_library.gd")
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const PRESENTER = preload("res://scripts/port/building/custom_port_presenter.gd")
var checks := 0
var failures: Array[String] = []
var choices: Array[String] = []

func _ready() -> void:
	var catalog := CustomPortCatalog.definitions()
	var before := JSON.stringify(catalog)
	var library := LIBRARY.new()
	add_child(library)
	library.configure(catalog, "foundation")
	_check(library.visible_asset_ids().size() == catalog.size() - 2, "Only the two legacy solid-box buildings are absent from new construction")
	_check(not library._buttons.has("warehouse") and not library._buttons.has("workshop") and not library._groups.has("Buildings"),
		"Legacy placeholders have no buttons or empty category")
	for id in catalog:
		if str(id).begins_with("workshop_"):
			_check(library.visible_asset_ids().has(id), "Authored modular piece remains available: " + id)
	library.asset_selected.connect(func(id: String): choices.append(id))
	library._choose("warehouse")
	library._choose("workshop")
	library._choose("unknown-piece")
	_check(choices.is_empty() and library._selected == "foundation", "Hidden and unknown choices cannot emit an equip request")
	library._choose("workshop_door_4m")
	_check(choices == ["workshop_door_4m"], "An available authored piece still emits a normal equip request")
	library.set_selected("foundation")
	_check(library._headings.size() == library.category.item_count - 1, "Categories have one heading each")
	_check(library._buttons.foundation.button_pressed, "Equipped piece is highlighted")
	_search(library, "  TRIANGLE   4  ")
	_check(library.visible_asset_ids() == ["foundation_triangle_4m"], "Search combines words, dimensions and case")
	_search(library, "no such crane exists")
	_check(library.visible_asset_ids().is_empty() and library._empty.visible, "No matches gives a clear empty result")
	_check(library._selected == "foundation", "Searching does not silently equip something else")
	_search(library, "")
	var fittings := -1
	for i in library.category.item_count:
		if library.category.get_item_text(i) == "Quay fittings": fittings = i
	_check(fittings >= 0, "Existing catalog supplies the fittings category")
	library.category.select(fittings)
	library.category.item_selected.emit(fittings)
	for id in library.visible_asset_ids():
		_check(catalog[id].category == "Quay fittings", "Category filter contains only its own pieces: " + id)
	_search(library, "tyre")
	_check(library.visible_asset_ids() == ["tractor_tire_fender"], "Search and category intersect")
	library.set_selected("tractor_tire_fender")
	_check(library._buttons.tractor_tire_fender.button_pressed and not library._buttons.foundation.button_pressed,
		"Only the equipped piece is highlighted")
	_check(library.selected_details.text.contains("quay edge") and library.selected_details.text.contains("1.5 × 0.62"),
		"Dimensions and snap behaviour use the real asset data")
	library.set_selected("container_crane_bay")
	_check(library.selected_details.text.contains("Reach") and library.selected_details.text.contains("empty yard"),
		"Crane selection explains actual reach and empty storage")
	_check(before == JSON.stringify(catalog), "Browsing does not mutate construction definitions")
	_test_legacy_saved_buildings(catalog)
	if failures.is_empty(): print("CUSTOM PORT LIBRARY PASS (%d checks)" % checks)
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_legacy_saved_buildings(catalog: Dictionary) -> void:
	var record := {"schema_version":1, "id":"legacy-port", "name":"Older saved harbour", "owner_company_id":"company-a",
		"world":{"seed":44, "generation_version":7, "checksum":"test-coast"}, "origin_m":[1000,0,2000], "deck_height_above_sea_m":2,
		"plots":[{"id":"plot-a", "rect_m":[-100,-100,200,200], "owner_company_id":"company-a"}],
		"placements":[CustomPortCatalog.placement("old-warehouse", "warehouse", Vector3(-20,0,0), 90, {"display_name":"Keep old warehouse"}),
			CustomPortCatalog.placement("old-workshop", "workshop", Vector3(20,0,0))],
		"water_regions":[], "stores":[], "vessels":[], "reservations":[], "receipts":{}, "revision":3}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(record, "", true, true))
	var state := STATE.from_dict(decoded, decoded.world, catalog)
	_check(state.validation_errors.is_empty(), "Saved legacy buildings still validate: %s" % [state.validation_errors])
	_check(state.to_dict().placements == decoded.placements, "Saved building IDs, poses and custom attributes remain untouched")
	var presenter := PRESENTER.new()
	presenter.simulate_vessels = false
	add_child(presenter)
	var snapshot := state.to_dict()
	presenter.load_record(snapshot)
	for id in ["old-warehouse", "old-workshop"]:
		var node: Node3D = presenter.placement_nodes.get(id)
		_check(is_instance_valid(node), "Legacy building still has its existing presentation: " + id)
		if not is_instance_valid(node): continue
		var colliders := node.find_children("*", "CollisionShape3D", true, false)
		var expected := Vector3(12,6,8) if id == "old-warehouse" else Vector3(8,4,8)
		_check(colliders.size() == 1 and colliders[0].shape is BoxShape3D and colliders[0].shape.size.is_equal_approx(expected),
			"Legacy full-box collision dimensions remain unchanged: " + id)
		_check(node.find_children("*", "MeshInstance3D", true, false).size() == 2, "Legacy box and flat roof remain unchanged: " + id)
	_check(state.to_dict() == snapshot, "Legacy presentation does not rewrite the saved document")
	presenter.free()

func _search(library: Control, text: String) -> void:
	library.search.text = text
	library.search.text_changed.emit(text)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
