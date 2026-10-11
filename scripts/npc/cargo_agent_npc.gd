class_name CargoAgentNpc
extends NpcInteractable

## Freight broker for a single port. The NPC is only a presentation surface;
## offer generation and accepted work remain in FreightService.

@export var port_id: String = ""


func _ready() -> void:
	appearance = CharacterCatalog.appearance_preset("shipping_manager")
	prompt_text = "Press F — Cargo Agent"
	super._ready()


func _accept(offer: Dictionary) -> void:
	var ship := _berthed_player_ship()
	if ship != null and FreightService.accept_offer_for_ship(offer, ship, port_id):
		LocalPlayerView.save_player_state()


func _berthed_player_ship() -> BoatBody:
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null or not FreightService.is_ship_ready_at_port(ship, port_id):
		return null
	return ship
