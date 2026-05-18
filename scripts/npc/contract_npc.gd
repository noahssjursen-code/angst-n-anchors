@tool
class_name ContractNpc
extends NpcInteractable

## Contract board NPC. Opens a contract list when the player interacts.
## Blocks interaction if player is carrying cargo.

const FLAT_CAP_PATH := "res://resources/data/meshes/characters/hat_flat_cap.json"

@export var port_id: String = ""

var _dialogue: DialoguePanel


func _ready() -> void:
	clothing_color = Color(0.22, 0.38, 0.60)
	trousers_color = Color(0.16, 0.24, 0.42)
	prompt_text    = "Press F to view contracts"
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
	_dialogue.show_panel()
	open_ui()


func _on_ui_cancel() -> void:
	_dialogue.hide_panel()
	close_ui()


# ── Panel ─────────────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	_dialogue.clear()

	var registry := _registry()
	if registry == null:
		_dialogue.add_label("ContractRegistry autoload not found.")
		return

	var contracts: Array[Contract] = registry.get_contracts_from_port(port_id)
	if contracts.is_empty():
		_dialogue.add_label("No contracts available.")
		return

	var active_count: int = registry.get_accepted_contracts().size()
	var slots_free:   int = registry.MAX_ACTIVE_CONTRACTS - active_count
	var ship_berthed: bool = _ship_is_berthed()
	var ship_cells_free: int = _ship_cells_free()

	# Header line above the rows. One contract at a time: the header is
	# "Active route" or "No active route", plus current ship capacity.
	var header_text := "No active route   ·   Ship capacity %d cells" % ship_cells_free
	if active_count > 0:
		header_text = "Route active   ·   Ship capacity %d cells" % ship_cells_free
	var header := _dialogue.add_label(header_text)
	header.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_dialogue.add_separator()

	for contract in contracts:
		_dialogue.add_custom(_make_row(contract, registry, slots_free, ship_berthed, ship_cells_free))


