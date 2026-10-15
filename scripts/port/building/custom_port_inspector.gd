class_name CustomPortInspector
extends PanelContainer
## Isolated harbour simulator UI. Every action uses the supplied authority model;
## this panel owns no fleet, inventory, persistence, or global input state.

signal state_changed(snapshot: Dictionary, result: Dictionary)
signal close_requested
signal test_vessel_requested(prebuilt_id: String)

const Berths = preload("res://scripts/port/state/custom_port_berths.gd")
const Style = preload("res://scripts/ui/voyage_style.gd")
const Commodities = preload("res://scripts/cargo/commodity_catalog.gd")
const Fish = preload("res://scripts/cargo/fish_catalog.gd")
const TestVisitors = preload("res://scripts/port/building/custom_port_test_visitors.gd")

var _state: RefCounted
var _catalog: Dictionary = {}
var _actor_company_id := ""
var _authority_context: Dictionary = {}
var _snapshot: Dictionary = {}
var _berths: Array[Dictionary] = []
var _built := false
var _refreshing := false
var _command_sequence := 0
var _title: Label
var _summary: Label
var _feedback: Label
var _vessel: OptionButton
var _berth: OptionButton
var _vessel_details: Label
var _berth_details: Label
var _fit_details: Label
var _dock: Button
var _undock: Button
var _store: OptionButton
var _lot: OptionButton
var _quantity: SpinBox
var _quantity_row: HBoxContainer
var _stock: Label
var _store_details: Label
var _cargo_access: Label
var _reserve: Button
var _reservation: OptionButton
var _load: Button
var _cancel: Button
var _unload_lot: OptionButton
var _unload: Button
var _manifest: Label
var _json: TextEdit
var _storage_admin_company_id := ""
var _settings_store: OptionButton
var _settings_role: Label
var _settings_capacity: Label
var _settings_name: LineEdit
var _visitors_collect: CheckBox
var _visitors_deliver: CheckBox
var _all_commodities: CheckBox
var _commodity_choices: VBoxContainer
var _commodity_checks: Dictionary = {}
var _save_storage: Button
var _panel_size := Vector2.ZERO
var _layout_pending := false
var _test_visitors_enabled := false
var _test_visitor_controls: VBoxContainer
var _test_visitor: OptionButton
var _invite_visitor: Button
var _tabs: TabContainer
var _cargo_focus_active := false
var _port_name: LineEdit
var _rename_port: Button
var _port_settings_role: Label


func configure(state: RefCounted, catalog: Dictionary = {}, actor_company_id: String = "", panel_size := Vector2(620, 620)) -> void:
	_panel_size = panel_size.max(Vector2(580, 540))
	_state = state
	_catalog = catalog.duplicate(true)
	_actor_company_id = actor_company_id
	_ensure_ui()
	_refresh_test_visitors()
	refresh()


## Workshop hosts explicitly opt in. This panel emits intent only: admission,
## identity, installed fitout and cargo remain the supplied authority's concern.
func set_test_visitors_enabled(enabled: bool) -> void:
	_test_visitors_enabled = enabled
	_ensure_ui()
	_refresh_test_visitors()
	if _state != null: _refresh_fit()
	_queue_layout()


func select_vessel(id: String) -> bool:
	if _state == null or id.is_empty(): return false
	refresh()
	for index in _vessel.item_count:
		if str(_vessel.get_item_metadata(index)) == id:
			_vessel.select(index)
			_refresh_vessel()
			return true
	return false


## Operator navigation changes only selection. Empty vessel means that no
## compatible vessel is alongside; never substitute an unrelated first record.
func focus_cargo(store_id: String, vessel_id := "") -> bool:
	if _state == null: return false
	var current: Dictionary = _state.call("to_dict")
	if _find(current.get("stores", []), store_id).is_empty(): return false
	if not vessel_id.is_empty() and _find(current.get("vessels", []), vessel_id).is_empty(): return false
	refresh()
	_cargo_focus_active = true
	_select_exact(_store, store_id)
	_select_exact(_vessel, vessel_id)
	_tabs.current_tab = 1
	_feedback.text = ""
	_refresh_vessel()
	return true


func focus_berths() -> void:
	_ensure_ui()
	_cargo_focus_active = false
	_tabs.current_tab = 0
	_feedback.text = ""
	if _state != null: refresh()


func _select_exact(selector: OptionButton, id: String) -> void:
	selector.select(-1)
	for index in selector.item_count:
		if not id.is_empty() and str(selector.get_item_metadata(index)) == id:
			selector.select(index)
			return


func set_authority_context(context: Dictionary) -> void:
	_authority_context = context.duplicate(true)
	if _built: _refresh_storage_settings()


func set_storage_admin_actor(company_id: String) -> void:
	# The isolated workshop opts into an owner role explicitly. Vessel commands
	# still use their own actor; opening this panel never grants port ownership.
	_storage_admin_company_id = company_id
	if _built:
		_refresh_storage_settings()
		_refresh_port_settings()


func _ready() -> void:
	_ensure_ui()
	visibility_changed.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	if _state != null: refresh()


