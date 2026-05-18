@tool
class_name ContractNpc
extends NpcInteractable

## Contract board NPC. Opens a contract list when the player interacts.
## Blocks interaction if player is carrying cargo.

const FLAT_CAP_PATH := "res://resources/data/meshes/characters/hat_flat_cap.json"

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
	if _nearest_player() == null:
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

	var active_count: int = registry.get_accepted_contracts().size()
	var slots_free:   int = registry.MAX_ACTIVE_CONTRACTS - active_count
	var ship_berthed: bool = _ship_is_berthed()
	var ship_cells_free: int = _ship_cells_free()

	# Header line above the rows.
	var header := _plain_label("Active %d / %d   ·   Ship capacity %d free cells" % [
		active_count, registry.MAX_ACTIVE_CONTRACTS, ship_cells_free,
	])
	header.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_list.add_child(header)
	_list.add_child(HSeparator.new())

	for contract in contracts:
		_list.add_child(_make_row(contract, registry, slots_free, ship_berthed, ship_cells_free))


func _make_row(contract: Contract, registry: Node, slots_free: int, ship_berthed: bool, ship_cells_free: int) -> Control:
	# ── Data ────────────────────────────────────────────────────────────────
	var info: Dictionary = registry.commodity_info(contract.commodity)
	var color: Color     = registry.commodity_color(contract.commodity)
	var max_units: int   = int(info.get("max_pallet_units", 4))
	# One unit = one cell. Pallets are 1×N strips up to max_units long.
	var cells_needed   := contract.quantity
	var pallets_needed := int(ceil(float(contract.quantity) / float(maxi(max_units, 1))))
	var stock          := int(registry.get_export_stock(contract.origin_port_id, contract.commodity))

	var dest_name: String = registry.get_destination_name(contract)
	var origin_pos: Vector3 = registry.get_port_position(contract.origin_port_id)
	var dest_pos:   Vector3 = registry.get_port_position(contract.destination_port_id)
	var dist_str := ""
	if origin_pos.x != INF and dest_pos.x != INF:
		var d := origin_pos.distance_to(dest_pos)
		dist_str = "%.0f m" % d if d < 1852.0 else "%.1f nm" % (d / 1852.0)
	if dist_str.is_empty():
		dist_str = "in port"

	# ── Row 1: color swatch · commodity (qty) → dest · distance · reward · button
	var swatch        := ColorRect.new()
	swatch.color      = color
	swatch.custom_minimum_size = Vector2(18, 32)

	var headline      := Label.new()
	headline.text     = "%s ×%d  →  %s   %s" % [
		contract.display_name, contract.quantity, dest_name, dist_str,
	]
	headline.add_theme_font_size_override("font_size", 14)
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var reward_lbl    := Label.new()
	reward_lbl.text   = "ℳ %d" % contract.reward_gold
	reward_lbl.add_theme_font_size_override("font_size", 14)
	reward_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	reward_lbl.custom_minimum_size = Vector2(70, 0)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(110, 0)
	match contract.state:
		Contract.State.AVAILABLE:
			if slots_free <= 0:
				btn.text     = "Full"
				btn.disabled = true
			elif not ship_berthed:
				btn.text     = "Berth ship"
				btn.disabled = true
			elif stock < contract.quantity:
				btn.text     = "Out of stock"
				btn.disabled = true
			elif ship_cells_free < cells_needed:
				btn.text     = "No space"
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

	var row1 := HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_FILL
	row1.add_child(swatch)
	row1.add_child(headline)
	row1.add_child(reward_lbl)
	row1.add_child(btn)

	# ── Row 2: pallet/footprint · stock · capacity hint
	# Each unit = 1 cell. Layout: greedy fill by max_units, last pallet smaller.
	var last_pallet_size: int = contract.quantity - (pallets_needed - 1) * max_units
	var full_fp: Vector2i = PalletFactory.best_footprint(max_units, max_units)
	var last_fp: Vector2i = PalletFactory.best_footprint(last_pallet_size, max_units)
	var shape_hint := ""
	if pallets_needed == 1:
		shape_hint = "1 pallet · %d×%d" % [last_fp.x, last_fp.y]
	elif last_pallet_size == max_units:
		shape_hint = "%d pallets · %d×%d each" % [pallets_needed, full_fp.x, full_fp.y]
	else:
		shape_hint = "%d pallets · %d × %d×%d + 1 × %d×%d" % [
			pallets_needed,
			pallets_needed - 1, full_fp.x, full_fp.y,
			last_fp.x, last_fp.y,
		]
	var caps_text := "%s  ·  stock %d  ·  needs %d of %d cells" % [
		shape_hint, stock, cells_needed, ship_cells_free,
	]
	var caps := Label.new()
	caps.text = caps_text
	caps.add_theme_font_size_override("font_size", 11)
	var dim := Color(0.78, 0.78, 0.82)
	if stock < contract.quantity or (ship_berthed and ship_cells_free < cells_needed):
		dim = Color(0.95, 0.55, 0.45)  # warning
	caps.add_theme_color_override("font_color", dim)

	var wrapper := VBoxContainer.new()
	wrapper.add_child(row1)
	wrapper.add_child(caps)
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
	_panel.theme      = HudStyle.make_theme()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -320.0
	_panel.offset_right  =  320.0
	_panel.offset_top    = -280.0
	_panel.offset_bottom =  280.0
	ui_layer.add_child(_panel)

	var title                  := Label.new()
	title.text                 = "CONTRACT BOARD"
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


## Sum of free cells across every CARGO deck (port_id empty → ship deck) in
## the scene. With one player and one boat this is just that boat's capacity;
## fleets sum naturally.
func _ship_cells_free() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null:
			continue
		if not deck.port_id.is_empty():
			continue  # apron deck, not a ship
		total += deck.get_available()
	return total


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")
