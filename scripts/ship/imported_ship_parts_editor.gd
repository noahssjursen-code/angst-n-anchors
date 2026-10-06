class_name ImportedShipPartsEditor
extends Node

const ROOT := "res://resources/models/parts/trawler_rails/"
const FLOOR_HEIGHT := 2.2
const CELL_HEIGHT := 0.1
const CELLS_PER_FLOOR := 22
const DECK_HEIGHT := 2.92
var deck_height := DECK_HEIGHT
var hull_id := "trawler_hull_14m"
const MAX_FLOOR := 24
const SAVE_PATH := "user://imported_trawler_draft.json"
var editor: ShipyardBrickEditor
var records: Dictionary = {}
var hull_colors: Dictionary = {}
var mesh_faces: Dictionary = {}
var selection: Dictionary = {}
var selected: String:
	get:
		return str(selection.keys()[0]) if not selection.is_empty() else ""
	set(value):
		selection.clear()
		if not value.is_empty():
			selection[value] = true
var overlay: Control
var dragging := false
var drag_start := Vector2.ZERO
var drag_end := Vector2.ZERO
var drag_add := false
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var gesture_snapshot: Dictionary = {}
var delete_button: Button
var selection_label: Label
var wall_color := Color(0.74, 0.78, 0.75)
var recipes: Dictionary = {}
var rising_bow: CheckButton
var placement_rising := false
var selection_material: StandardMaterial3D
var parts_root: Node3D
var ghost: Node3D
var panel: VBoxContainer
var wall_picker: ColorPickerButton
var info: Label
var hull_pickers: Dictionary = {}
var _ghost_key := ""
var structure_anchor: Variant = null
var reference_root: Node3D
var moving_reference := false
var door_open: CheckButton
var placement_hint: Label
var end_run_button: Button
var draft_path := ""
var saved_state := ""
var save_dialog: FileDialog
var load_dialog: FileDialog
var unsaved_dialog: ConfirmationDialog
var draft_menu: PopupMenu
var pending_action: Callable
var draft_tick := 0.0
var right_start := Vector2.ZERO
var right_dragged := false
var previous_auto_accept_quit := true
var active_floor := 0
var cell_offset := 0
var surface_outline := PackedVector2Array()
var surface_cursor := Vector2.ZERO
var surface_pickers: Dictionary = {}
var surface_colors: Dictionary = {}
var close_surface_button: Button
var roof_crown: CheckButton
var roof_visor: OptionButton
var roof_visor_label: Label
var counter_picker: ColorPickerButton
var upholstery_picker: ColorPickerButton
var interaction_button: Button
var steering_slider: HSlider
var throttle_slider: HSlider
var furniture_yaw := 0.0
var console_side := 1
var placement_crown := false
var placement_visor := 0
var floor_label: Label
var floor_down: Button
var floor_up: Button


func setup(owner_editor: ShipyardBrickEditor) -> void:
	editor = owner_editor
	selection_material = StandardMaterial3D.new()
	selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_material.albedo_color = Color(0.1, 0.85, 1.0, 0.5)
	selection_material.render_priority = 1
	selection_material.no_depth_test = true
	selection_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor.get("_viewport").add_child(overlay)
	overlay.draw.connect(_draw_selection)
	# Old rotation/layer controls do not apply to perimeter models.
	var toolbar: Node = editor.get("_tool_mark_btn").get_parent()
	for child in toolbar.get_children():
		if child == editor.get("_layer_lbl") or (child is Button and child.text in ["Rotate  R", "−", "+"]):
			child.hide()
	var floors := HBoxContainer.new()
	floors.name = "FloorControls"
	toolbar.add_child(floors)
	toolbar.move_child(floors, 3)
	floor_down = Button.new()
	floor_down.text = "Floor down"
	floor_down.tooltip_text = "Down one storey (2.2 m) · Page Down / ["
	floor_down.pressed.connect(func() -> void: set_floor(active_floor - 1, cell_offset))
	floors.add_child(floor_down)
	floor_label = Label.new()
	floor_label.custom_minimum_size.x = 140
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floors.add_child(floor_label)
	floor_up = Button.new()
	floor_up.text = "Floor up"
	floor_up.tooltip_text = "Up one storey (2.2 m) · Page Up / ]"
	floor_up.pressed.connect(func() -> void: set_floor(active_floor + 1, cell_offset))
	floors.add_child(floor_up)
	parts_root = Node3D.new()
	parts_root.name = "ImportedPlacedParts"
	editor.get("_world").add_child(parts_root)
	recipes = ImportedHullCatalog.rail_recipes(hull_id)
	for slot in ["upper", "lower", "deck"]:
		hull_colors[slot] = ModelPaint.encode(ModelPaint.DEFAULTS[slot])
	var col := editor.get("_context_drawer").get_child(0) as VBoxContainer
	for child in col.get_children():
		(child as Control).hide()
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	col.add_child(panel)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(info)
	rising_bow = CheckButton.new()
	rising_bow.text = "Rising bow"
	rising_bow.tooltip_text = "Set the profile of selected bow pieces, or the profile for new pieces in Place mode."
	rising_bow.toggled.connect(_set_bow_profile)
	panel.add_child(rising_bow)
	door_open = CheckButton.new()
	door_open.text = "Open door"
	door_open.toggled.connect(_set_doors_open)
	panel.add_child(door_open)
	interaction_button=Button.new()
	interaction_button.text="Interact with selected item"
	interaction_button.pressed.connect(_interact_selected)
	panel.add_child(interaction_button)
	for channel in ["steering","throttle"]:
		var name_label:=Label.new();name_label.text="Test "+channel
		panel.add_child(name_label)
		var slider:=HSlider.new();slider.min_value=-1;slider.max_value=1;slider.step=.05
		var field: String=channel
		slider.value_changed.connect(func(value: float) -> void: _request_part_state(field,value))
		panel.add_child(slider)
		if channel=="steering": steering_slider=slider
		else: throttle_slider=slider
	placement_hint = Label.new()
	placement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(placement_hint)
	end_run_button = Button.new()
	end_run_button.text = "End run · Esc / right-click"
	end_run_button.pressed.connect(cancel_placement)
	panel.add_child(end_run_button)
	var reference_toggle := CheckButton.new()
	reference_toggle.text = "Player scale reference"
	reference_toggle.button_pressed = true
	reference_toggle.toggled.connect(func(show_reference: bool) -> void: reference_root.visible = show_reference)
	panel.add_child(reference_toggle)
	var move_reference := Button.new()
	move_reference.text = "Move scale reference"
	move_reference.pressed.connect(func() -> void:
		moving_reference = true
		structure_anchor = null
		surface_outline.clear()
		clear_ghost()
		placement_hint.text = "Click the deck to move the player reference."
	)
	panel.add_child(move_reference)
	_build_scale_reference()
	selection_label = Label.new()
	panel.add_child(selection_label)
	delete_button = Button.new()
	delete_button.text = "Delete selected · Del"
	delete_button.pressed.connect(delete_selected)
	panel.add_child(delete_button)
	var undo_button := Button.new()
	undo_button.text = "Undo · Ctrl+Z"
	undo_button.pressed.connect(undo)
	panel.add_child(undo_button)
	wall_picker = _picker("Wall / door paint", wall_color, func(color: Color) -> void:
		wall_color = color
		remember()
		for key in selection:
			if records.has(key) and _paintable(str(records[key]["asset_id"])):
				records[key]["colors"] = {"wall": ModelPaint.encode(color)}
		rebuild()
		clear_ghost()
	)
	roof_crown = CheckButton.new()
	roof_crown.text = "Shallow crown"
	roof_crown.toggled.connect(func(enabled: bool) -> void:
		placement_crown=enabled
		_update_roof_profile()
	)
	panel.add_child(roof_crown)
	roof_visor_label=Label.new()
	roof_visor_label.text="Extended overhang"
	panel.add_child(roof_visor_label)
	roof_visor=OptionButton.new()
	for title in ["None - uniform edge", "Bow side", "Stern side", "Port side", "Starboard side"]: roof_visor.add_item(title)
	roof_visor.item_selected.connect(func(index: int) -> void:
		placement_visor=index
		_update_roof_profile()
	)
	panel.add_child(roof_visor)
	close_surface_button = Button.new()
	close_surface_button.text = "Finish outline · Enter"
	close_surface_button.pressed.connect(_finish_surface)
	panel.add_child(close_surface_button)
	for slot in ["surface", "fascia", "underside"]:
		var target: String = slot
		surface_colors[slot] = ModelPaint.encode(ModelPaint.DEFAULTS[slot])
		surface_pickers[slot] = _picker({"surface":"Floor / roof surface", "fascia":"Roof edge", "underside":"Underside"}[slot], ModelPaint.DEFAULTS[slot], func(color: Color) -> void:
			surface_colors[target] = ModelPaint.encode(color)
			remember()
			for key in selection:
				if records.has(key) and ShipSurfaceKit.is_surface(records[key]["asset_id"]):
					if not records[key].has("colors"): records[key]["colors"] = surface_colors.duplicate(true)
					records[key]["colors"][target] = ModelPaint.encode(color)
			rebuild()
			clear_ghost()
		)
	counter_picker=_picker("Console worktop",Color(.055,.075,.085),func(color: Color) -> void:
		remember()
		for key in selection:
			if records.has(key) and BrickCatalog.get_entry(records[key]["asset_id"]).get("kind","")=="console":
				var colors: Dictionary=records[key].get("colors",{}).duplicate()
				colors["surface"]=ModelPaint.encode(color)
				records[key]["colors"]=colors
		rebuild()
	)
	upholstery_picker=_picker("Seat upholstery",Color(.065,.11,.14),func(color: Color) -> void:
		remember()
		for key in selection:
			if records.has(key) and BrickCatalog.get_entry(records[key]["asset_id"]).get("style","") in ["helm_chair","passenger_seat","bench"]:
				var colors: Dictionary=records[key].get("colors",{}).duplicate()
				colors["upholstery"]=ModelPaint.encode(color)
				records[key]["colors"]=colors
		rebuild()
	)
	var main_panel := panel
	var hull_toggle := Button.new()
	hull_toggle.text = "Hull colours ▸"
	hull_toggle.toggle_mode = true
	main_panel.add_child(hull_toggle)
	var hull_panel := VBoxContainer.new()
	hull_panel.visible = false
	main_panel.add_child(hull_panel)
	hull_toggle.toggled.connect(func(opened: bool) -> void:
		hull_panel.visible = opened
		hull_toggle.text = "Hull colours ▾" if opened else "Hull colours ▸"
	)
	panel = hull_panel
	for slot in ["upper", "lower", "deck"]:
		var target: String = slot
		hull_pickers[slot] = _picker({"upper":"Upper hull", "lower":"Lower hull", "deck":"Deck"}[slot], ModelPaint.DEFAULTS[slot], func(color: Color) -> void:
			hull_colors[target] = ModelPaint.encode(color)
			ModelPaint.apply(editor.get("_imported_hull_preview"), hull_colors)
		)
	var reset := Button.new()
	reset.text = "Reset hull colours"
	reset.pressed.connect(func() -> void:
		for slot in hull_pickers:
			hull_colors[slot] = ModelPaint.encode(ModelPaint.DEFAULTS[slot])
			hull_pickers[slot].color = ModelPaint.DEFAULTS[slot]
		ModelPaint.apply(editor.get("_imported_hull_preview"), hull_colors)
	)
	panel.add_child(reset)
	panel = main_panel
	_setup_drafts()
	ModelPaint.apply(editor.get("_imported_hull_preview"), hull_colors)
	refresh_ui()
	saved_state = _draft_state()
	_update_draft_title()
	_apply_floor_view()


