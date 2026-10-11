class_name BridgeWatchAlarm
extends Node3D

## Player watchkeeping monitor (BNWAS-inspired). While passage autopilot steers,
## detected movement near a helm resets the timer. NPC captains do not use this
## component; their authority state continuously owns the watch.

signal alarm_started
signal alarm_acknowledged

@export_range(30.0, 600.0, 1.0) var inactivity_interval_s := 180.0
@export_range(2.0, 30.0, 0.5) var alarm_repeat_s := 6.0
@export_range(2.0, 12.0, 0.5) var bridge_sensor_radius_m := 5.5
@export_range(0.02, 1.0, 0.01) var movement_threshold_m := 0.12

var alarm_active := false
var remaining_s := 180.0

var _body: BoatBody
var _autopilot: VesselAutopilot
var _last_bridge_position := Vector3(INF, INF, INF)
var _repeat_remaining_s := 0.0
var _audio: AudioStreamPlayer3D
var _bridge_input_pulse := false


func _ready() -> void:
	_body = get_parent() as BoatBody
	remaining_s = inactivity_interval_s
	_build_audio()


func _process(delta: float) -> void:
	if _body == null or not _body.is_in_group(PlayerVessel.GROUP):
		return
	if _autopilot == null or not is_instance_valid(_autopilot):
		_autopilot = _body.get_node_or_null("VesselAutopilot") as VesselAutopilot
	if _autopilot == null or not _autopilot.is_engaged():
		reset_watch()
		return
	if _bridge_activity_detected():
		acknowledge()
		return
	remaining_s = maxf(remaining_s - delta, 0.0)
	if remaining_s > 0.0:
		return
	if not alarm_active:
		alarm_active = true
		alarm_started.emit()
		_play_alarm()
		_repeat_remaining_s = alarm_repeat_s
		return
	_repeat_remaining_s -= delta
	if _repeat_remaining_s <= 0.0:
		_play_alarm()
		_repeat_remaining_s = alarm_repeat_s


func _input(event: InputEvent) -> void:
	## A seated watchkeeper may not move the character body. Mouse-look or an
	## intentional key press while physically near the bridge also proves that
	## someone is awake, without adding a separate arcade acknowledgement key.
	if event is InputEventMouseMotion:
		_bridge_input_pulse = (event as InputEventMouseMotion).relative.length_squared() >= 4.0
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_bridge_input_pulse = true


func acknowledge() -> void:
	var was_active := alarm_active
	alarm_active = false
	remaining_s = inactivity_interval_s
	_repeat_remaining_s = 0.0
	if was_active:
		alarm_acknowledged.emit()


func reset_watch() -> void:
	alarm_active = false
	remaining_s = inactivity_interval_s
	_repeat_remaining_s = 0.0
	_last_bridge_position = Vector3(INF, INF, INF)
	_bridge_input_pulse = false


func snapshot() -> Dictionary:
	return {
		"alarm_active": alarm_active,
		"remaining_s": remaining_s,
		"interval_s": inactivity_interval_s,
	}


func _bridge_activity_detected() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var player := tree.get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return false
	var near_helm := false
	for raw in _body.find_children("*", "BridgeInteractable", true, false):
		var helm := raw as Node3D
		if helm != null and player.global_position.distance_to(helm.global_position) <= bridge_sensor_radius_m:
			near_helm = true
			break
	if not near_helm:
		_last_bridge_position = Vector3(INF, INF, INF)
		_bridge_input_pulse = false
		return false
	if _bridge_input_pulse:
		_bridge_input_pulse = false
		_last_bridge_position = player.global_position
		return true
	if not _last_bridge_position.is_finite():
		_last_bridge_position = player.global_position
		return true
	var moved := player.global_position.distance_to(_last_bridge_position) >= movement_threshold_m
	if moved:
		_last_bridge_position = player.global_position
	return moved


func _build_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "BridgeWatchAlarmAudio"
	_audio.unit_size = 18.0
	_audio.max_distance = 80.0
	_audio.stream = _alarm_stream()
	_audio.bus = AudioLibrary.bus("res://resources/audio/world/helm/watch_alarm_1.wav")
	_audio.volume_db = -10.0
	add_child(_audio)


func _play_alarm() -> void:
	if _audio != null:
		var stations := _body.find_children("*", "BridgeInteractable", true, false) if _body != null else []
		if not stations.is_empty():
			_audio.global_position = (stations[0] as Node3D).global_position
		_audio.play()


static func _alarm_stream() -> AudioStreamWAV:
	return AudioLibrary.stream("res://resources/audio/world/helm/watch_alarm_1.wav", false) as AudioStreamWAV
