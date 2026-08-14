extends Node

const TestReport := preload("res://tests/support/test_report.gd")

var _t := TestReport.new("shipyard_editor_ui_test", false)


func _ready() -> void:
	var editor := ShipyardBrickEditor.new()
	add_child(editor)
	await get_tree().process_frame

	_check(editor.find_child("TopBar", true, false) != null, "top bar exists")
	_check(editor.find_child("PartsPalette", true, false) != null, "parts palette exists")
	_check(editor.find_child("BuildViewport", true, false) != null, "build viewport exists")
	_check(editor.find_child("ContextStrip", true, false) != null, "viewport context strip exists")
	_check(editor.find_child("PropertiesDrawer", true, false) != null, "properties drawer exists")
	_check(editor.find_child("ShipDialog", true, false) != null, "ship dialog exists")
	_check(editor.find_child("PowerHeader", true, false) != null, "ship dialog exposes per-ship shaft power")
	_check(editor.find_child("RegistrationOption", true, false) != null, "legal registration picker exists")
	_check(editor.find_child("HelpOverlay", true, false) != null, "help overlay exists")
	_check(editor.find_child("ClearConfirmation", true, false) != null, "clear confirmation exists")

	var parts_grid := editor.find_child("PartsGrid", true, false) as GridContainer
	_check(parts_grid != null and parts_grid.columns == 2, "palette uses compact two-column tiles")
	_check(
		parts_grid != null and parts_grid.get_child_count() == BrickCatalog.ids().size(),
		"every catalog brick remains available",
	)
	_check(BrickCatalog.has("railing_45"), "45-degree railing is in the shared catalog")
	_check(BrickCatalog.has("mast_base"), "mast base is in the shared catalog")
	_check(BrickCatalog.has("mast_pole"), "mast pole is in the shared catalog")
	_check(
		BrickCatalog.has_tag("railing_45", "diagonal_plan"),
		"45-degree railing can follow tapered bow cells",
	)
	_check(
		BrickCatalog.footprint_of("mast_base") == Vector3i(2, 1, 2),
		"mast base centres on a 2x2 deck pad",
	)
	_check(
		BrickCatalog.footprint_of("mast_pole") == Vector3i(2, 1, 2),
		"mast pole stacks on the same 2x2 column",
	)
	_check(BrickCatalog.has_tag("mast_base", "ship_only"), "mast base is ship-only")
	_check(BrickCatalog.has_tag("mast_pole", "mast"), "mast pole shares the mast tag")
	var mast_base := BrickCatalog.create_visual("mast_base")
	var mast_pole := BrickCatalog.create_visual("mast_pole")
	_check(mast_base.get_child_count() >= 4, "mast base builds a tabernacle assembly")
	_check(mast_pole.get_child_count() >= 3, "mast pole builds a stackable spar segment")
	mast_base.free()
	mast_pole.free()
	var railing := BrickCatalog.create_visual("railing")
	var railing_45 := BrickCatalog.create_visual("railing_45")
	## Two edge posts + handrail + mid-rail + toe plate.
	_check(railing.get_child_count() == 5, "straight railing is a tileable edge-post segment")
	_check(railing_45.get_child_count() == 1, "45-degree railing wraps a diagonal segment")
	## `position.z < -0.4` was a restated number, not a property. It was derived
	## from a 1.0 m cell — `_railing_edge_z` returns `-sz.z * 0.5 + 0.028`, which
	## was -0.472 while `WorldUnits.DECK_CELL_M` was 1.0. `a70bdbc` halved that
	## constant to 0.5, so the face moved to -0.25 and the rail to -0.222, and a
	## bound of -0.4 became unreachable: it now asks for a post OUTSIDE the cell
	## it belongs to. The railing is drawn exactly where it always was, in cell
	## terms. State that instead — every part of the run hugs the -Z cell face,
	## measured against the brick's own size, so the check survives the next
	## change to the cell constant.
	var rail_face_z := -BrickCatalog.size_m("railing").z * 0.5
	var outboard := 0
	for child in railing.get_children():
		var part := child as Node3D
		if part != null and part.position.z <= rail_face_z + 0.08 and part.position.z >= rail_face_z:
			outboard += 1
	_check(
		outboard == railing.get_child_count() and railing.get_child_count() > 0,
		"straight railing sits on the local -Z cell face (%d of %d parts within 0.08 m of z=%.3f)"
		% [outboard, railing.get_child_count(), rail_face_z],
	)
	var diagonal_root: Node3D = railing_45.get_child(0) as Node3D
	_check(
		diagonal_root != null and is_equal_approx(diagonal_root.rotation_degrees.y, 45.0),
		"45-degree railing follows the block_45 diagonal",
	)
	railing.free()
	railing_45.free()

	editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
	var drawer := editor.find_child("PropertiesDrawer", true, false) as Control
	_check(drawer != null and drawer.visible, "selection mode shows contextual drawer")
	editor.call("_set_tool", ShipyardBrickEditor.Tool.ERASE)
	_check(drawer != null and not drawer.visible, "erase mode removes irrelevant drawer")
	editor.call("_set_tool", ShipyardBrickEditor.Tool.PLACE)
	_check(drawer != null and drawer.visible, "place mode restores properties drawer")

	var hulls := HullRegistry.catalog()
	_check(not hulls.is_empty(), "hull catalog is available")
	if not hulls.is_empty():
		editor.open_for_authoring(hulls[0] as Dictionary)
		await get_tree().process_frame
		var grid := editor.get("_grid") as DeckGrid
		var layout := editor.get("_layout") as BrickLayout
		_check(grid != null and layout != null, "editor opens a buildable hull")
		if grid != null and layout != null:
			editor.set("_registration_id", "general_vessel")
			editor.call("_select_registration_option", "general_vessel")
			var cell := Vector3i(grid.width / 2, 0, grid.length / 2)
			editor.call("_select_brick", "block")
			_check(bool(editor.call("_try_place", cell)), "place workflow adds a brick")
			editor.call("_refresh_rules")
			var confirm := editor.get("_confirm_btn") as Button
			_check(
				confirm != null and not confirm.disabled,
				"incomplete legal checklist still allows draft save in the authoring tool",
			)
			_check(
				confirm != null and "draft" in confirm.text.to_lower(),
				"confirm button offers draft save while checklist is incomplete",
			)
			editor.set("_mark_min", cell)
			editor.set("_mark_max", cell)
			editor.set("_mark_complete", true)
			editor.call("_copy_marked_region")
			var clipboard: Dictionary = editor.get("_clipboard")
			_check(int(clipboard.get("cell_count", 0)) == 1, "copy workflow captures selection")
			editor.call("_set_layer_y", 1)
			editor.call("_paste_clipboard_on_layer")
			_check(layout.has_cell(Vector3i(cell.x, 1, cell.z)), "paste-on-layer stamps copied brick")

	editor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_t.finish(get_tree())


func _check(condition: bool, message: String) -> void:
	_t.check(message, condition)