func _picker(title: String, color: Color, callback: Callable) -> ColorPickerButton:
	var label := Label.new()
	label.text = title
	panel.add_child(label)
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(0, 32)
	picker.color = color
	picker.color_changed.connect(callback)
	panel.add_child(picker)
	return picker


func refresh_ui() -> void:
	editor.get("_context_drawer").show()
	var id: String = editor.get("_brick_id")
	if records.has(selected):
		id = records[selected]["asset_id"]
	var paintable := _paintable(id) if selection.is_empty() else false
	for key in selection:
		if records.has(key) and _paintable(str(records[key]["asset_id"])):
			paintable = true
	var selected_style: String=BrickCatalog.get_entry(id).get("style","")
	interaction_button.text="Open / close door" if selected_style=="door" else ("Leave seat (preview)" if bool(records.get(selected,{}).get("part_state",{}).get("occupied",false)) else "Occupy seat (preview)")
	interaction_button.visible=not selection.is_empty() and selected_style in ["door","helm_chair","passenger_seat"]
	steering_slider.visible=not selection.is_empty() and selected_style=="wheel"
	throttle_slider.visible=not selection.is_empty() and selected_style=="throttle"
	for slider in [steering_slider,throttle_slider]: slider.get_parent().get_child(slider.get_index()-1).visible=slider.visible
	wall_picker.disabled = not paintable
	counter_picker.visible=selected_style=="console"
	counter_picker.get_parent().get_child(counter_picker.get_index()-1).visible=counter_picker.visible
	upholstery_picker.visible=selected_style in ["helm_chair","passenger_seat","bench"]
	upholstery_picker.get_parent().get_child(upholstery_picker.get_index()-1).visible=upholstery_picker.visible
	wall_picker.visible = paintable and not upholstery_picker.visible
	wall_picker.get_parent().get_child(wall_picker.get_index()-1).visible = wall_picker.visible
	selection_label.text = "%d parts selected" % selection.size()
	delete_button.disabled = selection.is_empty()
	_sync_bow_control()
	_sync_door_control()
	end_run_button.visible = structure_anchor != null or moving_reference or not surface_outline.is_empty()
	close_surface_button.visible = _surface_family() and int(editor.get("_tool")) == ShipyardBrickEditor.Tool.PLACE
	close_surface_button.disabled = surface_outline.size() < 3
	var show_roof := id=="roof_tile"
	roof_crown.visible=show_roof
	roof_visor.visible=show_roof
	roof_visor_label.visible=show_roof
	for picker in surface_pickers.values():
		picker.get_parent().get_child(picker.get_index()-1).visible = _surface_family() or ShipSurfaceKit.is_surface(id)
		picker.visible = _surface_family() or ShipSurfaceKit.is_surface(id)
	editor.get("_hint_lbl").text = tool_hint()
	placement_hint.text = "Walls / doors / windows: click a start, then aim and click to join. 0.5 m grid; angles fit automatically. Escape ends the run." if _structural_family() else "Railings / half-walls: click the hull edge."
	if _furniture_family():
		placement_hint.text="Click to place; R rotates 45 degrees. Wheel, throttle and display mount on a console countertop. Select to test controls."
	if selected_style=="bench":
		placement_hint.text="Draw a bench run along a wall; straight lengths every 0.5 m, up to 6 m per section. F flips the seating side; Esc ends the run."
	if selected_style=="console":
		placement_hint.text="Draw along the inside of window walls. F flips the console side; Esc ends the run."
	if _surface_family():
		placement_hint.text = "Click outline corners · Click first point / Enter to finish · Backspace removes last point · Esc cancels. Straight, 26.565° or 45° edges."
	_sync_selection_visuals()
	overlay.queue_redraw()
	info.text = "Selected parts" if not selection.is_empty() else "Build settings"


func _point(screen: Vector2) -> Variant:
	var camera := editor.get("_camera") as Camera3D
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	if absf(ray.y) < 0.00001:
		return null
	var t := (floor_y() - origin.y) / ray.y
	return origin + ray * t if t > 0 else null


func _position(record: Dictionary) -> Vector3:
	var p: Array = record["position"]
	return Vector3(p[0], p[1], p[2])


func _end(record: Dictionary) -> Vector3:
	var entry := BrickCatalog.get_entry(record["asset_id"])
	var p: Array = entry["end_xz"]
	return _position(record) + Basis(Vector3.UP, deg_to_rad(float(record["yaw_degrees"]))) * Vector3(p[0], 0, p[1])


func _distance(point: Vector3, record: Dictionary) -> float:
	var start := _position(record)
	var end := _end(record)
	if start.is_equal_approx(end):
		return point.distance_to(start)
	return point.distance_to(Geometry3D.get_closest_point_to_segment(point, start, end))


