class_name HarbourMasterNpc
extends StaticBody3D

## Harbour master NPC. Handles berth booking and harbour dues enquiries.
## Dialogue is menu-driven. VHF radio will call the same API remotely once built.

const LAYER_WORLD    := 1
const NPC_COLOR      := Color(0.15, 0.22, 0.45)   # dark navy uniform
const HAT_COLOR      := Color(0.78, 0.62, 0.14)   # gold-band peaked cap

@export var port_id:       String = ""
@export var interact_range: float = 4.0

var _open:   bool  = false
var _panel:  Panel
var _body:   VBoxContainer   # swapped out per screen
var _prompt: Label

enum _Screen { MAIN, REQUEST_BERTH, PAY_DUES, VESSEL_INFO }
var _screen: _Screen = _Screen.MAIN


func _ready() -> void:
	_build_body()
	if not Engine.is_editor_hint():
		_build_ui()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _prompt != null:
		_prompt.visible = _player_in_range() and not _open


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("ui_cancel") and _open:
		if _screen == _Screen.MAIN:
			_close()
		else:
			_show_main()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and _player_in_range() and not _open:
		_open_panel()
		get_viewport().set_input_as_handled()


# ── Screens ───────────────────────────────────────────────────────────────────

func _open_panel() -> void:
	_show_main()
	_panel.visible   = true
	_open            = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	_panel.visible   = false
	_open            = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_main() -> void:
	_screen = _Screen.MAIN
	_clear_body()
	_add_quote("Good day, Captain. What can I do for you?")
	_add_option("I would like to request a berth.",  _show_request_berth)
	_add_option("I am here to pay my harbour dues.", _show_pay_dues)
	_add_option("What vessels can dock here?",        _show_vessel_info)
	_add_option("Nothing, thank you.",                _close)


func _show_request_berth() -> void:
	_screen = _Screen.REQUEST_BERTH
	_clear_body()

	var dock := _get_dock()
	if dock == null:
		_add_quote("I'm afraid the dock is not operational at the moment.")
		_add_back_button()
		return

	var berths := dock.get_berths()
	var free_count := 0
	for b in berths:
		if int((b as Dictionary)["status"]) == PortDock.BerthStatus.FREE:
			free_count += 1

	if free_count == 0:
		_add_quote("I'm sorry, Captain — we have no berths free at present.")
		_add_back_button()
		return

	_add_quote("We have %d berth%s available. Which would you like?" % [
		free_count, "s" if free_count != 1 else ""
	])

	for i in range(berths.size()):
		var b      := berths[i] as Dictionary
		var status := int(b["status"])
		if status == PortDock.BerthStatus.FREE:
			var idx := i
			_add_option("Berth #%d — assign me here." % (i + 1),
				func() -> void: _on_berth_selected(idx))
		else:
			var by  : String = str(b["reserved_by"])
			var lbl : String = "Berth #%d — %s" % [
				i + 1,
				("reserved by %s" % by) if status == PortDock.BerthStatus.RESERVED else "occupied",
			]
			_add_disabled_option(lbl)

	_add_back_button()


func _on_berth_selected(index: int) -> void:
	var dock := _get_dock()
	if dock == null:
		return
	var gs          := get_node_or_null("/root/GameState")
	var player_name : String = "Captain"
	if gs != null:
		player_name = str(gs.get("player").get("display_name") if gs.get("player") != null else "Captain")

	if dock.reserve_berth(index, player_name):
		_clear_body()
		_add_quote("Berth #%d is yours, Captain. Mind the tides." % (index + 1))
		_add_option("Thank you.", _close)
	else:
		_clear_body()
		_add_quote("I'm sorry — that berth was just taken.")
		_add_back_button()


func _show_pay_dues() -> void:
	_screen = _Screen.PAY_DUES
	_clear_body()
	_add_quote("No outstanding dues on record, Captain.")   # stub — billing system TBD
	_add_back_button()


