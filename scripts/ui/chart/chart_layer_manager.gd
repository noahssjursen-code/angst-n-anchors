class_name ChartLayerManager
extends RefCounted

enum Preset { HARBOUR, COASTAL, PASSAGE, WEATHER }

const PRESET_NAMES: Array[String] = ["Harbour", "Coastal", "Passage", "Weather"]
const LAYER_ORDER: Array[String] = [
	"base", "fishing", "weather", "routes", "approaches",
	"traffic", "nav_vectors", "annotations",
]

var preset := Preset.COASTAL
var revision := 0
var _layers: Dictionary = {}


func _init() -> void:
	apply_preset(Preset.COASTAL)


func apply_preset(next_preset: int) -> void:
	preset = next_preset
	match preset:
		Preset.HARBOUR:
			_layers = _make_layers(true, false, false, true, true, true, true, true)
		Preset.COASTAL:
			_layers = _make_layers(true, false, false, true, false, true, true, true)
		Preset.PASSAGE:
			_layers = _make_layers(true, false, false, true, false, true, true, false)
		Preset.WEATHER:
			_layers = _make_layers(true, false, true, true, false, false, true, false)
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


static func _make_layers(
	base: bool,
	fishing: bool,
	weather: bool,
	routes: bool,
	approaches: bool,
	traffic: bool,
	nav_vectors: bool,
	annotations: bool,
) -> Dictionary:
	return {
		"base": base,
		"fishing": fishing,
		"weather": weather,
		"routes": routes,
		"approaches": approaches,
		"traffic": traffic,
		"nav_vectors": nav_vectors,
		"annotations": annotations,
	}
