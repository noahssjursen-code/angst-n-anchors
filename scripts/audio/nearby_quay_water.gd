extends Node3D
## One harbour-water voice, placed on the nearest quay face.
## A foghorn building does not have to exist for the quay to be heard.


var _water: AudioStreamPlayer3D
var _face := Vector3.ZERO
var _found := false
var _search := 0.0


func _process(delta: float) -> void:
	var host := get_viewport().get_camera_3d() as Node3D
	if host == null:
		return
	if _water == null:
		_water = WorldSound.loop_on(self, "res://resources/audio/world/water/quay_lap_1.wav", "NearbyQuayWater")
		if _water != null:
			_water.top_level = true
	_search -= delta
	if _search <= 0.0:
		_search = 0.45
		_found = _nearest_face(host)
	if _water == null:
		return
	if not _found:
		WorldSound.drive(_water, 0.0, -16.0)
		return
	_water.global_position = _face
	WorldSound.drive(_water, 1.0, -16.0)


func _nearest_face(host: Node3D) -> bool:
	var best := 32.0
	var found := false
	for node in host.get_tree().get_nodes_in_group("quay_berth_slot"):
		var slot := node as QuayBerthSlot
		if slot == null or not slot.is_inside_tree():
			continue
		var water := slot.water_dir_local
		if water.length_squared() < 0.0001:
			continue
		var face := slot.to_global(water.normalized() * slot.face_offset_m)
		face.y = WaveSurface.WATER_LEVEL
		var distance := host.global_position.distance_to(face)
		if distance < best:
			best = distance
			_face = face
			found = true
	return found
