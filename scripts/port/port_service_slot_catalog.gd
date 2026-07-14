class_name PortServiceSlotCatalog
extends RefCounted

## Official default-port service slots. Authored by PortSlotEditor and consumed
## by PortFacilities so harbourmaster / shipwright / future roles stay data-driven.

const SLOT_PATH := "res://resources/data/ports/default_service_slots.json"
const FORMAT_VERSION := 1

## Known gameplay roles. Slot editor picks from this list instead of free typing.
const ROLE_PRESETS := [
	{"id": "harbour_master", "display_name": "HARBOUR MASTER", "color": Color(0.58, 0.47, 0.18), "footprint": Vector3(10.0, 0.12, 8.0)},
	{"id": "contractor", "display_name": "CONTRACTOR", "color": Color(0.18, 0.46, 0.29), "footprint": Vector3(10.0, 0.12, 8.0)},
	{"id": "shipwright", "display_name": "SHIPWRIGHT", "color": Color(0.50, 0.25, 0.14), "footprint": Vector3(12.0, 0.12, 10.0)},
	{"id": "warehouse", "display_name": "WAREHOUSE", "color": Color(0.32, 0.34, 0.38), "footprint": Vector3(16.0, 0.12, 12.0)},
	{"id": "customs", "display_name": "CUSTOMS", "color": Color(0.22, 0.36, 0.52), "footprint": Vector3(10.0, 0.12, 8.0)},
	{"id": "marine_engineer", "display_name": "MARINE ENGINEER", "color": Color(0.42, 0.28, 0.18), "footprint": Vector3(12.0, 0.12, 10.0)},
]

static var _cache: Array[Dictionary] = []
static var _loaded := false


static func clear_cache() -> void:
	_cache.clear()
	_loaded = false


static func slots() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for slot in _cache:
		out.append(slot.duplicate(true))
	return out


static func by_id(service_id: String) -> Dictionary:
	_ensure_loaded()
	for slot in _cache:
		if str(slot.get("id", "")) == service_id:
			return slot.duplicate(true)
	return {}


static func blueprint_ids() -> Dictionary:
	## service_id → blueprint_id for slots that have a building attached.
	_ensure_loaded()
	var out := {}
	for slot in _cache:
		var blueprint_id := str(slot.get("blueprint_id", "")).strip_edges()
		if blueprint_id.is_empty():
			continue
		out[str(slot.get("id", ""))] = blueprint_id
	return out


static func role_ids() -> Array[String]:
	var out: Array[String] = []
	for preset in ROLE_PRESETS:
		out.append(str(preset["id"]))
	return out


static func role_preset(role_id: String) -> Dictionary:
	for preset in ROLE_PRESETS:
		if str(preset["id"]) == role_id:
			return (preset as Dictionary).duplicate(true)
	return {}


static func make_slot(role_id: String, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var preset := role_preset(role_id)
	if preset.is_empty():
		preset = {
			"id": role_id,
			"display_name": role_id.to_upper().replace("_", " "),
			"color": Color(0.40, 0.40, 0.40),
			"footprint": Vector3(10.0, 0.12, 8.0),
		}
	return {
		"id": str(preset["id"]),
		"display_name": str(preset["display_name"]),
		"position": position,
		"footprint": preset.get("footprint", Vector3(10.0, 0.12, 8.0)),
		"color": preset.get("color", Color(0.4, 0.4, 0.4)),
		"blueprint_id": "",
		"yaw_degrees": 0.0,
	}


static func save(slots_data: Array) -> bool:
	var serialized: Array = []
	for entry in slots_data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := entry as Dictionary
		var position := _as_vector3(slot.get("position", Vector3.ZERO))
		var footprint := _as_vector3(slot.get("footprint", Vector3(10.0, 0.12, 8.0)))
		var color := _as_color(slot.get("color", Color(0.4, 0.4, 0.4)))
		serialized.append({
			"id": str(slot.get("id", "")).strip_edges(),
			"display_name": str(slot.get("display_name", "")).strip_edges(),
			"position": [position.x, position.y, position.z],
			"footprint": [footprint.x, footprint.y, footprint.z],
			"color": [color.r, color.g, color.b],
			"blueprint_id": str(slot.get("blueprint_id", "")).strip_edges(),
			"yaw_degrees": snappedf(float(slot.get("yaw_degrees", 0.0)), 0.1),
		})
	var payload := {
		"format_version": FORMAT_VERSION,
		"slots": serialized,
	}
	var directory := ProjectSettings.globalize_path(SLOT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(SLOT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("PortServiceSlotCatalog: could not write %s" % SLOT_PATH)
		return false
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
	clear_cache()
	_ensure_loaded()
	return true


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache.clear()
	if not FileAccess.file_exists(SLOT_PATH):
		_cache = _default_slots()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SLOT_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PortServiceSlotCatalog: invalid JSON at %s" % SLOT_PATH)
		_cache = _default_slots()
		return
	var raw_slots := (parsed as Dictionary).get("slots", []) as Array
	if raw_slots.is_empty():
		_cache = _default_slots()
		return
	for entry in raw_slots:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := _normalize_slot(entry as Dictionary)
		if str(slot.get("id", "")).is_empty():
			continue
		_cache.append(slot)


static func _default_slots() -> Array[Dictionary]:
	return [
		make_slot("harbour_master", Vector3(-13.0, 0.0, 10.0)),
		make_slot("contractor", Vector3(0.0, 0.0, 10.0)),
		make_slot("shipwright", Vector3(14.0, 0.0, 11.0)),
	]


static func _normalize_slot(raw: Dictionary) -> Dictionary:
	return {
		"id": str(raw.get("id", "")).strip_edges(),
		"display_name": str(raw.get("display_name", "")).strip_edges(),
		"position": _as_vector3(raw.get("position", Vector3.ZERO)),
		"footprint": _as_vector3(raw.get("footprint", Vector3(10.0, 0.12, 8.0))),
		"color": _as_color(raw.get("color", Color(0.4, 0.4, 0.4))),
		"blueprint_id": str(raw.get("blueprint_id", "")).strip_edges(),
		"yaw_degrees": float(raw.get("yaw_degrees", 0.0)),
	}


static func _as_vector3(value: Variant) -> Vector3:
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


static func _as_color(value: Variant) -> Color:
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
