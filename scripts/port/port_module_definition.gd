class_name PortModuleDefinition
extends RefCounted

## Data-only template for one socketed port layout module.

var id := ""
var display_name := ""
var kind := ""
var footprint_m := Vector3.ONE
var color := Color(0.5, 0.5, 0.5)
var tags: Array[String] = []
var slots: Array[Dictionary] = []


static func from_dict(raw: Dictionary) -> PortModuleDefinition:
	var out := PortModuleDefinition.new()
	out.id = str(raw.get("id", "")).strip_edges()
	out.display_name = str(raw.get("display_name", out.id.to_upper())).strip_edges()
	out.kind = str(raw.get("kind", "module")).strip_edges()
	out.footprint_m = _vector3(raw.get("footprint_m", [1.0, 1.0, 1.0]))
	out.color = _color(raw.get("color", [0.5, 0.5, 0.5]))
	for tag in raw.get("tags", []) as Array:
		out.tags.append(str(tag))
	for slot_raw in raw.get("slots", []) as Array:
		if typeof(slot_raw) != TYPE_DICTIONARY:
			continue
		var source := slot_raw as Dictionary
		var accepts: Array[String] = []
		for accepted in source.get("accepts", []) as Array:
			accepts.append(str(accepted))
		out.slots.append({
			"id": str(source.get("id", "")).strip_edges(),
			"type": str(source.get("type", "")).strip_edges(),
			"position_m": _vector3(source.get("position_m", Vector3.ZERO)),
			"yaw_degrees": float(source.get("yaw_degrees", 0.0)),
			"direction": str(source.get("direction", "output")).strip_edges(),
			"accepts": accepts,
		})
	return out


func is_valid() -> bool:
	if id.is_empty() or footprint_m.x <= 0.0 or footprint_m.z <= 0.0:
		return false
	var seen: Dictionary = {}
	for slot in slots:
		var slot_id := str(slot.get("id", ""))
		if slot_id.is_empty() or seen.has(slot_id):
			return false
		seen[slot_id] = true
	return true


func input_for(output_type: String) -> Dictionary:
	for slot in slots:
		if str(slot.get("direction", "")) != "input":
			continue
		var accepts := slot.get("accepts", []) as Array
		if accepts.has(output_type) or str(slot.get("type", "")) == output_type:
			return slot.duplicate(true)
	return {}


func output_slot(slot_id: String) -> Dictionary:
	for slot in slots:
		if str(slot.get("id", "")) == slot_id and str(slot.get("direction", "")) == "output":
			return slot.duplicate(true)
	return {}


func output_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in slots:
		if str(slot.get("direction", "")) == "output":
			out.append(slot.duplicate(true))
	return out


## Returns a size-scaled clone. Catalog templates are authored at
## PortSizing.CATALOG_REFERENCE_SIZE; quays/aprons/yards use absolute contracts.
func scaled_for_size(size: int) -> PortModuleDefinition:
	var n := PortSizing.normalized_size(size)
	var out := PortModuleDefinition.new()
	out.id = id
	out.display_name = display_name
	out.kind = kind
	out.color = color
	out.tags = tags.duplicate()
	out.footprint_m = footprint_m
	out.slots = []
	for slot in slots:
		out.slots.append(slot.duplicate(true))

	var target := _target_footprint(n)
	if target == Vector3.ZERO:
		return out
	var sx := target.x / maxf(footprint_m.x, 0.001)
	var sz := target.z / maxf(footprint_m.z, 0.001)
	out.footprint_m = Vector3(target.x, footprint_m.y, target.z)
	for i in range(out.slots.size()):
		var slot: Dictionary = out.slots[i]
		var pos := slot.get("position_m", Vector3.ZERO) as Vector3
		slot["position_m"] = Vector3(pos.x * sx, pos.y, pos.z * sz)
		out.slots[i] = slot
	if out.kind == "apron" or out.kind == "basin" or out.tags.has("root"):
		out._space_parallel_seaward_piers(n)
	return out


