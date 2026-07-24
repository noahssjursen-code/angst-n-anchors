class_name StructureItemCatalog
extends RefCounted

## Point equipment / decorative asset catalog for StructurePlan.items.
##
## This pass ships an EMPTY catalog on purpose — Structure Studio and the
## baker/mount pipeline are ready, but no functional or decorative item
## definitions are authored yet. When items land, add JSON entries shaped like:
##
##   "helm_console": {
##     "label": "Helm console",
##     "kind": "equipment",          ## equipment | decor
##     "tags": ["helm", "interactive"],
##     "footprint": [1, 1, 1],       ## cells (w,h,l)
##     "mount": "deck",              ## deck | wall | ceiling
##     "yaw_steps": 90,
##     "visual": "primitive"         ## future: mesh path / assembler model
##   }
##
## DeckFitout.apply_plan walks plan.items and skips unknown ids.

const DATA_PATH := "res://resources/data/structures/item_catalog.json"

static var _items: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_loaded = false
	_items.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_items.clear()
	if not FileAccess.file_exists(DATA_PATH):
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_items = ((parsed as Dictionary).get("items", {}) as Dictionary).duplicate(true)


static func ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for key in _items.keys():
		out.append(str(key))
	out.sort()
	return out


static func is_empty() -> bool:
	return ids().is_empty()


static func has_id(item_id: String) -> bool:
	_ensure_loaded()
	return _items.has(item_id.strip_edges())


static func definition(item_id: String) -> Dictionary:
	_ensure_loaded()
	var key := item_id.strip_edges()
	if not _items.has(key):
		return {}
	return (_items[key] as Dictionary).duplicate(true)


static func label_of(item_id: String) -> String:
	var def := definition(item_id)
	if def.is_empty():
		return item_id
	return str(def.get("label", item_id))


static func kind_of(item_id: String) -> String:
	return str(definition(item_id).get("kind", "equipment"))


static func tags_of(item_id: String) -> Array:
	return definition(item_id).get("tags", []) as Array


static func footprint_of(item_id: String) -> Vector3i:
	var raw: Variant = definition(item_id).get("footprint", [1, 1, 1])
	if raw is Array and (raw as Array).size() >= 3:
		var list := raw as Array
		return Vector3i(int(list[0]), int(list[1]), int(list[2]))
	return Vector3i.ONE


## Future mount entry point. Returns a Node3D visual or null when the catalog
## has no definition / no visual yet. Callers must tolerate null.
static func try_instantiate(item_id: String) -> Node3D:
	var def := definition(item_id)
	if def.is_empty():
		return null
	## No authored visuals in this pass — reserved for the equipment slice.
	return null
