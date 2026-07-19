class_name CompanyPanel
extends Control

## Per-client company readout. All reads pass through LocalPlayerView; command
## buttons call the company authority, which can later be replaced by RPCs.

signal close_requested

@export var preview_mode := false

const TAB_NAMES := ["OVERVIEW", "OPERATIONS", "FLEET", "CREW", "FINANCE"]

var _tabs: TabContainer
var _name_gate: Control
var _name_edit: LineEdit
var _name_error: Label
var _company_title: Label
var _status: Label
var _snapshot: Dictionary = {}
var _margin: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = HudStyle.make_theme()
	_build()
	if not get_viewport().size_changed.is_connected(_sync_viewport_layout):
		get_viewport().size_changed.connect(_sync_viewport_layout)
	_sync_viewport_layout()
	if not preview_mode:
		call_deferred("_connect_player_view")


func requires_name() -> bool:
	return str(_snapshot.get("name", "")).is_empty()


func focus_name_entry() -> void:
	if _name_edit != null:
		_name_edit.grab_focus()


func refresh() -> void:
	if preview_mode:
		return
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null:
		_rebuild(view.get_company_snapshot())


func set_preview_snapshot(snapshot: Dictionary) -> void:
	preview_mode = true
	_rebuild(snapshot)


func _connect_player_view() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	if view == null:
		call_deferred("_connect_player_view")
		return
	if not view.company_changed.is_connected(_on_company_changed):
		view.company_changed.connect(_on_company_changed)
	if view.has_signal("company_traffic_changed") \
			and not view.company_traffic_changed.is_connected(_on_company_traffic_changed):
		view.company_traffic_changed.connect(_on_company_traffic_changed)
	refresh()


func _on_company_changed(snapshot: Dictionary) -> void:
	# GameMenu refreshes on open. Reconstructing every tab while this full-screen
	# panel is hidden was pure main-thread work during ordinary sailing.
	if not is_visible_in_tree():
		return
	_rebuild(snapshot)


func _on_company_traffic_changed() -> void:
	if is_visible_in_tree():
		refresh()


func _build() -> void:
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := UiBuilder.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_company_title = UiBuilder.title_label("COMPANY", 25)
	_company_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_company_title)
	var close := UiBuilder.compact_button("CLOSE  [ B ]", 125)
	close.pressed.connect(func() -> void:
		if not requires_name():
			close_requested.emit()
	)
	header.add_child(close)
	_status = UiBuilder.subtitle_label("", 12)
	root.add_child(_status)
	root.add_child(UiBuilder.separator())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_name_gate = ColorRect.new()
	_name_gate.color = Color(0.01, 0.025, 0.045, 0.97)
	_name_gate.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_name_gate)
	_name_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_name_gate.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var name_panel := UiBuilder.panel(Vector2(520, 260))
	center.add_child(name_panel)
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 15)
	name_panel.add_child(name_box)
	name_box.add_child(UiBuilder.title_label("NAME YOUR COMPANY", 24))
	name_box.add_child(UiBuilder.body_label(
		"This name appears on your fleet ledger, contracts, and future multiplayer records.", 13))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. North Sea Coastal"
	_name_edit.max_length = 40
	_name_edit.text_submitted.connect(func(_text: String) -> void: _submit_name())
	name_box.add_child(_name_edit)
	_name_error = UiBuilder.body_label("", 12)
	_name_error.add_theme_color_override("font_color", HudStyle.C_RED)
	name_box.add_child(_name_error)
	var establish := UiBuilder.button("ESTABLISH COMPANY")
	establish.pressed.connect(_submit_name)
	name_box.add_child(establish)


func _sync_viewport_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if _margin == null:
		return
	var edge := 14 if viewport_size.x < 1100.0 or viewport_size.y < 700.0 else 24
	_margin.add_theme_constant_override("margin_left", edge)
	_margin.add_theme_constant_override("margin_right", edge)
	_margin.add_theme_constant_override("margin_top", edge)
	_margin.add_theme_constant_override("margin_bottom", edge)