## Parallel seaward pier sockets must leave a navigable fairway between docks.
## Apron width grows so asphalt always reaches every pier root (no floating fingers).
func _space_parallel_seaward_piers(size: int) -> void:
	var seaward_indices: Array[int] = []
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if str(slot.get("direction", "")) != "output":
			continue
		if str(slot.get("type", "")) != "harbour_branch":
			continue
		var yaw := wrapf(float(slot.get("yaw_degrees", 0.0)), -180.0, 180.0)
		## Seaward face = local −Z, yaw near 0.
		if absf(yaw) <= 1.0:
			seaward_indices.append(i)
	if seaward_indices.size() < 2:
		return
	seaward_indices.sort_custom(func(a: int, b: int) -> bool:
		var ax := (slots[a].get("position_m", Vector3.ZERO) as Vector3).x
		var bx := (slots[b].get("position_m", Vector3.ZERO) as Vector3).x
		return ax < bx
	)
	var spacing := PortSizing.parallel_pier_center_spacing_m(size)
	var seaward_z := -footprint_m.z * 0.5
	var span := spacing * float(seaward_indices.size() - 1)
	var start_x := -span * 0.5
	for order in range(seaward_indices.size()):
		var index := seaward_indices[order]
		var slot: Dictionary = slots[index]
		var pos := slot.get("position_m", Vector3.ZERO) as Vector3
		slot["position_m"] = Vector3(start_x + spacing * float(order), pos.y, seaward_z)
		slots[index] = slot

	var min_x := (slots[seaward_indices[0]].get("position_m", Vector3.ZERO) as Vector3).x
	var max_x := min_x
	for index in seaward_indices:
		var x := (slots[index].get("position_m", Vector3.ZERO) as Vector3).x
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
	var deck_margin := PortSizing.quay_deck_width_m(size) * 0.5 + 14.0
	var needed_half := maxf(absf(min_x), absf(max_x)) + deck_margin
	if needed_half > footprint_m.x * 0.5:
		footprint_m.x = needed_half * 2.0

	## Keep alongshore pier sockets on the apron flanks after any width grow.
	var half_x := footprint_m.x * 0.5
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if str(slot.get("direction", "")) != "output":
			continue
		if str(slot.get("type", "")) != "harbour_branch":
			continue
		var yaw := wrapf(float(slot.get("yaw_degrees", 0.0)), -180.0, 180.0)
		if absf(absf(yaw) - 90.0) > 1.0:
			continue
		var pos := slot.get("position_m", Vector3.ZERO) as Vector3
		var x := -half_x if yaw > 0.0 else half_x
		slot["position_m"] = Vector3(x, pos.y, pos.z)
		slots[i] = slot


func _target_footprint(size: int) -> Vector3:
	match kind:
		"coast":
			return Vector3(6.0, footprint_m.y, 6.0)
		"shore":
			var seg_len := clampf(26.0 + float(size) * 3.5, 26.0, 44.0)
			return Vector3(seg_len, footprint_m.y, footprint_m.z)
		"apron", "basin":
			return Vector3(PortSizing.apron_width_m(size), footprint_m.y, PortSizing.apron_depth_m(size))
		"quay":
			var length := PortSizing.slot_width_m(size)
			if tags.has("extension"):
				length = PortSizing.slot_width_m(size)
			elif tags.has("branch"):
				length = PortSizing.slot_width_m(size) * 0.55
			elif tags.has("liquid"):
				length = PortSizing.slot_width_m(size) * 0.72
			elif tags.has("bulk_ore") or tags.has("bulk") or tags.has("container"):
				length = PortSizing.slot_width_m(size) * 1.12
			elif tags.has("bulk_grain"):
				length = PortSizing.slot_width_m(size) * 1.05
			elif tags.has("fishing"):
				length = PortSizing.slot_width_m(size) * 0.85
			var width := PortSizing.quay_deck_width_m(size)
			if tags.has("liquid") or tags.has("branch"):
				width = maxf(width * 0.55, 10.0)
			return Vector3(width, footprint_m.y, length)
		"cargo":
			var yard := PortSizing.cargo_yard_size_m(size)
			return Vector3(yard.x, footprint_m.y, yard.y)
		"equipment":
			var pad := 8.0 + float(size) * 2.0
			return Vector3(pad, footprint_m.y, pad)
		"service":
			if tags.has("fuel"):
				return Vector3(12.0 + float(size) * 2.0, footprint_m.y, 10.0 + float(size))
			return Vector3(16.0 + float(size) * 3.0, footprint_m.y, 12.0 + float(size) * 2.0)
		"road":
			return Vector3(8.0 + float(size), footprint_m.y, 28.0 + float(size) * 8.0)
		_:
			return Vector3.ZERO


func to_dict() -> Dictionary:
	var serialized_slots: Array = []
	for slot in slots:
		var pos := slot.get("position_m", Vector3.ZERO) as Vector3
		serialized_slots.append({
			"id": str(slot.get("id", "")),
			"type": str(slot.get("type", "")),
			"position_m": [pos.x, pos.y, pos.z],
			"yaw_degrees": float(slot.get("yaw_degrees", 0.0)),
			"direction": str(slot.get("direction", "")),
			"accepts": (slot.get("accepts", []) as Array).duplicate(),
		})
	return {
		"id": id,
		"display_name": display_name,
		"kind": kind,
		"footprint_m": [footprint_m.x, footprint_m.y, footprint_m.z],
		"color": [color.r, color.g, color.b],
		"tags": tags.duplicate(),
		"slots": serialized_slots,
	}


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


static func _color(value: Variant) -> Color:
	if value is Color:
		return value as Color
	if value is Array:
		var arr := value as Array
		return Color(
			float(arr[0]) if arr.size() > 0 else 0.5,
			float(arr[1]) if arr.size() > 1 else 0.5,
			float(arr[2]) if arr.size() > 2 else 0.5,
		)
	return Color(0.5, 0.5, 0.5)
