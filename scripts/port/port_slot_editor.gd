class_name PortSlotEditor
extends CanvasLayer

## Developer tool: place service slots on a default port and attach building
## JSON files (filename stem = blueprint id). Saves
## resources/data/ports/default_service_slots.json.

const NUDGE_M := 1.0
const NUDGE_FINE_M := 0.25
const DEFAULT_PORT_SIZE := 2

var _draft: Array[Dictionary] = []
var _selected_id: String = ""

var _root: Control
var _viewport: SubViewport
var _world: Node3D
var _port_root: Node3D
var _facilities: PortFacilities
var _selection_ring: MeshInstance3D
var _camera: Camera3D
var _cam_yaw: float = 28.0
var _cam_pitch: float = -28.0
var _cam_dist: float = 90.0
var _cam_target: Vector3 = Vector3(0.0, 4.0, 8.0)
var _orbiting := false
var _panning := false
var _orbit_last: Vector2 = Vector2.ZERO

var _status_lbl: Label
var _slot_list: ItemList
var _role_option: OptionButton
var _building_option: OptionButton
var _pos_x: SpinBox
var _pos_z: SpinBox
var _yaw: SpinBox
var _save_lbl: Label
var _vp_host: SubViewportContainer


func _init() -> void:
	name = "PortSlotEditor"
	layer = 14
	_draft = PortServiceSlotCatalog.slots()
	if not _draft.is_empty():
		_selected_id = str(_draft[0].get("id", ""))
	_build_chrome()


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_resize):
		vp.size_changed.connect(_resize)
	_resize()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_port()
	_refresh_slot_list()
	_refresh_building_options()
	_sync_inspector()
	_update_camera()