func slot_key(record: Dictionary) -> String:
	var a := _position(record)
	if record["asset_id"] == "bulk_divider_5m": return "%.4f|bulk_divider|%.3f,%.3f" % [a.y,a.x,a.z]
	if ShipSurfaceKit.is_surface(record["asset_id"]):
		var vertices: Array[String] = []
		for p in record.get("outline", []): vertices.append("%.3f,%.3f" % [p[0],p[1]])
		vertices.sort()
		return "%.4f|surface|" % a.y + ":".join(vertices)
	if BrickCatalog.get_entry(record["asset_id"]).get("kind", "") == "furniture":
		return "%.4f|item|%.3f,%.3f" % [a.y,a.x,a.z]
	var b := _end(record)
	var keys := ["%.4f,%.4f" % [a.x,a.z], "%.4f,%.4f" % [b.x,b.z]]
	keys.sort()
	return "%.4f|" % a.y + (str(BrickCatalog.get_entry(record["asset_id"])["kind"])+"|" if BrickCatalog.get_entry(record["asset_id"]).get("kind", "") in ["console","bench"] else "") + ":".join(keys)


func candidate_at(screen: Vector2) -> Dictionary:
	var point: Variant = _point(screen)
	if point == null:
		return {}
	if _furniture_family():
		return _furniture_candidate(point)
	if _structural_family():
		return _structural_candidate(point)
	var best: Dictionary = {}
	var distance := 0.8
	var id: String = editor.get("_brick_id")
	var style: String = BrickCatalog.get_entry(id).get("style", "")
	var variant := style + ("_rising" if placement_rising else "_flat")
	for base_candidate in recipes.get(variant, []):
		var candidate: Dictionary = base_candidate.duplicate(true)
		candidate["position"][1] = floor_y()
		if BrickCatalog.get_entry(candidate["asset_id"]).get("kind", "") != "panel":
			continue
		var d := _distance(point, candidate)
		if d < distance:
			distance = d
			best = candidate
	return best


func hover(screen: Vector2) -> void:
	if moving_reference or int(editor.get("_tool")) != ShipyardBrickEditor.Tool.PLACE:
		clear_ghost()
		return
	if _surface_family():
		_hover_surface(screen)
		return
	var candidate := candidate_at(screen)
	if candidate.is_empty():
		clear_ghost()
		return
	var key := slot_key(candidate) + str(candidate["asset_id"])
	if key == _ghost_key:
		return
	clear_ghost()
	ghost = create_part(candidate)
	editor.get("_world").add_child(ghost)
	editor.call("_tint_ghost", ghost, true)
	_ghost_key = key


func clear_ghost() -> void:
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	_ghost_key = ""


func create_part(record: Dictionary) -> Node3D:
	var root := ShipSurfaceKit.create(record) if ShipSurfaceKit.is_surface(record["asset_id"]) else BrickCatalog.create_visual(record["asset_id"])
	root.position = _position(record)
	root.rotation_degrees.y = float(record["yaw_degrees"])
	_fit_wall_ends(root, record)
	if _paintable(str(record["asset_id"])):
		ModelPaint.apply(root, record.get("colors", {"wall": ModelPaint.encode(wall_color)}))
	if ShipSurfaceKit.is_surface(record["asset_id"]):
		ModelPaint.apply(root, record.get("colors", surface_colors))
	if BrickCatalog.get_entry(record["asset_id"]).get("style","") in ["door","wheel","throttle","helm_chair","passenger_seat","display"]:
		var driver:=ShipPartState.new()
		driver.name="PartState"
		root.add_child(driver)
		driver.setup(root,true)
		driver.apply_snapshot(record.get("part_state",{"door_open":bool(record.get("door_open",false))}),0,true)
	return root


func place_record(candidate: Dictionary) -> void:
	remember()
	var record := candidate.duplicate(true)
	if _paintable(str(record["asset_id"])):
		record["colors"] = {"wall": ModelPaint.encode(wall_color)}
	if BrickCatalog.get_entry(record["asset_id"]).get("kind","")=="console":
		record["colors"]["surface"]=ModelPaint.encode(counter_picker.color)
	if BrickCatalog.get_entry(record["asset_id"]).get("style","") in ["helm_chair","passenger_seat","bench"]:
		record["colors"]["upholstery"]=ModelPaint.encode(upholstery_picker.color)
	records[slot_key(record)] = record
	rebuild()
	refresh_ui()


func click(screen: Vector2) -> void:
	var tool: int = editor.get("_tool")
	if moving_reference:
		var point: Variant = _point(screen)
		if point != null and _on_deck(point):
			reference_root.position = point
			moving_reference = false
			refresh_ui()
		return
	if tool == ShipyardBrickEditor.Tool.PLACE and _surface_family():
		_click_surface(screen)
		return
	if tool == ShipyardBrickEditor.Tool.PLACE and _structural_family():
		var point: Variant = _point(screen)
		if point == null:
			return
		if structure_anchor == null:
			var start := _snap_structure(point)
			if _on_deck(start):
				structure_anchor = start
		else:
			var candidate := _structural_candidate(point)
			if not candidate.is_empty():
				place_record(candidate)
				structure_anchor = _end(candidate)
		clear_ghost()
		refresh_ui()
		return
	if tool == ShipyardBrickEditor.Tool.PLACE:
		var candidate := candidate_at(screen)
		if not candidate.is_empty():
			place_record(candidate)
		return
	var hit := _hit_record(screen)
	if tool == ShipyardBrickEditor.Tool.ERASE:
		if records.has(hit):
			remember()
			records.erase(hit)
			selection.erase(hit)
			rebuild()
	else:
		select_hit(hit, false)
	refresh_ui()


func select_hit(hit: String, additive: bool) -> void:
	if not additive:
		selection.clear()
	if not hit.is_empty():
		if additive and selection.has(hit):
			selection.erase(hit)
		else:
			selection[hit] = true
		if records.has(hit):
			var raw: Array = records[hit].get("colors", {}).get("wall", ModelPaint.encode(ModelPaint.DEFAULTS["wall"]))
			wall_color = Color(raw[0], raw[1], raw[2])
			wall_picker.color = wall_color
			var live: Dictionary=records[hit].get("part_state",{})
			steering_slider.set_value_no_signal(float(live.get("steering",0.0)))
			throttle_slider.set_value_no_signal(float(live.get("throttle",0.0)))

			if ShipSurfaceKit.is_surface(records[hit]["asset_id"]):
				placement_crown=bool(records[hit].get("crown",false))
				placement_visor=int(records[hit].get("visor_direction",0))
				roof_crown.set_pressed_no_signal(placement_crown)
				roof_visor.select(placement_visor)
				for slot in surface_pickers:
					var tint: Array = records[hit].get("colors",{}).get(slot,ModelPaint.encode(ModelPaint.DEFAULTS[slot]))
					surface_colors[slot]=tint.duplicate()
					surface_pickers[slot].set_block_signals(true)
					surface_pickers[slot].color=Color(tint[0],tint[1],tint[2])
					surface_pickers[slot].set_block_signals(false)
	refresh_ui()


func _hit_record(screen: Vector2) -> String:
	var camera := editor.get("_camera") as Camera3D
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest := INF
	var found := ""
	for model in parts_root.get_children():
		if not _on_active_floor(model):
			continue
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var inverse: Transform3D = mesh.global_transform.affine_inverse()
			var local_origin: Vector3 = inverse * origin
			var local_ray: Vector3 = inverse.basis * direction
			if _pick_bounds(mesh).intersects_ray(local_origin, local_ray) == null:
				continue
			var faces := _deformed_faces(mesh)
			for index in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_ray, faces[index], faces[index + 1], faces[index + 2])
				if hit is Vector3:
					var point: Vector3 = mesh.global_transform * hit
					var distance := origin.distance_to(point)
					if distance < nearest:
						nearest = distance
						found = str(model.get_meta("record_key"))
	return found


