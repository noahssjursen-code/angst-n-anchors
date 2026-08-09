extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")

## The voxel brick vocabulary was wiped on 2026-07-24 with the Structure Studio
## rework: `BrickCatalog.BRICKS` is `{}`, the two authored blueprints went with it,
## and the building brick editor scene was retired. Nothing that names a brick id
## can be placed, validated or baked until the rebuild lands — `set_brick()`,
## `place_footprint()` and `BuildingRules.validate()` all gate on
## `BrickCatalog.has()`. So this file covers the brick-independent half of the
## blueprint pipeline plus the gates that keep dead vocabulary out of the catalog.
##
## The two tripwires in `_check_vocabulary_still_wiped` go red the moment the
## vocabulary or a blueprint returns. That is the cue to restore the placement,
## footprint and bake coverage this file carried before the wipe — see
## `git show aabdf198` for what it used to assert.


func _initialize() -> void:
	var t := TestReport.new("building_blueprint_test")
	_run(t)
	t.finish(self)


func _run(t: TestReport) -> void:
	_check_vocabulary_still_wiped(t)
	_check_catalog_gate(t)
	_check_grid_math(t)
	_check_layout_bookkeeping(t)
	_check_volume_growth(t)
	_check_serialisation(t)
	_check_fitout(t)


func _check_vocabulary_still_wiped(t: TestReport) -> void:
	t.check(
		"brick vocabulary is still wiped — when it returns, restore placement coverage here",
		BrickCatalog.ids().is_empty(),
	)
	t.check("no building brick survives the wipe either", BrickCatalog.ids_for_buildings().is_empty())
	t.check(
		"no blueprint is authored yet — when the first lands, assert it loads and validates",
		BuildingBlueprintCatalog.ids().is_empty(),
	)
	t.check("the catalog therefore yields no layouts", BuildingBlueprintCatalog.all().is_empty())


## Everything downstream of the catalog refuses ids it cannot resolve. These are
## the checks that make the empty vocabulary a hard stop rather than silent rot.
func _check_catalog_gate(t: TestReport) -> void:
	var layout := BuildingLayout.new()
	layout.grid_size = Vector3i(8, 6, 8)
	t.check("set_brick refuses an uncatalogued id", not layout.set_brick(Vector3i(1, 0, 1), "block"))
	t.check(
		"place_footprint refuses an uncatalogued id",
		not layout.place_footprint(Vector3i(1, 0, 1), "block", 0),
	)
	t.check("a refused placement stores nothing", layout.count() == 0)

	## A blueprint carrying dead vocabulary must be rejected, not half-loaded.
	var stale := BuildingLayout.new()
	stale.grid_size = Vector3i(8, 6, 8)
	stale.cells = {"1,0,1": {"brick_id": "block", "yaw": 0}}
	var stale_report := BuildingRules.validate(stale)
	t.check("a layout naming a dead brick fails validation", not bool(stale_report.get("ok", true)))
	t.check(
		"the error names the unknown brick",
		_contains(stale_report.get("errors", PackedStringArray()), "Unknown brick 'block'"),
	)

	var blank_report := BuildingRules.validate(BuildingLayout.new())
	t.check("an empty layout still validates", bool(blank_report.get("ok", false)))
	t.check(
		"an empty layout warns that it has no bricks",
		_contains(blank_report.get("warnings", PackedStringArray()), "no bricks"),
	)

	var null_report := BuildingRules.validate(null)
	t.check("a null layout fails validation", not bool(null_report.get("ok", true)))

	t.check("by_id rejects a blank id", BuildingBlueprintCatalog.by_id("   ") == null)
	t.check(
		"load_path returns null for a missing file",
		BuildingBlueprintCatalog.load_path("res://resources/data/buildings/not_a_file.json") == null,
	)
	# Filename stem is the public id.
	t.check(
		"path_for maps an id onto the blueprint directory",
		BuildingBlueprintCatalog.path_for("warehouse") == "res://resources/data/buildings/warehouse.json",
	)


