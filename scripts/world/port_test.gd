extends Node3D

## Minimal playable test scene: one port, renderer, player.
## Keeps the main scene runnable without spinning up the full world generator.

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")


func _ready() -> void:
	var renderer  := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)

	var plot  := PortPlot.new()
	plot.name = "Port"
	add_child(plot)

	_spawn_player()


func _spawn_player() -> void:
	# PortPlot._rebuild and PortDock are both deferred — wait two frames.
	await get_tree().process_frame
	await get_tree().process_frame

	var plot      := get_node_or_null("Port") as PortPlot
	var spawn_pos := Vector3(0.0, 1.0, 0.0)
	if plot != null:
		spawn_pos = plot.get_spawn_position()

	var player      := PLAYER_SCENE.instantiate()
	player.position = spawn_pos
	add_child(player)