func _rebuild(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	if _tabs == null:
		return
	_company_title.text = str(snapshot.get("name", "COMPANY"))
	_status.text = "%s  ·  %d vessels  ·  %d employees" % [
		PlayerSession.format_money(int(snapshot.get("marks", 0))),
		(snapshot.get("owned_vessels", []) as Array).size(),
		(snapshot.get("employees", []) as Array).size(),
	]
	var selected := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tabs.add_child(_overview_tab(snapshot))
	_tabs.add_child(_operations_tab(snapshot))
	_tabs.add_child(_fleet_tab(snapshot))
	_tabs.add_child(_crew_tab(snapshot))
	_tabs.add_child(_finance_tab(snapshot))
	_tabs.current_tab = clampi(selected, 0, _tabs.get_tab_count() - 1)
	_name_gate.visible = str(snapshot.get("name", "")).is_empty()
	if _name_gate.visible:
		call_deferred("focus_name_entry")


func _overview_tab(snapshot: Dictionary) -> Control:
	var box := _tab_box(TAB_NAMES[0])
	var active := 0
	var held := 0
	var loading := 0
	for raw in (snapshot.get("fleet", {}) as Dictionary).values():
		var status := str((raw as Dictionary).get("status", ""))
		active += 1 if status == "underway" else 0
		held += 1 if status == "unpaid" else 0
		loading += 1 if status in ["preparing", "turnaround"] else 0
	var hourly_payroll := 0
	for raw in snapshot.get("employees", []) as Array:
		hourly_payroll += int((raw as Dictionary).get("wage_per_hour", 0))
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	metrics.add_child(_metric_card("AVAILABLE FUNDS", PlayerSession.format_money(int(snapshot.get("marks", 0))), HudStyle.C_GREEN))
	metrics.add_child(_metric_card("UNDERWAY", str(active), HudStyle.C_TEXT))
	metrics.add_child(_metric_card("IN PORT", str(loading), HudStyle.C_TEXT))
	metrics.add_child(_metric_card("PAYROLL / HR", PlayerSession.format_money(hourly_payroll), HudStyle.C_AMBER))
	box.add_child(metrics)
	if held > 0:
		box.add_child(_alert_card("PAYROLL HOLD", "%d vessel(s) are held safely at berth until wages can be covered." % held, true))
	elif (snapshot.get("fleet", {}) as Dictionary).is_empty():
		box.add_child(_alert_card("FLEET READY", "Assign a route and crew to an owned vessel to begin company operations.", false))
	else:
		box.add_child(_alert_card("OPERATIONS NORMAL", "Crews are paid and no vessel requires immediate attention.", false))
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("HOW YOUR FLEET WORKS"))
	box.add_child(UiBuilder.body_label(
		"Paid crews continue their assigned service while you are away. Every voyage uses the same berth-to-berth route and boat controls as a player vessel. Traffic agreements and harbour queues are shared authority decisions.", 14))
	(box.get_child(box.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("COMPANY IDENTITY"))
	var rename_row := HBoxContainer.new()
	var rename_edit := LineEdit.new()
	rename_edit.text = str(snapshot.get("name", ""))
	rename_edit.max_length = 40
	rename_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_edit.text_submitted.connect(func(_value: String) -> void: _rename_company(rename_edit))
	rename_row.add_child(rename_edit)
	var rename := UiBuilder.compact_button("UPDATE NAME", 130)
	rename.pressed.connect(_rename_company.bind(rename_edit))
	rename_row.add_child(rename)
	box.add_child(rename_row)
	return _scroll(box)


func _operations_tab(snapshot: Dictionary) -> Control:
	var box := _tab_box(TAB_NAMES[1])
	box.add_child(UiBuilder.section_header("LIVE FLEET OPERATIONS"))
	var traffic := snapshot.get("traffic", {}) as Dictionary
	var intent_by_vessel: Dictionary = {}
	for raw in traffic.get("intents", []) as Array:
		var intent := raw as Dictionary
		intent_by_vessel[str(intent.get("vessel_id", ""))] = intent
	var queue_by_vessel: Dictionary = {}
	for raw in traffic.get("port_queues", []) as Array:
		var ticket := raw as Dictionary
		queue_by_vessel[str(ticket.get("vessel_id", ""))] = ticket
	var agreement_by_vessel: Dictionary = {}
	for raw in traffic.get("agreements", []) as Array:
		var agreement := raw as Dictionary
		for vessel_id in agreement.get("vessel_ids", []) as Array:
			agreement_by_vessel[str(vessel_id)] = agreement
	var shown := 0
	for vessel_uid in (snapshot.get("fleet", {}) as Dictionary).keys():
		var vessel := _owned_vessel_row(snapshot, str(vessel_uid))
		var assignment := vessel.get("company_assignment", {}) as Dictionary
		if assignment.is_empty():
			assignment = snapshot["fleet"][vessel_uid] as Dictionary
		var card := UiBuilder.inner_panel()
		box.add_child(card)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 7)
		card.add_child(rows)
		var route := assignment.get("route", {}) as Dictionary
		rows.add_child(UiBuilder.section_header(str(vessel.get("display", vessel.get("name", vessel_uid)))))
		rows.add_child(UiBuilder.key_value_row("Service", "%s to %s" % [
			str(route.get("origin_name", "Origin")), str(route.get("destination_name", "Destination"))]))
		var intent := intent_by_vessel.get(str(vessel_uid), {}) as Dictionary
		var operation := str(intent.get("phase", "")).replace("_", " ").capitalize() \
			if not intent.is_empty() else _assignment_status_label(assignment)
		rows.add_child(UiBuilder.key_value_row("Operation", operation))
		var projection := assignment.get("projection", {}) as Dictionary
		if not projection.is_empty() and str(assignment.get("status", "")) == "underway":
			var progress := ProgressBar.new()
			progress.min_value = 0.0
			progress.max_value = 100.0
			progress.value = float(projection.get("progress", 0.0)) * 100.0
			progress.show_percentage = true
			rows.add_child(progress)
			rows.add_child(UiBuilder.key_value_row("Estimated arrival", _format_duration(int(projection.get("eta_seconds", 0)))))
		var ticket := queue_by_vessel.get(str(vessel_uid), {}) as Dictionary
		if not ticket.is_empty():
			rows.add_child(_alert_card("HARBOUR QUEUE", "Holding outside port - position %d" % int(ticket.get("queue_position", 1)), false))
		var agreement := agreement_by_vessel.get(str(vessel_uid), {}) as Dictionary
		if not agreement.is_empty():
			rows.add_child(_alert_card("VHF TRAFFIC AGREEMENT", "%s - closest approach %.0f m" % [
				str(agreement.get("situation", "traffic")).replace("_", " ").capitalize(),
				float(agreement.get("predicted_separation_m", 0.0))], false))
		shown += 1
	if shown == 0:
		box.add_child(UiBuilder.body_label("No active company services. Start one from the Fleet tab.", 14))
	return _scroll(box)


