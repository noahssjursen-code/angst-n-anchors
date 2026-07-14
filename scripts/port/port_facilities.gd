@tool
class_name PortFacilities
extends Node3D

## Land-side port shell. Ports deliberately start empty: only stable service
## slots and the lighthouse/fog-horn landmarks exist. Slot positions and optional
## building JSON bindings come from PortServiceSlotCatalog (authored by
## PortSlotEditor). Per-plot service_blueprint_ids can still override a slot.

const FOGHORN_SCENE := preload("res://scenes/systems/fog_horn_building.tscn")
const LIGHTHOUSE_SCENE := preload("res://scenes/systems/lighthouse_building.tscn")

const PLACES_PER_FRAME := 1

@export var port_size: int = 1:
	set(value):
		port_size = value
		if is_inside_tree():
			_rebuild()

@export var plot_width: float = PortSizing.island_width_m(1):
	set(value):
		plot_width = value
		if is_inside_tree():
			_rebuild()

@export var plot_depth: float = PortSizing.facilities_depth_m(PortSizing.DOCK_INLAND_DEPTH_M):
	set(value):
		plot_depth = value
		if is_inside_tree():
			_rebuild()

@export var layout_seed: int = 0

@export var has_lighthouse: bool = false:
	set(value):
		has_lighthouse = value
		if is_inside_tree():
			_rebuild()

@export var has_fog_horn: bool = false:
	set(value):
		has_fog_horn = value
		if is_inside_tree():
			_rebuild()

## Colored authoring pads (slot editor only). Game ports leave this off —
## buildings and NPC anchors still come from the slot catalog.
@export var show_service_slots: bool = false:
	set(value):
		show_service_slots = value
		if is_inside_tree():
			_rebuild()

## Optional service_id -> building JSON stem overrides. When a key is present it
## wins over the catalog binding (empty string clears that slot's building).
@export var service_blueprint_ids: Dictionary = {}

## Editor draft slots. Empty means load PortServiceSlotCatalog.
var _slots_override: Array[Dictionary] = []

var _place_queue: Array[Callable] = []


func _ready() -> void:
	_rebuild()


func _exit_tree() -> void:
	_place_queue.clear()


func is_build_complete() -> bool:
	return _place_queue.is_empty()


func apply_slots(slots: Array) -> void:
	_slots_override.clear()
	for entry in slots:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_slots_override.append((entry as Dictionary).duplicate(true))
	if is_inside_tree():
		_rebuild()


func clear_slot_override() -> void:
	_slots_override.clear()
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	_place_queue.clear()
	set_process(false)
	for child in get_children():
		child.free()

	for slot in _iter_slots():
		var service_id := str(slot.get("id", "")).strip_edges()
		if service_id.is_empty():
			continue
		# Colored pads are editor-only authoring helpers, not gameplay scenery.
		if show_service_slots:
			_place_queue.append(_add_service_marker.bind(service_id, slot))
		var blueprint_id := _blueprint_for(service_id, slot)
		if not blueprint_id.is_empty():
			var yaw_degrees := float(slot.get("yaw_degrees", 0.0))
			_place_queue.append(_add_service_blueprint.bind(service_id, blueprint_id, yaw_degrees))
	if has_fog_horn:
		_place_queue.append(_add_fog_horn)
	if has_lighthouse:
		_place_queue.append(_add_lighthouse)

	if Engine.is_editor_hint():
		_flush_queue()
		_own_generated_children()
	elif not _place_queue.is_empty():
		set_process(true)


func _process(_delta: float) -> void:
	for _index in range(PLACES_PER_FRAME):
		if _place_queue.is_empty():
			set_process(false)
			return
		var job: Callable = _place_queue.pop_front()
		job.call()


func _flush_queue() -> void:
	while not _place_queue.is_empty():
		var job: Callable = _place_queue.pop_front()
		job.call()


func _iter_slots() -> Array[Dictionary]:
	if not _slots_override.is_empty():
		var out: Array[Dictionary] = []
		for slot in _slots_override:
			out.append(slot.duplicate(true))
		return out
	return PortServiceSlotCatalog.slots()


func _blueprint_for(service_id: String, slot: Dictionary) -> String:
	if service_blueprint_ids.has(service_id):
		return str(service_blueprint_ids[service_id]).strip_edges()
	return str(slot.get("blueprint_id", "")).strip_edges()


func service_slot(service_id: String) -> Dictionary:
	for slot in _iter_slots():
		if str(slot.get("id", "")) == service_id:
			return slot.duplicate(true)
	return {}


