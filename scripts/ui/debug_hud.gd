extends Node

## Autoload — owns the F3 debug overlay. F4 weather presets + E midday/calm while panel is open.
## Layer 100: always above every other UI element.

const _WEATHER_PANEL := preload("res://scripts/weather/weather_debug_presets.gd")

var _layer:   CanvasLayer
var _overlay: DebugDraw
var _weather_preset_panel: Control
var _shown:   bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer              = CanvasLayer.new()
	_layer.layer        = 100
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_overlay              = DebugDraw.new()
	_overlay.name         = "DebugDraw"
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible      = false
	_layer.add_child(_overlay)

	_weather_preset_panel          = _WEATHER_PANEL.new()
	_weather_preset_panel.name    = "WeatherDebugPresets"
	_weather_preset_panel.visible = false
	_layer.add_child(_weather_preset_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.physical_keycode == KEY_F3:
			_shown           = not _shown
			_overlay.visible = _shown
			if not _shown:
				_weather_preset_panel.visible = false
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_F4 and _shown:
			_weather_preset_panel.visible = not _weather_preset_panel.visible
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_E and _shown:
			_apply_debug_day_calm_preset()
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_F5 and _shown:
			_spawn_debug_local_contract()
			get_viewport().set_input_as_handled()


## Spawn an auto-accepted same-port contract at the port nearest the player.
## Pickup and dropoff are at the same dock so the crane can be exercised
## without sailing anywhere.
func _spawn_debug_local_contract() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var player_pos := player.global_position
	var nearest_id := ""
	var nearest_d := INF
	for pid in registry.call("get_port_ids"):
		var pos: Vector3 = registry.call("get_port_position", pid)
		if pos.x == INF:
			continue
		var d := player_pos.distance_to(pos)
		if d < nearest_d:
			nearest_d = d
			nearest_id = pid
	if nearest_id.is_empty():
		return
	registry.call("debug_spawn_local_contract", nearest_id)


func _apply_debug_day_calm_preset() -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl != null:
		wl.automatic_time_enabled = false
		wl.apply_weather_state(WeatherState.create_clear_calm())

	WorldWeather.set_blend_to_lighting_paused(true)

	var wc := get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("snap_time_of_day"):
		wc.snap_time_of_day(0.5)
