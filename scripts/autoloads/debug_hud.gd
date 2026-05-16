extends Node

## Autoload — owns the F3 debug overlay (+ F4 weather preset panel while open).
## Layer 100: always above every other UI element.

const _WEATHER_PANEL := preload("res://scripts/ui/weather_debug_presets.gd")

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
