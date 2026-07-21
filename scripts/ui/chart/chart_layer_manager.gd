class_name ChartLayerManager
extends RefCounted

## Shared chart state. Navigation is the display profile; Weather and Fishing
## are independent overlays and may be enabled together.

enum Preset { NAVIGATION, WEATHER, FISHING }
## Legacy saved `chart_profile` value for the removed Harbour tab.
const LEGACY_HARBOUR_PROFILE := 3

const PRESET_NAMES: Array[String] = ["Navigation", "Weather", "Fishing"]
const LAYER_ORDER: Array[String] = [
	"base", "weather", "fishing", "routes", "approaches",
	"traffic", "nav_vectors", "annotations",
]

var preset := Preset.NAVIGATION
var revision := 0
var _layers: Dictionary = {
	"base": true,
	"weather": false,
	"fishing": false,
	"routes": true,
	"approaches": false,
	"traffic": true,
	"nav_vectors": true,
	"annotations": true,
}


func _init() -> void:
	apply_preset(Preset.NAVIGATION)


func apply_preset(next_preset: int) -> void:
	## Old saves may still store Harbour (3) — fold into Navigation.
	if next_preset == LEGACY_HARBOUR_PROFILE:
		next_preset = Preset.NAVIGATION
	preset = clampi(next_preset, Preset.NAVIGATION, Preset.FISHING)
	match preset:
		Preset.WEATHER:
			_layers["weather"] = true
		Preset.FISHING:
			_layers["fishing"] = true
		_:
			_layers["routes"] = true
			_layers["traffic"] = true
			_layers["approaches"] = false
			_layers["annotations"] = true
	revision += 1


func is_visible(layer_name: String) -> bool:
	return bool(_layers.get(layer_name, false))


func set_visible(layer_name: String, shown: bool) -> void:
	if not LAYER_ORDER.has(layer_name) or is_visible(layer_name) == shown:
		return
	_layers[layer_name] = shown
	revision += 1


func toggle(layer_name: String) -> bool:
	set_visible(layer_name, not is_visible(layer_name))
	return is_visible(layer_name)


func cache_key() -> String:
	var bits := PackedStringArray()
	for layer_name in LAYER_ORDER:
		bits.append("1" if is_visible(layer_name) else "0")
	return "%d:%s" % [preset, "".join(bits)]


func snapshot() -> Dictionary:
	return _layers.duplicate()


func set_overlay_preferences(weather_on: bool, fishing_on: bool) -> void:
	set_visible("weather", weather_on)
	set_visible("fishing", fishing_on)