func _fleet_tab(snapshot: Dictionary) -> Control:
	var box := _tab_box(TAB_NAMES[2])
	box.add_child(UiBuilder.section_header("OWNED VESSELS"))
	var routes := snapshot.get("route_templates", []) as Array
	for raw in snapshot.get("owned_vessels", []) as Array:
		var vessel := raw as Dictionary
		var uid := str(vessel.get("uid", ""))
		var assignment := vessel.get("company_assignment", {}) as Dictionary
		var card := UiBuilder.inner_panel()
		box.add_child(card)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 7)
		card.add_child(rows)
		rows.add_child(UiBuilder.section_header(str(vessel.get("display", vessel.get("name", "Vessel")))))
		rows.add_child(UiBuilder.key_value_row("Minimum crew", str(int(vessel.get("required_crew", 0)))))
		if assignment.is_empty():
			var deployed_for_player := bool(vessel.get("deployed_for_player", false))
			var deployed_at_berth := bool(vessel.get("deployed_at_berth", false))
			rows.add_child(UiBuilder.body_label(
				"Deployed for your use" if deployed_for_player else "Unassigned", 12))
			if deployed_for_player:
				var recall := UiBuilder.compact_button("RECALL TO REGISTRY", 210)
				recall.disabled = not deployed_at_berth
				recall.tooltip_text = (
					"Immediately retrieve this moored vessel" if deployed_at_berth
					else "Return the vessel to a berth before recalling it")
				recall.pressed.connect(_recall_vessel.bind(uid))
				rows.add_child(recall)
			var route_pick := _route_picker(routes, vessel.get("supported_route_ids", PackedStringArray()) as PackedStringArray)
			rows.add_child(route_pick)
			var assign := UiBuilder.compact_button("CONFIRM ROUTE & START", 210)
			assign.disabled = deployed_for_player
			assign.pressed.connect(_assign_route.bind(uid, route_pick))
			rows.add_child(assign)
		else:
			var status := _assignment_status_label(assignment)
			rows.add_child(UiBuilder.key_value_row("Status", status,
				HudStyle.C_RED if str(assignment.get("status", "")) == "unpaid" else HudStyle.C_GREEN))
			var route := assignment.get("route", {}) as Dictionary
			rows.add_child(UiBuilder.key_value_row("Service", "%s ↔ %s" % [
				str(route.get("origin_name", "Port A")), str(route.get("destination_name", "Port B"))]))
			rows.add_child(UiBuilder.key_value_row("Crew aboard", str((assignment.get("crew_ids", PackedStringArray()) as PackedStringArray).size())))
			var shown_commodity := str(assignment.get("commodity_id", ""))
			if str(assignment.get("status", "")) == "turnaround" \
					and not str(assignment.get("arriving_commodity_id", "")).is_empty():
				shown_commodity = str(assignment.get("arriving_commodity_id", ""))
			rows.add_child(UiBuilder.key_value_row(
				"Current cargo", CommodityCatalog.commodity_display(shown_commodity)))
			rows.add_child(UiBuilder.key_value_row("Completed legs", str(int(assignment.get("completed_legs", 0)))))
			var projection := assignment.get("projection", {}) as Dictionary
			if str(assignment.get("status", "")) == "underway" and not projection.is_empty():
				rows.add_child(UiBuilder.key_value_row("Voyage progress", "%d%%  ·  ETA %s" % [
					roundi(float(projection.get("progress", 0.0)) * 100.0),
					_format_duration(int(projection.get("eta_seconds", 0)))]))
			if str(assignment.get("status", "")) == "underway":
				var stop := UiBuilder.compact_button("STOP AFTER CURRENT LEG", 220)
				stop.pressed.connect(_stop_vessel.bind(uid))
				rows.add_child(stop)
			elif str(assignment.get("status", "")) in ["preparing", "turnaround"]:
				var hold := UiBuilder.compact_button("HOLD AT BERTH", 180)
				hold.pressed.connect(_stop_vessel.bind(uid))
				rows.add_child(hold)
			elif str(assignment.get("status", "")) in ["unpaid", "inactive", "berthed"]:
				var resume := UiBuilder.compact_button("RESUME SERVICE", 180)
				resume.pressed.connect(_resume_vessel.bind(uid))
				rows.add_child(resume)
				var end := UiBuilder.compact_button("END ASSIGNMENT", 180)
				end.pressed.connect(_end_assignment.bind(uid))
				rows.add_child(end)
	if (snapshot.get("owned_vessels", []) as Array).is_empty():
		box.add_child(UiBuilder.body_label("No registered vessels. Visit a shipwright to purchase one.", 14))
	return _scroll(box)


