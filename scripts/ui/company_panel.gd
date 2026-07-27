class_name CompanyPanel
extends Control

signal close_requested()

var _title: Label
var _subtitle: Label
var _overview: VBoxContainer
var _vessels: VBoxContainer
var _inventory: VBoxContainer
var _ledger: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = BrandTheme.shared()
	_build()
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null and view.has_signal("company_changed"):
		view.company_changed.connect(func(_summary: Dictionary) -> void: refresh())
	visibility_changed.connect(func() -> void:
		if visible:
			refresh()
	)


func refresh() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	var summary: Dictionary = view.get_company_summary() if view != null and view.has_method("get_company_summary") else {}
	_title.text = str(summary.get("name", "UNREGISTERED COMPANY")).to_upper()
	_subtitle.text = "%s  ·  HOME %s" % [
		BrandFormat.money_text(int(summary.get("balance_marks", 0))),
		str(summary.get("home_port_id", "—")).to_upper(),
	]
	_clear(_overview)
	_clear(_vessels)
	_clear(_inventory)
	_clear(_ledger)
	_build_overview(summary)
	_build_vessels(summary.get("vessels", []) as Array)
	_build_inventory(summary)
	_build_ledger(summary.get("recent_transactions", []) as Array)


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = BrandTokens.alpha(BrandTokens.SCRIM, 0.92)
	add_child(shade)
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 52)
	outer.add_theme_constant_override("margin_right", 52)
	outer.add_theme_constant_override("margin_top", 38)
	outer.add_theme_constant_override("margin_bottom", 38)
	add_child(outer)
	var panel := BrandPanel.new(BrandPanel.Variant.RULED)
	outer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var heading := HBoxContainer.new()
	root.add_child(heading)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(names)
	_title = Label.new()
	BrandTheme.apply_display_font(_title, BrandTokens.DISPLAY_M, BrandTokens.INK)
	names.add_child(_title)
	_subtitle = Label.new()
	BrandTheme.apply_body_font(_subtitle, BrandTokens.LABEL_MONO, BrandTokens.BRASS_DEEP, true)
	names.add_child(_subtitle)
	var close := BrandButton.new("CLOSE · ESC", BrandButton.Variant.QUIET)
	close.pressed.connect(func() -> void: close_requested.emit())
	heading.add_child(close)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	_overview = _tab_column(tabs, "Overview")
	_vessels = _tab_column(tabs, "Vessels")
	_inventory = _tab_column(tabs, "Inventory")
	_ledger = _tab_column(tabs, "Ledger")


func _tab_column(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	return column


func _build_overview(summary: Dictionary) -> void:
	_section(_overview, "COMPANY STATUS")
	_row(_overview, "Available funds", BrandFormat.money_text(int(summary.get("balance_marks", 0))))
	_row(_overview, "Owned vessels", str((summary.get("vessels", []) as Array).size()))
	_row(_overview, "Stored lots", str((summary.get("inventory_lots", []) as Array).size()))
	var leases := summary.get("warehouse_leases", []) as Array
	_row(_overview, "Active leases", str(leases.size()))
	_section(_overview, "OPERATING PRINCIPLE")
	_note(_overview, "Your company is the authoritative owner of money, vessels and stored goods. Nearby objects and menus are views of this record.")
	if not leases.is_empty() and typeof(leases[0]) == TYPE_DICTIONARY:
		var lease := leases[0] as Dictionary
		_section(_overview, "HOME-PORT STORAGE")
		_row(_overview, "Port", str(lease.get("port_id", "—")).to_upper())
		_row(_overview, "Capacity", "%d units" % int(lease.get("capacity_units", 0)))
		_row(_overview, "Used", "%d units" % int(lease.get("used_units", 0)))
		_row(_overview, "Rent", "%s / day" % BrandFormat.money_text(int(lease.get("rent_marks_per_day", 0))))


func _build_vessels(summary: Array) -> void:
	_section(_vessels, "OWNED FLEET")
	if summary.is_empty():
		_note(_vessels, "No vessels registered.")
		return
	for raw in summary:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var vessel := raw as Dictionary
		_row(_vessels, VesselSpawn.vessel_name_of(vessel), "%s  ·  %s" % [
			str(vessel.get("registration_id", "unregistered")).replace("_", " ").to_upper(),
			str(vessel.get("hull_id", "unknown")),
		])


func _build_inventory(summary: Dictionary) -> void:
	_section(_inventory, "COMPANY-OWNED GOODS")
	var lots := summary.get("inventory_lots", []) as Array
	if lots.is_empty():
		_note(_inventory, "Your leased warehouse is empty. Future market purchases and landed catch will appear here as owned inventory lots.")
		return
	for raw in lots:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var lot := raw as Dictionary
		_row(_inventory, str(lot.get("commodity_id", "unknown")).replace("_", " ").to_upper(), "%s %s  ·  %s" % [
			str(lot.get("quantity", 0)), str(lot.get("unit", "units")), str(lot.get("location_id", "—")),
		])


func _build_ledger(entries: Array) -> void:
	_section(_ledger, "RECENT TRANSACTIONS")
	if entries.is_empty():
		_note(_ledger, "No transactions recorded.")
		return
	var reversed := entries.duplicate(true)
	reversed.reverse()
	for raw in reversed:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry := raw as Dictionary
		var amount := int(entry.get("amount_marks", 0))
		_row(_ledger, str(entry.get("description", "Transaction")), "%s%s" % [
			"+" if amount > 0 else "", BrandFormat.money_text(amount),
		])


func _section(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_constant_override("outline_size", 1)
	BrandTheme.apply_body_font(label, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED, true)
	parent.add_child(label)


func _row(parent: VBoxContainer, key: String, value: String) -> void:
	parent.add_child(BrandComponents.key_value_row(key, value, BrandTokens.INK))


func _note(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(label, BrandTokens.BODY, BrandTokens.INK_BODY)
	parent.add_child(label)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()