func rebuild() -> void:
	for child in parts_root.get_children():
		parts_root.remove_child(child)
		child.queue_free()
	var joints: Dictionary = {}
	for record in records.values():
		var model := create_part(record)
		model.set_meta("record_key", slot_key(record))
		parts_root.add_child(model)
		var spec := BrickCatalog.get_entry(record["asset_id"])
		if spec["style"] != "rail" or spec["kind"] == "joint":
			continue
		for endpoint in [0,1]:
			var point := _position(record) if endpoint == 0 else _end(record)
			var height := float(spec["height_start_m"] if endpoint == 0 else spec["height_end_m"])
			var key := "%.4f,%.4f,%.4f" % [point.x,point.y,point.z]
			var level := clampi(roundi((height-1.0)/0.15),0,5)
			joints[key] = {"asset_id":"rail_joint_%d" % level, "position":[point.x,point.y,point.z], "yaw_degrees":0,"owner_key":slot_key(record)}
	for joint in joints.values():
		var post := create_part(joint)
		post.set_meta("record_key", joint["owner_key"])
		parts_root.add_child(post)
	_sync_selection_visuals()
	_apply_floor_view()


func reset_colors() -> void:
	wall_color = ModelPaint.DEFAULTS["wall"]
	wall_picker.color = wall_color
	remember()
	for key in selection:
		if records.has(key) and _paintable(str(records[key]["asset_id"])):
			records[key]["colors"] = {"wall":ModelPaint.encode(wall_color)}
	for slot in hull_pickers:
		hull_colors[slot] = ModelPaint.encode(ModelPaint.DEFAULTS[slot])
		hull_pickers[slot].color = ModelPaint.DEFAULTS[slot]
	ModelPaint.apply(editor.get("_imported_hull_preview"), hull_colors)
	rebuild()


func _draft_data() -> Dictionary:
	return {"version":1,"hull":hull_id,"hull_colors":hull_colors,"parts":records.values(),"rising_bow":placement_rising,"active_floor":active_floor,"cell_offset":cell_offset}


func _draft_state() -> String:
	return JSON.stringify(_draft_data())


