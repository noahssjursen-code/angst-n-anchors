extends Node


func _material(root: Node, prefix: String) -> StandardMaterial3D:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		for index in range(node.mesh.get_surface_count()):
			var base: Material = node.mesh.surface_get_material(index)
			if base.resource_name.begins_with(prefix):
				return node.get_active_material(index) as StandardMaterial3D
	return null


func _ready() -> void:
	assert(BrickCatalog.ids().size() == 14)
	assert(not BrickCatalog.has("block"))
	var editor := ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	for i in range(8):
		await get_tree().process_frame
	var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
	assert(parts != null)
	assert(editor.find_child("PartsGrid", true, false).get_child_count() == 14)
	var camera := editor.get("_camera") as Camera3D
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/parts/trawler_rails/halfwall_rising_assembly.json"))
	# Every hull segment resolves its exact asset from only two family choices.
	for style in ["rail", "halfwall"]:
		editor.call("_select_brick", style + "_straight_100cm")
		for rising in [false, true]:
			parts.rising_bow.button_pressed = rising
			var variant: String = style + ("_rising" if rising else "_flat")
			for expected in parts.recipes[variant]:
				if BrickCatalog.get_entry(expected["asset_id"])["kind"] != "panel":
					continue
				var target: Vector3 = (parts._position(expected) + parts._end(expected)) * 0.5
				var actual := parts.candidate_at(camera.unproject_position(target))
				assert(actual.get("asset_id", "") == expected["asset_id"], "Automatic edge variant: " + str(expected["asset_id"]))
				assert(parts.slot_key(actual) == parts.slot_key(expected))
	# Every hull segment resolves its exact asset from only two family choices.
	for style in ["rail", "halfwall"]:
		editor.call("_select_brick", style + "_straight_100cm")
		for rising in [false, true]:
			parts.rising_bow.button_pressed = rising
			var variant: String = style + ("_rising" if rising else "_flat")
			for expected in parts.recipes[variant]:
				if BrickCatalog.get_entry(expected["asset_id"])["kind"] != "panel":
					continue
				var target: Vector3 = (parts._position(expected) + parts._end(expected)) * 0.5
				var actual := parts.candidate_at(camera.unproject_position(target))
				assert(actual.get("asset_id", "") == expected["asset_id"], "Automatic edge variant: " + str(expected["asset_id"]))
				assert(parts.slot_key(actual) == parts.slot_key(expected))
	# Exercise the actual editor selection and click route for the first panel.
	var first: Dictionary = recipe["placements"][0]
	editor.call("_select_brick", "halfwall_straight_100cm")
	var midpoint := (parts._position(first) + parts._end(first)) * 0.5
	editor.call("_paint_at_screen", camera.unproject_position(midpoint))
	assert(parts.records.size() == 1, "Library click must place an imported model")
	for placement in recipe["placements"]:
		var target := (parts._position(placement) + parts._end(placement)) * 0.5
		editor.call("_paint_at_screen", camera.unproject_position(target))
	assert(parts.records.size() == 37)
	var visible_part: Dictionary = recipe["placements"][-3]
	var surface_point := (parts._position(visible_part) + parts._end(visible_part)) * 0.5 + Vector3(0,0.35,0)
	editor.set("_tool", ShipyardBrickEditor.Tool.MARK)
	editor.call("_paint_at_screen", camera.unproject_position(surface_point))
	assert(parts.selected == parts.slot_key(visible_part), "Select must hit the visible wall surface")
	var keys := parts.records.keys()
	parts.selected = keys[0]
	parts.wall_picker.color_changed.emit(Color(0.85, 0.12, 0.08))
	var painted := parts.parts_root.get_child(0)
	var untouched := parts.parts_root.get_child(1)
	var painted_wall := _material(painted,"Warm white painted steel")
	var other_wall := _material(untouched,"Warm white painted steel")
	assert(painted_wall != null and other_wall != null)
	assert(painted_wall.albedo_color.is_equal_approx(Color(0.85,0.12,0.08)))
	assert(not other_wall.albedo_color.is_equal_approx(painted_wall.albedo_color), "Paint must not leak to another instance")
	var cap := _material(painted,"Dark gunwale cap")
	var cap_before := cap.albedo_color
	ModelPaint.apply(painted,{"wall":Color.BLUE})
	assert(_material(painted,"Dark gunwale cap").albedo_color.is_equal_approx(cap_before))
	parts.hull_pickers["upper"].color_changed.emit(Color(0.2,0.45,0.7))
	parts.hull_pickers["lower"].color_changed.emit(Color(0.5,0.12,0.05))
	parts.hull_pickers["deck"].color_changed.emit(Color(0.7,0.65,0.45))
	var hull: Node = editor.get("_imported_hull_preview")
	assert(_material(hull,"Paint_HullUpper").albedo_color.is_equal_approx(Color(0.2,0.45,0.7)))
	assert(_material(hull,"Paint_HullLower").albedo_color.is_equal_approx(Color(0.5,0.12,0.05)))
	assert(_material(hull,"Paint_Deck").albedo_color.is_equal_approx(Color(0.7,0.65,0.45)))
	var stripe := _material(hull,"Fixed_BootStripe")
	assert(stripe.albedo_texture == null and stripe.albedo_color.r < 0.3, "Boot stripe stays dark and fixed")
	var snapshot := JSON.stringify(parts.records)
	var colors := JSON.stringify(parts.hull_colors)
	parts.save_draft("user://imported_parts_paint_test.json")
	parts.records.clear()
	parts.rising_bow.button_pressed = false
	parts.rising_bow.button_pressed = false
	parts.load_draft("user://imported_parts_paint_test.json")
	assert(parts.placement_rising)
	assert(parts.placement_rising)
	assert(JSON.stringify(parts.records) == snapshot)
	assert(JSON.stringify(parts.hull_colors) == colors)
	# Erase through the editor and restore so the captured preview stays complete.
	editor.set("_tool", ShipyardBrickEditor.Tool.ERASE)
	editor.call("_paint_at_screen", camera.unproject_position(midpoint))
	assert(parts.records.size() == 36)
	parts.load_draft("user://imported_parts_paint_test.json")
	editor.set("_tool", ShipyardBrickEditor.Tool.MARK)
	parts.refresh_ui()
	# Place drags must never draw a selection marquee or select the placed model.
	editor.call("_set_tool", ShipyardBrickEditor.Tool.PLACE)
	parts.selection.clear()
	_mouse(editor, camera.unproject_position(midpoint), true)
	_motion(editor, camera.unproject_position(midpoint) + Vector2(20, 20))
	assert(not parts.selection_box_visible())
	assert(parts.selection.is_empty())
	_mouse(editor, camera.unproject_position(midpoint) + Vector2(20, 20), false)
	parts.load_draft("user://imported_parts_paint_test.json")
	editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
	# Exercise mouse press/move/release through the builder's viewport handler.
	var selectable: Array[Node] = []
	for model in parts.parts_root.get_children():
		if model.has_meta("record_key"):
			selectable.append(model)
	var bounds := parts.screen_bounds(selectable[0]).grow(4)
	_mouse(editor, bounds.position, true)
	_motion(editor, bounds.end)
	assert(parts.dragging and parts.selection_box_visible())
	_mouse(editor, bounds.end, false)
	assert(not parts.dragging and parts.selection.size() > 0, "Box drag must select intersecting models")
	var first_selection := parts.selection.duplicate()
	# Reverse-direction additive box must preserve previous selected parts.
	var other := parts.screen_bounds(selectable[18]).grow(4)
	_mouse(editor, other.end, true, true)
	_motion(editor, other.position)
	_mouse(editor, other.position, false, true)
	assert(parts.selection.size() > first_selection.size())
	for key in first_selection:
		assert(parts.selection.has(key))
	# Also send real viewport events through Godot GUI routing, not only the handler.
	parts.selection.clear()
	var host := editor.get("_vp_host") as Control
	var gui_point := host.global_position + surface_point_to_screen(camera, parts, visible_part)
	for pressed in [true, false]:
		var gui_event := InputEventMouseButton.new()
		gui_event.button_index = MOUSE_BUTTON_LEFT
		gui_event.position = gui_point
		gui_event.global_position = gui_point
		gui_event.pressed = pressed
		get_viewport().push_input(gui_event, true)
		await get_tree().process_frame
	assert(parts.selection.size() == 1, "Real GUI mouse routing must select a visible model")
	var hit := parts._hit_record(surface_point_to_screen(camera, parts, visible_part))
	assert(not hit.is_empty())
	parts.select_hit(hit, false)
	assert(parts.selection.size() == 1)
	_mouse(editor, surface_point_to_screen(camera, parts, visible_part), true, true)
	_mouse(editor, surface_point_to_screen(camera, parts, visible_part), false, true)
	assert(parts.selection.is_empty(), "Shift-click toggles a selected part off")
	_key(parts, KEY_A, true)
	assert(parts.selection.size() == 37)
	parts.wall_picker.color_changed.emit(Color(0.3, 0.6, 0.8))
	for record in parts.records.values():
		assert(record["colors"]["wall"] == ModelPaint.encode(Color(0.3, 0.6, 0.8)))
	var before_delete := parts.records.duplicate(true)
	_key(parts, KEY_DELETE)
	assert(parts.records.is_empty() and parts.selection.is_empty())
	_key(parts, KEY_Z, true)
	assert(parts.records == before_delete, "Undo must restore a group deletion")
	_key(parts, KEY_Y, true)
	assert(parts.records.is_empty())
	_key(parts, KEY_Z, true)
	# Empty-space click clears selection; erase uses visible geometry.
	_key(parts, KEY_A, true)
	_mouse(editor, Vector2(5, 5), true)
	_mouse(editor, Vector2(5, 5), false)
	assert(parts.selection.is_empty())
	editor.call("_set_tool", ShipyardBrickEditor.Tool.ERASE)
	_mouse(editor, surface_point_to_screen(camera, parts, visible_part), true)
	_mouse(editor, surface_point_to_screen(camera, parts, visible_part), false)
	assert(parts.records.size() == 36)
	parts.undo()
	assert(parts.records.size() == 37)
	parts.load_draft("user://imported_parts_paint_test.json")
	editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
	# Bow selection reads the actual model, and editing preserves position/paint.
	var bow_keys: Array[String] = []
	for key in parts.records:
		if not parts._bow_variants(parts.records[key]).is_empty():
			bow_keys.append(key)
	assert(bow_keys.size() == 10)
	parts.select_hit(bow_keys[0], false)
	assert(parts.rising_bow.button_pressed and not parts.rising_bow.disabled)
	var original: Dictionary = parts.records[bow_keys[0]].duplicate(true)
	parts.rising_bow.button_pressed = false
	assert(parts.records[bow_keys[0]]["asset_id"] == parts._bow_variants(original)["flat"])
	assert(parts.records[bow_keys[0]]["position"] == original["position"])
	assert(parts.records[bow_keys[0]]["colors"] == original["colors"])
	parts.select_hit(bow_keys[1], true)
	assert(parts.rising_bow.text.contains("Mixed"))
	parts.rising_bow.button_pressed = true
	assert(not parts.rising_bow.text.contains("Mixed"))
	assert(parts.records[bow_keys[0]]["asset_id"] == original["asset_id"])
	parts.undo()
	parts.select_hit(bow_keys[0], false)
	assert(not parts.rising_bow.button_pressed)
	parts.redo()
	parts.select_hit(bow_keys[0], false)
	assert(parts.rising_bow.button_pressed)
	parts.select_hit(bow_keys[1], true)
	parts.refresh_ui()
	for model in parts.parts_root.get_children():
		var highlighted := parts.selection.has(str(model.get_meta("record_key", "")))
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			assert((mesh.material_overlay != null) == highlighted)
	editor.call("_set_tool", ShipyardBrickEditor.Tool.PLACE)
	for model in parts.parts_root.get_children():
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			assert(mesh.material_overlay == null)
	editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
	parts.select_hit(parts.slot_key(first), false)
	assert(parts.rising_bow.disabled, "Straight walls have no bow profile")
	parts.select_hit(bow_keys[0], false)
	parts.select_hit(bow_keys[1], true)
	print("PASS: model overlays, Select-only marquee, bow profile inspection/editing/mixed state/undo")
	print("PASS: click, box drag both directions, additive selection, Shift toggle, group paint, Delete, undo/redo, visible-surface erase")
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Documents/Codex/2026-10-05/referenced-chatgpt-conversation-this-is-an/outputs/trawler-rails/parts-library-paint.png")
	print("PASS: two families resolve all 148 perimeter choices; library placement, independent wall/cap and hull paint, erase, and draft round-trip")
	editor.queue_free()
	for i in range(4):
		await get_tree().process_frame
	get_tree().quit()


func surface_point_to_screen(camera: Camera3D, parts: ImportedShipPartsEditor, record: Dictionary) -> Vector2:
	return camera.unproject_position((parts._position(record) + parts._end(record)) * 0.5 + Vector3(0, 0.35, 0))


func _mouse(editor: ShipyardBrickEditor, point: Vector2, pressed: bool, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	event.shift_pressed = shift
	editor.call("_on_viewport_gui_input", event)


func _motion(editor: ShipyardBrickEditor, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	editor.call("_on_viewport_gui_input", event)


func _key(parts: ImportedShipPartsEditor, code: Key, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	assert(parts.key_input(event))
