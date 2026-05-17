@tool
class_name HarbourMasterNpc
extends NpcInteractable

## Harbour master NPC. Handles berth booking and harbour dues enquiries.

const PEAKED_CAP_PATH := "res://resources/data/meshes/characters/hat_peaked_cap.json"

@export var port_id: String = ""

var _panel:  Panel
var _body:   VBoxContainer

enum _Screen { MAIN, REQUEST_BERTH, PAY_DUES, VESSEL_INFO }
var _screen: _Screen = _Screen.MAIN


func _ready() -> void:
	clothing_color = Color(0.15, 0.22, 0.45)
	trousers_color = Color(0.12, 0.16, 0.32)
	prompt_text    = "Press E — Harbour Master"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")
	else:
		call_deferred("_add_hat")


func _add_hat() -> void:
	add_overlay("hat", PEAKED_CAP_PATH)


# ── NpcInteractable hooks ──────────────────────────────────────────────────────

func _on_interact() -> void:
	_show_main()
	_panel.visible = true
	open_ui()


func _on_ui_cancel() -> void:
	if _screen == _Screen.MAIN:
		_panel.visible = false
		close_ui()
	else:
		_show_main()


# ── Screens ───────────────────────────────────────────────────────────────────

func _close() -> void:
	_panel.visible = false
	close_ui()


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

	var berths     := dock.get_berths()
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
	if dock.reserve_berth(index, "Captain"):
		dock.spawn_player_ship(index)
		var plot := get_parent() as PortPlot
		if plot != null:
			plot.respawn_staged_cargo()
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
	_add_quote("No outstanding dues on record, Captain.")
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
	_body.add_child(lbl)
	_body.add_child(HSeparator.new())


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
	_body.add_child(HSeparator.new())
	_add_option("← Back", _show_main)


# ── Dock lookup ───────────────────────────────────────────────────────────────

func _get_dock() -> PortDock:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PortDock") as PortDock


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_overlay("hat", PEAKED_CAP_PATH)

	var layer      := CanvasLayer.new()
	layer.name     = "HarbourMasterLayer"
	add_child(layer)

	_panel               = Panel.new()
	_panel.name          = "HarbourMasterPanel"
	_panel.visible       = false
	_panel.theme         = HudStyle.make_theme()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -300.0
	_panel.offset_right  =  300.0
	_panel.offset_top    = -220.0
	_panel.offset_bottom =  220.0
	layer.add_child(_panel)

	var title                  := Label.new()
	title.text                 = "HARBOUR MASTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 10.0
	title.offset_bottom = 40.0
	_panel.add_child(title)

	var scroll           := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 48.0
	scroll.offset_bottom = -8.0
	_panel.add_child(scroll)

	_body                       = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