func save_draft(path: String = "") -> void:
	finish_gesture()
	if path.is_empty():
		if draft_path.is_empty():
			show_save_as()
			return
		path = draft_path
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		pending_action = Callable()
		editor.call("_show_toast", "Could not save draft. Choose a writable folder.", true)
		return
	file.store_string(JSON.stringify(_draft_data(), "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		pending_action = Callable()
		editor.call("_show_toast", "Draft write failed. Previous file kept.", true)
		return
	if FileAccess.file_exists(absolute):
		if DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
			pending_action = Callable()
			editor.call("_show_toast", "Could not back up draft. Previous file kept.", true)
			return
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		pending_action = Callable()
		editor.call("_show_toast", "Could not replace draft. Previous file kept.", true)
		return
	draft_path = path
	saved_state = _draft_state()
	_update_draft_title()
	editor.call("_show_toast", "Saved " + path.get_file())
	_continue_pending()


func _valid_colors(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not ModelPaint.SLOTS.has(key) or not value[key] is Array or value[key].size() != 3:
			return false
		for component in value[key]:
			if not (component is float or component is int) or not is_finite(float(component)) or component < 0 or component > 1:
				return false
	return true


func load_draft(path: String = SAVE_PATH) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var valid: bool = data is Dictionary
	if valid:
		valid = data.get("version",0) == 1 and ImportedHullCatalog.has(str(data.get("hull",""))) and data.get("parts") is Array and _valid_colors(data.get("hull_colors",{}))
	if valid:
		var stored_floor: Variant = data.get("active_floor", 0)
		valid = (stored_floor is int or stored_floor is float) and is_finite(float(stored_floor)) and float(stored_floor) == floor(float(stored_floor)) and stored_floor >= 0 and stored_floor <= MAX_FLOOR
	if valid:
		var stored_cell: Variant = data.get("cell_offset", 0)
		valid = (stored_cell is int or stored_cell is float) and is_finite(float(stored_cell)) and float(stored_cell) == floor(float(stored_cell)) and stored_cell >= 0 and stored_cell < CELLS_PER_FLOOR
		valid = valid and (data.get("active_floor", 0) < MAX_FLOOR or stored_cell == 0)
	var loaded := {}
	if valid:
		for record in data["parts"]:
			if not record is Dictionary or not BrickCatalog.has(str(record.get("asset_id",""))) or not record.get("position") is Array or record["position"].size() != 3 or not _valid_colors(record.get("colors",{})):
				valid = false
				break
			for number in record["position"] + [record.get("yaw_degrees")]:
				if not (number is float or number is int) or not is_finite(float(number)):
					valid = false
			if not valid:
				break
			if ShipSurfaceKit.is_surface(record["asset_id"]):
				if not _valid_surface_record(record):
					valid = false
					break
			if record.has("part_state"):
				var validator:=ShipPartState.new()
				valid=record["part_state"] is Dictionary and validator.apply_snapshot(record["part_state"],0)
				validator.free()
				if not valid: break
			var key := slot_key(record)
			if loaded.has(key):
				valid = false
				break
			loaded[key] = record
	if not valid:
		editor.call("_show_toast", "Cannot open draft: missing, damaged or unsupported. Current work kept.", true)
		return
	cancel_placement()
	undo_stack.clear()
	redo_stack.clear()
	hull_id = data.hull
	deck_height = float(ImportedHullCatalog.ENTRIES[hull_id].depth_m)
	active_floor = 0
	cell_offset = 0
	editor.set_imported_hull(hull_id)
	recipes = ImportedHullCatalog.rail_recipes(hull_id)
	rising_bow.visible = ImportedHullCatalog.ENTRIES[hull_id].rising
	if is_instance_valid(reference_root): reference_root.position = Vector3(0,deck_height,float(ImportedHullCatalog.ENTRIES[hull_id].reference_z))
	records = loaded
	placement_rising = bool(data.get("rising_bow", false)) and ImportedHullCatalog.ENTRIES[hull_id].rising
	rising_bow.set_pressed_no_signal(placement_rising)
	selected = ""
	hull_colors = data.get("hull_colors",{}).duplicate(true)
	for slot in hull_pickers:
		var raw: Array = hull_colors.get(slot,ModelPaint.encode(ModelPaint.DEFAULTS[slot]))
		hull_colors[slot] = raw
		hull_pickers[slot].set_block_signals(true)
		hull_pickers[slot].color = Color(raw[0],raw[1],raw[2])
		hull_pickers[slot].set_block_signals(false)
	ModelPaint.apply(editor.get("_imported_hull_preview"), hull_colors)
	rebuild()
	refresh_ui()
	set_floor(int(data.get("active_floor", 0)), int(data.get("cell_offset", 0)))
	draft_path = path
	saved_state = _draft_state()
	_update_draft_title()
	editor.call("_show_toast", "Opened " + path.get_file())


func _process(_delta: float) -> void:
	draft_tick += _delta
	if draft_tick > 0.25:
		draft_tick = 0
		_update_draft_title()
	if is_instance_valid(overlay):
		overlay.queue_redraw()


func _exit_tree() -> void:
	if is_instance_valid(editor) and editor.standalone_tool and get_tree() != null:
		get_tree().auto_accept_quit = previous_auto_accept_quit
	if is_instance_valid(reference_root):
		reference_root.queue_free()
	if is_instance_valid(overlay):
		overlay.queue_free()


func screen_bounds(model: Node3D) -> Rect2:
	var camera := editor.get("_camera") as Camera3D
	var bounds := Rect2()
	var initialized := false
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = _pick_bounds(mesh)
		for i in range(8):
			var world_point: Vector3 = mesh.global_transform * aabb.get_endpoint(i)
			if camera.is_position_behind(world_point):
				continue
			var point := camera.unproject_position(world_point)
			if not initialized:
				bounds = Rect2(point, Vector2.ZERO)
				initialized = true
			else:
				bounds = bounds.expand(point)
	return bounds


func _draw_selection() -> void:
	if not surface_outline.is_empty() and _surface_family() and int(editor.get("_tool")) == ShipyardBrickEditor.Tool.PLACE:
		var camera := editor.get("_camera") as Camera3D
		var points := surface_outline.duplicate()
		points.append(surface_cursor)
		for i in points.size():
			var p := camera.unproject_position(Vector3(points[i].x,floor_y()+.11,points[i].y))
			overlay.draw_circle(p,5,Color(1,.65,.15))
			if i>0:
				var previous := camera.unproject_position(Vector3(points[i-1].x,floor_y()+.11,points[i-1].y))
				overlay.draw_line(previous,p,Color(1,.65,.15),2,true)
	if structure_anchor != null and int(editor.get("_tool")) == ShipyardBrickEditor.Tool.PLACE:
		var camera := editor.get("_camera") as Camera3D
		var point := camera.unproject_position(structure_anchor)
		overlay.draw_circle(point, 5, Color(1, 0.65, 0.15))
	if selection_box_visible():
		var rect := Rect2(drag_start, drag_end - drag_start).abs()
		overlay.draw_rect(rect, Color(0.1, 0.7, 1, 0.15))
		overlay.draw_rect(rect, Color(0.1, 0.9, 1), false, 2)


func select_box(rect: Rect2, additive: bool) -> void:
	if not additive:
		selection.clear()
	for model in parts_root.get_children():
		if _on_active_floor(model) and rect.abs().intersects(screen_bounds(model)):
			selection[str(model.get_meta("record_key"))] = true
	refresh_ui()


func viewport_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			right_start = event.position
			right_dragged = false
		elif not right_dragged and (structure_anchor != null or moving_reference or not surface_outline.is_empty()):
			cancel_placement()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		right_dragged = right_dragged or right_start.distance_to(event.position) > 5
	if moving_reference and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click(event.position)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			gesture_snapshot = records.duplicate(true)
			dragging = true
			drag_start = event.position
			drag_end = drag_start
			drag_add = event.shift_pressed or event.ctrl_pressed
			if int(editor.get("_tool")) != ShipyardBrickEditor.Tool.MARK:
				click(event.position)
		else:
			if dragging and int(editor.get("_tool")) == ShipyardBrickEditor.Tool.MARK:
				if drag_start.distance_to(event.position) > 5:
					select_box(Rect2(drag_start, event.position - drag_start), drag_add)
				else:
					select_hit(_hit_record(event.position), drag_add)
			finish_gesture()
		return true
	if event is InputEventMouseMotion and dragging:
		drag_end = event.position
		if int(editor.get("_tool")) != ShipyardBrickEditor.Tool.MARK:
			if int(editor.get("_tool")) == ShipyardBrickEditor.Tool.ERASE or (not _structural_family() and not _surface_family() and not _furniture_family()):
				click(event.position)
			hover(event.position)
		return true
	return false


func finish_gesture() -> void:
	if dragging and gesture_snapshot != records:
		undo_stack.append(gesture_snapshot)
		redo_stack.clear()
	dragging = false
	gesture_snapshot = {}
	overlay.queue_redraw()


func remember() -> void:
	if dragging:
		return
	undo_stack.append(records.duplicate(true))
	if undo_stack.size() > 100:
		undo_stack.pop_front()
	redo_stack.clear()


func delete_selected() -> void:
	if selection.is_empty():
		return
	remember()
	for key in selection:
		records.erase(key)
	selection.clear()
	rebuild()
	refresh_ui()


func undo() -> void:
	finish_gesture()
	if undo_stack.is_empty():
		return
	redo_stack.append(records.duplicate(true))
	records = undo_stack.pop_back()
	selection.clear()
	rebuild()
	refresh_ui()


func redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(records.duplicate(true))
	records = redo_stack.pop_back()
	selection.clear()
	rebuild()
	refresh_ui()


func key_input(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_S:
			if not event.ctrl_pressed:
				return false
			if event.shift_pressed:
				show_save_as()
			else:
				save_draft()
		KEY_O:
			if not event.ctrl_pressed:
				return false
			request_open()
		KEY_PAGEUP, KEY_BRACKETRIGHT:
			if event.shift_pressed and event.keycode == KEY_PAGEUP:
				step_cell(1)
			else:
				set_floor(active_floor + 1, cell_offset)
		KEY_PAGEDOWN, KEY_BRACKETLEFT:
			if event.shift_pressed and event.keycode == KEY_PAGEDOWN:
				step_cell(-1)
			else:
				set_floor(active_floor - 1, cell_offset)
		KEY_R:
			if not _furniture_family(): return false
			furniture_yaw=fmod(furniture_yaw+45.0,360.0)
			clear_ghost()
		KEY_F:
			if BrickCatalog.get_entry(editor.get("_brick_id")).get("style","") not in ["console","bench"]: return false
			console_side=-console_side
			clear_ghost()
		KEY_ENTER, KEY_KP_ENTER:
			if not _surface_family(): return false
			_finish_surface()
		KEY_DELETE, KEY_BACKSPACE:
			if event.keycode == KEY_BACKSPACE and not surface_outline.is_empty():
				surface_outline.resize(surface_outline.size()-1)
				clear_ghost()
				refresh_ui()
			else:
				delete_selected()
		KEY_A:
			if not event.ctrl_pressed:
				return false
			editor.call("_set_tool", ShipyardBrickEditor.Tool.MARK)
			for key in records:
				if absf(_position(records[key]).y - (.85 if records[key]["asset_id"] in ["helm_wheel","helm_throttle","helm_display"] else 0.0) - floor_y()) < 0.01:
					selection[key] = true
			refresh_ui()
		KEY_Z:
			if not event.ctrl_pressed:
				return false
			if event.shift_pressed:
				redo()
			else:
				undo()
		KEY_Y:
			if not event.ctrl_pressed:
				return false
			redo()
		KEY_ESCAPE:
			if structure_anchor != null or moving_reference or not surface_outline.is_empty():
				cancel_placement()
				return true
			if selection.is_empty() and not dragging:
				return false
			finish_gesture()
			selection.clear()
			refresh_ui()
		_:
			return false
	return true


func selection_box_visible() -> bool:
	return int(editor.get("_tool")) == ShipyardBrickEditor.Tool.MARK and dragging and drag_start.distance_to(drag_end) > 5


func _sync_selection_visuals() -> void:
	var selecting := int(editor.get("_tool")) == ShipyardBrickEditor.Tool.MARK
	for model in parts_root.get_children():
		var highlight := selecting and selection.has(str(model.get_meta("record_key", "")))
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = selection_material if highlight else null


func _bow_variants(record: Dictionary) -> Dictionary:
	var style: String = BrickCatalog.get_entry(record["asset_id"]).get("style", "")
	var key := slot_key(record)
	var result := {}
	for profile in ["flat", "rising"]:
		for candidate in recipes.get(style + "_" + profile, []):
			if _horizontal_key(candidate) == _horizontal_key(record):
				result[profile] = candidate["asset_id"]
				break
	if result.size() != 2 or result["flat"] == result["rising"]:
		return {} # Straight sections have no bow profile.
	return result


func _sync_bow_control() -> void:
	rising_bow.text = "Rising bow"
	rising_bow.visible = (not _structural_family() and not _surface_family() and not _furniture_family()) if selection.is_empty() else true
	if not selection.is_empty():
		rising_bow.visible = false
		for key in selection:
			if records.has(key) and not _bow_variants(records[key]).is_empty(): rising_bow.visible = true
	rising_bow.visible = rising_bow.visible and ImportedHullCatalog.ENTRIES[hull_id].rising
	if int(editor.get("_tool")) == ShipyardBrickEditor.Tool.PLACE:
		rising_bow.disabled = _structural_family()
		rising_bow.set_pressed_no_signal(placement_rising)
		return
	var flat := false
	var rising := false
	for key in selection:
		if not records.has(key):
			continue
		var variants := _bow_variants(records[key])
		if variants.is_empty():
			continue
		rising = rising or records[key]["asset_id"] == variants["rising"]
		flat = flat or records[key]["asset_id"] == variants["flat"]
	rising_bow.disabled = not (flat or rising)
	rising_bow.set_pressed_no_signal(rising and not flat)
	if flat and rising:
		rising_bow.text = "Rising bow · Mixed"


func _set_bow_profile(enabled: bool) -> void:
	clear_ghost()
	if int(editor.get("_tool")) == ShipyardBrickEditor.Tool.PLACE:
		placement_rising = enabled
		return
	var changes := {}
	for key in selection:
		if not records.has(key):
			continue
		var variants := _bow_variants(records[key])
		if not variants.is_empty():
			var target: String = variants["rising" if enabled else "flat"]
			if records[key]["asset_id"] != target:
				changes[key] = target
	if not changes.is_empty():
		remember()
		for key in changes:
			records[key]["asset_id"] = changes[key]
		rebuild()
	refresh_ui()


func _paintable(id: String) -> bool:
	return bool(BrickCatalog.get_entry(id).get("paintable",false)) or id.begins_with("halfwall") or id.begins_with("cabin_") or id in ["helm_wheel","helm_throttle","helm_chair","passenger_seat"]


func _structural_family() -> bool:
	return str(editor.get("_brick_id")).begins_with("cabin_")


func _snap_structure(point: Vector3) -> Vector3:
	return Vector3(snappedf(point.x, 0.5), floor_y(), snappedf(point.z, 0.5))


func _on_deck(point: Vector3) -> bool:
	var grid := editor.get("_grid") as DeckGrid
	if point.y < deck_height + .5:
		for opening in grid.deck_openings:
			if Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),opening): return false
	return Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), grid.deck_polygon)


