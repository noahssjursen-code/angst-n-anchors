@tool
class_name ShipwrightPreview
extends Node3D

## Visual-only hull + bridge for the shipwright catalog SubViewport.

const SUPER_OFFSET := ShipBuilder.SUPERSTRUCTURE_OFFSET
const _DeckGridOverlay := preload("res://scripts/ship/deck_grid_visualizer.gd")

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
	var hull_data := JsonUtil.load(hull_path)
	var stations := HullStations.from_hull_json(hull_data, 10)
	var scale := ShipBuilder.HULL_WORLD_SCALE
	var slots := _read_slots(hull_data, scale)

	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = "Pivot"
		add_child(_pivot)
	_pivot.rotation.y = _display_yaw

	var frame := Node3D.new()
	frame.name = "ShipFrame"
	frame.rotation.y = ShipBuilder.SHIP_FRAME_Y_ROT
	_pivot.add_child(frame)

	var hull_asm := ModelAssembler.new()
	hull_asm.name = "HullVisuals"
	hull_asm.build_part_colliders = false
	hull_asm.absolute_scale = scale
	hull_asm.model_data_path = hull_path
	frame.add_child(hull_asm)

	var super_key := str(entry.get("superstructure", ""))
	if not super_key.is_empty() and slots.has("bridge"):
		var scene_path := ShipBuilder.SUPER_SCENE_DIR + super_key + ".tscn"
		if ResourceLoader.exists(scene_path):
			var super_node := ShipBuilder.instantiate_superstructure(super_key)
			if super_node != null:
				super_node.name = "Superstructure"
				var local_pos: Vector3 = slots["bridge"] + SUPER_OFFSET * scale
				super_node.position = local_pos.rotated(
					Vector3.UP, ShipBuilder.HULL_AUTHORED_Y_ROT
				)
				super_node.rotation.y = ShipBuilder.HULL_AUTHORED_Y_ROT
				frame.add_child(super_node)

	_DeckGridOverlay.attach(frame, stations, scale, slots, entry, hull_data)

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
