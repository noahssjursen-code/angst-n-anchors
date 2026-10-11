class_name PassengerTerminalPanel
extends Control

signal close_requested
var agent: PassengerAgentNpc
var _heading: Label
var _status: Label
var _manifest: Label
var _routes: VBoxContainer
var _buttons: Dictionary = {}
var _feedback: Label
var _timer := 0.0
var _route_key := ""
var _requests: Dictionary = {}
var _had_manifest := false
var _card: PanelContainer
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _closing := false

static func current(tree: SceneTree) -> PassengerTerminalPanel:
	return tree.get_first_node_in_group("passenger_terminal_panel") as PassengerTerminalPanel

static func open(npc: PassengerAgentNpc) -> void:
	var previous := current(npc.get_tree())
	if previous != null: previous.close()
	var layer := CanvasLayer.new()
	layer.layer = 25
	# Lifetime follows the streamed terminal; no retained references to an old port.
	npc.add_child(layer)
	var panel := PassengerTerminalPanel.new()
	panel.agent = npc
	layer.add_child(panel)
	panel.close_requested.connect(panel.close)

func close() -> void:
	if _closing: return
	_closing = true
	remove_from_group("passenger_terminal_panel")
	Input.mouse_mode = _previous_mouse_mode
	get_parent().queue_free()

func _exit_tree() -> void:
	if not _closing: Input.mouse_mode = _previous_mouse_mode

func _input(event: InputEvent) -> void:
	if _closing: return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_map") or event.is_action_pressed("open_journal") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()

func _ready() -> void:
	add_to_group("passenger_terminal_panel")
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = HudStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	_card = card
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.anchor_left = .52
	card.anchor_right = .97
	card.anchor_top = .12
	card.anchor_bottom = .9
	card.add_theme_stylebox_override("panel", HudStyle.make_title_panel_style())
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_heading = _label("Passenger terminal", 28)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_heading)
	top.add_child(_button("Close · Esc", func(): close_requested.emit()))
	column.add_child(HSeparator.new())
	_status = _label("", 20)
	column.add_child(_status)
	_manifest = _label("", 23)
	column.add_child(_manifest)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_routes = VBoxContainer.new()
	_routes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_routes)
	for action: String in ["arrive", "boarding_access", "cancel"]:
		var titles := {"arrive": "Land passengers", "boarding_access": "Open boarding access", "cancel": "Cancel sailing and return passengers"}
		var button := _button(titles[action], func(): _send(action))
		button.name = action
		column.add_child(button)
		_buttons[action] = button
	_feedback = _label("", 18)
	column.add_child(_feedback)
	_refresh()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0:
		_timer = .3
		_refresh()

func _refresh() -> void:
	if not is_instance_valid(agent): close_requested.emit(); return
	var state := LocalPlayerView.passenger_terminal_snapshot(agent)
	_heading.text = str(state.port) + " · Passengers"
	_status.text = str(state.status)
	var item: Dictionary = state.manifest
	if item.is_empty() and _had_manifest: _requests.clear()
	_had_manifest = not item.is_empty()
	_card.anchor_bottom = .63 if _had_manifest else .9
	_manifest.text = ""
	if not item.is_empty():
		_manifest.text = "To %s\n%d / %d aboard · %d landed\nFare on completion: %s" % [state.destination,
			item.onboard, item.total, item.landed, PlayerData.format_money(int(item.total) * int(item.fare_marks))]
	_buttons.arrive.visible = bool(state.can_arrive)
	_buttons.boarding_access.visible = bool(state.can_board)
	_buttons.cancel.visible = bool(state.can_cancel)
	var key := JSON.stringify(state.offers)
	if _route_key == key: return
	_route_key = key
	for child in _routes.get_children():
		_routes.remove_child(child)
		child.queue_free()
	for offer: Dictionary in state.offers:
		_routes.add_child(_label(str(offer.name), 24))
		_routes.add_child(_label("%d passengers · %.1f km direct\n%s on completion" % [offer.count,
			float(offer.distance_m) / 1000.0, PlayerData.format_money(int(offer.count) * int(offer.fare))], 19))
		var button := _button("Book sailing", func(): _send("book", str(offer.id)))
		button.set_meta("route_id", offer.id)
		_routes.add_child(button)
		_routes.add_child(HSeparator.new())

func _send(action: String, id: String = "") -> void:
	if not is_instance_valid(agent): return
	if action == "book" and not _requests.has(id): _requests[id] = PlayerData.new_uuid()
	var result := agent.request(action, id, str(_requests.get(id, "")))
	_feedback.text = str(result.get("message", "")) if not result.get("ok", false) else "Request accepted. You can close this panel while passengers transfer."
	_refresh()

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(label, size)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(callback)
	return button