func _structural_candidate(point: Vector3) -> Dictionary:
	var start: Vector3 = structure_anchor if structure_anchor != null else _snap_structure(point)
	var target := point if structure_anchor != null else start + Vector3(0, 0, -1)
	if start.distance_to(target) < 0.2:
		return {}
	var style: String = BrickCatalog.get_entry(editor.get("_brick_id")).get("style", "")
	var best := {}
	var distance := INF
	for id in BrickCatalog.imported_entries():
		var spec := BrickCatalog.get_entry(id)
		if spec.get("kind", "") not in ["structure","console","bench"] or spec["style"] != style or (style in ["console","bench"] and int(spec.get("side",1))!=console_side):
			continue
		for yaw in [0, 90, 180, 270]:
			var candidate := {"asset_id":id, "position":[start.x,start.y,start.z], "yaw_degrees":float(yaw)}
			var end := _end(candidate)
			var d := end.distance_to(target)
			if d < distance:
				distance = d
				best = candidate
	if best.is_empty() or not _structure_fits(best):
		return {}
	return best


func _structure_fits(candidate: Dictionary) -> bool:
	var start := _position(candidate)
	var end := _end(candidate)
	var normal := (end - start).cross(Vector3.UP).normalized() * 0.07
	for point in [start + normal, start - normal, end + normal, end - normal]:
		if not _on_deck(point):
			return false
	var a := Vector2(start.x, start.z)
	var b := Vector2(end.x, end.z)
	for record in records.values():
		if BrickCatalog.get_entry(record["asset_id"]).get("kind", "") != BrickCatalog.get_entry(candidate["asset_id"]).get("kind", "") or slot_key(record) == slot_key(candidate):
			continue
		var p := _position(record)
		if absf(p.y-start.y) > 0.01:
			continue
		var q := _end(record)
		var c := Vector2(p.x, p.z)
		var d := Vector2(q.x, q.z)
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
		if hit != null and not ((hit.is_equal_approx(a) or hit.is_equal_approx(b)) and (hit.is_equal_approx(c) or hit.is_equal_approx(d))):
			return false
		# Reject collinear overlaps, but allow matching full-slot replacements.
		if absf((b-a).cross(d-c)) < 0.0001 and absf((b-a).cross(c-a)) < 0.0001:
			var axis := (b-a).normalized()
			var lo := minf((c-a).dot(axis), (d-a).dot(axis))
			var hi := maxf((c-a).dot(axis), (d-a).dot(axis))
			if minf((b-a).length(),hi) - maxf(0,lo) > 0.001:
				return false
	return true


func _sync_door_control() -> void:
	var opened := false
	var closed := false
	for key in selection:
		if records.has(key) and BrickCatalog.get_entry(records[key]["asset_id"]).get("style", "") == "door":
			opened = opened or bool(records[key].get("door_open", false))
			closed = closed or not bool(records[key].get("door_open", false))
	door_open.visible = opened or closed
	door_open.text = "Open door · Mixed" if opened and closed else "Open door"
	door_open.set_pressed_no_signal(opened and not closed)


func _set_doors_open(enabled: bool) -> void:
	_request_part_state("door_open",enabled)



func _build_scale_reference() -> void:
	reference_root = Node3D.new()
	reference_root.name = "PlayerScaleReference"
	editor.get("_world").add_child(reference_root)
	reference_root.position = Vector3(0, deck_height, float(ImportedHullCatalog.ENTRIES[hull_id].reference_z))
	var npc := NpcBase.new()
	npc.name = "ReferenceCaptain"
	reference_root.add_child(npc)
	npc.set_idle()
	# Use the actual game's character at a measured 1.80 m standing height.
	var low := INF
	var high := -INF
	for mesh in npc.find_children("*", "MeshInstance3D", true, false):
		for i in range(8):
			var point: Vector3 = reference_root.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(i)
			low = minf(low, point.y)
			high = maxf(high, point.y)
	if high > low:
		var factor := 1.8 / (high - low)
		npc.scale = Vector3.ONE * factor
		npc.position.y = -low * factor
	var label := Label3D.new()
	label.text = "Player · 1.80 m"
	label.position.y = 2.0
	label.font_size = 24
	label.pixel_size = 0.0025
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reference_root.add_child(label)


# The GLB carries Blender-authored end-only shape keys. We choose weights, not meshes.
func _end_shear(record: Dictionary, at_start: bool) -> float:
	var direction := (_end(record) - _position(record)).normalized()
	var normal := direction.cross(Vector3.UP)
	var endpoint := _position(record) if at_start else _end(record)
	for other in records.values():
		if slot_key(other) == slot_key(record) or BrickCatalog.get_entry(other["asset_id"]).get("kind", "") != BrickCatalog.get_entry(record["asset_id"]).get("kind", ""):
			continue
		var a := _position(other)
		var b := _end(other)
		var away := Vector3.ZERO
		if a.distance_to(endpoint) < 0.001:
			away = (b-a).normalized()
		elif b.distance_to(endpoint) < 0.001:
			away = (a-b).normalized()
		else:
			continue
		var neighbour := -away if at_start else away
		var other_normal := neighbour.cross(Vector3.UP)
		var divisor := 1.0 + normal.dot(other_normal)
		if divisor < 0.001:
			return 0.0
		var miter := (normal + other_normal) / divisor
		return miter.dot(direction)
	return 0.0


func _fit_wall_ends(root: Node3D, record: Dictionary) -> void:
	if BrickCatalog.get_entry(record["asset_id"]).get("kind", "") not in ["structure","console","bench"]:
		return
	var weights := {"MiterStart":_end_shear(record, true)/4.0, "MiterEnd":_end_shear(record, false)/4.0}
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		for i in range(mesh.get_blend_shape_count()):
			var shape_name: String = mesh.mesh.get_blend_shape_name(i)
			if weights.has(shape_name):
				mesh.set_blend_shape_value(i, weights[shape_name])
		mesh.custom_aabb = mesh.mesh.get_aabb().grow(0.25)


func _pick_bounds(mesh: MeshInstance3D) -> AABB:
	return mesh.custom_aabb if mesh.custom_aabb.size != Vector3.ZERO else mesh.mesh.get_aabb()


func deformed_vertices(mesh: MeshInstance3D, surface: int) -> PackedVector3Array:
	var base: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var result := base.duplicate()
	var shapes: Array = mesh.mesh.surface_get_blend_shape_arrays(surface)
	for i in range(shapes.size()):
		var weight := mesh.get_blend_shape_value(i)
		if is_zero_approx(weight):
			continue
		var vertices: PackedVector3Array = shapes[i][Mesh.ARRAY_VERTEX]
		for j in range(result.size()):
			result[j] += (vertices[j] - base[j] if mesh.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else vertices[j]) * weight
	return result


