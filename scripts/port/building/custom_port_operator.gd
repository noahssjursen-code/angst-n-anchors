extends NpcInteractable

var display_name := "Port operator"

func _on_interact() -> void:
	# The owning workshop supplies its authority-backed panel via the existing
	# interaction signal; this NPC never writes inventory or docking state.
	interaction_requested.emit()