func _build_chrome() -> void:
	_root = Control.new()
	_root.name = "EditorRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = HudStyle.make_theme()
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07, 1.0)
	_root.add_child(bg)

	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 0)
	_root.add_child(main)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var side_sb := StyleBoxFlat.new()
	side_sb.bg_color = HudStyle.C_BG
	side_sb.border_color = HudStyle.C_BRASS
	side_sb.set_border_width_all(1)
	side.add_theme_stylebox_override("panel", side_sb)
	main.add_child(side)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	side.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "PORT SLOTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(title)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	_status_lbl.text = (
		"Default port fixture — place service slots, attach a building JSON.\n"
		+ "RMB orbit · MMB pan · Scroll zoom\n"
		+ "Arrow keys nudge · R / Q·E rotate 90° · Shift = fine step"
	)
	col.add_child(_status_lbl)

	col.add_child(HSeparator.new())

	var slots_hdr := Label.new()
	slots_hdr.text = "SLOTS"
	slots_hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(slots_hdr)

	_slot_list = ItemList.new()
	_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot_list.custom_minimum_size = Vector2(0, 160)
	_slot_list.item_selected.connect(_on_slot_selected)
	col.add_child(_slot_list)

	var role_lbl := Label.new()
	role_lbl.text = "Add role"
	role_lbl.add_theme_font_size_override("font_size", 12)
	role_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(role_lbl)
	_role_option = OptionButton.new()
	_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role_i := 0
	for preset in PortServiceSlotCatalog.ROLE_PRESETS:
		_role_option.add_item(str(preset["display_name"]), role_i)
		_role_option.set_item_metadata(role_i, str(preset["id"]))
		role_i += 1
	col.add_child(_role_option)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	col.add_child(add_row)
	var add_btn := UiBuilder.button("Add / focus")
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_add_or_focus_role)
	add_row.add_child(add_btn)
	var remove_btn := UiBuilder.button("Remove")
	remove_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_btn.pressed.connect(_remove_selected)
	add_row.add_child(remove_btn)

	col.add_child(HSeparator.new())

	var pos_hdr := Label.new()
	pos_hdr.text = "SELECTED"
	pos_hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(pos_hdr)

	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 6)
	col.add_child(pos_row)
	_pos_x = _make_axis_spin(pos_row, "X")
	_pos_z = _make_axis_spin(pos_row, "Z")
	_pos_x.value_changed.connect(func(_v: float) -> void: _apply_spin_position())
	_pos_z.value_changed.connect(func(_v: float) -> void: _apply_spin_position())

	var nudge_row := HBoxContainer.new()
	nudge_row.add_theme_constant_override("separation", 4)
	col.add_child(nudge_row)
	for entry in [
		["←", Vector3(-1, 0, 0)],
		["→", Vector3(1, 0, 0)],
		["↑", Vector3(0, 0, -1)],
		["↓", Vector3(0, 0, 1)],
	]:
		var btn := UiBuilder.button(str(entry[0]))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dir: Vector3 = entry[1]
		btn.pressed.connect(func() -> void: _nudge(dir))
		nudge_row.add_child(btn)

	var yaw_row := HBoxContainer.new()
	yaw_row.add_theme_constant_override("separation", 6)
	col.add_child(yaw_row)
	_yaw = _make_yaw_spin(yaw_row)
	_yaw.value_changed.connect(func(_v: float) -> void: _apply_spin_yaw())
	var yaw_ccw := UiBuilder.button("⟲ 90°")
	yaw_ccw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yaw_ccw.pressed.connect(func() -> void: _rotate_yaw(-90.0))
	yaw_row.add_child(yaw_ccw)
	var yaw_cw := UiBuilder.button("⟳ 90°")
	yaw_cw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yaw_cw.pressed.connect(func() -> void: _rotate_yaw(90.0))
	yaw_row.add_child(yaw_cw)

	var building_lbl := Label.new()
	building_lbl.text = "Building JSON"
	building_lbl.add_theme_font_size_override("font_size", 12)
	building_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(building_lbl)
	_building_option = OptionButton.new()
	_building_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_option.item_selected.connect(_on_building_selected)
	col.add_child(_building_option)

	var refresh_buildings := UiBuilder.button("Refresh building list")
	refresh_buildings.pressed.connect(_refresh_building_options)
	col.add_child(refresh_buildings)

	col.add_child(HSeparator.new())

	var save_btn := UiBuilder.button("Save default slots")
	save_btn.pressed.connect(_save_slots)
	col.add_child(save_btn)
	var reload_btn := UiBuilder.button("Reload from disk")
	reload_btn.pressed.connect(_reload_slots)
	col.add_child(reload_btn)

	_save_lbl = Label.new()
	_save_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_lbl.add_theme_font_size_override("font_size", 10)
	_save_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(_save_lbl)

	_vp_host = SubViewportContainer.new()
	_vp_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vp_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vp_host.stretch = true
	_vp_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_vp_host.gui_input.connect(_on_viewport_gui_input)
	_vp_host.focus_mode = Control.FOCUS_ALL
	main.add_child(_vp_host)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.handle_input_locally = true
	_vp_host.add_child(_viewport)

	_world = Node3D.new()
	_world.name = "EditorWorld"
	_viewport.add_child(_world)

	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.current = true
	_world.add_child(_camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 40.0, 0.0)
	sun.light_energy = 1.2
	_world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -130.0, 0.0)
	fill.light_energy = 0.35
	_world.add_child(fill)

	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.06, 0.08, 0.11)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.2, 0.22, 0.26)
	we.ambient_light_energy = 0.95
	env.environment = we
	_world.add_child(env)

	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 5.2
	torus.outer_radius = 5.6
	torus.rings = 24
	torus.ring_segments = 48
	_selection_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.95, 0.78, 0.25, 0.85)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.85, 0.6, 0.15)
	ring_mat.emission_energy_multiplier = 0.6
	ring_mat.roughness = 0.4
	_selection_ring.material_override = ring_mat
	_selection_ring.visible = false
	_world.add_child(_selection_ring)


func _make_axis_spin(parent: HBoxContainer, axis: String) -> SpinBox:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)
	var lbl := Label.new()
	lbl.text = axis
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	wrap.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = -200.0
	spin.max_value = 200.0
	spin.step = 0.25
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(spin)
	return spin


func _make_yaw_spin(parent: HBoxContainer) -> SpinBox:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)
	var lbl := Label.new()
	lbl.text = "Yaw °"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	wrap.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 359.0
	spin.step = 1.0
	spin.suffix = "°"
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(spin)
	return spin


