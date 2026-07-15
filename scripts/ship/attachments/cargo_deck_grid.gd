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
	deck.deck_width_m = maxf(_boat.beam_m * 0.7, 4.0) if _boat != null else 8.0
	deck.deck_length_m = maxf(_boat.length_m * 0.45, 6.0) if _boat != null else 12.0
	deck.cell_size_x_m = 1.5
	deck.cell_size_z_m = 1.5
	add_child(deck)
