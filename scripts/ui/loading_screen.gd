extends Control

## Unused standalone scene stub — LoadingGate autoload owns the real overlay.
## Kept so scene path references remain valid.

const WORLD_SCENE := "res://scenes/world.tscn"


func _ready() -> void:
	var gate := get_node_or_null("/root/LoadingGate")
	var destination := WORLD_SCENE
	if gate != null and not str(gate.pending_scene_path).is_empty():
		destination = str(gate.pending_scene_path)
	get_tree().change_scene_to_file(destination)
