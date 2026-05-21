class_name ShipwrightPreview
extends Node3D

## Visual-only hull + bridge for the shipwright catalog SubViewport.

const SUPER_MODEL_DIR := "res://resources/data/models/superstructures/"
const SUPER_OFFSET := Vector3(0.0, -0.3, -1.0)

var _pivot: Node3D
var _spin_enabled: bool = true
## Turntable angle — kept when swapping catalog entries so Next/Prev does not reset spin.
var _display_yaw: float = 0.0


func _process(delta: float) -> void:
	if not _spin_enabled:
		return
	_display_yaw += delta * 0.38
	if _pivot != null:
		_pivot.rotation.y = _display_yaw


func show_entry(entry: Dictionary) -> HullStations:
	_clear_models()
	var hull_path := ShipBuilder.HULL_BASE_DIR + str(entry.get("hull_file", ""))
	var hull_data := ShipBuilder._load_json(hull_path)
	var stations := HullStations.from_hull_json(hull_data, 10)
	var slots := _read_slots(hull_data, 1.0)

	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = "Pivot"
		add_child(_pivot)
	_pivot.rotation.y = _display_yaw

	var hull_asm := ModelAssembler.new()
	hull_asm.name = "HullVisuals"
	hull_asm.build_part_colliders = false
	hull_asm.model_data_path = hull_path
	_pivot.add_child(hull_asm)

	var super_key := str(entry.get("superstructure", ""))
	if not super_key.is_empty() and slots.has("bridge"):
		var super_node := _build_superstructure(super_key)
		if super_node != null:
			super_node.position = slots["bridge"] + SUPER_OFFSET
			_pivot.add_child(super_node)

	return stations


func clear() -> void:
	_clear_models()
	_spin_enabled = true


func _clear_models() -> void:
	if _pivot != null:
		for child in _pivot.get_children():
			child.queue_free()


func set_spin_enabled(enabled: bool) -> void:
	_spin_enabled = enabled


static func camera_transform_for_length(length_m: float) -> Transform3D:
	var len_m := maxf(length_m, 10.0)
	# Between the old far shot and the tight close-up — fills the frame without clipping.
	var dist := len_m * 0.95 + 9.0
	var height := len_m * 0.28 + 3.5
	var cam_pos := Vector3(dist * 0.48, height, dist * 0.72)
	var target := Vector3(0.0, len_m * 0.11, 0.0)
	var xf := Transform3D.IDENTITY
	xf.origin = cam_pos
	return xf.looking_at(target, Vector3.UP)


static func _read_slots(hull_data: Dictionary, scale: float) -> Dictionary:
	var out: Dictionary = {}
	if not hull_data.has("slots"):
		return out
	var raw = hull_data["slots"]
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key in raw.keys():
		var v = raw[key]
		if typeof(v) == TYPE_ARRAY and v.size() >= 3:
			out[key] = Vector3(float(v[0]), float(v[1]), float(v[2])) * scale
	return out


static func _build_superstructure(key: String) -> Node3D:
	var json_path := SUPER_MODEL_DIR + key + ".json"
	if not FileAccess.file_exists(json_path):
		return null
	var root := Node3D.new()
	var visuals := ModelAssembler.new()
	visuals.name = "BridgeVisuals"
	visuals.build_part_colliders = false
	visuals.model_data_path = json_path
	root.add_child(visuals)
	return root