func _resize() -> void:
	if _vp_host == null or _viewport == null:
		return
	var size := _vp_host.size
	if size.x < 2.0 or size.y < 2.0:
		return
	_viewport.size = Vector2i(int(size.x), int(size.y))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var step := NUDGE_FINE_M if key.shift_pressed else NUDGE_M
		match key.keycode:
			KEY_LEFT:
				_nudge(Vector3(-step, 0.0, 0.0))
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_nudge(Vector3(step, 0.0, 0.0))
				get_viewport().set_input_as_handled()
			KEY_UP:
				_nudge(Vector3(0.0, 0.0, -step))
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_nudge(Vector3(0.0, 0.0, step))
				get_viewport().set_input_as_handled()
			KEY_R, KEY_E:
				_rotate_yaw(90.0)
				get_viewport().set_input_as_handled()
			KEY_Q:
				_rotate_yaw(-90.0)
				get_viewport().set_input_as_handled()


func _on_viewport_gui_input(event: InputEvent) -> void:
	_vp_host.grab_focus()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			_orbit_last = mb.position
			_vp_host.accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_orbit_last = mb.position
			_vp_host.accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist * 0.9, 25.0, 220.0)
			_update_camera()
			_vp_host.accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist * 1.1, 25.0, 220.0)
			_update_camera()
			_vp_host.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			var delta := mm.position - _orbit_last
			_orbit_last = mm.position
			_cam_yaw -= delta.x * 0.35
			_cam_pitch = clampf(_cam_pitch - delta.y * 0.35, -80.0, -8.0)
			_update_camera()
			_vp_host.accept_event()
		elif _panning:
			var delta := mm.position - _orbit_last
			_orbit_last = mm.position
			var right := _camera.global_transform.basis.x
			var up := Vector3.UP
			_cam_target -= right * delta.x * 0.08
			_cam_target += up * delta.y * 0.08
			_update_camera()
			_vp_host.accept_event()


func _update_camera() -> void:
	if _camera == null:
		return
	var pitch := deg_to_rad(_cam_pitch)
	var yaw := deg_to_rad(_cam_yaw)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		-sin(pitch),
		cos(pitch) * cos(yaw),
	) * _cam_dist
	_camera.position = _cam_target + offset
	_camera.look_at(_cam_target, Vector3.UP)


func _rebuild_port() -> void:
	if _port_root != null and is_instance_valid(_port_root):
		_port_root.free()
	_port_root = Node3D.new()
	_port_root.name = "DefaultPort"
	_world.add_child(_port_root)

	var definition := PortDefinition.new()
	definition.port_id = "port-slot-editor"
	definition.display_name = "DEFAULT PORT"
	definition.size = DEFAULT_PORT_SIZE
	definition.has_lighthouse = true
	definition.has_fog_horn = true
	var data := PortExpander.expand(definition, 44117)
	data.has_lighthouse = true
	data.has_fog_horn = true

	var plot := PortPlot.new()
	plot.name = "PortPlot"
	_port_root.add_child(plot)
	plot.configure(data)

	var water := MeshInstance3D.new()
	water.name = "WaterPlane"
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(420.0, 420.0)
	water.mesh = water_mesh
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.08, 0.22, 0.28)
	water_material.roughness = 0.26
	water_material.metallic = 0.18
	water.material_override = water_material
	water.position.y = -0.32
	_port_root.add_child(water)

	_facilities = null
	call_deferred("_bind_facilities_when_ready")


func _bind_facilities_when_ready() -> void:
	if _port_root == null or not is_instance_valid(_port_root):
		return
	var plot := _port_root.get_node_or_null("PortPlot") as PortPlot
	if plot == null:
		return
	var existing := plot.get_node_or_null("PortFacilities") as PortFacilities
	if existing != null:
		_facilities = existing
		_facilities.show_service_slots = true
		_apply_draft_to_facilities()
		return
	if not plot.child_entered_tree.is_connected(_on_plot_child_entered):
		plot.child_entered_tree.connect(_on_plot_child_entered)


func _on_plot_child_entered(node: Node) -> void:
	if not (node is PortFacilities):
		return
	_facilities = node as PortFacilities
	_facilities.show_service_slots = true
	var plot := _port_root.get_node_or_null("PortPlot") as PortPlot if _port_root != null else null
	if plot != null and plot.child_entered_tree.is_connected(_on_plot_child_entered):
		plot.child_entered_tree.disconnect(_on_plot_child_entered)
	_apply_draft_to_facilities()


