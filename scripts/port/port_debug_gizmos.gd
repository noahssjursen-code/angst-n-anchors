@tool
class_name PortDebugGizmos
extends Node3D

## Visualise where the port is registered, what size box was used, and where coast dots landed.

const ORIGIN_COLOR := Color(1.0, 0.15, 0.15)
const SIZE_BOX_COLOR := Color(0.2, 0.95, 0.35, 0.85)
const TRACE_BOX_COLOR := Color(1.0, 0.85, 0.1, 0.85)
const SEAWARD_COLOR := Color(0.25, 0.55, 1.0)
const INLAND_COLOR := Color(0.35, 1.0, 0.45)
const TERRAIN_COAST_COLOR := Color(1.0, 0.55, 0.1)
const SPINE_COLOR := Color(0.95, 0.2, 0.95)
const DOCK_COLOR := Color(0.2, 0.85, 1.0)
const ANCHOR_COLOR := Color(1.0, 1.0, 0.2)


func configure(graph: PortLayoutGraph) -> void:
	for child in get_children():
		child.free()
	if graph == null:
		return
	var port_area := graph.initial_attributes.get("port_area", {}) as Dictionary
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var size := int(graph.initial_attributes.get("size", 1))
	var half_w := float(port_area.get("half_width_m", 0.0))
	var half_d := float(port_area.get("half_depth_m", 0.0))
	var trace_w := float(port_area.get("trace_half_width_m", half_w))
	var trace_d := float(port_area.get("trace_half_depth_m", half_d))
	_stamp_origin(size, half_w, half_d, trace_w, trace_d)
	_stamp_axis_arrow(Vector3(0.0, 0.0, -1.0), 90.0, SEAWARD_COLOR, "SEAWARD -Z")
	_stamp_axis_arrow(Vector3(0.0, 0.0, 1.0), 90.0, INLAND_COLOR, "INLAND +Z")
	_stamp_axis_arrow(Vector3(1.0, 0.0, 0.0), 70.0, Color(0.9, 0.9, 0.9), "ALONG +X")
	_stamp_ground_rect("SizeBox", half_w, half_d, SIZE_BOX_COLOR, 0.8)
	_stamp_ground_rect("TraceBox", trace_w, trace_d, TRACE_BOX_COLOR, 1.2)
	_stamp_polyline_dots(
		port_area.get("terrain_coast_polyline", []) as Array,
		TERRAIN_COAST_COLOR,
		2.4,
		"TerrainTrace",
	)
	_stamp_polyline_dots(foundation.get("spine", []) as Array, SPINE_COLOR, 3.2, "Spine")
	_stamp_polyline_dots(
		port_area.get("natural_shore_polyline", []) as Array,
		Color(0.95, 0.45, 0.95),
		2.0,
		"ShoreSpan",
	)
	_stamp_polyline_dots(port_area.get("coast_polyline", []) as Array, DOCK_COLOR, 2.6, "DockFace")
	_stamp_polyline_lines(foundation.get("spine", []) as Array, SPINE_COLOR, 0.35)
	var modules := graph.modules
	for instance_id in modules:
		var placed := modules[instance_id] as PortPlacedModule
		if str(placed.assignment.get("role", "")) == "foundation_anchor":
			_stamp_dot(placed.position_m, ANCHOR_COLOR, 5.0, "GraphRoot")


func _stamp_origin(
		size: int,
		half_w: float,
		half_d: float,
		trace_w: float,
		trace_d: float,
) -> void:
	var pole := MeshBuilder.cylinder(1.8, 28.0, ORIGIN_COLOR, 0.7, 0.1)
	pole.name = "PortOrigin"
	pole.position = Vector3(0.0, 14.0, 0.0)
	add_child(pole)
	_stamp_dot(Vector3.ZERO, ORIGIN_COLOR, 4.5, "OriginDot")
	_label(
		"OriginLabel",
		"PORT ORIGIN (registered site)\nsize %d · area %.0f×%.0f m\nscan %.0f×%.0f m" % [
			size,
			half_w * 2.0,
			half_d * 2.0,
			trace_w * 2.0,
			trace_d * 2.0,
		],
		Vector3(0.0, 34.0, 0.0),
		ORIGIN_COLOR,
	)


func _stamp_axis_arrow(direction: Vector3, length_m: float, color: Color, text: String) -> void:
	var shaft := MeshBuilder.box(Vector3(1.2, 1.2, length_m), color, 0.75, 0.0)
	shaft.name = "Axis_%s" % text
	shaft.position = direction * (length_m * 0.5) + Vector3(0.0, 2.0, 0.0)
	add_child(shaft)
	_label("AxisLabel_%s" % text, text, shaft.position + Vector3(0.0, 8.0, 0.0), color)


func _stamp_ground_rect(node_name: String, half_x: float, half_z: float, color: Color, y: float) -> void:
	if half_x < 1.0 or half_z < 1.0:
		return
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	var thickness := 1.4
	var y_pos := y
	var corners := [
		Vector3(-half_x, y_pos, -half_z),
		Vector3(half_x, y_pos, -half_z),
		Vector3(half_x, y_pos, half_z),
		Vector3(-half_x, y_pos, half_z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[0, 2], [1, 3],
	]
	for pair in edges:
		var a: Vector3 = corners[pair[0]]
		var b: Vector3 = corners[pair[1]]
		var edge := MeshBuilder.box(Vector3(thickness, thickness, a.distance_to(b)), color, 0.8, 0.0)
		edge.position = (a + b) * 0.5
		edge.look_at(b, Vector3.UP)
		root.add_child(edge)
	_label(
		"%sLabel" % node_name,
		node_name.replace("Box", " box ") + " %.0f × %.0f m" % [half_x * 2.0, half_z * 2.0],
		Vector3(0.0, y + 10.0, -half_z - 12.0),
		color,
	)


func _stamp_polyline_dots(points: Array, color: Color, radius: float, prefix: String) -> void:
	for index in range(points.size()):
		var raw := points[index] as Array
		if raw.size() < 2:
			continue
		var pos := Vector3(float(raw[0]), 3.0, float(raw[1]))
		_stamp_dot(pos, color, radius, "%s_%d" % [prefix, index])


func _stamp_polyline_lines(points: Array, color: Color, thickness: float) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		var a_raw := points[index] as Array
		var b_raw := points[index + 1] as Array
		if a_raw.size() < 2 or b_raw.size() < 2:
			continue
		var a := Vector3(float(a_raw[0]), 4.0, float(a_raw[1]))
		var b := Vector3(float(b_raw[0]), 4.0, float(b_raw[1]))
		var span := a.distance_to(b)
		if span < 0.5:
			continue
		var edge := MeshBuilder.box(Vector3(thickness, thickness, span), color, 0.75, 0.0)
		edge.position = (a + b) * 0.5
		edge.look_at(b, Vector3.UP)
		add_child(edge)


func _stamp_dot(position: Vector3, color: Color, radius: float, node_name: String) -> void:
	var dot := MeshBuilder.sphere(radius, color, 0.7, 0.05)
	dot.name = node_name
	dot.position = position
	add_child(dot)


func _label(node_name: String, text: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = position
	label.pixel_size = 0.018
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	add_child(label)
