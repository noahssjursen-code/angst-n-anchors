class_name ShippingLaneDebugDraw
extends Node3D

## Region-streamed F3 presentation for ShippingLaneNetwork.
##
## This node only draws immutable traffic infrastructure. It never owns or
## advances vessels. The viewport camera (including the detached F3 freecam)
## selects which part of the network is materialized as gizmos.

const REBUILD_INTERVAL := 0.45
const REBUILD_DISTANCE := 450.0
const DEFAULT_RADIUS := 6200.0
const WATER_Y := 2.8

const COLOR_MAIN_OUT := Color(0.08, 0.72, 1.0, 0.95)
const COLOR_MAIN_IN := Color(0.30, 0.94, 1.0, 0.95)
const COLOR_CONNECTOR := Color(0.94, 0.86, 0.48, 0.95)
const COLOR_APPROACH := Color(0.25, 1.0, 0.48, 1.0)
const COLOR_QUAY := Color(1.0, 0.48, 0.12, 1.0)
const COLOR_JUNCTION := Color(1.0, 0.78, 0.22, 1.0)
const COLOR_BOUNDARY := Color(0.74, 0.88, 0.92, 0.26)
const COLOR_BLOCK := Color(0.92, 0.96, 1.0, 0.72)
const COLOR_REGULAR_SIGNAL := Color(0.28, 1.0, 0.38, 1.0)
const COLOR_CHAIN_SIGNAL := Color(0.35, 0.74, 1.0, 1.0)
const COLOR_HOLDING := Color(0.92, 0.35, 1.0, 0.95)
const COLOR_GATE := Color(1.0, 0.68, 0.18, 1.0)
const COLOR_ERROR := Color(1.0, 0.10, 0.22, 1.0)

var network: ShippingLaneNetwork
var draw_radius := DEFAULT_RADIUS
var always_visible := false

var _content: Node3D
var _last_center := Vector3(1.0e20, 0.0, 1.0e20)
var _elapsed := REBUILD_INTERVAL
var _material_cache: Dictionary = {}


func configure(value: ShippingLaneNetwork, radius_m := DEFAULT_RADIUS, force_visible := false) -> void:
	network = value
	draw_radius = maxf(radius_m, 500.0)
	always_visible = force_visible
	_elapsed = REBUILD_INTERVAL
	if is_inside_tree():
		_register_with_world_gizmos()
		if visible:
			_rebuild(_camera_center())


func _ready() -> void:
	_content = Node3D.new()
	_content.name = "RegionGizmos"
	add_child(_content)
	_register_with_world_gizmos()
	visibility_changed.connect(_on_visibility_changed)
	set_process(true)
	if network != null and visible:
		_rebuild(_camera_center())


func _exit_tree() -> void:
	pass


func _process(delta: float) -> void:
	if network == null or not visible:
		return
	_elapsed += delta
	if _elapsed < REBUILD_INTERVAL:
		return
	_elapsed = 0.0
	var center := _camera_center()
	if center.distance_squared_to(_last_center) >= REBUILD_DISTANCE * REBUILD_DISTANCE:
		_rebuild(center)


func _register_with_world_gizmos() -> void:
	if always_visible:
		visible = true
		return
	WorldGizmos.register(self, WorldGizmos.LAYER_NAVIGATION)


func _on_visibility_changed() -> void:
	if _content == null:
		return
	if not visible:
		for child in _content.get_children():
			child.queue_free()
		_last_center = Vector3(1.0e20, 0.0, 1.0e20)
		return
	if network != null:
		_rebuild(_camera_center())


func _camera_center() -> Vector3:
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null:
			return Vector3(camera.global_position.x, WATER_Y, camera.global_position.z)
	return Vector3.ZERO


