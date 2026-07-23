class_name WorldProjectionStore
extends RefCounted

signal changed(kind: String, id: String, projection: Dictionary)

var _records: Dictionary = {}


func clear() -> void:
	_records.clear()


func apply(projection: Dictionary) -> bool:
	var kind := str(projection.get("kind", "")).strip_edges()
	var id := str(projection.get("id", "")).strip_edges()
	if kind.is_empty() or id.is_empty():
		return false
	var key := _key(kind, id)
	var incoming_revision := int(projection.get("revision", 0))
	var current := _records.get(key, {}) as Dictionary
	if not current.is_empty() and int(current.get("revision", 0)) > incoming_revision:
		return false
	var copy := projection.duplicate(true)
	_records[key] = copy
	changed.emit(kind, id, copy.duplicate(true))
	return true


func get_projection(kind: String, id: String) -> Dictionary:
	return (_records.get(_key(kind, id), {}) as Dictionary).duplicate(true)


func all(kind: String = "") -> Array:
	var out: Array = []
	for value in _records.values():
		var projection := value as Dictionary
		if kind.is_empty() or str(projection.get("kind", "")) == kind:
			out.append(projection.duplicate(true))
	return out


func remove(kind: String, id: String) -> void:
	_records.erase(_key(kind, id))


func _key(kind: String, id: String) -> String:
	return "%s\u001f%s" % [kind.strip_edges(), id.strip_edges()]
