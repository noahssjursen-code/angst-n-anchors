class_name ShipLighting
extends Node

## Ship lighting component. Attach as child of BoatBody.
## L key cycles presets: OFF → NAV → WORK → ALL.
## Nav lights auto-activate at night or in fog unless preset is OFF.

signal preset_changed(preset_name: String)

enum Preset { OFF = 0, NAV = 1, WORK = 2, ALL = 3 }

const PRESET_NAMES: Array[String] = ["OFF", "NAV", "WORK", "ALL"]

var _preset: int = Preset.NAV
var _auto_nav_active: bool = false
var _tick: float = 0.0

var _nav_lights:    Array[Light3D] = []
var _work_lights:   Array[Light3D] = []
var _window_lights: Array[Light3D] = []


func _ready() -> void:
	call_deferred("_build_lights")


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

	# Auto-override: nav lights come on at night/fog even in non-nav presets,
	# but respect OFF — if the captain switched them off, leave them off.
	if _auto_nav_active and _preset != Preset.OFF:
		nav_on = true

	_set_group(_nav_lights,    nav_on)
	_set_group(_work_lights,   work_on)
	_set_group(_window_lights, window_on)


func _set_group(lights: Array[Light3D], on: bool) -> void:
	for light in lights:
		if is_instance_valid(light):
			light.visible = on


func _build_lights() -> void:
	var boat := get_parent() as BoatBody
	if boat == null:
		return

	var hs := boat.hull_size
	var hc := boat.hull_center

	# --- Navigation lights ---
	# Port (red) — left side when facing bow (+Z)
	_nav_lights.append(_omni(
		hc + Vector3(-hs.x * 0.48, hs.y * 0.5 + 0.4, hs.z * 0.25),
		Color(1.0, 0.05, 0.05), 8.0, 5.0, 3.0
	))
	# Starboard (green) — right side
	_nav_lights.append(_omni(
		hc + Vector3( hs.x * 0.48, hs.y * 0.5 + 0.4, hs.z * 0.25),
		Color(0.05, 1.0, 0.15), 8.0, 5.0, 3.0
	))
	# Masthead (white) — high on the mast, forward arc
	_nav_lights.append(_omni(
		hc + Vector3(0.0, hs.y * 0.5 + 4.0, hs.z * 0.15),
		Color(1.0, 1.0, 0.95), 14.0, 6.0, 4.0
	))
	# Stern (white) — low aft
	_nav_lights.append(_omni(
		hc + Vector3(0.0, hs.y * 0.5 + 0.8, -hs.z * 0.46),
		Color(1.0, 1.0, 0.95), 10.0, 4.0, 2.5
	))

	# --- Work lights (deck floods) ---
	_work_lights.append(_spot_down(
		hc + Vector3(0.0, hs.y * 0.5 + 2.5, hs.z * 0.15),
		16.0, 12.0, 55.0
	))
	_work_lights.append(_spot_down(
		hc + Vector3(0.0, hs.y * 0.5 + 2.5, -hs.z * 0.2),
		14.0, 10.0, 50.0
	))

	# --- Window / cabin lights ---
	_window_lights.append(_omni(
		hc + Vector3(0.0, hs.y * 0.5 + 1.2, hs.z * 0.1),
		Color(1.0, 0.80, 0.50), 6.0, 1.5, 0.4
	))

	_apply_preset()


func _omni(pos: Vector3, color: Color, range_m: float, energy: float, vol_energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position                   = pos
	light.light_color                = color
	light.omni_range                 = range_m
	light.light_energy               = energy
	light.light_volumetric_fog_energy = vol_energy
	light.shadow_enabled             = false
	light.visible                    = false
	add_child(light)
	return light


func _spot_down(pos: Vector3, range_m: float, energy: float, angle_deg: float) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position                   = pos
	light.rotation_degrees           = Vector3(-90.0, 0.0, 0.0)  # -Z default → -Y (down)
	light.light_color                = Color(1.0, 0.97, 0.90)
	light.spot_range                 = range_m
	light.light_energy               = energy
	light.spot_angle                 = angle_deg
	light.spot_angle_attenuation     = 1.0
	light.shadow_enabled             = false
	light.visible                    = false
	add_child(light)
	return light