func _check_grid_math(t: TestReport) -> void:
	var grid := BuildingGrid.create(Vector3i(8, 6, 8))
	t.check("create keeps the requested size", grid.size() == Vector3i(8, 6, 8))
	t.check(
		"create clamps every axis to at least one cell",
		BuildingGrid.create(Vector3i(0, -3, 2)).size() == Vector3i(1, 1, 2),
	)
	t.check("the far corner is in bounds", grid.in_bounds(Vector3i(7, 5, 7)))
	t.check("one cell past the width is out of bounds", not grid.in_bounds(Vector3i(8, 0, 0)))
	t.check("a negative index is out of bounds", not grid.in_bounds(Vector3i(-1, 0, 0)))

	## The 2×3×1 door footprint the pre-wipe test asserted, stated in grid terms.
	var upright := grid.footprint_cells(Vector3i(3, 0, 1), Vector3i(2, 3, 1), 0)
	t.check("a 2×3×1 footprint occupies six cells", upright.size() == 6)
	t.check("it spans two cells on X", upright.has(Vector3i(4, 0, 1)))
	t.check("it spans three cells on Y", upright.has(Vector3i(3, 2, 1)))
	t.check("it stays one cell deep on Z", not upright.has(Vector3i(3, 0, 2)))

	var yawed := grid.footprint_cells(Vector3i(3, 0, 1), Vector3i(2, 3, 1), 1)
	t.check("a quarter turn keeps the cell count", yawed.size() == 6)
	t.check("a quarter turn swaps the span onto Z", yawed.has(Vector3i(3, 0, 2)))
	t.check("a quarter turn frees the X neighbour", not yawed.has(Vector3i(4, 0, 1)))

	t.check(
		"cell centres are X/Z-centred at ground level",
		grid.cell_center_local(Vector3i(1, 0, 1)).is_equal_approx(Vector3(-2.5, 0.5, -2.5)),
	)
	t.check(
		"a cell centre maps back to its own cell",
		grid.local_to_cell(grid.cell_center_local(Vector3i(1, 0, 1))) == Vector3i(1, 0, 1),
	)


func _check_layout_bookkeeping(t: TestReport) -> void:
	t.check("cell keys carry the sign", BuildingLayout.cell_key(Vector3i(-2, 0, 3)) == "-2,0,3")
	t.check("cell keys parse back", BuildingLayout.parse_cell_key("-2,0,3") == Vector3i(-2, 0, 3))
	t.check(
		"a malformed cell key parses to the sentinel",
		BuildingLayout.parse_cell_key("nonsense") == Vector3i(-1, -1, -1),
	)

	t.check("yaw wraps negatives", BuildingLayout.norm_yaw(-90) == 270)
	t.check("yaw wraps past a full turn", BuildingLayout.norm_yaw(450) == 90)
	t.check("yaw snaps to the 90° step", BuildingLayout.norm_yaw(200) == 180)
	t.check("yaw snaps to a finer step", BuildingLayout.norm_yaw(200, 45) == 180)

	var painted := {"brick_id": "block", "color": BuildingLayout.color_to_array(Color(0.7, 0.2, 0.15))}
	t.check("a painted entry stores its colour", painted.has("color"))
	t.check(
		"a painted entry keeps the requested colour",
		BuildingLayout.color_from_entry(painted, "block").is_equal_approx(Color(0.7, 0.2, 0.15)),
	)
	t.check(
		"an unpainted uncatalogued brick falls back to neutral grey",
		BuildingLayout.color_from_entry({"brick_id": "block"}, "block").is_equal_approx(
			Color(0.7, 0.7, 0.7)
		),
	)

	## Multi-cell bricks store one primary entry plus `occupied_by` fillers.
	var layout := BuildingLayout.new()
	layout.grid_size = Vector3i(8, 6, 8)
	layout.cells = {
		"1,0,1": {"brick_id": "block", "yaw": 0},
		"2,0,1": {"brick_id": "block", "yaw": 0, "occupied_by": "1,0,1"},
		"1,1,1": {"brick_id": "block", "yaw": 90},
	}
	t.check("every stored cell counts", layout.count() == 3)
	t.check("iter_cells returns fillers too", layout.iter_cells().size() == 3)
	t.check("primary cells skip occupied fillers", layout.iter_primary_cells().size() == 2)
	t.check(
		"primary cells come back bottom-up",
		(layout.iter_primary_cells()[0]["cell"] as Vector3i) == Vector3i(1, 0, 1),
	)
	t.check("a filler resolves to its primary", layout.primary_cell_of(Vector3i(2, 0, 1)) == Vector3i(1, 0, 1))
	t.check("a filler blocks its cell", layout.has_blocking_content(Vector3i(2, 0, 1)))
	t.check("an empty cell blocks nothing", not layout.has_blocking_content(Vector3i(5, 5, 5)))
	t.check("get_brick on an empty cell is empty", layout.get_brick(Vector3i(5, 5, 5)).is_empty())

	t.check("erasing an empty cell reports nothing removed", not layout.erase_footprint_at(Vector3i(5, 5, 5)))
	t.check("erasing a filler reports a removal", layout.erase_footprint_at(Vector3i(2, 0, 1)))
	t.check("erasing a filler takes the whole footprint with it", layout.count() == 1)
	t.check("the unrelated brick above survives", layout.has_cell(Vector3i(1, 1, 1)))


