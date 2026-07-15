class_name PortPlacedModule
extends RefCounted

## One concrete module in a PortLayoutGraph.

var instance_id := ""
var module_id := ""
var parent_instance_id := ""
var parent_slot_id := ""
var input_slot_id := ""
var position_m := Vector3.ZERO
var yaw_degrees := 0.0
var assignment: Dictionary = {}
var consumed_slots: Array[String] = []


func consumes(slot_id: String) -> bool:
	return consumed_slots.has(slot_id)


func consume(slot_id: String) -> void:
	if not consumed_slots.has(slot_id):
		consumed_slots.append(slot_id)
		consumed_slots.sort()


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"module_id": module_id,
		"parent_instance_id": parent_instance_id,
		"parent_slot_id": parent_slot_id,
		"input_slot_id": input_slot_id,
		"position_m": [position_m.x, position_m.y, position_m.z],
		"yaw_degrees": snappedf(yaw_degrees, 0.001),
		"assignment": assignment.duplicate(true),
		"consumed_slots": consumed_slots.duplicate(),
	}


static func from_dict(raw: Dictionary) -> PortPlacedModule:
	var out := PortPlacedModule.new()
	out.instance_id = str(raw.get("instance_id", ""))
	out.module_id = str(raw.get("module_id", ""))
	out.parent_instance_id = str(raw.get("parent_instance_id", ""))
	out.parent_slot_id = str(raw.get("parent_slot_id", ""))
	out.input_slot_id = str(raw.get("input_slot_id", ""))
	out.position_m = _vector3(raw.get("position_m", Vector3.ZERO))
	out.yaw_degrees = float(raw.get("yaw_degrees", 0.0))
	out.assignment = (raw.get("assignment", {}) as Dictionary).duplicate(true)
	for slot_id in raw.get("consumed_slots", []) as Array:
		out.consumed_slots.append(str(slot_id))
	out.consumed_slots.sort()
	return out


static func _vector3(value: Variant) -> Vector3:
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
