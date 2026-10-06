@tool
class_name ShipwrightPreview
extends Node3D

## Visual-only vessel preview for the shipwright catalog SubViewport.

var _pivot: Node3D
var _spin_enabled: bool = true
var _display_yaw: float = 0.0


func _process(delta: float) -> void:
	if not _spin_enabled:
		return
	_display_yaw += delta * 0.38
	if _pivot != null:
		_pivot.rotation.y = _display_yaw


func show_entry(entry: Dictionary, brick_layout: Dictionary = {}) -> HullStations:
	_clear_models()
	var hull_id := str(entry.get("hull_id", entry.get("id", "fishing_trawler_small")))
	var loa := float(entry.get("loa_m", 28.0))
	var beam := float(entry.get("beam_m", 10.0))
	var depth := float(entry.get("depth_m", 5.6))
	var stations: HullStations = HullStations.from_box(loa, beam, depth, 10)

	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = "Pivot"
		add_child(_pivot)
	_pivot.rotation.y = _display_yaw

	if ImportedHullCatalog.has(hull_id):
		var imported := VesselSpawn.instantiate(hull_id, brick_layout)
		if imported != null:
			imported.name = "PreviewBoat"
			imported.freeze = true
			imported.process_mode = Node.PROCESS_MODE_DISABLED
			_pivot.add_child(imported)
		return stations

	var boat := HullRegistry.build_hull(hull_id)
	boat.name = "PreviewBoat"
	boat.freeze = true
	# Skip deferred fit-out; catalog explicitly chooses bare or ready-built.
	boat.set_meta("fitout_applied", true)
	DeckFitout.clear(boat)
	for child_name in ["BoatController", "BoatCamera", "ShipLighting", "BoatAudio"]:
		var n := boat.get_node_or_null(child_name)
		if n != null:
			n.queue_free()
	_pivot.add_child(boat)
	if not brick_layout.is_empty():
		DeckFitout.apply(boat, BrickLayout.from_dict(brick_layout))
	return stations


static func camera_transform_for_length(length_m: float) -> Transform3D:
	var len_m := maxf(length_m, 10.0)
	var dist := len_m * 0.95 + 9.0
	var height := len_m * 0.28 + 3.5
	var cam_pos := Vector3(dist * 0.48, height, dist * 0.72)
	var target := Vector3(0.0, len_m * 0.11, 0.0)
	var xf := Transform3D.IDENTITY
	xf.origin = cam_pos
	return xf.looking_at(target, Vector3.UP)


func set_spin_enabled(enabled: bool) -> void:
	_spin_enabled = enabled


func set_show_cargo_decks(_show: bool) -> void:
	pass


func clear() -> void:
	_clear_models()
	_spin_enabled = true


func _clear_models() -> void:
	if _pivot == null:
		return
	for child in _pivot.get_children():
		child.queue_free()