func _show_vessel_info() -> void:
	_screen = _Screen.VESSEL_INFO
	_clear_body()
	var dock := _get_dock()
	if dock == null:
		_add_quote("Dock information unavailable.")
		_add_back_button()
		return
	var class_name_str : String = ShipClass.display_name(dock.max_ship_class)
	var max_len        : float  = ShipClass.max_length(dock.max_ship_class)
	var slots          : int    = dock.berth_count()
	_add_quote(
		"This port accepts vessels up to %s class (max %.0f m).\n%d berth%s available." % [
			class_name_str, max_len, slots, "s" if slots != 1 else ""
		]
	)
	_add_back_button()


# ── UI helpers ────────────────────────────────────────────────────────────────

func _clear_body() -> void:
	for child in _body.get_children():
		child.queue_free()


func _add_quote(text: String) -> void:
	var lbl                    := Label.new()
	lbl.text                   = text
	lbl.autowrap_mode          = TextServer.AUTOWRAP_WORD
	lbl.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	var sep                    := HSeparator.new()
	_body.add_child(lbl)
	_body.add_child(sep)


func _add_option(text: String, callback: Callable) -> void:
	var btn                   := Button.new()
	btn.text                  = text
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_body.add_child(btn)


func _add_disabled_option(text: String) -> void:
	var btn                   := Button.new()
	btn.text                  = text
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled              = true
	_body.add_child(btn)


func _add_back_button() -> void:
	var sep := HSeparator.new()
	_body.add_child(sep)
	_add_option("← Back", _show_main)


# ── Proximity ─────────────────────────────────────────────────────────────────

func _player_in_range() -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= interact_range:
			return true
	return false


# ── Dock lookup ───────────────────────────────────────────────────────────────

func _get_dock() -> PortDock:
	var parent := get_parent()
	if parent == null:
		return null
	var dock := parent.get_node_or_null("PortDock") as PortDock
	return dock


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_body() -> void:
	collision_layer = LAYER_WORLD
	collision_mask  = 0

	var shape      := BoxShape3D.new()
	shape.size     = Vector3(0.7, 1.8, 0.7)
	var col        := CollisionShape3D.new()
	col.name       = "Body"
	col.shape      = shape
	col.position   = Vector3.UP * 0.9
	add_child(col)

	var body       := MeshBuilder.box(shape.size, NPC_COLOR, 0.6, 0.0)
	body.name      = "NpcVisual"
	body.position  = Vector3.UP * 0.9
	add_child(body)

	# Peaked cap — wider brim than the other NPCs to mark authority
	var hat        := MeshBuilder.box(Vector3(0.82, 0.10, 0.82), HAT_COLOR, 0.5, 0.0)
	hat.name       = "NpcHat"
	hat.position   = Vector3.UP * 1.87
	add_child(hat)


func _build_ui() -> void:
	var layer      := CanvasLayer.new()
	layer.name     = "HarbourMasterLayer"
	add_child(layer)

	_panel               = Panel.new()
	_panel.name          = "HarbourMasterPanel"
	_panel.visible       = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -300.0
	_panel.offset_right  =  300.0
	_panel.offset_top    = -220.0
	_panel.offset_bottom =  220.0
	layer.add_child(_panel)

	var title                  := Label.new()
	title.text                 = "Harbour Master"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 10.0
	title.offset_bottom = 40.0
	_panel.add_child(title)

	var scroll              := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 48.0
	scroll.offset_bottom = -8.0
	_panel.add_child(scroll)

	_body                       = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	# Prompt
	var prompt_layer      := CanvasLayer.new()
	prompt_layer.name     = "HarbourMasterPromptLayer"
	add_child(prompt_layer)

	_prompt                      = Label.new()
	_prompt.text                 = "Press E — Harbour Master"
	_prompt.visible              = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left   = -220.0
	_prompt.offset_right  =  220.0
	_prompt.offset_top    = -148.0
	_prompt.offset_bottom = -108.0
	prompt_layer.add_child(_prompt)