func refresh() -> void:
	_ensure_ui()
	if _state == null: return
	_refreshing = true
	var focused_store := _selected(_store)
	var focused_vessel := _selected(_vessel)
	_snapshot = _state.call("to_dict")
	_berths = _state.call("derived_berths")
	_title.text = str(_snapshot.get("name", "Harbour records"))
	_summary.text = "%d berths · %d stores · Revision %d" % [_berths.size(), _snapshot.get("stores", []).size(), int(_snapshot.get("revision", 0))]
	_fill(_vessel, _snapshot.get("vessels", []), "No vessels")
	_fill(_berth, _berths, "No berths")
	_fill(_store, _snapshot.get("stores", []), "No storage")
	_fill(_settings_store, _snapshot.get("stores", []), "No storage")
	if _cargo_focus_active:
		_select_exact(_store, focused_store)
		_select_exact(_vessel, focused_vessel)
	_refreshing = false
	_refresh_vessel()
	_refresh_storage_settings()
	_refresh_port_settings()
	_json.text = JSON.stringify(_snapshot, "\t", true, true)
	var validation: Array = _state.get("validation_errors")
	if not validation.is_empty(): _set_feedback("Port data needs repair: " + "; ".join(validation), false)


func _ensure_ui() -> void:
	if _built: return
	_built = true
	theme = Style.theme()
	theme.default_font_size = 18
	custom_minimum_size = Vector2(580.0, 540.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", Style.box(Style.PAPER, 20))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	_title = Style.label("Harbour records", 27)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_title)
	var close_button := _button("Close", func(): close_requested.emit())
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	heading.add_child(close_button)
	_summary = Style.label("", 16, Style.MUTED)
	body.add_child(_summary)
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.tab_changed.connect(func(_index: int): _queue_layout())
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", Style.box(Style.PAPER, 10))
	body.add_child(tabs)
	var berths_layout := _page(tabs, "Berths")
	var berths_page: VBoxContainer = berths_layout.content
	_test_visitor_controls = VBoxContainer.new()
	_test_visitor_controls.visible = false
	_test_visitor_controls.add_theme_constant_override("separation", 3)
	berths_page.add_child(_test_visitor_controls)
	_test_visitor_controls.add_child(Style.label("Test visitor", 16, Style.MUTED))
	var invite_row := HBoxContainer.new()
	_test_visitor_controls.add_child(invite_row)
	_test_visitor = OptionButton.new()
	_test_visitor.custom_minimum_size.y = 42
	_test_visitor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_test_visitor.clip_text = true
	for option in TestVisitors.options():
		_test_visitor.add_item(str(option.name))
		_test_visitor.set_item_metadata(_test_visitor.item_count - 1, str(option.id))
	invite_row.add_child(_test_visitor)
	_invite_visitor = _button("Invite", _request_test_vessel)
	_invite_visitor.size_flags_horizontal = Control.SIZE_SHRINK_END
	_invite_visitor.disabled = true
	_invite_visitor.tooltip_text = "Invite an empty vessel to this workshop's records. Dock it using an available berth."
	invite_row.add_child(_invite_visitor)
	_test_visitor_controls.add_child(Style.label("Empty vessel · workshop only", 15, Style.MUTED))
	_vessel = _selector(berths_page, "Vessel", func(_index: int): _refresh_vessel())
	_vessel_details = _text(berths_page)
	_berth = _selector(berths_page, "Berth", func(_index: int): _refresh_fit())
	_berth_details = _text(berths_page)
	_fit_details = _text(berths_layout.actions, 18)
	var berth_actions := HBoxContainer.new()
	berths_layout.actions.add_child(berth_actions)
	_dock = _button("Dock vessel", _dock_selected, true)
	_undock = _button("Leave berth", _undock_selected)
	berth_actions.add_child(_dock)
	berth_actions.add_child(_undock)
	var cargo_layout := _page(tabs, "Cargo")
	var cargo_page: VBoxContainer = cargo_layout.content
	_cargo_access = _text(cargo_page)
	_store = _selector(cargo_page, "Storage", func(_index: int): _refresh_store())
	_store_details = _text(cargo_page, 16)
	_lot = _selector(cargo_page, "Available cargo", func(_index: int): _refresh_stock())
	_stock = _text(cargo_page)
	_reservation = _selector(cargo_page, "Reserved for this vessel", func(_index: int): _refresh_reservation_actions())
	cargo_page.add_child(HSeparator.new())
	_manifest = _text(cargo_page)
	_unload_lot = _selector(cargo_page, "Cargo aboard", func(_index: int): _refresh_unload_action())
	var request := HBoxContainer.new()
	_quantity_row = request
	cargo_layout.actions.add_child(request)
	var quantity_label := Style.label("Quantity", 18)
	quantity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	quantity_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	request.add_child(quantity_label)
	_quantity = SpinBox.new()
	_quantity.min_value = 0.0
	_quantity.max_value = 1000000.0
	_quantity.step = 1.0
	_quantity.value = 1.0
	_quantity.custom_minimum_size.x = 130.0
	_quantity.custom_minimum_size.y = 42.0
	_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quantity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quantity.tooltip_text = "Quantity for divisible cargo. A whole fish is always transferred intact."
	request.add_child(_quantity)
	var stock_actions := HBoxContainer.new()
	cargo_layout.actions.add_child(stock_actions)
	_reserve = _button("Reserve cargo", _reserve_selected, true)
	_unload = _button("Unload quantity", _unload_selected)
	_reserve.tooltip_text = "Reserve this quantity of the selected available cargo."
	_unload.tooltip_text = "Return this quantity of the selected cargo aboard to the selected storage."
	stock_actions.add_child(_reserve)
	stock_actions.add_child(_unload)
	var load_actions := HBoxContainer.new()
	cargo_layout.actions.add_child(load_actions)
	_load = _button("Load reservation", _load_selected, true)
	_load.tooltip_text = "Load the entire selected reservation aboard."
	_cancel = _button("Cancel reservation", _cancel_selected)
	load_actions.add_child(_load)
	load_actions.add_child(_cancel)
	var storage_layout := _page(tabs, "Storage")
	var storage_page: VBoxContainer = storage_layout.content
	_settings_role = _text(storage_page, 16)
	_settings_store = _selector(storage_page, "Storage", func(_index: int): _refresh_storage_settings())
	_settings_capacity = _text(storage_page, 16)
	storage_page.add_child(Style.label("Name", 16, Style.MUTED))
	_settings_name = LineEdit.new()
	_style_name_field(_settings_name)
	_settings_name.max_length = 80
	_settings_name.custom_minimum_size.y = 42
	_settings_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_page.add_child(_settings_name)
	_visitors_collect = _checkbox(storage_page, "Visitors may collect cargo")
	_visitors_deliver = _checkbox(storage_page, "Visitors may deliver cargo")
	storage_page.add_child(Style.label("Accepted goods", 16, Style.MUTED))
	_all_commodities = _checkbox(storage_page, "All supported goods")
	_all_commodities.toggled.connect(func(_pressed: bool): _refresh_commodity_controls())
	_commodity_choices = VBoxContainer.new()
	storage_page.add_child(_commodity_choices)
	_save_storage = _button("Save storage settings", _save_storage_settings, true)
	storage_layout.actions.add_child(_save_storage)
	var json_page := VBoxContainer.new()
	json_page.name = "Port data"
	tabs.add_child(json_page)
	_json = TextEdit.new()
	_json.editable = false
	_json.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_json.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json.add_theme_font_size_override("font_size", 14)
	_json.add_theme_color_override("font_color", Style.INK)
	_json.add_theme_stylebox_override("normal", Style.box(Color("f8f6f0"), 10))
	json_page.add_child(_json)
	var port_layout := _page(tabs, "Harbour")
	var port_page: VBoxContainer = port_layout.content
	_port_settings_role = _text(port_page, 16)
	port_page.add_child(Style.label("Harbour name", 16, Style.MUTED))
	_port_name = LineEdit.new()
	_style_name_field(_port_name)
	_port_name.max_length = 80
	_port_name.custom_minimum_size.y = 42
	_port_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_page.add_child(_port_name)
	_port_name.text_submitted.connect(func(_text: String): _rename_selected_port())
	_rename_port = _button("Save harbour name", _rename_selected_port, true)
	port_layout.actions.add_child(_rename_port)
	_feedback = Style.label("", 17, Style.ACCENT)
	_feedback.custom_minimum_size.y = 28.0
	body.add_child(_feedback)
	_refresh_test_visitors()


func _refresh_test_visitors() -> void:
	if _test_visitor_controls == null: return
	_test_visitor_controls.visible = _test_visitors_enabled
	var available := _test_visitors_enabled and _state != null and _test_visitor.item_count > 0
	_test_visitor.disabled = not available
	_invite_visitor.disabled = not available


func _style_name_field(field: LineEdit) -> void:
	# The host's dark focus box otherwise paints over this paper form, hiding
	# its dark text even though the normal LineEdit style is white.
	field.add_theme_stylebox_override("normal", Style.box(Color.WHITE, 12))
	field.add_theme_stylebox_override("read_only", Style.box(Color("e9e9e0"), 12))
	var focus := Style.box(Color.TRANSPARENT, 12)
	focus.set_border_width_all(2)
	focus.border_color = Style.ACCENT
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", Style.INK)
	field.add_theme_color_override("font_uneditable_color", Style.MUTED)
	field.add_theme_color_override("caret_color", Style.ACCENT)


func _request_test_vessel() -> void:
	if not _test_visitors_enabled or _state == null: return
	var requested := _selected(_test_visitor)
	for option in TestVisitors.options():
		if str(option.id) == requested:
			test_vessel_requested.emit(requested)
			return


func _page(tabs: TabContainer, title: String) -> Dictionary:
	# Keep command controls outside the scroll: a short host or expanded details
	# must never make the action the player came here to perform disappear.
	var page := VBoxContainer.new()
	page.name = title
	page.add_theme_constant_override("separation", 8)
	tabs.add_child(page)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	page.add_child(actions)
	return {"content": content, "actions": actions}


func _selector(parent: Control, title: String, callback: Callable) -> OptionButton:
	parent.add_child(Style.label(title, 16, Style.MUTED))
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 42.0
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.clip_text = true
	selector.item_selected.connect(callback)
	parent.add_child(selector)
	return selector


func _text(parent: Control, font_size: int = 18) -> Label:
	var label := Style.label("", font_size)
	parent.add_child(label)
	return label


func _checkbox(parent: Control, title: String) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = title
	checkbox.custom_minimum_size.y = 34
	parent.add_child(checkbox)
	return checkbox


func _button(title: String, callback: Callable, primary: bool = false) -> Button:
	var button := Style.button(title, callback, primary)
	button.custom_minimum_size.y = 42.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	return button


func _fill(selector: OptionButton, records: Array, empty: String, preferred: String = "") -> void:
	var previous := preferred if not preferred.is_empty() else _selected(selector)
	selector.clear()
	var ordinal := 0
	for record in records:
		if not record is Dictionary: continue
		ordinal += 1
		var id := str(record.get("id", ""))
		var display := str(record.get("name", record.get("label", "Item %d" % ordinal)))
		if record.has("bollard_ids"):
			display = "Berth %d · %.0f m" % [ordinal, float(record.max_length_m)]
		if record.has("commodity_id"):
			display = _fish_label(record) if _is_specimen(record) else "%s · %s %s" % [_commodity(record), _quantity_text(float(record.get("quantity", 0.0))), _units(record)]
		selector.add_item(display)
		selector.set_item_metadata(selector.item_count - 1, id)
		if id == previous: selector.select(selector.item_count - 1)
	if selector.item_count == 0:
		selector.add_item(empty)
		selector.set_item_metadata(0, "")
		selector.disabled = true
	else: selector.disabled = false


func _selected(selector: OptionButton) -> String:
	if selector == null or selector.selected < 0 or selector.selected >= selector.item_count: return ""
	return str(selector.get_item_metadata(selector.selected))


func _refresh_vessel() -> void:
	if _refreshing: return
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	if ship.is_empty():
		_vessel_details.text = "No vessel records are available."
	else:
		_vessel_details.text = "%.1f m long · %.1f m beam · %.1f m draft\n%s" % [float(ship.get("length_m", 0.0)), float(ship.get("beam_m", 0.0)), float(ship.get("draft_m", 0.0)), "Alongside" if not str(ship.get("berth_id", "")).is_empty() else "Awaiting berth"]
		_vessel_details.text += "\n" + _capacity_summary(ship, false)
		if not str(ship.get("berth_id", "")).is_empty():
			_fill(_berth, _berths, "No berths", str(ship.berth_id))
	_refresh_fit()
	_refresh_store()
	_refresh_manifest()
	_queue_layout()


func _refresh_fit() -> void:
	if _refreshing: return
	var berth := _find(_berths, _selected(_berth))
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	if berth.is_empty():
		_berth_details.text = "Place bollards along a continuous quay edge to define berths."
		_fit_details.text = "No berth selected."
		_dock.disabled = true
	else:
		var depth := "%.1f m water depth" % float(berth.depth_m) if berth.get("water_verified", false) else "Water depth and approach not verified"
		var cranes: Array = Berths.services_for_vessel(berth, ship).crane_ids
		var crane_names: Array[String] = []
		for id in cranes: crane_names.append(_placement_name(str(id)))
		_berth_details.text = "Up to %.1f m long × %.1f m beam\n%s · %.1f m under-keel clearance" % [float(berth.max_length_m), float(berth.max_beam_m), depth, float(berth.under_keel_clearance_m)]
		if not ship.is_empty(): _berth_details.text += "\n" + ("Crane: " + ", ".join(crane_names) if not crane_names.is_empty() else "No crane reaches this vessel")
		var result := Berths.fit(berth, ship, _occupancy())
		_fit_details.text = "Vessel fits this berth." if result.ok else " · ".join(_friendly_reasons(result.reasons))
		_fit_details.add_theme_color_override("font_color", Style.ACCENT if result.ok else Color("8b3d30"))
		if ship.is_empty():
			_fit_details.text = "Invite a test visitor to try this berth." if _test_visitors_enabled else "Select a vessel to check this berth."
			_fit_details.add_theme_color_override("font_color", Style.MUTED)
		_dock.disabled = not result.ok or not str(ship.get("berth_id", "")).is_empty()
	_undock.disabled = ship.is_empty() or str(ship.get("berth_id", "")).is_empty()


func _refresh_store() -> void:
	if _refreshing: return
	var store := _find(_snapshot.get("stores", []), _selected(_store))
	_store_details.text = _capacity_summary(store, true) if not store.is_empty() else ""
	_fill(_lot, store.get("lots", []), "Storage is empty")
	_refresh_stock()
	_refresh_reservations()
	_refresh_unload_action()


func _can_configure_storage() -> bool:
	return not _storage_admin_company_id.is_empty() and _storage_admin_company_id == str(_snapshot.get("owner_company_id", ""))


func _refresh_port_settings() -> void:
	if _port_name == null: return
	var allowed := _can_configure_storage()
	_port_name.text = str(_snapshot.get("name", ""))
	_port_name.editable = allowed
	_rename_port.disabled = not allowed
	_port_settings_role.text = "Owner settings" if allowed else "Only the port owner can rename this harbour."


func _rename_selected_port() -> void:
	if not _can_configure_storage(): return
	_submit("rename_port", {"name":_port_name.text}, _storage_admin_company_id)


func _refresh_storage_settings() -> void:
	if _refreshing or _settings_store == null: return
	var store := _find(_snapshot.get("stores", []), _selected(_settings_store))
	var allowed := _can_configure_storage() and not store.is_empty()
	_settings_role.text = "Owner settings" if allowed else "Only the port owner can change storage settings."
	_settings_capacity.text = _capacity_summary(store, true) if not store.is_empty() else "Place a cargo terminal to add storage."
	_settings_name.text = str(store.get("name", "Storage")) if not store.is_empty() else ""
	_settings_name.editable = allowed
	_visitors_collect.set_pressed_no_signal(store.get("public_loading", false))
	_visitors_deliver.set_pressed_no_signal(store.get("public_unloading", false))
	_visitors_collect.disabled = not allowed
	_visitors_deliver.disabled = not allowed
	_save_storage.disabled = not allowed
	_all_commodities.disabled = not allowed
	for child in _commodity_choices.get_children():
		_commodity_choices.remove_child(child)
		child.queue_free()
	_commodity_checks.clear()
	var goods := _storage_commodities(store)
	var accepted: Array = store.get("accepted_commodities", [])
	var all_selected := accepted.is_empty()
	if not goods.is_empty() and accepted.size() == goods.size():
		all_selected = true
		for id in goods:
			if id not in accepted: all_selected = false
	_all_commodities.set_pressed_no_signal(all_selected)
	for id in goods:
		var checkbox := _checkbox(_commodity_choices, str(goods[id]))
		checkbox.set_pressed_no_signal(all_selected or id in accepted)
		_commodity_checks[id] = checkbox
	_refresh_commodity_controls()
	_queue_layout()


func _storage_commodities(store: Dictionary) -> Dictionary:
	var goods: Dictionary = {}
	var placement := _find(_snapshot.get("placements", []), str(store.get("placement_id", "")))
	var definition: Dictionary = _catalog.get(placement.get("asset_id", ""), {}).get("attached_store", {})
	var supported: Array = definition.get("accepted_commodities", [])
	var modes: Array = store.get("accepted_handling_modes", [])
	for entry in Commodities.COMMODITIES:
		if not supported.is_empty() and entry.id not in supported: continue
		# Containers may hold any supported commodity. A bulk grab or fish depot
		# still keeps its physical handling rules when an owner edits this filter.
		if supported.is_empty() and not modes.is_empty() and "container" not in modes and entry.handling_mode not in modes: continue
		goods[str(entry.id)] = str(entry.display)
	var extra: Array = supported + store.get("accepted_commodities", []) + _authority_context.get("commodity_ids", [])
	for lot in store.get("lots", []): extra.append(lot.commodity_id)
	for id in extra:
		if not goods.has(str(id)): goods[str(id)] = str(id).replace("_", " ").capitalize()
	return goods


func _refresh_commodity_controls() -> void:
	var allowed := _can_configure_storage() and not _selected(_settings_store).is_empty()
	for checkbox in _commodity_checks.values():
		checkbox.disabled = not allowed or _all_commodities.button_pressed


func _save_storage_settings() -> void:
	if not _can_configure_storage():
		_set_feedback("Only the port owner can change storage settings.", false)
		return
	var accepted: Array = []
	var store := _find(_snapshot.get("stores", []), _selected(_settings_store))
	var placement := _find(_snapshot.get("placements", []), str(store.get("placement_id", "")))
	var supported: Array = _catalog.get(placement.get("asset_id", ""), {}).get("attached_store", {}).get("accepted_commodities", [])
	if _all_commodities.button_pressed:
		accepted = supported.duplicate()
	else:
		for id in _commodity_checks:
			if _commodity_checks[id].button_pressed: accepted.append(id)
		if accepted.is_empty():
			_set_feedback("Choose at least one good, or accept all supported goods.", false)
			return
	_submit("configure_store", {"store_id": _selected(_settings_store), "changes": {
		"name": _settings_name.text, "public_loading": _visitors_collect.button_pressed,
		"public_unloading": _visitors_deliver.button_pressed, "accepted_commodities": accepted,
	}}, _storage_admin_company_id)


func _refresh_stock() -> void:
	if _refreshing: return
	var store := _find(_snapshot.get("stores", []), _selected(_store))
	var lot := _find(store.get("lots", []), _selected(_lot))
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	var access := _selected_store_served(ship, store)
	var ship_name := str(ship.get("name", "Selected vessel"))
	_cargo_access.text = "%s · %s" % [ship_name, "Storage reachable from berth" if access else "Dock at a berth served by this storage"]
	if lot.is_empty(): _stock.text = "No cargo available in this storage."
	else:
		var available := float(lot.get("quantity", 0.0))
		for reservation in _snapshot.get("reservations", []):
			if reservation.store_id == store.id and reservation.lot_id == lot.id: available -= float(reservation.quantity)
		_stock.text = "%s %s available" % [_quantity_text(maxf(available, 0.0)), _units(lot)]
		if _is_specimen(lot):
			_stock.text = _fish_label(lot) + (" · Available" if available > 0.0 else " · Reserved")
		elif not is_equal_approx(float(lot.get("unit_mass_kg", 0.0)), 1.0):
			_stock.text += " · %s each" % _mass_text(float(lot.get("unit_mass_kg", 0.0)))
		var reserved := float(lot.get("quantity", 0.0)) - maxf(available, 0.0)
		if reserved > 0 and not _is_specimen(lot): _stock.text += " · %s reserved" % _quantity_text(reserved)
		var compatibility: Dictionary = CustomPortState._cargo_compatibility(ship, lot)
		if not compatibility.ok: _stock.text += "\n" + _failure_text(compatibility, "reserve_cargo")
		var attributes: Dictionary = lot.get("attributes", {})
		_quantity.step = 1.0 if attributes.get("indivisible", false) or attributes.get("whole_units", false) or attributes.has("container_type") else 0.1
	# Deliberately allow requests above stock; authority returns a real shortage.
	_reserve.disabled = lot.is_empty() or not access
	_reserve.text = "Reserve fish" if _is_specimen(lot) else "Reserve cargo"
	_reserve.tooltip_text = "Reserve the selected whole fish; the quantity field does not apply." if _is_specimen(lot) else "Reserve this quantity of the selected available cargo."
	_refresh_quantity_control()


func _refresh_reservations() -> void:
	var records: Array = []
	for reservation in _snapshot.get("reservations", []):
		if str(reservation.vessel_id) != _selected(_vessel): continue
		if _cargo_focus_active and str(reservation.store_id) != _selected(_store): continue
		var entry: Dictionary = reservation.duplicate()
		var store := _find(_snapshot.get("stores", []), str(reservation.store_id))
		var lot := _find(store.get("lots", []), str(reservation.lot_id))
		entry.name = ("%s · %s" % [_fish_label(lot), str(store.get("name", "Storage"))]) if _is_specimen(lot) else "%s %s · %s" % [_quantity_text(float(reservation.quantity)), _commodity(lot), str(store.get("name", "Storage"))]
		records.append(entry)
	_fill(_reservation, records, "Nothing reserved")
	_refresh_reservation_actions()


func _refresh_reservation_actions() -> void:
	if _refreshing: return
	var selected := _find(_snapshot.get("reservations", []), _selected(_reservation))
	_load.disabled = selected.is_empty()
	_cancel.disabled = selected.is_empty()


func _refresh_manifest() -> void:
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	var lots: Array = ship.get("lots", [])
	_manifest.text = _capacity_summary(ship, true)
	var reserved_mass := 0.0
	for reservation in _snapshot.get("reservations", []):
		if str(reservation.vessel_id) == str(ship.get("id", "")):
			reserved_mass += float(reservation.quantity) * float(reservation.unit_mass_kg)
	if reserved_mass > 0: _manifest.text += "\n%s reserved ashore" % _mass_text(reserved_mass)
	_fill(_unload_lot, lots, "Vessel is empty")
	_refresh_unload_action()


func _refresh_unload_action() -> void:
	if _refreshing: return
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	var store := _find(_snapshot.get("stores", []), _selected(_store))
	var lot := _find(ship.get("lots", []), _selected(_unload_lot))
	_unload.disabled = _selected(_unload_lot).is_empty() or not _selected_store_served(ship, store)
	_unload.text = "Unload fish" if _is_specimen(lot) else "Unload quantity"
	_unload.tooltip_text = "Unload the selected whole fish; the quantity field does not apply." if _is_specimen(lot) else "Return this quantity of the selected cargo aboard to the selected storage."
	_refresh_quantity_control()


func _refresh_quantity_control() -> void:
	var store := _find(_snapshot.get("stores", []), _selected(_store))
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	var stock := _find(store.get("lots", []), _selected(_lot))
	var aboard := _find(ship.get("lots", []), _selected(_unload_lot))
	# The selectors are independent: retain quantity if either action operates
	# on divisible cargo, but never ask for a fish's internal kg/count encoding.
	_quantity_row.visible = (not stock.is_empty() and not _is_specimen(stock)) or (not aboard.is_empty() and not _is_specimen(aboard))
	_queue_layout()


func _selected_store_served(ship: Dictionary, store: Dictionary) -> bool:
	if ship.is_empty() or store.is_empty(): return false
	var berth := _find(_berths, str(ship.get("berth_id", "")))
	return Berths.services_for_vessel(berth, ship).store_ids.has(str(store.id))


func _dock_selected() -> void:
	_submit("dock", {"vessel_id": _selected(_vessel), "berth_id": _selected(_berth)})


func _undock_selected() -> void:
	_submit("undock", {"vessel_id": _selected(_vessel)})


func _reserve_selected() -> void:
	var store := _find(_snapshot.get("stores", []), _selected(_store))
	var lot := _find(store.get("lots", []), _selected(_lot))
	_submit("reserve_cargo", {"store_id": _selected(_store), "vessel_id": _selected(_vessel), "lot_id": _selected(_lot), "quantity": float(lot.quantity) if _is_specimen(lot) else _quantity.value})


func _load_selected() -> void:
	_submit("load_cargo", {"reservation_id": _selected(_reservation)})


func _cancel_selected() -> void:
	_submit("cancel_reservation", {"reservation_id": _selected(_reservation)})


func _unload_selected() -> void:
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	var lot := _find(ship.get("lots", []), _selected(_unload_lot))
	_submit("unload_cargo", {"store_id": _selected(_store), "vessel_id": _selected(_vessel), "lot_id": _selected(_unload_lot), "quantity": float(lot.quantity) if _is_specimen(lot) else _quantity.value})


func _submit(kind: String, payload: Dictionary, explicit_actor: String = "") -> void:
	if _state == null: return
	var ship := _find(_snapshot.get("vessels", []), _selected(_vessel))
	var source_lot := _transfer_lot(kind, payload)
	var fish_label := _fish_label(source_lot) if _is_specimen(source_lot) else ""
	var actor := _actor_company_id if not _actor_company_id.is_empty() else str(ship.get("owner_company_id", ""))
	if kind in ["configure_store", "rename_port"]: actor = explicit_actor
	_command_sequence += 1
	var result: Dictionary = _state.call("apply", {
		"command_id": "inspector-%d-%d-%d" % [Time.get_ticks_usec(), get_instance_id(), _command_sequence],
		"expected_revision": int(_snapshot.get("revision", 0)),
		"actor_company_id": actor, "kind": kind, "payload": payload,
	}, _authority_context)
	if result.get("ok", false):
		var snapshot: Dictionary = result.get("snapshot", _state.call("to_dict"))
		refresh()
		var message := _success_text(kind, result.get("result", {}))
		if not fish_label.is_empty():
			message = fish_label + {"reserve_cargo": " reserved.", "load_cargo": " loaded aboard.", "unload_cargo": " landed."}.get(kind, "")
		_set_feedback(message, true)
		state_changed.emit(snapshot, result)
	else:
		_set_feedback(_failure_text(result, kind), false)


func _transfer_lot(kind: String, payload: Dictionary) -> Dictionary:
	if kind == "reserve_cargo":
		var store := _find(_snapshot.get("stores", []), str(payload.get("store_id", "")))
		return _find(store.get("lots", []), str(payload.get("lot_id", "")))
	if kind == "unload_cargo":
		var ship := _find(_snapshot.get("vessels", []), str(payload.get("vessel_id", "")))
		return _find(ship.get("lots", []), str(payload.get("lot_id", "")))
	if kind == "load_cargo":
		var reservation := _find(_snapshot.get("reservations", []), str(payload.get("reservation_id", "")))
		var store := _find(_snapshot.get("stores", []), str(reservation.get("store_id", "")))
		return _find(store.get("lots", []), str(reservation.get("lot_id", "")))
	return {}


func _success_text(kind: String, result: Dictionary) -> String:
	match kind:
		"dock": return "Vessel secured alongside."
		"undock": return "Berth released."
		"reserve_cargo": return "%s reserved for this vessel." % _quantity_text(float(result.get("quantity", 0.0)))
		"load_cargo": return "%s loaded aboard." % _quantity_text(float(result.get("quantity", 0.0)))
		"unload_cargo": return "%s returned to storage." % _quantity_text(float(result.get("quantity", 0.0)))
		"cancel_reservation": return "Reservation released."
		"configure_store": return "Storage settings saved."
		"rename_port": return "Harbour name saved."
	return "Updated."


func _failure_text(result: Dictionary, kind: String = "") -> String:
	var details: Dictionary = result.get("details", {})
	match str(result.get("code", "rejected")):
		"insufficient_stock": return "Only %s available; requested %s. No cargo moved." % [_quantity_text(float(details.get("available", 0.0))), _quantity_text(float(details.get("requested", _quantity.value)))]
		"vessel_capacity_exceeded": return "Only %s of carrying capacity remains." % _mass_text(float(details.free_mass_kg)) if details.has("free_mass_kg") else "The vessel cannot carry that much cargo."
		"vessel_slots_exceeded": return "Only %s cargo positions remain." % _quantity_text(float(details.free_units)) if details.has("free_units") else "The vessel has too few cargo positions for this load."
		"handling_not_supported":
			var mode := str(details.get("handling_mode", "general"))
			if kind == "unload_cargo": return "This storage cannot accept %s." % {"container": "containers", "general": "general cargo", "bulk": "dry bulk", "catch": "fish", "liquid": "liquids"}.get(mode, "that cargo")
			return "This vessel has no %s." % _handling_name(mode).to_lower()
		"handling_capacity_exceeded": return "The selected cargo exceeds the capacity of its hold."
		"bulk_compartments_exceeded": return "No suitable hold is free. Separate bulk shipments need separate holds."
		"catch_compartments_exceeded": return "The catch will not fit the available fish holds. A whole fish must fit in one hold."
		"invalid_cargo_holds": return "The vessel's hold layout needs repair before loading."
		"container_does_not_fit": return "No compatible %s container positions." % str(details.get("container_type", "selected"))
		"commodity_not_accepted": return "This storage does not accept that commodity."
		"not_docked": return "Dock this vessel before moving cargo."
		"store_capacity_exceeded": return "The selected storage is full."
		"store_slots_exceeded": return "The selected storage has too few free cargo positions."
		"store_out_of_reach": return "This berth's crane cannot reach the selected storage."
		"crane_handling_not_supported": return "This berth has no crane that can handle the selected cargo."
		"cargo_reserved": return "Load or cancel this vessel's reservations before leaving."
		"vessel_does_not_fit": return " · ".join(_friendly_reasons(details.get("reasons", [])))
		"revision_conflict": return "The port changed. Refresh its records before trying again."
		"not_vessel_owner": return "This vessel belongs to another company."
		"store_access_denied": return "This storage does not permit transfers to your company."
		"invalid_quantity": return "Enter a valid quantity for this cargo."
		"not_port_owner": return "Only the port owner can change these settings."
		"invalid_port_name": return "Enter a harbour name of up to 80 characters on one line."
		"port_name_unchanged": return "This is already the harbour's name."
		"invalid_store_name": return "Enter a storage name of up to 80 characters."
		"store_has_visitor_reservation": return "A visitor has reserved cargo here. Keep collection enabled until it is loaded or cancelled."
		"store_contains_excluded_goods": return "This storage still holds goods excluded by the new filter. Move them first."
		"unsupported_commodity_filter": return "Choose goods supported by this terminal."
		"unknown_commodity", "invalid_commodity_filter": return "Choose valid goods from the list."
	return str(result.get("code", "Request rejected")).replace("_", " ").capitalize() + "."


func _friendly_reasons(reasons: Array) -> Array[String]:
	var result: Array[String] = []
	for reason in reasons:
		match str(reason):
			"water_unverified": result.append("Approach needs a water-depth survey")
			"insufficient_length": result.append("Vessel too long")
			"insufficient_beam": result.append("Not enough manoeuvring width")
			"insufficient_depth": result.append("Not enough water under the keel")
			"occupied": result.append("Berth occupied")
			"adjacent_berth_occupied": result.append("Adjacent vessel blocks this berth")
			"invalid_vessel_dimensions": result.append("Select a vessel with valid dimensions")
			_: result.append(str(reason).replace("_", " ").capitalize())
	return result


func _occupancy() -> Array:
	var result: Array = []
	for vessel in _snapshot.get("vessels", []):
		if not str(vessel.get("berth_id", "")).is_empty(): result.append({"berth_id": vessel.berth_id, "vessel_id": vessel.id})
	return result


func _find(records: Array, id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get("id", "")) == id: return record
	return {}


func _commodity(lot: Dictionary) -> String:
	return str(lot.get("name", lot.get("commodity_id", "Cargo"))).replace("_", " ").capitalize()


func _is_specimen(lot: Dictionary) -> bool:
	return not lot.is_empty() and CustomPortState._handling_mode(lot) == "catch" and lot.get("attributes", {}).get("specimen", false) == true


func _fish_label(lot: Dictionary) -> String:
	var species_id := str(lot.get("attributes", {}).get("species_id", ""))
	var species_name := str(Fish.species(species_id).get("name", species_id.replace("_", " ").capitalize()))
	if species_name.is_empty(): species_name = _commodity(lot)
	return "%s · %s" % [species_name, _mass_text(float(lot.get("quantity", 0.0)) * float(lot.get("unit_mass_kg", 0.0)))]


func _units(lot: Dictionary) -> String:
	if lot.get("attributes", {}).has("container_type"): return "containers"
	if lot.has("unit"): return str(lot.unit)
	if CustomPortState._handling_mode(lot) in ["bulk", "catch", "liquid"] and is_equal_approx(float(lot.get("unit_mass_kg", 0)), 1.0): return "kg"
	return "units"


func _handling_name(mode: String) -> String:
	return {"container": "Container deck", "general": "General cargo deck", "bulk": "Dry bulk hold", "catch": "Fish hold", "liquid": "Liquid tank"}.get(mode, "Cargo space")


func _capacity_summary(record: Dictionary, include_load: bool) -> String:
	var lines: Array[String] = []
	var lots: Array = record.get("lots", [])
	var capacities: Dictionary = record.get("handling_capacity_kg", {})
	if capacities.is_empty() or capacities.size() > 1:
		var total := float(record.get("capacity_kg", 0.0))
		lines.append("Cargo · %s / %s" % [_mass_text(CustomPortState._mass(lots)), _mass_text(total)] if include_load else "Cargo capacity · " + _mass_text(total))
	for mode in capacities:
		var capacity := _mass_text(float(capacities[mode]))
		var heading := _handling_name(mode)
		if record.has("placement_id"):
			heading = {"container": "Container yard", "general": "Cargo storage", "bulk": "Bulk storage", "catch": "Fish storage", "liquid": "Tank storage"}.get(mode, "Cargo storage")
		lines.append("%s · %s / %s" % [heading, _mass_text(CustomPortState._mode_mass(lots, str(mode))), capacity] if include_load else "%s · %s" % [heading, capacity])
	if float(record.get("capacity_units", 0)) > 0:
		var maximum := _quantity_text(float(record.capacity_units))
		lines.append("%s / %s cargo positions" % [_quantity_text(CustomPortState._units(lots)), maximum] if include_load else "%s cargo positions" % maximum)
	return "\n".join(lines)


func _mass_text(mass_kg: float) -> String:
	return "%s t" % _quantity_text(mass_kg / 1000.0) if mass_kg >= 1000.0 else "%s kg" % _quantity_text(mass_kg)


func _placement_name(id: String) -> String:
	var placement := _find(_snapshot.get("placements", []), id)
	var attributes: Dictionary = placement.get("attributes", {})
	if attributes.has("display_name"): return str(attributes.display_name)
	var asset_id := str(placement.get("asset_id", ""))
	var asset: Dictionary = _catalog.get(asset_id, {})
	return str(asset.get("name", asset.get("label", "Cargo crane")))


func _quantity_text(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.2f" % value


func _set_feedback(message: String, success: bool) -> void:
	_feedback.text = message
	_feedback.add_theme_color_override("font_color", Style.ACCENT if success else Color("8b3d30"))
	_queue_layout()


func _queue_layout() -> void:
	if _layout_pending or not is_inside_tree() or not is_visible_in_tree(): return
	_layout_pending = true
	_settle_layout.call_deferred()


func _settle_layout() -> void:
	# Hidden containers do not sort their children. Their wrapping labels can
	# therefore report one-character widths and enormous minimum heights. Never
	# adopt that hidden measurement; show/resize queues a fresh visible layout.
	await get_tree().process_frame
	if not is_inside_tree(): return
	await get_tree().process_frame
	if not is_inside_tree(): return
	if not is_visible_in_tree():
		_layout_pending = false
		return
	# Hosts may use centre/right anchors. Keep the resulting panel within the
	# actual viewport after its labels settle, including subsequent resizes.
	var bounds := get_viewport_rect().grow(-16)
	var desired := _panel_size.min(bounds.size)
	size = desired.max(get_combined_minimum_size())
	global_position = Vector2(clampf(global_position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x-size.x)),
		clampf(global_position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y-size.y)))
	_layout_pending = false