func _rebuild(center: Vector3) -> void:
	_last_center = center
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()

	var batches: Dictionary = {}
	var visible_node_ids: Dictionary = {}
	for edge_id in network.sorted_edge_ids():
		var edge := network.edge(edge_id)
		var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() < 2 or not _polyline_near(points, center, draw_radius):
			continue
		visible_node_ids[String(edge.get("from", ""))] = true
		visible_node_ids[String(edge.get("to", ""))] = true
		var color := _edge_color(edge)
		_add_polyline(batches, color, points, WATER_Y)
		_add_lane_boundaries(batches, points, float(edge.get("lane_width_m", 70.0)))
		_add_direction_arrows(batches, color, points)
		_add_block_crossbar(batches, edge)

	for color_key in batches:
		_add_line_mesh(batches[color_key] as PackedVector3Array, _color_from_key(String(color_key)))

	_draw_nodes(visible_node_ids, center)
	_draw_holding_slots(center)
	_draw_validation_issues(center)


func _draw_nodes(visible_node_ids: Dictionary, center: Vector3) -> void:
	for node_id in visible_node_ids:
		var record := network.node(String(node_id))
		if record.is_empty():
			continue
		var point := record.get("position", Vector2.ZERO) as Vector2
		var position := Vector3(point.x, WATER_Y + 0.7, point.y)
		var kind := String(record.get("kind", ""))
		if kind == "port_gate":
			_add_marker(position, 9.0, COLOR_GATE, "PORT GATE\n%s" % String(record.get("port_id", "")))

	var regular_vertices := PackedVector3Array()
	var chain_vertices := PackedVector3Array()
	for signal_id in network.sorted_signal_ids():
		var signal_record := network.signals[signal_id] as Dictionary
		var node_record := network.node(String(signal_record.get("node_id", "")))
		if node_record.is_empty():
			continue
		var point := node_record.get("position", Vector2.ZERO) as Vector2
		var position := Vector3(point.x, WATER_Y + 1.2, point.y)
		if Vector2(position.x - center.x, position.z - center.z).length_squared() > draw_radius * draw_radius:
			continue
		var kind := String(signal_record.get("kind", "regular"))
		if kind == "chain":
			chain_vertices = _append_cross(chain_vertices, position, 5.0)
		else:
			regular_vertices = _append_cross(regular_vertices, position, 2.8)
	_add_line_mesh(regular_vertices, COLOR_REGULAR_SIGNAL)
	_add_line_mesh(chain_vertices, COLOR_CHAIN_SIGNAL)


func _draw_holding_slots(center: Vector3) -> void:
	for slot_id in network.sorted_holding_slot_ids():
		var slot := network.holding_slots[slot_id] as Dictionary
		var point := slot.get("position", Vector2.ZERO) as Vector2
		var position := Vector3(point.x, WATER_Y + 0.5, point.y)
		if Vector2(position.x - center.x, position.z - center.z).length_squared() > draw_radius * draw_radius:
			continue
		_add_cross(position, 18.0, COLOR_HOLDING)
		_add_label(position + Vector3(0.0, 4.0, 0.0), "HOLD %d" % (int(slot.get("queue_index", 0)) + 1), COLOR_HOLDING)


func _draw_validation_issues(center: Vector3) -> void:
	for issue_value in network.validation_issues:
		var issue := issue_value as Dictionary
		if String(issue.get("severity", "warning")) != "error":
			continue
		var point := issue.get("position", Vector2.ZERO) as Vector2
		var position := Vector3(point.x, WATER_Y + 1.0, point.y)
		if Vector2(position.x - center.x, position.z - center.z).length_squared() > draw_radius * draw_radius:
			continue
		_add_cross(position, 26.0, COLOR_ERROR)
		_add_label(position + Vector3(0.0, 7.0, 0.0), "NETWORK ERROR\n%s" % String(issue.get("message", "")), COLOR_ERROR)


func _add_lane_boundaries(batches: Dictionary, points: PackedVector2Array, width_m: float) -> void:
	var half_width := clampf(width_m * 0.5, 8.0, 90.0)
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var direction := (b - a).normalized()
		if direction.length_squared() < 0.5:
			continue
		var normal := Vector2(-direction.y, direction.x) * half_width
		_add_line(batches, COLOR_BOUNDARY, a + normal, b + normal, WATER_Y - 0.12)
		_add_line(batches, COLOR_BOUNDARY, a - normal, b - normal, WATER_Y - 0.12)