func _crew_tab(snapshot: Dictionary) -> Control:
	var box := _tab_box(TAB_NAMES[3])
	var assigned_to: Dictionary = {}
	for vessel_uid in (snapshot.get("fleet", {}) as Dictionary).keys():
		var assignment := snapshot["fleet"][vessel_uid] as Dictionary
		var vessel := _owned_vessel_row(snapshot, str(vessel_uid))
		for crew_id in assignment.get("crew_ids", PackedStringArray()) as PackedStringArray:
			assigned_to[str(crew_id)] = str(vessel.get("display", vessel.get("name", vessel_uid)))
	var payroll := 0
	for raw in snapshot.get("employees", []) as Array:
		payroll += int((raw as Dictionary).get("wage_per_hour", 0))
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	metrics.add_child(_metric_card("EMPLOYED", str((snapshot.get("employees", []) as Array).size()), HudStyle.C_TEXT))
	metrics.add_child(_metric_card("ASSIGNED", str(assigned_to.size()), HudStyle.C_GREEN))
	metrics.add_child(_metric_card("PAYROLL / HR", PlayerSession.format_money(payroll), HudStyle.C_AMBER))
	box.add_child(metrics)
	box.add_child(UiBuilder.section_header("EMPLOYEES"))
	for raw in snapshot.get("employees", []) as Array:
		var crew := raw as Dictionary
		var line := HBoxContainer.new()
		var assignment_text := str(assigned_to.get(str(crew.get("id", "")), "Available"))
		line.add_child(_wide_label("%s  ·  %s  ·  %s/hr  ·  %s" % [
			str(crew.get("name", "Crew")), str(crew.get("role", "Deck crew")),
			PlayerSession.format_money(int(crew.get("wage_per_hour", 0))), assignment_text]))
		var release := UiBuilder.compact_button("RELEASE", 90)
		release.pressed.connect(_dismiss.bind(str(crew.get("id", ""))))
		line.add_child(release)
		box.add_child(line)
	box.add_child(UiBuilder.separator())
	box.add_child(UiBuilder.section_header("AVAILABLE SEAFARERS"))
	for raw in snapshot.get("crew_candidates", []) as Array:
		var candidate := raw as Dictionary
		var line := HBoxContainer.new()
		line.add_child(_wide_label("%s  ·  %s  ·  %s/hr" % [
			str(candidate.get("name", "Crew")), str(candidate.get("role", "Deck crew")),
			PlayerSession.format_money(int(candidate.get("wage_per_hour", 0)))]))
		var hire := UiBuilder.compact_button("HIRE", 90)
		hire.pressed.connect(_hire.bind(str(candidate.get("id", ""))))
		line.add_child(hire)
		box.add_child(line)
	return _scroll(box)