func _apply_draft_to_facilities() -> void:
	if _facilities == null or not is_instance_valid(_facilities):
		return
	_facilities.apply_slots(_draft)
	_update_selection_ring()


func _refresh_slot_list() -> void:
	_slot_list.clear()
	var selected_index := -1
	for i in range(_draft.size()):
		var slot := _draft[i]
		var service_id := str(slot.get("id", ""))
		var building := str(slot.get("blueprint_id", "")).strip_edges()
		var label := str(slot.get("display_name", service_id))
		if building.is_empty():
			label += "  ·  (empty)"
		else:
			label += "  ·  %s.json" % building
		var yaw := int(round(float(slot.get("yaw_degrees", 0.0)))) % 360
		if yaw < 0:
			yaw += 360
		if yaw != 0:
			label += "  ·  %d°" % yaw
		_slot_list.add_item(label)
		_slot_list.set_item_metadata(i, service_id)
		if service_id == _selected_id:
			selected_index = i
	if selected_index >= 0:
		_slot_list.select(selected_index)


func _refresh_building_options() -> void:
	if _building_option.item_selected.is_connected(_on_building_selected):
		_building_option.item_selected.disconnect(_on_building_selected)
	var previous := ""
	if _building_option.selected >= 0:
		previous = str(_building_option.get_item_metadata(_building_option.selected))
	_building_option.clear()
	_building_option.add_item("(none)", 0)
	_building_option.set_item_metadata(0, "")
	var index := 1
	var select_index := 0
	for blueprint_id in BuildingBlueprintCatalog.ids():
		_building_option.add_item("%s.json" % blueprint_id, index)
		_building_option.set_item_metadata(index, blueprint_id)
		if blueprint_id == previous:
			select_index = index
		index += 1
	_building_option.select(select_index)
	_building_option.item_selected.connect(_on_building_selected)
	_sync_inspector()


func _on_slot_selected(index: int) -> void:
	_selected_id = str(_slot_list.get_item_metadata(index))
	_sync_inspector()
	_update_selection_ring()


func _sync_inspector() -> void:
	var slot := _slot_by_id(_selected_id)
	var has := not slot.is_empty()
	_pos_x.editable = has
	_pos_z.editable = has
	_yaw.editable = has
	_building_option.disabled = not has
	if not has:
		return
	var position := _as_vector3(slot.get("position", Vector3.ZERO))
	_pos_x.set_value_no_signal(position.x)
	_pos_z.set_value_no_signal(position.z)
	_yaw.set_value_no_signal(_normalize_yaw(float(slot.get("yaw_degrees", 0.0))))
	var blueprint_id := str(slot.get("blueprint_id", "")).strip_edges()
	var found := 0
	for i in range(_building_option.item_count):
		if str(_building_option.get_item_metadata(i)) == blueprint_id:
			found = i
			break
	_building_option.select(found)


func _apply_spin_position() -> void:
	var slot := _slot_by_id(_selected_id)
	if slot.is_empty():
		return
	slot["position"] = Vector3(_pos_x.value, 0.0, _pos_z.value)
	_replace_slot(slot)
	_apply_draft_to_facilities()
	_refresh_slot_list()


func _apply_spin_yaw() -> void:
	var slot := _slot_by_id(_selected_id)
	if slot.is_empty():
		return
	slot["yaw_degrees"] = _normalize_yaw(_yaw.value)
	_replace_slot(slot)
	_apply_draft_to_facilities()
	_refresh_slot_list()
	_update_selection_ring()


func _rotate_yaw(delta_degrees: float) -> void:
	var slot := _slot_by_id(_selected_id)
	if slot.is_empty():
		return
	slot["yaw_degrees"] = _normalize_yaw(float(slot.get("yaw_degrees", 0.0)) + delta_degrees)
	_replace_slot(slot)
	_sync_inspector()
	_apply_draft_to_facilities()
	_refresh_slot_list()
	_update_selection_ring()


func _normalize_yaw(degrees: float) -> float:
	var yaw := fposmod(degrees, 360.0)
	if yaw >= 359.95:
		return 0.0
	return snappedf(yaw, 0.1)


