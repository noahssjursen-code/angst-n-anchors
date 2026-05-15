@tool
extends Node3D

## Composition root for the starting island.
## Instantiates WorldRenderer, the island ground, a Port, and (at runtime) AtmosphericEffects and the player.
## No geometry, shader setup, or weather logic lives here.

const PLAYER_SCENE := preload("res://scenes/islands/starting_island/player.tscn")
const C_SAND       := Color(0.82, 0.74, 0.58)

const REMOTE_PORT_ID       := "harbor-north"
const REMOTE_PORT_NAME     := "Harbor"
const REMOTE_PORT_POSITION := Vector3(0.0, 0.0, 400.0)


func _ready() -> void:
	# In the editor, queue_free() is deferred — old nodes stay alive when new
	# ones are added with the same name, causing Godot to auto-rename them and
	# breaking owner assignment. free() removes them immediately.
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_add_world_renderer()
	_add_ground()
	_add_port()

	if not Engine.is_editor_hint():
		_add_atmospheric_effects()
		_add_proximity_loader()
		_spawn_player()
		call_deferred("_pre_register_remote_port")


func _add_world_renderer() -> void:
	var renderer  := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)
	if Engine.is_editor_hint():
		_own_subtree(renderer)


func _add_ground() -> void:
	var ground      := MeshBuilder.static_box(Vector3(80, 2, 60), C_SAND)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)
	if Engine.is_editor_hint():
		ground.owner = get_tree().edited_scene_root


func _add_port() -> void:
	var port  := Port.new()
	port.name = "Port"
	add_child(port)
	if Engine.is_editor_hint():
		_own_subtree(port)


func _add_atmospheric_effects() -> void:
	var fx  := AtmosphericEffects.new()
	fx.name = "AtmosphericEffects"
	add_child(fx)


func _add_proximity_loader() -> void:
	var loader  := ProximityLoader.new()
	loader.name = "ProximityLoader"
	add_child(loader)
	loader.register(
		REMOTE_PORT_POSITION,
		func() -> Node3D:
			var island                   := BasicIsland.new()
			island.dock_facing_degrees   = 180.0
			island.port_id               = REMOTE_PORT_ID
			island.port_display_name     = REMOTE_PORT_NAME
			return island,
		200.0,
	)


func _pre_register_remote_port() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	registry.register_port(REMOTE_PORT_ID, REMOTE_PORT_NAME, REMOTE_PORT_POSITION, null)


func _spawn_player() -> void:
	var port      := get_node_or_null("Port") as Port
	var spawn_pos := Vector3(7.5, 0.1, 22.8)
	if port != null:
		spawn_pos = port.get_player_spawn_position()
	var player      := PLAYER_SCENE.instantiate()
	player.position = spawn_pos
	add_child(player)


## Recursively assigns ownership to node and all its descendants so they appear
## in the editor scene tree and are saved with the scene.
func _own_subtree(node: Node) -> void:
	var esc := get_tree().edited_scene_root
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
