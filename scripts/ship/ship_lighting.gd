class_name ShipLighting
extends Node

## Preset controller for ship lights. Discovers ShipLight nodes placed under the parent
## BoatBody and drives them via set_active(). L key cycles presets (wired in BoatController).
## Nav lights auto-activate at night or in fog unless preset is OFF.

signal preset_changed(preset_name: String)

enum Preset { OFF = 0, NAV = 1, WORK = 2, ALL = 3 }

const PRESET_NAMES: Array[String] = ["OFF", "NAV", "WORK", "ALL"]

var _preset: int = Preset.NAV
var _auto_nav_active: bool = false
var _tick: float = 0.0

var _nav_lights:    Array[Node] = []
var _work_lights:   Array[Node] = []
var _window_lights: Array[Node] = []


func _ready() -> void:
	call_deferred("_gather_lights")


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_update_auto_nav()


func cycle_preset() -> void:
	_preset = (_preset + 1) % 4
	_apply_preset()
	preset_changed.emit(PRESET_NAMES[_preset])


func get_preset_name() -> String:
	return PRESET_NAMES[_preset]


func _gather_lights() -> void:
	_nav_lights.clear()
	_work_lights.clear()
	_window_lights.clear()

	var boat := get_parent() as BoatBody
	if boat == null:
		return

	for node in get_tree().get_nodes_in_group(ShipLight.GROUP):
		if not boat.is_ancestor_of(node):
			continue
		var sl := node as ShipLight
		if sl == null:
			continue
		match sl.light_type:
			ShipLight.LightType.NAV_PORT, ShipLight.LightType.NAV_STARBOARD, \
			ShipLight.LightType.NAV_MASTHEAD, ShipLight.LightType.NAV_STERN:
				_nav_lights.append(sl)
			ShipLight.LightType.WORK:
				_work_lights.append(sl)
			ShipLight.LightType.WINDOW:
				_window_lights.append(sl)

	_apply_preset()


func _update_auto_nav() -> void:
	var weather := get_node_or_null("/root/WeatherLighting")
	if weather == null:
		return
	var tod := float(weather.get("time_of_day"))
	var fog := float(weather.get("fog_density"))

	var dist_from_noon := absf(tod - 0.5)
	var is_night       := smoothstep(0.15, 0.35, dist_from_noon) > 0.5
	var is_foggy       := fog > 0.25

	var should_auto := is_night or is_foggy
	if should_auto != _auto_nav_active:
		_auto_nav_active = should_auto
		_apply_preset()


func _apply_preset() -> void:
	var nav_on    := false
	var work_on   := false
	var window_on := false

	match _preset:
		Preset.OFF:
			pass
		Preset.NAV:
			nav_on    = true
			window_on = true
		Preset.WORK:
			work_on   = true
			window_on = true
		Preset.ALL:
			nav_on    = true
			work_on   = true
			window_on = true

	if _auto_nav_active and _preset != Preset.OFF:
		nav_on = true

	_set_group(_nav_lights,    nav_on)
	_set_group(_work_lights,   work_on)
	_set_group(_window_lights, window_on)


func _set_group(lights: Array[Node], on: bool) -> void:
	for light in lights:
		if is_instance_valid(light):
			light.call("set_active", on)