func _nudge(dir: Vector3) -> void:
	var slot := _slot_by_id(_selected_id)
	if slot.is_empty():
		return
	var step := dir
	if absf(dir.x) == 1.0 or absf(dir.z) == 1.0:
		var fine := Input.is_key_pressed(KEY_SHIFT)
		step = dir * (NUDGE_FINE_M if fine else NUDGE_M)
	var position := _as_vector3(slot.get("position", Vector3.ZERO)) + step
	slot["position"] = position
	_replace_slot(slot)
	_sync_inspector()
	_apply_draft_to_facilities()
	_refresh_slot_list()


func _on_building_selected(index: int) -> void:
	var slot := _slot_by_id(_selected_id)
	if slot.is_empty():
		return
	slot["blueprint_id"] = str(_building_option.get_item_metadata(index))
	_replace_slot(slot)
	_apply_draft_to_facilities()
	_refresh_slot_list()


func _add_or_focus_role() -> void:
	if _role_option.selected < 0:
		return
	var role_id := str(_role_option.get_item_metadata(_role_option.selected))
	var existing := _slot_by_id(role_id)
	if not existing.is_empty():
		_selected_id = role_id
		_refresh_slot_list()
		_sync_inspector()
		_update_selection_ring()
		_save_lbl.text = "Focused existing %s slot" % role_id
		return
	var slot := PortServiceSlotCatalog.make_slot(role_id, Vector3(0.0, 0.0, 12.0))
	_draft.append(slot)
	_selected_id = role_id
	_refresh_slot_list()
	_sync_inspector()
	_apply_draft_to_facilities()
	_save_lbl.text = "Added %s" % role_id


func _remove_selected() -> void:
	if _selected_id.is_empty():
		return
	for i in range(_draft.size()):
		if str(_draft[i].get("id", "")) == _selected_id:
			_draft.remove_at(i)
			break
	_selected_id = str(_draft[0].get("id", "")) if not _draft.is_empty() else ""
	_refresh_slot_list()
	_sync_inspector()
	_apply_draft_to_facilities()
	_save_lbl.text = "Removed slot"


func _save_slots() -> void:
	if PortServiceSlotCatalog.save(_draft):
		_save_lbl.text = "Saved %s" % PortServiceSlotCatalog.SLOT_PATH
	else:
		_save_lbl.text = "Save failed"


func _reload_slots() -> void:
	PortServiceSlotCatalog.clear_cache()
	_draft = PortServiceSlotCatalog.slots()
	_selected_id = str(_draft[0].get("id", "")) if not _draft.is_empty() else ""
	_refresh_slot_list()
	_refresh_building_options()
	_sync_inspector()
	_apply_draft_to_facilities()
	_save_lbl.text = "Reloaded from disk"


func _update_selection_ring() -> void:
	var slot := _slot_by_id(_selected_id)
	if slot.is_empty() or _facilities == null or not is_instance_valid(_facilities):
		_selection_ring.visible = false
		return
	var local := _as_vector3(slot.get("position", Vector3.ZERO))
	_selection_ring.global_position = _facilities.to_global(local) + Vector3(0.0, 0.08, 0.0)
	var footprint := _as_vector3(slot.get("footprint", Vector3(10.0, 0.12, 8.0)))
	var radius := maxf(footprint.x, footprint.z) * 0.55
	var torus := _selection_ring.mesh as TorusMesh
	if torus != null:
		torus.inner_radius = radius
		torus.outer_radius = radius + 0.4
	_selection_ring.visible = true


func _slot_by_id(service_id: String) -> Dictionary:
	for slot in _draft:
		if str(slot.get("id", "")) == service_id:
			return slot
	return {}


func _replace_slot(updated: Dictionary) -> void:
	var service_id := str(updated.get("id", ""))
	for i in range(_draft.size()):
		if str(_draft[i].get("id", "")) == service_id:
			_draft[i] = updated
			return


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var arr := value as Array
		return Vector3(
			float(arr[0]) if arr.size() > 0 else 0.0,
			float(arr[1]) if arr.size() > 1 else 0.0,
			float(arr[2]) if arr.size() > 2 else 0.0,
		)
	return Vector3.ZERO
