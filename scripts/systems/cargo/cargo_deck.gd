class_name CargoDeck
extends Node3D

@export var grid_size: Vector3i = Vector3i(4, 2, 3):
	set(v):
		grid_size = Vector3i(maxi(v.x, 1), maxi(v.y, 1), maxi(v.z, 1))
		if is_node_ready():
			_rebuild_load_area()

@export var slot_size: Vector3 = Vector3(0.9, 0.85, 0.9):
	set(v):
		slot_size = Vector3(maxf(v.x, 0.1), maxf(v.y, 0.1), maxf(v.z, 0.1))
		if is_node_ready():
			_rebuild_load_area()

@export var deck_origin: Vector3 = Vector3.ZERO:
	set(v):
		deck_origin = v
		if is_node_ready():
			_rebuild_load_area()
			_rebuild_visuals()

@export var load_zone_extra: Vector3 = Vector3(0.6, 1.4, 0.6)

var cargo_entries: Array[Resource] = []

var _load_area: Area3D
var _visual_root: Node3D


func _ready() -> void:
	_ensure_nodes()
	_rebuild_load_area()
	_rebuild_visuals()


func try_load_cargo(data: Resource) -> bool:
	if data == null or is_full():
		return false
	cargo_entries.append(data.call("duplicate_data") as Resource)
	_spawn_cargo_visual(cargo_entries.size() - 1, data)
	return true


func is_full() -> bool:
	return cargo_entries.size() >= capacity()


func capacity() -> int:
	return grid_size.x * grid_size.y * grid_size.z


func get_cargo_count() -> int:
	return cargo_entries.size()


func clear_cargo() -> void:
	cargo_entries.clear()
	_rebuild_visuals()


func _ensure_nodes() -> void:
	_load_area = get_node_or_null("LoadArea") as Area3D
	if _load_area == null:
		_load_area = Area3D.new()
		_load_area.name = "LoadArea"
		add_child(_load_area)

	_visual_root = get_node_or_null("CargoVisuals") as Node3D
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = "CargoVisuals"
		add_child(_visual_root)


func _rebuild_load_area() -> void:
	_ensure_nodes()
	for child in _load_area.get_children():
		child.queue_free()

	var shape := BoxShape3D.new()
	shape.size = _grid_world_size() + load_zone_extra

	var collision := CollisionShape3D.new()
	collision.name = "LoadAreaShape"
	collision.shape = shape
	_load_area.add_child(collision)
	_load_area.position = deck_origin + Vector3.UP * (shape.size.y * 0.5)


func _rebuild_visuals() -> void:
	_ensure_nodes()
	for child in _visual_root.get_children():
		child.queue_free()
	for i in range(cargo_entries.size()):
		_spawn_cargo_visual(i, cargo_entries[i])


func _spawn_cargo_visual(index: int, data: Resource) -> void:
	_ensure_nodes()
	if index < 0 or index >= capacity() or data == null:
		return
	var visual := data.call("make_crate_visual") as MeshInstance3D
	if visual == null:
		return
	visual.name = "CargoSlot_%03d_%s" % [index, str(data.get("cargo_id"))]
	visual.position = _slot_position(index)
	_visual_root.add_child(visual)


func _slot_position(index: int) -> Vector3:
	var layer_size := grid_size.x * grid_size.z
	var y := floori(float(index) / float(layer_size))
	var layer_index := index % layer_size
	var z := floori(float(layer_index) / float(grid_size.x))
	var x := layer_index % grid_size.x

	var x_offset := (float(x) - float(grid_size.x - 1) * 0.5) * slot_size.x
	var y_offset := float(y) * slot_size.y + slot_size.y * 0.5
	var z_offset := (float(z) - float(grid_size.z - 1) * 0.5) * slot_size.z
	return deck_origin + Vector3(x_offset, y_offset, z_offset)


func _grid_world_size() -> Vector3:
	return Vector3(
		float(grid_size.x) * slot_size.x,
		float(grid_size.y) * slot_size.y,
		float(grid_size.z) * slot_size.z
	)