func _add_direction_arrows(batches: Dictionary, color: Color, points: PackedVector2Array) -> void:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var delta := b - a
		var length := delta.length()
		if length < 70.0:
			continue
		var direction := delta.normalized()
		var normal := Vector2(-direction.y, direction.x)
		var midpoint := a.lerp(b, 0.58)
		var arrow_size := clampf(length * 0.08, 10.0, 28.0)
		_add_line(batches, color, midpoint, midpoint - direction * arrow_size + normal * arrow_size * 0.55, WATER_Y + 0.15)
		_add_line(batches, color, midpoint, midpoint - direction * arrow_size - normal * arrow_size * 0.55, WATER_Y + 0.15)


func _add_block_crossbar(batches: Dictionary, edge: Dictionary) -> void:
	var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
	if points.size() < 2:
		return
	var a := points[0]
	var b := points[1]
	var direction := (b - a).normalized()
	if direction.length_squared() < 0.5:
		return
	var normal := Vector2(-direction.y, direction.x)
	var width := clampf(float(edge.get("lane_width_m", 70.0)) * 0.58, 10.0, 95.0)
	_add_line(batches, COLOR_BLOCK, a - normal * width, a + normal * width, WATER_Y + 0.28)


func _add_marker(position: Vector3, radius: float, color: Color, text := "") -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _material(color)
	mesh_instance.position = position
	_content.add_child(mesh_instance)
	if not text.is_empty():
		_add_label(position + Vector3(0.0, radius + 3.0, 0.0), text, color)


func _add_cross(position: Vector3, radius: float, color: Color) -> void:
	var vertices := PackedVector3Array()
	vertices = _append_cross(vertices, position, radius)
	_add_line_mesh(vertices, color)


static func _append_cross(vertices: PackedVector3Array, position: Vector3, radius: float) -> PackedVector3Array:
	vertices.append(position + Vector3(-radius, 0.0, -radius))
	vertices.append(position + Vector3(radius, 0.0, radius))
	vertices.append(position + Vector3(-radius, 0.0, radius))
	vertices.append(position + Vector3(radius, 0.0, -radius))
	return vertices


func _add_label(position: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.modulate = color
	label.outline_modulate = Color(0.01, 0.02, 0.03, 0.95)
	label.outline_size = 6
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	_content.add_child(label)


func _add_polyline(batches: Dictionary, color: Color, points: PackedVector2Array, y: float) -> void:
	for i in range(points.size() - 1):
		_add_line(batches, color, points[i], points[i + 1], y)


func _add_line(batches: Dictionary, color: Color, a: Vector2, b: Vector2, y: float) -> void:
	var key := _color_key(color)
	var vertices := batches.get(key, PackedVector3Array()) as PackedVector3Array
	vertices.append(Vector3(a.x, y, a.y))
	vertices.append(Vector3(b.x, y, b.y))
	batches[key] = vertices


func _add_line_mesh(vertices: PackedVector3Array, color: Color) -> void:
	if vertices.size() < 2:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	_content.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var key := _color_key(color)
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.no_depth_test = true
	_material_cache[key] = material
	return material


func _edge_color(edge: Dictionary) -> Color:
	var kind := String(edge.get("kind", ""))
	if kind == "port_approach" or kind == "holding_link":
		return COLOR_APPROACH
	if kind == "quay_maneuver":
		return COLOR_QUAY
	if kind == "port_connector":
		return COLOR_CONNECTOR
	if kind in ["junction", "ocean_bus_connector", "waterway_junction", "ocean_merge"]:
		return COLOR_JUNCTION
	return COLOR_MAIN_IN if String(edge.get("direction", "outbound")) == "inbound" else COLOR_MAIN_OUT


func _polyline_near(points: PackedVector2Array, center: Vector3, radius: float) -> bool:
	var radius_squared := radius * radius
	for point in points:
		if Vector2(point.x - center.x, point.y - center.z).length_squared() <= radius_squared:
			return true
	return false


func _color_key(color: Color) -> String:
	return color.to_html(true)


func _color_from_key(key: String) -> Color:
	return Color.from_string(key, Color.WHITE)