func _finance_tab(snapshot: Dictionary) -> Control:
	var box := _tab_box(TAB_NAMES[4])
	var income := 0
	var costs := 0
	for raw in snapshot.get("ledger", []) as Array:
		var amount := int((raw as Dictionary).get("amount", 0))
		if amount >= 0:
			income += amount
		else:
			costs += -amount
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	metrics.add_child(_metric_card("REVENUE", PlayerSession.format_money(income), HudStyle.C_GREEN))
	metrics.add_child(_metric_card("COSTS", PlayerSession.format_money(costs), HudStyle.C_RED))
	metrics.add_child(_metric_card("NET RESULT", PlayerSession.format_money(income - costs),
		HudStyle.C_GREEN if income >= costs else HudStyle.C_RED))
	metrics.add_child(_metric_card("CASH", PlayerSession.format_money(int(snapshot.get("marks", 0))), HudStyle.C_TEXT))
	box.add_child(metrics)
	box.add_child(UiBuilder.section_header("COMPANY LEDGER"))
	for raw in snapshot.get("ledger", []) as Array:
		var row := raw as Dictionary
		var amount := int(row.get("amount", 0))
		box.add_child(UiBuilder.key_value_row(str(row.get("memo", "Entry")),
			("+" if amount > 0 else "") + PlayerSession.format_money(amount),
			HudStyle.C_GREEN if amount >= 0 else HudStyle.C_RED))
	if (snapshot.get("ledger", []) as Array).is_empty():
		box.add_child(UiBuilder.body_label("No company transactions yet.", 14))
	return _scroll(box)