## `ensure_fit_cells` grows the authoring volume symmetrically on X/Z so existing
## bricks keep their world position. That invariant is the point of the test.
func _check_volume_growth(t: TestReport) -> void:
	var layout := BuildingLayout.new()
	layout.grid_size = Vector3i(8, 6, 8)
	layout.cells = {
		"0,0,0": {"brick_id": "block", "yaw": 0},
		"1,0,0": {"brick_id": "block", "yaw": 0, "occupied_by": "0,0,0"},
	}
	var before := layout.grid().cell_center_local(Vector3i(0, 0, 0))

	t.check("an in-bounds cell needs no growth", layout.ensure_fit_cells([Vector3i(1, 1, 1)]) == Vector3i.ZERO)
	t.check("an empty request needs no growth", layout.ensure_fit_cells([]) == Vector3i.ZERO)
	t.check("the volume is untouched", layout.grid_size == Vector3i(8, 6, 8))

	var shift := layout.ensure_fit_cells([Vector3i(-2, 0, 0)])
	t.check("growing past -X shifts existing cells by the overhang", shift == Vector3i(2, 0, 0))
	t.check("X grows on both sides", layout.grid_size == Vector3i(12, 6, 8))
	t.check("the existing brick moved to its shifted index", layout.has_cell(Vector3i(2, 0, 0)))
	t.check("its old index is vacated", not layout.has_cell(Vector3i(0, 0, 0)))
	t.check(
		"the shifted brick keeps its world position",
		layout.grid().cell_center_local(Vector3i(2, 0, 0)).is_equal_approx(before),
	)
	t.check(
		"the filler's occupied_by is remapped with it",
		layout.primary_cell_of(Vector3i(3, 0, 0)) == Vector3i(2, 0, 0),
	)

	var tall := BuildingLayout.new()
	tall.grid_size = Vector3i(8, 6, 8)
	t.check("growing up needs no shift", tall.ensure_fit_cells([Vector3i(0, 9, 0)]) == Vector3i.ZERO)
	t.check("height grows upward only", tall.grid_size == Vector3i(8, 10, 8))


