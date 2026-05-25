class_name PortProximity
extends Node

## Tracks the player's nearest port and updates GameState.world.nearest_port_id.
## AutonomousVesselManager listens for port changes to reload DB-backed fleet NPCs.

const CHECK_INTERVAL_S := 1.0
const PORT_CONTEXT_RADIUS_M := 3500.0
const WorldReference := preload("res://scripts/world/world_reference.gd")

var _timer: float = 0.0
var _last_port_id: String = ""


func _ready() -> void:
	call_deferred("_tick")


func _tick() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	var tree := get_tree()
	var ref := WorldReference.gameplay_position(tree)
	var xz := Vector2(ref.x, ref.z)
	var port_id := ""
	if registry.has_method("nearest_port_id"):
		port_id = str(registry.call("nearest_port_id", xz, PORT_CONTEXT_RADIUS_M))
	if port_id == _last_port_id:
		return
	_last_port_id = port_id
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.get("world") != null:
		(gs.world as WorldState).nearest_port_id = port_id


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL_S
	_tick()


