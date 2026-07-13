class_name ChartLayerManager
extends RefCounted

## Shared chart state. Navigation/Harbour are display profiles; Weather and
## Fishing are independent overlays and may be enabled together.

enum Preset { NAVIGATION, WEATHER, FISHING, HARBOUR }

const PRESET_NAMES: Array[String] = ["Navigation", "Weather", "Fishing", "Harbour"]
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
	"traffic": false,
	"nav_vectors": true,
	"annotations": true,
}


func _init() -> void:
	apply_preset(Preset.NAVIGATION)


func apply_preset(next_preset: int) -> void:
	preset = clampi(next_preset, Preset.NAVIGATION, Preset.HARBOUR)
	match preset:
		Preset.WEATHER:
			_layers["weather"] = true
		Preset.FISHING:
			_layers["fishing"] = true
		Preset.HARBOUR:
			_layers["routes"] = true
			_layers["approaches"] = true
			_layers["annotations"] = true
		_:
			_layers["routes"] = true
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
