@tool
class_name BoatController
extends Node

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

func _init() -> void:
	add_to_group(VehicleGroups.SHIP_OWNER_ONLY)


## Routes player input to the boat's components when seated at the helm.
## Activate/deactivate is called by CaptainsChair when the player boards or exits.

## How many helms are currently being controlled. Lets unrelated systems
## tell whether the player is sailing.
static var helmed_count: int = 0
##
## Input mapping:
##   Throttle stage — W / S (move_forward / move_back) increments / decrements stage
##   Direct stage set — number keys 1..5 (astern..full ahead)
##   Rudder   — A / D  (move_left / move_right)
##   Thruster mode cycle — T (boat_docking_thrusters): Off → Bow-only → Crab → Off
##     Bow-only: Q/R yaw the bow (useful for swinging the bow at low speed)
##     Crab: Q/R pure lateral drift (bow + stern together)

@export var ship_name:         String = "Unnamed Vessel"
@export var throttle_response: float = 1.8   # how fast throttle ramps (units/s)
@export var rudder_response:   float = 1.35
## Ordered throttle table. Index is the helm stage.
## Default stages:
## 0 full astern, 1 stop, 2 dead slow, 3 half, 4 full ahead.
@export var throttle_stage_values: PackedFloat32Array = PackedFloat32Array([
	-0.55, 0.0, 0.28, 0.56, 1.0
])
@export var stage_label_astem: String = "ASTERN"
@export var stage_label_stop: String = "STOP"
@export var stage_label_ahead: String = "AHEAD"

signal helm_activated
signal helm_deactivated

var _active: bool = false

## 0 = off, 1 = bow-only (yaw), 2 = crab (lateral drift)
var _thruster_mode: int = 0

var _throttle: float = 0.0
var _rudder:   float = 0.0
var _lateral:  float = 0.0
var _throttle_stage_idx: int = 1

## Accumulator for distance-sailed telemetry. Flushed to PlayerSession in
## ~5-second batches so we're not hammering the save layer per physics tick.
var _distance_accum_m:   float = 0.0
var _distance_flush_tick: float = 0.0
const DISTANCE_FLUSH_INTERVAL_S : float = 5.0
const MOORED_TOAST_COOLDOWN_S := 2.5
var _moored_toast_cooldown := 0.0

@onready var _propulsion:    PropulsionComponent  = get_node_or_null("../PropulsionComponent")
@onready var _rudder_comp:   RudderComponent      = get_node_or_null("../RudderComponent")
@onready var _bow_thruster:  BowThrusterComponent = get_node_or_null("../BowThrusterComponent")
@onready var _boat_body: RigidBody3D = get_parent() as RigidBody3D

var _hud_layer: CanvasLayer
var _ship_hud: ShipHud
var _autopilot: VesselAutopilot


func _ready() -> void:
	if not Engine.is_editor_hint():
		call_deferred("_ensure_autopilot")
		if not InputMap.has_action("boat_trawl_toggle"):
			InputMap.add_action("boat_trawl_toggle")
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_G
			InputMap.action_add_event("boat_trawl_toggle", ev)


func activate() -> void:
	_active = true
	helmed_count += 1
	if _boat_body != null:
		WaveSurface.set_local_visual_vessel(_boat_body)
	_ensure_hud()
	_set_hud_visible(true)
	if _is_moored() and _ship_hud != null:
		_ship_hud.show_toast("MOORED — leave helm and untie both quay lines [F]", 5.0)
	elif _autopilot != null and _autopilot.is_engaged() and _ship_hud != null:
		_ship_hud.show_toast("AUTOPILOT ENGAGED — [P] disengage, helm input overrides", 4.0)
	helm_activated.emit()
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.call_deferred("show", "first_helm")


