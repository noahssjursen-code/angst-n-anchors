class_name ImportedSeatInteractable
extends BridgeInteractable

## Same F/range/occlusion/exit interaction as the helm, without vessel controls.
var state_driver: ShipPartState

func _cache_boat_nodes() -> void:
	super._cache_boat_nodes()
	_boat_controller = null

func _board() -> void:
	super._board()
	if _occupied and state_driver != null:
		state_driver.request("occupied", true)

func _exit() -> void:
	super._exit()
	if state_driver != null:
		state_driver.request("occupied", false)

func _process(delta: float) -> void:
	super._process(delta)
	if _occupied and is_instance_valid(_player):
		_player.global_position = global_position