func _deformed_faces(mesh: MeshInstance3D) -> PackedVector3Array:
	var key := str(mesh.mesh.get_instance_id())
	for i in range(mesh.get_blend_shape_count()):
		key += ":%.6f" % mesh.get_blend_shape_value(i)
	if mesh_faces.has(key):
		return mesh_faces[key]
	var faces := PackedVector3Array()
	for surface in range(mesh.mesh.get_surface_count()):
		var vertices := deformed_vertices(mesh, surface)
		var indices: PackedInt32Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			faces.append_array(vertices)
		else:
			for index in indices:
				faces.append(vertices[index])
	mesh_faces[key] = faces
	return faces


func cancel_placement() -> void:
	finish_gesture()
	structure_anchor = null
	surface_outline.clear()
	moving_reference = false
	clear_ghost()
	refresh_ui()
	editor.call("_show_toast", "Run ended. Click a new start point.")


func _input(event: InputEvent) -> void:
	if not editor.is_open() or save_dialog == null or save_dialog.visible or load_dialog.visible or unsaved_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and (structure_anchor != null or moving_reference or not surface_outline.is_empty()):
			cancel_placement()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] or (not surface_outline.is_empty() and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE]):
			key_input(event)
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode in [KEY_S, KEY_O]:
			key_input(event)
			get_viewport().set_input_as_handled()


func _setup_drafts() -> void:
	var folder := ProjectSettings.globalize_path("user://shipyard_drafts")
	DirAccess.make_dir_recursive_absolute(folder)
	for saving in [true,false]:
		var dialog := FileDialog.new()
		dialog.title = "Save ship draft" if saving else "Open ship draft"
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray(["*.json ; Ship drafts"])
		dialog.current_dir = folder
		dialog.min_size = Vector2i(760,500)
		editor.add_child(dialog)
		if saving:
			save_dialog = dialog
			dialog.file_selected.connect(save_draft)
			dialog.canceled.connect(func() -> void: pending_action = Callable())
		else:
			load_dialog = dialog
			dialog.file_selected.connect(func(path: String) -> void: _guard(func() -> void: load_draft(path)))
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.title = "Unsaved draft"
	unsaved_dialog.dialog_text = "Save your changes before continuing?"
	unsaved_dialog.ok_button_text = "Save"
	unsaved_dialog.add_button("Discard changes", false, "discard")
	unsaved_dialog.confirmed.connect(func() -> void: save_draft())
	unsaved_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "discard":
			unsaved_dialog.hide()
			_continue_pending()
	)
	unsaved_dialog.canceled.connect(func() -> void: pending_action = Callable())
	editor.add_child(unsaved_dialog)
	draft_menu = PopupMenu.new()
	draft_menu.add_item("New draft",0)
	draft_menu.add_item("Open…  Ctrl+O",1)
	draft_menu.add_item("Save  Ctrl+S",2)
	draft_menu.add_item("Save as…  Ctrl+Shift+S",3)
	if FileAccess.file_exists(SAVE_PATH):
		draft_menu.add_separator()
		draft_menu.add_item("Open previous single-file draft",4)
	draft_menu.id_pressed.connect(func(id: int) -> void:
		match id:
			0: _guard(new_draft)
			1: request_open()
			2: save_draft()
			3: show_save_as()
			4: _guard(func() -> void: load_draft(SAVE_PATH))
	)
	editor.add_child(draft_menu)
	if editor.standalone_tool:
		previous_auto_accept_quit = get_tree().auto_accept_quit
		get_tree().auto_accept_quit = false
		get_tree().root.close_requested.connect(Callable(editor, "_close"))


func show_drafts() -> void:
	draft_menu.position = Vector2i(get_viewport().get_mouse_position())
	draft_menu.popup()


func show_save_as() -> void:
	cancel_placement()
	save_dialog.current_file = draft_path.get_file() if not draft_path.is_empty() else "Untitled ship.json"
	if not draft_path.is_empty():
		save_dialog.current_dir = ProjectSettings.globalize_path(draft_path).get_base_dir()
	save_dialog.popup_centered_ratio(0.65)


func request_open() -> void:
	cancel_placement()
	load_dialog.popup_centered_ratio(0.65)


func _guard(action: Callable) -> void:
	if _draft_state() == saved_state:
		action.call()
		return
	pending_action = action
	unsaved_dialog.popup_centered()


func _continue_pending() -> void:
	var action := pending_action
	pending_action = Callable()
	if action.is_valid():
		action.call()


func request_close() -> void:
	_guard(func() -> void: editor.call("_close", true))


func new_draft() -> void:
	cancel_placement()
	records.clear()
	selection.clear()
	undo_stack.clear()
	redo_stack.clear()
	draft_path = ""
	placement_rising = false
	set_floor(0)
	reset_colors()
	undo_stack.clear()
	refresh_ui()
	saved_state = _draft_state()
	_update_draft_title()


func _update_draft_title() -> void:
	if not is_instance_valid(editor):
		return
	var dirty := _draft_state() != saved_state
	var title := "Untitled ship" if draft_path.is_empty() else draft_path.get_file().get_basename()
	editor.get("_hull_lbl").text = title + (" · Unsaved changes" if dirty else (" · New draft" if draft_path.is_empty() else " · Saved")) + " · " + str(ImportedHullCatalog.ENTRIES[hull_id].label)
	editor.get("_confirm_btn").text = "Save *" if dirty else "Save"


func tool_hint() -> String:
	if _surface_family():
		return "Draw corners · Enter / first point: finish · Backspace: undo point · Esc: cancel"
	match int(editor.get("_tool")):
		ShipyardBrickEditor.Tool.MARK:
			return "Click / drag box · Shift: add/remove · Del: delete · Ctrl+Z: undo"
		ShipyardBrickEditor.Tool.ERASE:
			return "Click / drag over parts to erase · Ctrl+Z: undo"
	if _structural_family():
		return "Click next endpoint · Esc / right-click: end run" if structure_anchor != null else "Click a start point anywhere on the deck"
	if _furniture_family():return "Click: place · R: rotate · Esc / right-click: cancel · RMB drag: orbit"
	return "Click / drag along the hull edge · RMB drag: orbit · Wheel: zoom"


func floor_y() -> float:
	return deck_height + active_floor * FLOOR_HEIGHT + cell_offset * CELL_HEIGHT


func _horizontal_key(record: Dictionary) -> String:
	return slot_key(record).get_slice("|", 1)


func _on_active_floor(model: Node3D) -> bool:
	if not model.visible or not model.has_meta("record_key"): return false
	var style := str(BrickCatalog.get_entry(records.get(str(model.get_meta("record_key")),{}).get("asset_id","")).get("style",""))
	var offset := .85 if style in ["wheel","throttle","display"] else (.74 if style == "cargo_hatch" else 0.0)
	return absf(model.position.y - offset - floor_y()) < 0.01


func step_cell(direction: int) -> void:
	var total := clampi(active_floor * CELLS_PER_FLOOR + cell_offset + direction, 0, MAX_FLOOR * CELLS_PER_FLOOR)
	set_floor(floori(float(total) / CELLS_PER_FLOOR), total % CELLS_PER_FLOOR)


func set_floor(value: int, offset: int = 0) -> void:
	var next_floor := clampi(value, 0, MAX_FLOOR)
	var next_cell := clampi(offset, 0, CELLS_PER_FLOOR - 1) if next_floor < MAX_FLOOR else 0
	var difference := deck_height + next_floor * FLOOR_HEIGHT + next_cell * CELL_HEIGHT - floor_y()
	finish_gesture()
	structure_anchor = null
	surface_outline.clear()
	moving_reference = false
	selection.clear()
	clear_ghost()
	active_floor = next_floor
	cell_offset = next_cell
	var target: Vector3 = editor.get("_cam_target")
	target.y += difference
	editor.set("_cam_target", target)
	editor.call("_update_camera")
	_apply_floor_view()
	refresh_ui()