func deactivate() -> void:
	var autopilot_keeps_watch := _autopilot != null and _autopilot.is_engaged()
	if _active:
		helmed_count = maxi(helmed_count - 1, 0)
	_active         = false
	_thruster_mode  = 0
	_throttle       = 0.0
	_rudder         = 0.0
	_lateral        = 0.0
	_throttle_stage_idx = _nearest_stage_idx(0.0)
	if _boat_body != null:
		WaveSurface.clear_coupled_vessel_if(_boat_body)
	if not autopilot_keeps_watch:
		_push_to_components()
	_set_hud_visible(false)
	helm_deactivated.emit()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	_moored_toast_cooldown = maxf(_moored_toast_cooldown - delta, 0.0)

	if Input.is_action_just_pressed("boat_autopilot_toggle"):
		_toggle_autopilot()
		if _autopilot != null and _autopilot.is_engaged():
			return

	if _autopilot != null and _autopilot.is_engaged():
		if _manual_override_requested():
			_autopilot.disengage("manual_override")
		else:
			return

	if Input.is_action_just_pressed("boat_docking_thrusters"):
		_thruster_mode = (_thruster_mode + 1) % 3

	if Input.is_action_just_pressed("boat_trawl_toggle"):
		if _boat_body != null:
			var systems: Array[FishingSystem] = _boat_body.get_fishing_systems()
			if not systems.is_empty():
				systems[0].toggle_trawling()

	if Input.is_action_just_pressed("move_forward"):
		_step_throttle_stage(1)
	elif Input.is_action_just_pressed("move_back"):
		_step_throttle_stage(-1)

	# Stage table is signed (positive = ahead intent). PropulsionComponent treats
	# negative throttle as ahead, so we negate before sending.
	var throttle_target: float = -_target_throttle_from_stage()
	var rudder_target:   float = Input.get_axis("move_left", "move_right")

	var lateral_target: float = 0.0
	if _thruster_mode > 0:
		lateral_target = Input.get_axis("boat_thrust_left", "boat_thrust_right")

	if _is_moored() and (
			not is_zero_approx(throttle_target)
			or not is_zero_approx(lateral_target)
	):
		throttle_target = 0.0
		lateral_target = 0.0
		_throttle_stage_idx = _nearest_stage_idx(0.0)
		if _moored_toast_cooldown <= 0.0 and _ship_hud != null:
			_ship_hud.show_toast("MOORED — untie both quay lines before departure", 3.0)
			_moored_toast_cooldown = MOORED_TOAST_COOLDOWN_S

	# Throttle and rudder ramp smoothly; crab thrust is immediate
	_throttle = move_toward(_throttle, throttle_target, throttle_response * delta)
	_rudder   = move_toward(_rudder,   rudder_target,   rudder_response   * delta)
	_lateral  = lateral_target

	_push_to_components()
	_accumulate_distance_sailed(delta)


## Integrate the helmed ship's horizontal speed and flush to PlayerSession
## in five-second batches. Only ticks while a player is at the helm (which
## is implied by _active being true, gated at the top of the function).
func _accumulate_distance_sailed(delta: float) -> void:
	if _boat_body == null or not is_instance_valid(_boat_body):
		return
	var v := _boat_body.linear_velocity
	_distance_accum_m += Vector2(v.x, v.z).length() * delta
	_distance_flush_tick += delta
	if _distance_flush_tick < DISTANCE_FLUSH_INTERVAL_S:
		return
	_distance_flush_tick = 0.0
	if _distance_accum_m < 0.1:
		return
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_method("add_distance_sailed"):
		session.add_distance_sailed(_distance_accum_m)
	_distance_accum_m = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_1:
			_disengage_autopilot_for_manual_input()
			_set_stage_from_percent(0.0)
		KEY_2:
			_disengage_autopilot_for_manual_input()
			_set_stage_from_percent(0.25)
		KEY_3:
			_disengage_autopilot_for_manual_input()
			_set_stage_from_percent(0.5)
		KEY_4:
			_disengage_autopilot_for_manual_input()
			_set_stage_from_percent(0.75)
		KEY_5:
			_disengage_autopilot_for_manual_input()
			_set_stage_from_percent(1.0)
		KEY_X:
			_disengage_autopilot_for_manual_input()
			_set_stage_stop()
		KEY_L:
			var lighting := get_node_or_null("../ShipLighting") as ShipLighting
			if lighting != null:
				lighting.cycle_preset()
		_:
			return
	get_viewport().set_input_as_handled()


func _push_to_components() -> void:
	if _propulsion   != null: _propulsion.throttle       = _throttle
	if _rudder_comp  != null: _rudder_comp.rudder_input  = _rudder
	if _bow_thruster != null:
		_bow_thruster.lateral_input = _lateral
		_bow_thruster.crab_mode = (_thruster_mode == 2)


func _ensure_autopilot() -> void:
	if ShipyardPlaytestMode.active():
		return
	if _boat_body == null:
		return
	_autopilot = _boat_body.get_node_or_null("VesselAutopilot") as VesselAutopilot
	if _autopilot == null:
		_autopilot = VesselAutopilot.new()
		_autopilot.name = "VesselAutopilot"
		_boat_body.add_child(_autopilot)
	if not _autopilot.disengaged.is_connected(_on_autopilot_disengaged):
		_autopilot.disengaged.connect(_on_autopilot_disengaged)
	var watch := _boat_body.get_node_or_null("BridgeWatchAlarm") as BridgeWatchAlarm
	if watch == null:
		watch = BridgeWatchAlarm.new()
		watch.name = "BridgeWatchAlarm"
		_boat_body.add_child(watch)


