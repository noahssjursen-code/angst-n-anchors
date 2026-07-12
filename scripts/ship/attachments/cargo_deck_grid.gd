@tool
class_name CargoDeckGridAttachment
extends VesselAttachment

## Mounts a CargoDeckComponent at the cargo socket.


func attachment_id() -> String:
	return "cargo_deck_grid"


func kind() -> String:
	return "cargo"


func _on_mounted() -> void:
	var deck := CargoDeckComponent.new()
	deck.name = "CargoDeck_main"
	deck.affects_boat_cargo_mass = true
	if _boat is Workboat:
		deck.deck_width_m = Workboat.BEAM_M * 0.7
		deck.deck_length_m = Workboat.LOA_M * 0.45
		deck.cell_size_x_m = 1.5
		deck.cell_size_z_m = 1.5
	else:
		deck.deck_width_m = 8.0
		deck.deck_length_m = 12.0
		deck.cell_size_x_m = 1.5
		deck.cell_size_z_m = 1.5
	add_child(deck)