func _check_serialisation(t: TestReport) -> void:
	var layout := BuildingLayout.new()
	layout.blueprint_id = "roundtrip_house"
	layout.display_name = "Roundtrip House"
	layout.role = "service"
	layout.pad_template_id = "pad_2x2"
	layout.grid_size = Vector3i(8, 6, 8)
	layout.cells = {
		"1,0,1": {"brick_id": "block", "yaw": 0},
		"2,0,1": {"brick_id": "block", "yaw": 0, "occupied_by": "1,0,1"},
		"1,1,1": {"brick_id": "block", "yaw": 90},
	}

	var data := layout.to_dict()
	t.check("the dict is stamped with the format version", int(data.get("format_version", -1)) == 1)
	t.check("a pad-bound blueprint records its pad template", data.has("pad_template_id"))
	t.check(
		"a freeform blueprint omits the pad key",
		not BuildingLayout.new().to_dict().has("pad_template_id"),
	)
	(data["cells"] as Dictionary).erase("1,0,1")
	t.check("to_dict hands out a deep copy", layout.count() == 3)

	var restored := BuildingLayout.from_dict(layout.to_dict())
	t.check("the id survives the round-trip", restored.blueprint_id == "roundtrip_house")
	t.check("the display name survives", restored.display_name == "Roundtrip House")
	t.check("the role survives", restored.role == "service")
	t.check("the pad template survives", restored.pad_template_id == "pad_2x2")
	t.check("the grid size survives", restored.grid_size == Vector3i(8, 6, 8))
	t.check("every cell survives", restored.count() == 3)
	t.check("primary cells skip occupied fillers", restored.iter_primary_cells().size() == 2)
	t.check(
		"yaw survives the dict round-trip",
		int(restored.get_brick(Vector3i(1, 1, 1)).get("yaw", 0)) == 90,
	)

	var defaults := BuildingLayout.from_dict({})
	t.check("an empty dict falls back to the untitled id", defaults.blueprint_id == "untitled_building")
	t.check("an empty dict falls back to decorative", defaults.role == "decorative")
	t.check("an empty dict falls back to the default volume", defaults.grid_size == Vector3i(32, 16, 32))
	t.check("an empty dict has no cells", defaults.count() == 0)

	## A stored blueprint whose cells exceed its declared grid_size is refitted on
	## load rather than silently dropped.
	var oversize := BuildingLayout.from_dict({
		"id": "oversize",
		"grid_size": [4, 4, 4],
		"cells": {"0,0,6": {"brick_id": "block", "yaw": 0}},
	})
	t.check("loading refits Z around the out-of-bounds cell", oversize.grid_size == Vector3i(4, 4, 10))
	t.check("the cell was shifted into the grown volume", oversize.has_cell(Vector3i(0, 0, 9)))
	t.check("and it is now in bounds", oversize.grid().in_bounds(Vector3i(0, 0, 9)))


func _check_fitout(t: TestReport) -> void:
	var layout := BuildingLayout.new()
	layout.blueprint_id = "roundtrip_house"
	layout.grid_size = Vector3i(8, 6, 8)
	layout.cells = {"1,0,1": {"brick_id": "block", "yaw": 0}}

	var fitout := BuildingFitout.build(layout)
	t.check("the fitout root uses the shared name", fitout.name == BuildingFitout.ROOT_NAME)
	t.check(
		"fitout carries the blueprint id",
		str(fitout.get_meta("building_blueprint_id", "")) == "roundtrip_house",
	)
	t.check("lighting is attached", fitout.get_node_or_null("BuildingLighting") != null)
	t.check("a collision root is attached", fitout.get_node_or_null("Collision") != null)
	## No brick in the layout is catalogued, so nothing is drawn — a stale blueprint
	## bakes to an empty building rather than to placeholder boxes.
	t.check("only lighting and collision are built", fitout.get_child_count() == 2)
	fitout.free()

	var bare := BuildingFitout.build(layout, false)
	t.check("collision can be switched off", bare.get_node_or_null("Collision") == null)
	t.check("lighting stays", bare.get_child_count() == 1)
	bare.free()

	var empty := BuildingFitout.build(null)
	t.check("a null layout yields a bare root", empty.get_child_count() == 0)
	t.check("a null layout stamps no blueprint id", not empty.has_meta("building_blueprint_id"))
	empty.free()

	## An uncatalogued brick falls back to a 1×1×1 footprint centred on its cell.
	var grid := layout.grid()
	t.check(
		"an unknown brick centres on its own cell",
		BuildingFitout.footprint_center_local(grid, Vector3i(1, 0, 1), "block", 0).is_equal_approx(
			grid.cell_center_local(Vector3i(1, 0, 1))
		),
	)


func _contains(lines: Variant, needle: String) -> bool:
	if not (lines is PackedStringArray or lines is Array):
		return false
	for line in lines:
		if str(line).contains(needle):
			return true
	return false