func _toggle_autopilot() -> void:
	if _autopilot == null:
		_ensure_autopilot()
	if _autopilot == null:
		return
	if _autopilot.is_engaged():
		_autopilot.disengage("manual")
		return
	if _is_moored():
		_show_autopilot_toast("AUTOPILOT UNAVAILABLE — untie before departure")
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("get_world_layout"):
		_show_autopilot_toast("AUTOPILOT UNAVAILABLE — no navigation data")
		return
	var view := get_node_or_null("/root/LocalPlayerView")
	var contracts: Array = view.get_active_contracts() if view != null else []
	if contracts.is_empty():
		_show_autopilot_toast("AUTOPILOT NEEDS AN ACTIVE FREIGHT ROUTE")
		return
	var contract := contracts[0] as Dictionary
	var destination_id := str(contract.get("destination_port_id", ""))
	var destination := view.get_port_position(destination_id) as Vector3
	if destination_id.is_empty() or not destination.is_finite():
		_show_autopilot_toast("AUTOPILOT ROUTE DESTINATION UNAVAILABLE")
		return
	var layout := world.call("get_world_layout") as WorldLayout
	var planner := MarineRoutePlanner.new(layout)
	var start := Vector2(_boat_body.global_position.x, _boat_body.global_position.z)
	var destination_berth_id := BerthApproachLanes.best_target_id(
		destination_id,
		str(contract.get("terminal_family", "")),
		str(contract.get("commodity_id", "")),
	)
	var plan := planner.plan_berth_to_berth(
		start,
		Vector2(destination.x, destination.z),
		str(contract.get("origin_port_id", "")),
		str(contract.get("berth_id", "")),
		destination_id,
		destination_berth_id,
	)
	if not _autopilot.engage(plan):
		_show_autopilot_toast("AUTOPILOT COULD NOT FIND A SAFE SEA ROUTE")
		return
	_thruster_mode = 0
	_lateral = 0.0
	_show_autopilot_toast("AUTOPILOT ENGAGED TO %s — [P] disengage" % \
		str(view.get_port_display_name(destination_id)).to_upper(), 5.0)


func _manual_override_requested() -> bool:
	return Input.is_action_just_pressed("move_forward") \
		or Input.is_action_just_pressed("move_back") \
		or absf(Input.get_axis("move_left", "move_right")) > 0.1 \
		or absf(Input.get_axis("boat_thrust_left", "boat_thrust_right")) > 0.1


func _disengage_autopilot_for_manual_input() -> void:
	if _autopilot != null and _autopilot.is_engaged():
		_autopilot.disengage("manual_override")


func _on_autopilot_disengaged(reason: String) -> void:
	match reason:
		"arrived":
			_show_autopilot_toast("AUTOPILOT APPROACH COMPLETE — take the helm")
		"off_route":
			_show_autopilot_toast("AUTOPILOT DISENGAGED — vessel is off route")
		"manual_override":
			_show_autopilot_toast("AUTOPILOT DISENGAGED — manual helm")
		_:
			_show_autopilot_toast("AUTOPILOT DISENGAGED")


func _show_autopilot_toast(text: String, duration_s: float = 3.0) -> void:
	if _ship_hud != null:
		_ship_hud.show_toast(text, duration_s)


func _is_moored() -> bool:
	if _boat_body == null:
		return false
	var mooring := _boat_body.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	return mooring != null and mooring.is_moored


func _step_throttle_stage(step: int) -> void:
	_throttle_stage_idx = clampi(_throttle_stage_idx + step, 0, _stage_count() - 1)


func _set_stage_stop() -> void:
	_throttle_stage_idx = _nearest_stage_idx(0.0)


func _set_stage_from_percent(percent: float) -> void:
	var pct := clampf(percent, 0.0, 1.0)
	var target := lerpf(0.0, 1.0, pct)
	var best_idx := _nearest_stage_idx(target)
	_throttle_stage_idx = best_idx


func _stage_count() -> int:
	return maxi(throttle_stage_values.size(), 2)


func _target_throttle_from_stage() -> float:
	if throttle_stage_values.is_empty():
		return 0.0
	var idx := clampi(_throttle_stage_idx, 0, throttle_stage_values.size() - 1)
	return clampf(throttle_stage_values[idx], -1.0, 1.0)


func _nearest_stage_idx(value: float) -> int:
	if throttle_stage_values.is_empty():
		return 0
	var best_idx := 0
	var best_err := INF
	for i in range(throttle_stage_values.size()):
		var err := absf(throttle_stage_values[i] - value)
		if err < best_err:
			best_err = err
			best_idx = i
	return best_idx


func _ensure_hud() -> void:
	if _hud_layer != null and is_instance_valid(_hud_layer):
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "BoatHelmHUD"
	add_child(_hud_layer)

	_ship_hud = ShipHud.new()
	_ship_hud.name = "ShipHud"
	_hud_layer.add_child(_ship_hud)
	_ship_hud.setup(_boat_body, self)


func _set_hud_visible(on: bool) -> void:
	if _hud_layer != null:
		_hud_layer.visible = on


func get_throttle_stage_idx() -> int:
	return _throttle_stage_idx


func set_throttle_stage_idx(idx: int) -> void:
	_throttle_stage_idx = clampi(idx, 0, _stage_count() - 1)


func get_thruster_mode() -> int:
	return _thruster_mode


func get_autopilot() -> VesselAutopilot:
	return _autopilot


func get_helm_visual_state() -> Dictionary:
	## Read-only presentation state; propulsion uses negative throttle for ahead.
	return {"steering":_rudder,"throttle":-_throttle}
