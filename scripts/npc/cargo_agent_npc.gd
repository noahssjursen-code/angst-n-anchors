class_name CargoAgentNpc
extends NpcInteractable

## Freight broker for a single port. The NPC is only a presentation surface;
## offer generation and accepted work remain in FreightService.

@export var port_id: String = ""

var _dialogue: DialoguePanel


func _ready() -> void:
	appearance = CharacterCatalog.appearance_preset("shipping_manager")
	prompt_text = "Press F — Cargo Agent"
	super._ready()
	if Engine.is_editor_hint():
		return
	_dialogue = DialoguePanel.new("CARGO OFFICE", Vector2(760.0, 520.0))
	add_child(_dialogue)


func _on_interact() -> void:
	open_ui()
	_rebuild()
	_dialogue.show_panel()


func _on_ui_cancel() -> void:
	if _dialogue != null:
		_dialogue.hide_panel()
	close_ui()


func _rebuild() -> void:
	_dialogue.clear()
	var port_name := LocalPlayerView.get_port_display_name(port_id)
	_dialogue.set_title("%s — CARGO OFFICE" % port_name.to_upper())
	var active := LocalPlayerView.get_active_contracts()
	if not active.is_empty():
		_dialogue.add_quote("ACTIVE MANIFEST — %d / %d MOVEMENTS" % [active.size(), FreightService.MAX_ACTIVE_CONTRACTS])
		for contract in active:
			_show_active_card(contract as Dictionary)
		_dialogue.add_separator()
	var ship := _berthed_player_ship()
	if ship == null:
		_dialogue.add_quote("Bring your vessel alongside a working cargo berth before booking freight.")
		_dialogue.add_disabled_option("No player vessel berthed and ready at this port")
		_dialogue.add_separator()
		_dialogue.add_option("Close cargo office", _on_ui_cancel)
		return
	_dialogue.add_quote("Outbound freight. Choose a movement that suits your vessel, cargo gear, and onward route.")
	var offers := FreightService.eligible_offers_at(port_id, ship)
	if offers.is_empty():
		_dialogue.add_disabled_option("No movements match this vessel, berth, and free cargo capacity")
	else:
		for offer in offers:
			_dialogue.add_custom(_offer_card(offer))
	_dialogue.add_separator()
	_dialogue.add_option("Close cargo office", _on_ui_cancel)


func _show_active_card(contract: Dictionary) -> void:
	var destination := LocalPlayerView.get_port_display_name(str(contract.get("destination_port_id", "")))
	var card := BrandComponents.inner_panel(Vector2(0.0, 76.0))
	var column := VBoxContainer.new()
	card.add_child(column)
	column.add_child(BrandComponents.key_value_row(destination.to_upper(), PlayerData.format_money(int(contract.get("pay_marks", 0))), BrandTokens.BRASS))
	var commodity := CommodityCatalog.commodity_display(str(contract.get("commodity_id", "")))
	column.add_child(BrandComponents.key_value_row(commodity, _progress_text(contract)))
	_dialogue.add_custom(card)


func _offer_card(offer: Dictionary) -> Control:
	var card := BrandComponents.inner_panel(Vector2(0.0, 112.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	card.add_child(column)
	var destination := LocalPlayerView.get_port_display_name(str(offer.get("destination_port_id", "")))
	column.add_child(BrandComponents.key_value_row(destination.to_upper(), PlayerData.format_money(int(offer.get("pay_marks", 0))), BrandTokens.BRASS))
	column.add_child(BrandComponents.key_value_row(
		CommodityCatalog.commodity_display(str(offer.get("commodity_id", ""))),
		"%s  ·  %.1f km" % [_quantity_text(offer), float(offer.get("distance_m", 0.0)) / 1000.0],
	))
	var accept := BrandComponents.compact_button("Accept movement", 180.0)
	accept.pressed.connect(_accept.bind(offer))
	accept.disabled = not FreightService.can_accept(offer)
	if accept.disabled:
		accept.text = "Already on manifest" if _is_active_offer(offer) else "Manifest full"
	column.add_child(accept)
	return card


func _accept(offer: Dictionary) -> void:
	var ship := _berthed_player_ship()
	if ship != null and FreightService.accept_offer_for_ship(offer, ship, port_id):
		LocalPlayerView.save_player_state()
	_rebuild()


func _berthed_player_ship() -> BoatBody:
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null or not FreightService.is_ship_ready_at_port(ship, port_id):
		return null
	return ship


func _quantity_text(contract: Dictionary) -> String:
	var quantity := float(contract.get("quantity", 0.0))
	var unit := str(contract.get("quantity_unit", "units"))
	return "%d %s" % [int(round(quantity)), unit]


func _progress_text(contract: Dictionary) -> String:
	var loaded := float(contract.get("loaded_quantity", 0.0))
	return "%d / %s loaded" % [int(round(loaded)), _quantity_text(contract)]


func _is_active_offer(offer: Dictionary) -> bool:
	var offer_id := str(offer.get("id", ""))
	for active in LocalPlayerView.get_active_contracts():
		if str((active as Dictionary).get("id", "")) == offer_id:
			return true
	return false