func _tab_box(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	box.add_theme_constant_override("separation", 9)
	return box


func _scroll(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = content.name
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _wide_label(text: String) -> Label:
	var label := UiBuilder.body_label(text, 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _metric_card(label_text: String, value_text: String, color: Color) -> Control:
	var panel := UiBuilder.inner_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := UiBuilder.subtitle_label(label_text, 11)
	box.add_child(label)
	var value := UiBuilder.title_label(value_text, 19)
	value.add_theme_color_override("font_color", color)
	box.add_child(value)
	return panel


func _alert_card(title_text: String, body_text: String, danger: bool) -> Control:
	var panel := UiBuilder.inner_panel()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := UiBuilder.section_header(title_text)
	title.add_theme_color_override("font_color", HudStyle.C_RED if danger else HudStyle.C_GREEN)
	box.add_child(title)
	var body := UiBuilder.body_label(body_text, 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	return panel


func _owned_vessel_row(snapshot: Dictionary, vessel_uid: String) -> Dictionary:
	for raw in snapshot.get("owned_vessels", []) as Array:
		var vessel := raw as Dictionary
		if str(vessel.get("uid", "")) == vessel_uid:
			return vessel
	return {}


func _route_picker(routes: Array, supported_ids: PackedStringArray) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("CHOOSE A SERVICE ROUTE...")
	picker.set_item_metadata(0, "")
	picker.set_item_disabled(0, true)
	for raw in routes:
		var route := raw as Dictionary
		if str(route.get("id", "")) not in supported_ids:
			continue
		picker.add_item("%s → %s  ·  %.1f km  ·  %s out / %s back  ·  %s/leg" % [
			str(route.get("origin_name", "Origin")), str(route.get("destination_name", "Destination")),
			float(route.get("distance_m", 0.0)) / 1000.0,
			CommodityCatalog.commodity_display(str(route.get("outbound_commodity_id", ""))),
			CommodityCatalog.commodity_display(str(route.get("return_commodity_id", ""))),
			PlayerSession.format_money(int(route.get("pay_marks", 0)))])
		picker.set_item_metadata(picker.item_count - 1, str(route.get("id", "")))
	picker.select(0)
	return picker


func _submit_name() -> void:
	if preview_mode:
		return
	var service := get_node_or_null("/root/CompanyService")
	if service == null or not service.set_company_name(_name_edit.text):
		_name_error.text = "Enter at least two characters."
		return
	_name_error.text = ""


func _rename_company(edit: LineEdit) -> void:
	if preview_mode:
		return
	var service := get_node_or_null("/root/CompanyService")
	if service == null or not service.set_company_name(edit.text):
		_status.text = "Company name must contain at least two characters."
		return
	_status.text = "Company name updated."


func _hire(candidate_id: String) -> void:
	if preview_mode:
		return
	get_node("/root/CompanyService").hire_employee(candidate_id)


func _dismiss(employee_id: String) -> void:
	if preview_mode:
		return
	if not get_node("/root/CompanyService").dismiss_employee(employee_id):
		_status.text = "Crew assigned to a vessel cannot be released."


func _assign_route(vessel_uid: String, picker: OptionButton) -> void:
	if preview_mode:
		return
	if picker.item_count <= 1:
		_status.text = "No company routes are available in this world."
		return
	if picker.selected <= 0:
		_status.text = "Choose the vessel's service route before starting it."
		return
	var route_id := str(picker.get_item_metadata(picker.selected))
	if route_id.is_empty():
		_status.text = "Choose the vessel's service route before starting it."
		return
	var result: Dictionary = get_node("/root/CompanyService").assign_and_start(
		vessel_uid, route_id)
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("reason", "Could not start service"))


func _stop_vessel(vessel_uid: String) -> void:
	if preview_mode:
		return
	get_node("/root/CompanyService").stop_after_current_leg(vessel_uid)


func _recall_vessel(vessel_uid: String) -> void:
	if preview_mode:
		return
	if not get_node("/root/CompanyService").recall_deployed_vessel(vessel_uid):
		_status.text = "This vessel must be safely moored before it can be recalled."


func _resume_vessel(vessel_uid: String) -> void:
	if preview_mode:
		return
	var result: Dictionary = get_node("/root/CompanyService").resume_vessel(vessel_uid)
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("reason", "Could not resume service"))


func _end_assignment(vessel_uid: String) -> void:
	if preview_mode:
		return
	get_node("/root/CompanyService").end_assignment(vessel_uid)


func _format_duration(seconds: int) -> String:
	var minutes: int = int(maxi(seconds, 0) / 60)
	return "%dh %02dm" % [int(minutes / 60), minutes % 60] if minutes >= 60 else "%dm" % minutes


func _assignment_status_label(assignment: Dictionary) -> String:
	match str(assignment.get("status", "")):
		"preparing":
			return "Loading cargo" if not str(assignment.get("physical_contract_id", "")).is_empty() \
				else "Awaiting cargo"
		"turnaround":
			if bool(assignment.get("stop_after_leg", false)):
				return "Unloading, then holding at berth"
			return "Unloading cargo" if not str(assignment.get("arriving_contract_id", "")).is_empty() \
				else "Preparing return leg"
		"unpaid":
			return "Payroll hold at berth"
		"inactive":
			return "Held at berth"
		"underway":
			return "Underway"
		var raw:
			return str(raw).capitalize()
