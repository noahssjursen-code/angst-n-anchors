class_name OreMound
extends Node3D

## Bulk stockpile pickup source — visual size stays fixed; bucket draws material on proximity.

@export var commodity_id := "iron_ore"
@export var pickup_radius_m := 7.0

var _size := Vector3.ONE
var _visual: Node3D
var _seed := 0


static func create(commodity_id_in: String, size: Vector3, seed: int = 0) -> OreMound:
	var mound := OreMound.new()
	mound.commodity_id = OreMoundBuilder.resolve_commodity(commodity_id_in)
	mound._size = size
	mound._seed = seed
	mound.name = "OreMound_%s" % mound.commodity_id
	mound._rebuild_visual()
	mound.add_to_group("ore_mound")
	return mound


func _rebuild_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = OreMoundBuilder.build_mound(commodity_id, _size, _seed)
	add_child(_visual)


func pickup_global() -> Vector3:
	return global_position + Vector3(0.0, _size.y * 0.42, 0.0)


func take(tonnes_t: float) -> float:
	## Returns tonnes offered — mound visuals stay fixed.
	if tonnes_t <= 0.0:
		return 0.0
	return tonnes_t