func service_slot_local_position(service_id: String) -> Vector3:
	var slot := service_slot(service_id)
	var position: Variant = slot.get("position", Vector3.ZERO)
	if position is Vector3:
		return position as Vector3
	if position is Array:
		var arr := position as Array
		return Vector3(
			float(arr[0]) if arr.size() > 0 else 0.0,
			float(arr[1]) if arr.size() > 1 else 0.0,
			float(arr[2]) if arr.size() > 2 else 0.0,
		)
	return Vector3.ZERO


func set_service_blueprint(service_id: String, blueprint_id: String) -> void:
	if service_slot(service_id).is_empty():
		return
	if blueprint_id.is_empty():
		service_blueprint_ids.erase(service_id)
	else:
		service_blueprint_ids[service_id] = blueprint_id
	if is_inside_tree():
		_rebuild()


func get_spawn_position() -> Vector3:
	return to_global(service_slot_local_position("harbour_master") + Vector3(0.0, 0.02, -6.0))


func get_harbour_master_local_pos() -> Vector3:
	return service_slot_local_position("harbour_master")


func get_contract_npc_local_pos() -> Vector3:
	return service_slot_local_position("contractor")


func get_shipwright_local_pos() -> Vector3:
	return service_slot_local_position("shipwright")


func get_company_office_local_pos() -> Vector3:
	return Vector3.ZERO


func _add_service_marker(service_id: String, slot: Dictionary) -> void:
	if slot.is_empty():
		return
	var position := _as_vector3(slot.get("position", Vector3.ZERO))
	var footprint := _as_vector3(slot.get("footprint", Vector3(8.0, 0.12, 8.0)))
	var color := _as_color(slot.get("color", Color(0.35, 0.35, 0.35)))
	var body := StaticBody3D.new()
	body.name = "%sSlot" % service_id.to_pascal_case()
	body.position = position
	body.rotation_degrees.y = float(slot.get("yaw_degrees", 0.0))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Pad"
	var mesh := BoxMesh.new()
	mesh.size = footprint
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh_instance.material_override = material
	mesh_instance.position.y = footprint.y * 0.5
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = footprint
	collision.shape = shape
	collision.position.y = footprint.y * 0.5
	body.add_child(collision)

	var post := MeshInstance3D.new()
	post.name = "MarkerPost"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 1.8, 0.16)
	post.mesh = post_mesh
	post.material_override = material
	post.position = Vector3(0.0, 0.9, footprint.z * 0.5 - 0.4)
	body.add_child(post)

	var label := Label3D.new()
	label.name = "Label"
	label.text = str(slot.get("display_name", service_id.to_upper()))
	label.font_size = 34
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.1, footprint.z * 0.5 - 0.4)
	body.add_child(label)
	add_child(body)


func _add_service_blueprint(service_id: String, blueprint_id: String, yaw_degrees: float = 0.0) -> void:
	var building := BuildingBlueprintCatalog.build(blueprint_id)
	if building == null:
		push_warning("PortFacilities: building blueprint '%s' was not found." % blueprint_id)
		return
	building.name = "%sBuilding" % service_id.to_pascal_case()
	building.position = service_slot_local_position(service_id)
	building.rotation_degrees.y = yaw_degrees
	add_child(building)


func _add_lighthouse() -> void:
	var building := LIGHTHOUSE_SCENE.instantiate()
	building.name = "LighthouseBuilding"
	building.position = Vector3(0.0, 0.0, plot_depth - 8.0)
	building.scale = Vector3(2.0, 2.0, 2.0)
	add_child(building)


func _add_fog_horn() -> void:
	var edge_x := maxf(plot_width * 0.5 - 6.0, 8.0)
	var side := -1.0 if posmod(layout_seed, 2) == 0 else 1.0
	var building := FOGHORN_SCENE.instantiate()
	building.name = "FogHornBuilding"
	building.position = Vector3(side * edge_x, 0.0, 2.0)
	building.rotation.y = PI
	add_child(building)


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var arr := value as Array
		return Vector3(
			float(arr[0]) if arr.size() > 0 else 0.0,
			float(arr[1]) if arr.size() > 1 else 0.0,
			float(arr[2]) if arr.size() > 2 else 0.0,
		)
	return Vector3.ZERO


func _as_color(value: Variant) -> Color:
	if value is Color:
		return value as Color
	if value is Array:
		var arr := value as Array
		return Color(
			float(arr[0]) if arr.size() > 0 else 0.4,
			float(arr[1]) if arr.size() > 1 else 0.4,
			float(arr[2]) if arr.size() > 2 else 0.4,
		)
	return Color(0.4, 0.4, 0.4)


func _own_generated_children() -> void:
	if get_tree() == null or get_tree().edited_scene_root == null:
		return
	for child in get_children():
		_own_subtree(child, get_tree().edited_scene_root)


func _own_subtree(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for child in node.get_children():
		_own_subtree(child, scene_owner)
