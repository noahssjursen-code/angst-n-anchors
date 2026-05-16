@tool
class_name PortFacilities
extends Node3D

## Land-side port facilities. Local Z = 0 is the dock inner edge; +Z goes inland.
## Facilities are placed in priority rows — lowest priority number = closest to dock.
## Port size determines which facilities exist. Position is always computed, never arbitrary.

const C_AUTHORITY := Color(0.78, 0.62, 0.14)
const C_COMMERCE  := Color(0.24, 0.64, 0.36)
const C_SERVICES  := Color(0.72, 0.34, 0.14)
const C_STORAGE   := Color(0.52, 0.56, 0.64)
const C_TOWN      := Color(0.64, 0.44, 0.28)

const ROW_START_Z : float = 8.0   ## distance from facilities front to first row centre
const ROW_GAP     : float = 6.0   ## gap between rows
const EDGE_MARGIN : float = 4.0   ## margin on each side in X

var _spawn_local_pos:          Vector3 = Vector3.ZERO
var _harbour_master_local_pos: Vector3 = Vector3.ZERO

@export var port_size: int = 1:
	set(v): port_size = v; if is_inside_tree(): _rebuild()

@export var plot_width: float = 80.0:
	set(v): plot_width = v; if is_inside_tree(): _rebuild()

@export var plot_depth: float = 74.0:
	set(v): plot_depth = v; if is_inside_tree(): _rebuild()


func _ready() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_build_facilities()

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child, esc)


func _build_facilities() -> void:
	_spawn_local_pos          = Vector3.ZERO
	_harbour_master_local_pos = Vector3.ZERO

	# Collect facilities present at this port size
	var present: Array = []
	for def in _facility_defs():
		if int((def as Dictionary)["min_size"]) <= port_size:
			present.append(def)

	# Group into rows by priority
	var rows: Dictionary = {}
	for def in present:
		var d   := def as Dictionary
		var pri := int(d["priority"])
		if not rows.has(pri):
			rows[pri] = []
		(rows[pri] as Array).append(d)

	# Place rows from dock outward in priority order
	var priorities := rows.keys()
	priorities.sort()

	var cursor_z := ROW_START_Z
	for priority in priorities:
		var row       := rows[priority] as Array
		var row_depth := 0.0
		for def in row:
			row_depth = maxf(row_depth, float((def as Dictionary)["d"]))
		_place_row(row, cursor_z + row_depth * 0.5)
		cursor_z += row_depth + ROW_GAP


func _place_row(defs: Array, center_z: float) -> void:
	var n           := defs.size()
	var available_w := plot_width - EDGE_MARGIN * 2.0
	var slot_w      := available_w / float(n)

	for i in range(n):
		var d  := defs[i] as Dictionary
		var id := str(d["id"])
		var h  := float(d["h"])
		var bw := minf(float(d["w"]), slot_w - 2.0)
		var cx := -available_w * 0.5 + slot_w * (float(i) + 0.5)

		_box(Vector3(bw, h, float(d["d"])), Vector3(cx, h * 0.5, center_z), d["color"] as Color, id)

		if id == "HarbourMaster":
			_harbour_master_local_pos = Vector3(cx, 0.0, center_z)
			_spawn_local_pos          = Vector3(cx, 0.02, center_z - float(d["d"]) * 0.5 - 2.0)


func _facility_defs() -> Array:
	## Priority 0 = dock row (first contact), higher = further inland.
	return [
		{ "id": "HarbourMaster",  "w":  8.0, "h": 5.0, "d":  7.0, "priority": 0, "color": C_AUTHORITY, "min_size": 0 },
		{ "id": "Chandlery",      "w":  9.0, "h": 4.0, "d":  8.0, "priority": 0, "color": C_COMMERCE,  "min_size": 1 },
		{ "id": "ShippingAgent",  "w": 10.0, "h": 5.0, "d":  8.0, "priority": 1, "color": C_COMMERCE,  "min_size": 1 },
		{ "id": "MarineEngineer", "w": 11.0, "h": 4.0, "d":  9.0, "priority": 1, "color": C_SERVICES,  "min_size": 2 },
		{ "id": "Customs",        "w":  8.0, "h": 5.0, "d":  7.0, "priority": 1, "color": C_AUTHORITY, "min_size": 2 },
		{ "id": "Warehouse",      "w": 24.0, "h": 6.0, "d": 12.0, "priority": 2, "color": C_STORAGE,   "min_size": 0 },
		{ "id": "Town",           "w": 30.0, "h": 5.0, "d": 14.0, "priority": 3, "color": C_TOWN,      "min_size": 0 },
	]


func get_spawn_position() -> Vector3:
	return to_global(_spawn_local_pos)

func get_harbour_master_position() -> Vector3:
	return to_global(_harbour_master_local_pos)


func _box(size: Vector3, pos: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	var mi               := MeshInstance3D.new()
	mi.name              = "Mesh"
	var mesh             := BoxMesh.new()
	mesh.size            = size
	mi.mesh              = mesh
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = color
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	var body             := StaticBody3D.new()
	body.name            = node_name
	body.position        = pos
	var col              := CollisionShape3D.new()
	var box              := BoxShape3D.new()
	box.size             = size
	col.shape            = box
	body.add_child(mi)
	body.add_child(col)
	add_child(body)
	return mi


func _own_subtree(node: Node, esc: Node) -> void:
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