func _make_row(contract: Contract, registry: Node, slots_free: int, ship_berthed: bool, ship_cells_free: int) -> Control:
	# ── Data ────────────────────────────────────────────────────────────────
	var info: Dictionary = registry.commodity_info(contract.commodity)
	var color: Color     = registry.commodity_color(contract.commodity)
	var max_units: int   = int(info.get("max_pallet_units", 4))
	var stock: int       = int(registry.get_export_stock(contract.origin_port_id, contract.commodity))
	# Units the contract still has on offer + the largest count whose pallets
	# (including footprint overfills) actually fit in ship_cells_free.
	var still_offered    := contract.available_to_take()
	var stock_limit      := mini(still_offered, stock)
	var takeable         := PalletFactory.max_units_in_cells(stock_limit, max_units, ship_cells_free)
	var cells_needed     := PalletFactory.cells_needed_for(still_offered, max_units)
	var pallets_needed   := int(ceil(float(still_offered) / float(maxi(max_units, 1))))

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

	# Shows remaining-on-offer instead of original total once partials happen.
	var qty_str := "×%d" % still_offered
	if contract.taken_count > 0:
		qty_str = "×%d (of %d)" % [still_offered, contract.quantity]

	var headline      := Label.new()
	headline.text     = "%s %s  →  %s   %s" % [
		contract.display_name, qty_str, dest_name, dist_str,
	]
	headline.add_theme_font_size_override("font_size", 14)
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var reward_lbl    := Label.new()
	# Reward shown for what's offered now (proportional to remaining quantity).
	var offered_reward := contract.reward_per_unit() * still_offered
	reward_lbl.text   = "ℳ %d" % offered_reward
	reward_lbl.add_theme_font_size_override("font_size", 14)
	reward_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	reward_lbl.custom_minimum_size = Vector2(70, 0)
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 0)
	# Only one contract at a time. A NEW contract is locked out if any other
	# one is active; the active contract itself can still be topped up.
	var needs_slot := contract.taken_count == 0
	if still_offered <= 0:
		btn.text     = "Done"
		btn.disabled = true
	elif needs_slot and slots_free <= 0:
		btn.text     = "Finish active route first"
		btn.disabled = true
	elif not ship_berthed:
		btn.text     = "Berth ship"
		btn.disabled = true
	elif stock <= 0:
		btn.text     = "Out of stock"
		btn.disabled = true
	elif ship_cells_free <= 0:
		btn.text     = "No space"
		btn.disabled = true
	elif takeable <= 0:
		btn.text     = "No space"
		btn.disabled = true
	elif takeable < still_offered:
		btn.text     = "Take %d of %d" % [takeable, still_offered]
		btn.pressed.connect(_on_accept.bind(contract.id, takeable))
	else:
		btn.text = "Accept"
		btn.pressed.connect(_on_accept.bind(contract.id, 0))

	var row1 := HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_FILL
	row1.add_child(swatch)
	row1.add_child(headline)
	row1.add_child(reward_lbl)
	row1.add_child(btn)

	# ── Row 2: pallet/footprint · stock · capacity hint
	# Pallet layout is computed for what the player would actually take now.
	var take_units := maxi(takeable, 0)
	var take_pallets := int(ceil(float(take_units) / float(maxi(max_units, 1)))) if take_units > 0 else pallets_needed
	var shape_hint := ""
	if take_units > 0:
		var last_pallet_size: int = take_units - (take_pallets - 1) * max_units
		var full_fp: Vector2i = PalletFactory.best_footprint(max_units, max_units)
		var last_fp: Vector2i = PalletFactory.best_footprint(last_pallet_size, max_units)
		if take_pallets == 1:
			shape_hint = "1 pallet · %d×%d" % [last_fp.x, last_fp.y]
		elif last_pallet_size == max_units:
			shape_hint = "%d pallets · %d×%d each" % [take_pallets, full_fp.x, full_fp.y]
		else:
			shape_hint = "%d pallets · %d × %d×%d + 1 × %d×%d" % [
				take_pallets,
				take_pallets - 1, full_fp.x, full_fp.y,
				last_fp.x, last_fp.y,
			]
	else:
		shape_hint = "%d pallets · 1×1" % pallets_needed
	var caps_text := "%s  ·  stock %d  ·  ship has %d cells free" % [
		shape_hint, stock, ship_cells_free,
	]
	var caps := Label.new()
	caps.text = caps_text
	caps.add_theme_font_size_override("font_size", 11)
	var dim := Color(0.78, 0.78, 0.82)
	if takeable < still_offered:
		dim = Color(0.95, 0.78, 0.40)  # partial — gentle warning
	if takeable <= 0 and still_offered > 0:
		dim = Color(0.95, 0.55, 0.45)  # blocked — red
	caps.add_theme_color_override("font_color", dim)

	var wrapper := VBoxContainer.new()
	wrapper.add_child(row1)
	wrapper.add_child(caps)
	wrapper.add_child(HSeparator.new())
	return wrapper


func _on_accept(contract_id: String, take_units: int = 0) -> void:
	var registry := _registry()
	if registry != null:
		registry.accept_contract(contract_id, take_units)
	_refresh_list()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_overlay("hat", FLAT_CAP_PATH)
	_dialogue = DialoguePanel.new("CONTRACT BOARD", Vector2(640.0, 560.0))
	add_child(_dialogue)


func _ship_is_berthed() -> bool:
	var plot := get_parent() as PortPlot
	if plot == null:
		return false
	var dock := plot.get_node_or_null("PortDock") as PortDock
	if dock == null:
		return false
	return dock.find_occupied_berth() != -1


## Free CELLS the player can still commit to. Counts cells, not units, so
## footprint overfills (3 timber → 2×2 = 4 cells) are accounted for. Equals
## total ship deck capacity minus the cells occupied by every committed-but-
## undelivered pallet in the pipeline.
func _ship_cells_free() -> int:
	var total_capacity := 0
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null or not deck.port_id.is_empty():
			continue
		total_capacity += deck.get_capacity()

	var committed_cells := 0
	var registry := _registry()
	if registry != null:
		for c in registry.get_accepted_contracts():
			var contract := c as Contract
			if contract == null:
				continue
			var in_play := maxi(contract.taken_count - contract.delivered_count, 0)
			if in_play <= 0:
				continue
			committed_cells += PalletFactory.cells_needed(in_play, contract.commodity)

	return maxi(total_capacity - committed_cells, 0)


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")
