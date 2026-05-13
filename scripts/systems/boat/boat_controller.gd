@tool
class_name BoatController
extends Node

## Routes player input to the boat's components when seated at the helm.
## Activate/deactivate is called by CaptainsChair when the player boards or exits.
##
## Input mapping:
##   Throttle  — W / S  (reuses move_forward / move_back)
##   Rudder    — A / D  (reuses move_left / move_right)
##   Bow thrust — Q / R  (boat_thrust_left / boat_thrust_right)

@export var throttle_response: float = 1.8   # how fast throttle ramps (units/s)
@export var rudder_response:   float = 3.0

var _active: bool = false

var _throttle: float = 0.0
var _rudder:   float = 0.0
var _lateral:  float = 0.0

@onready var _propulsion:    PropulsionComponent  = get_node_or_null("../PropulsionComponent")
@onready var _rudder_comp:   RudderComponent      = get_node_or_null("../RudderComponent")
@onready var _bow_thruster:  BowThrusterComponent = get_node_or_null("../BowThrusterComponent")


func activate() -> void:
	_active = true


func deactivate() -> void:
	_active   = false
	_throttle = 0.0
	_rudder   = 0.0
	_lateral  = 0.0
	_push_to_components()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return

	var throttle_target: float = Input.get_axis("move_back",   "move_forward")
	var rudder_target:   float = Input.get_axis("move_right",  "move_left")
	var lateral_target:  float = Input.get_axis("boat_thrust_left", "boat_thrust_right")

	# Throttle and rudder ramp smoothly; bow thruster is immediate
	_throttle = move_toward(_throttle, throttle_target, throttle_response * delta)
	_rudder   = move_toward(_rudder,   rudder_target,   rudder_response   * delta)
	_lateral  = lateral_target

	_push_to_components()


func _push_to_components() -> void:
	if _propulsion   != null: _propulsion.throttle       = _throttle
	if _rudder_comp  != null: _rudder_comp.rudder_input  = _rudder
	if _bow_thruster != null: _bow_thruster.lateral_input = _lateral
