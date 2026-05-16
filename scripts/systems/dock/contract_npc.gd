@tool
class_name ContractNpc
extends NpcInteractable

## Contract board NPC. Opens a contract list when the player interacts.
## Blocks interaction if player is carrying cargo.

const FLAT_CAP_PATH := "res://resources/data/meshes/hat_flat_cap.json"

@export var port_id: String = ""

var _panel: Panel
var _list:  VBoxContainer


func _ready() -> void:
	clothing_color = Color(0.22, 0.38, 0.60)
	trousers_color = Color(0.16, 0.24, 0.42)
	prompt_text    = "Press E to view contracts"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")
	else:
		call_deferred("_add_hat")


func _add_hat() -> void:
	add_overlay("hat", FLAT_CAP_PATH)


# ── NpcInteractable hooks ──────────────────────────────────────────────────────

func _on_interact() -> void:
	var player := _nearest_player()
	if player == null:
		return
	var carry := player.get_node_or_null("PlayerCarryComponent") as PlayerCarryComponent
	if carry != null and carry.is_carrying():
		return
	_refresh_list()
	_panel.visible = true
	open_ui()


func _on_ui_cancel() -> void:
	_panel.visible = false
	close_ui()


# ── Panel ─────────────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var registry := _registry()
	if registry == null:
		_list.add_child(_plain_label("ContractRegistry autoload not found."))
		return

	var contracts: Array[Contract] = registry.get_contracts_from_port(port_id)
	if contracts.is_empty():
		_list.add_child(_plain_label("No contracts available."))
		return

	var has_active:   bool = registry.get_accepted_contracts().size() > 0
	var ship_berthed: bool = _ship_is_berthed()

	for contract in contracts:
		_list.add_child(_make_row(contract, registry, has_active, ship_berthed))


func _make_row(contract: Contract, registry: Node, has_active: bool, ship_berthed: bool) -> Control:
	var dest: String = registry.get_destination_name(contract)

	var info           := Label.new()
	info.text          = "%s  →  %s\n%d × %s   %d gold" % [
		registry.get_port_display_name(contract.origin_port_id),
		dest,
		contract.quantity,
		contract.display_name,
		contract.reward_gold,
	]
	info.autowrap_mode         = TextServer.AUTOWRAP_WORD
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var btn := Button.new()
	match contract.state:
		Contract.State.AVAILABLE:
			if has_active:
				btn.text     = "Busy"
				btn.disabled = true
			elif not ship_berthed:
				btn.text     = "Berth ship first"
				btn.disabled = true
			else:
				btn.text = "Accept"
				btn.pressed.connect(_on_accept.bind(contract.id))
		Contract.State.ACCEPTED:
			btn.text     = "Active"
			btn.disabled = true
		Contract.State.COMPLETED:
			btn.text     = "Done"
			btn.disabled = true

	var row                   := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(info)
	row.add_child(btn)

	var wrapper := VBoxContainer.new()
	wrapper.add_child(row)
	wrapper.add_child(HSeparator.new())
	return wrapper


func _on_accept(contract_id: String) -> void:
	var registry := _registry()
	if registry != null:
		registry.accept_contract(contract_id)
	_refresh_list()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_overlay("hat", FLAT_CAP_PATH)

	var ui_layer      := CanvasLayer.new()
	ui_layer.name     = "ContractNpcLayer"
	add_child(ui_layer)

	_panel            = Panel.new()
	_panel.name       = "ContractBoard"
	_panel.visible    = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -320.0
	_panel.offset_right  =  320.0
	_panel.offset_top    = -280.0
	_panel.offset_bottom =  280.0
	ui_layer.add_child(_panel)

	var title                  := Label.new()
	title.text                 = "Contract Board"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 10.0
	title.offset_bottom = 40.0
	_panel.add_child(title)

	var scroll           := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 48.0
	scroll.offset_bottom = -44.0
	_panel.add_child(scroll)

	_list                       = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close_btn           := Button.new()
	close_btn.text          = "Close"
	close_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	close_btn.offset_top    = -38.0
	close_btn.offset_bottom = -6.0
	close_btn.offset_left   = 8.0
	close_btn.offset_right  = -8.0
	close_btn.pressed.connect(_on_ui_cancel)
	_panel.add_child(close_btn)


func _plain_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _ship_is_berthed() -> bool:
	var plot := get_parent() as PortPlot
	if plot == null:
		return false
	var dock := plot.get_node_or_null("PortDock") as PortDock
	if dock == null:
		return false
	return dock.find_occupied_berth() != -1


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")
