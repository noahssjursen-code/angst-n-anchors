extends Node

## Autoload — owns the F3 debug overlay. F4 weather presets + E midday/calm while panel is open.
## Layer 100: always above every other UI element.

signal visibility_changed(visible: bool)

const _WEATHER_PANEL := preload("res://scripts/weather/weather_debug_presets.gd")

var _layer:   CanvasLayer
var _overlay: DebugDraw
var _weather_preset_panel: Control
var _shown:   bool = false


func is_open() -> bool:
	return _shown


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
			visibility_changed.emit(_shown)
			_refresh_lane_debug_draw()
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_F4 and _shown:
			_weather_preset_panel.visible = not _weather_preset_panel.visible
			get_viewport().set_input_as_handled()
		elif ke.pressed and not ke.echo and ke.physical_keycode == KEY_E and _shown:
			_apply_debug_day_calm_preset()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _shown:
		return
	if not event is InputEventKey:
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	match ke.physical_keycode:
		KEY_O:
			AutonomousSimDebug.adjust_speed(-1)
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
		KEY_I:
			AutonomousSimDebug.adjust_speed(1)
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
		KEY_B:
			BerthApproachLanes.toggle_debug()
			_refresh_lane_debug_draw()
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()


func _apply_debug_day_calm_preset() -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl != null:
		wl.automatic_time_enabled = false
		wl.apply_weather_state(WeatherState.create_clear_calm())

	WorldWeather.set_blend_to_lighting_paused(true)

	var wc := get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("snap_time_of_day"):
		wc.snap_time_of_day(0.5)


func _refresh_lane_debug_draw() -> void:
	var mgr := get_node_or_null("/root/AutonomousVesselManager")
	if mgr != null and mgr.has_method("refresh_lane_debug"):
		mgr.call("refresh_lane_debug")