func _apply_floor_view() -> void:
	var floor_name := "Deck" if active_floor == 0 else "Floor %d" % active_floor
	floor_label.text = "%s +%.1f m" % [floor_name, floor_y()-deck_height]
	floor_label.tooltip_text = "Shift + Page Up / Down: one 10 cm cell."
	floor_down.disabled = active_floor == 0
	floor_up.disabled = active_floor == MAX_FLOOR
	var grid: Node3D = editor.get("_grid_overlay")
	if is_instance_valid(grid):
		grid.position.y = floor_y() - deck_height
	if is_instance_valid(reference_root):
		reference_root.position.y = floor_y()
	for model in parts_root.get_children():
		var id := str(records.get(str(model.get_meta("record_key")),{}).get("asset_id",""))
		var offset := .86 if id in ["helm_wheel","helm_throttle","helm_display"] else (.75 if BrickCatalog.get_entry(id).get("style","") == "cargo_hatch" else .01)
		model.visible = model.position.y <= floor_y() + offset


func _surface_family() -> bool:
	return ShipSurfaceKit.is_surface(str(editor.get("_brick_id")))

func _surface_record(poly: PackedVector2Array) -> Dictionary:
	var points: Array = []
	for p in poly: points.append([p.x,p.y])
	return {"asset_id":str(editor.get("_brick_id")),"position":[0.0,floor_y(),0.0],"yaw_degrees":0.0,"outline":points,"colors":surface_colors.duplicate(true),"crown":placement_crown,"visor_direction":float(placement_visor)}

func _valid_surface_record(record: Dictionary) -> bool:
	if not record.get("outline") is Array or record["outline"].size()>64:
		return false
	for p in record["outline"]:
		if not p is Array or p.size()!=2: return false
		for value in p:
			if not (value is float or value is int) or not is_finite(float(value)): return false
	var visor: Variant=record.get("visor_direction",0)
	if not (visor is float or visor is int) or not is_finite(float(visor)) or visor!=floor(float(visor)) or visor<0 or visor>4: return false
	if record.has("crown") and not record["crown"] is bool: return false
	return ShipSurfaceKit.valid(ShipSurfaceKit.polygon(record)) and record["position"][0]==0 and record["position"][2]==0 and record["yaw_degrees"]==0

func _surface_fits(poly: PackedVector2Array) -> bool:
	if not ShipSurfaceKit.valid(poly): return false
	for p in poly:
		if not _on_deck(Vector3(p.x,floor_y(),p.y)): return false
	for record in records.values():
		if not ShipSurfaceKit.is_surface(record["asset_id"]) or absf(_position(record).y-floor_y())>.01: continue
		for intersection in Geometry2D.intersect_polygons(poly,ShipSurfaceKit.polygon(record)):
			if ShipSurfaceKit.area(intersection)>.0001: return false
	return true

func _click_surface(screen: Vector2) -> void:
	var point: Variant = _point(screen)
	if point == null: return
	var snapped := _snap_structure(point)
	if not _on_deck(snapped): return
	var p := Vector2(snapped.x,snapped.z)
	if surface_outline.size()>=3 and p.distance_to(surface_outline[0])<.01:
		_finish_surface()
		return
	if surface_outline.has(p): return
	if surface_outline.size()>=64: return
	surface_outline.append(p)
	surface_cursor=p
	clear_ghost()
	refresh_ui()
	_hover_surface(screen)

func _hover_surface(screen: Vector2) -> void:
	var point: Variant = _point(screen)
	if point == null: return
	var snapped := _snap_structure(point)
	surface_cursor=Vector2(snapped.x,snapped.z)
	overlay.queue_redraw()
	var points := surface_outline.duplicate()
	if not points.has(surface_cursor): points.append(surface_cursor)
	var record := _surface_record(points)
	var key := JSON.stringify(record)
	if key==_ghost_key: return
	clear_ghost()
	_ghost_key=key
	if not _surface_fits(points): return
	ghost=create_part(record)
	editor.get("_world").add_child(ghost)
	editor.call("_tint_ghost",ghost,true)

func _finish_surface() -> void:
	if not _surface_fits(surface_outline):
		editor.call("_show_toast","Outline must stay on the deck, avoid overlaps, and use straight, 26.565° or 45° edges.",true)
		return
	var record := _surface_record(surface_outline)
	if ShipSurfaceKit.tiles(surface_outline,"roof" if record["asset_id"]=="roof_tile" else "floor").is_empty():
		editor.call("_show_toast","Cannot fit this outline to the model kit.",true)
		return
	remember()
	records[slot_key(record)]=record
	surface_outline.clear()
	clear_ghost()
	rebuild()
	refresh_ui()


func _update_roof_profile() -> void:
	remember()
	for key in selection:
		if records.has(key) and records[key]["asset_id"]=="roof_tile":
			records[key]["crown"]=placement_crown
			records[key]["visor_direction"]=float(placement_visor)
	clear_ghost()
	rebuild()
	refresh_ui()


func _furniture_family() -> bool:
	return BrickCatalog.get_entry(editor.get("_brick_id")).get("kind","")=="furniture"

func _furniture_candidate(point: Vector3) -> Dictionary:
	var p:=Vector3(snappedf(point.x,.1),floor_y(),snappedf(point.z,.1))
	var id: String=editor.get("_brick_id")
	if id == "bulk_divider_5m":
		if hull_id != "hull_24x8" or active_floor != 0: return {}
		# Separate slot from the coaming, sharing its authored centre datum.
		return {"asset_id":id,"position":[0,deck_height,0],"yaw_degrees":0.0}
	if id in ["hold_coaming_5x8", "hatch_cover_5x4"]:
		var platform: Dictionary = ImportedHullCatalog.ENTRIES[hull_id]
		if not platform.has("coaming") or active_floor != 0: return {}
		# One palette family resolves the matching authored hull-specific size.
		if id == "hold_coaming_5x8":
			id=platform.coaming;p=Vector3(0,deck_height,0)
		else:
			id=platform.hatch
			var nearest: float=platform.hatch_stations[0]
			for station: float in platform.hatch_stations:
				if absf(point.z-station)<absf(point.z-nearest):nearest=station
			p=Vector3(0,deck_height+.74,nearest)
		return {"asset_id":id,"position":[p.x,p.y,p.z],"yaw_degrees":0.0}
	if not _on_deck(p): return {}
	if id in ["trawl_winch", "insulated_catch_tank"]:
		var bounds := Rect2(-.55,-1.16,1.10,2.13) if id=="trawl_winch" else Rect2(-.72,-.62,1.64,1.24)
		var rotation := Basis(Vector3.UP,deg_to_rad(furniture_yaw))
		for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
			if not _on_deck(p+rotation*Vector3(corner.x,0,corner.y)): return {}
	if id in ["helm_wheel","helm_throttle","helm_display"]:
		var found:=false
		for record in records.values():
			if BrickCatalog.get_entry(record["asset_id"]).get("kind","")!="console" or absf(_position(record).y-floor_y())>.01: continue
			var a:=_position(record)
			var b:=_end(record)
			var e:=(b-a).normalized()
			var relative:=p-a
			var across:=relative.dot(e.cross(Vector3.UP))*float(BrickCatalog.get_entry(record["asset_id"]).get("side",1))
			if across>=.10 and across<=.55 and relative.dot(e)>=.05 and relative.dot(e)<=a.distance_to(b)-.05: found=true
		if not found: return {}
		p.y+=.85
	return {"asset_id":id,"position":[p.x,p.y,p.z],"yaw_degrees":furniture_yaw}


func _interact_selected() -> void:
	if not records.has(selected): return
	var style: String=BrickCatalog.get_entry(records[selected]["asset_id"]).get("style","")
	var field: String="door_open" if style=="door" else "occupied"
	_request_part_state(field,not bool(records[selected].get("part_state",{}).get(field,records[selected].get("door_open",false))))

func _request_part_state(field: String,value: Variant) -> void:
	remember()
	for model in parts_root.get_children():
		var key: String=str(model.get_meta("record_key",""))
		if not selection.has(key): continue
		var driver:=model.get_node_or_null("PartState") as ShipPartState
		if driver==null: continue
		var style: String=BrickCatalog.get_entry(records[key]["asset_id"]).get("style","")
		if field=="door_open" and style!="door": continue
		if field=="steering" and style!="wheel": continue
		if field=="throttle" and style!="throttle": continue
		if field=="occupied" and style not in ["helm_chair","passenger_seat"]: continue
		driver.request(field,value)
		records[key]["part_state"]=driver.state.duplicate()
		if field=="door_open": records[key]["door_open"]=bool(value)
	refresh_ui()
