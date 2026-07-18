class_name BerthApproachLanesDebugDraw
extends Node3D

## F3 + B — spine + port/starboard flank lanes per berth.

const LINE_Y_OFFSET := 4.5
const REFRESH_SEC := 0.75

const LANE_COLORS: Array[Color] = [
	Color(0.35, 1.0, 0.45, 0.98),   ## SPINE — seaward
	Color(0.25, 0.82, 1.0, 0.98),   ## FLANK_PORT
	Color(1.0, 0.55, 0.18, 0.98),   ## FLANK_STARBOARD
]

var _mesh_root: Node3D
var _refresh_clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	add_to_group("berth_lane_debug")
	_mesh_root = Node3D.new()
	_mesh_root.name = "LaneMeshes"
	add_child(_mesh_root)
	sync_visibility(false)
	call_deferred("_connect_hud")


func _connect_hud() -> void:
	var hud := get_node_or_null("/root/DebugHud")
	if hud == null:
		return
	if hud.has_signal("visibility_changed"):
		if not hud.visibility_changed.is_connected(_on_hud_visibility):
			hud.visibility_changed.connect(_on_hud_visibility)
	sync_visibility(hud.call("is_open"))


func _on_hud_visibility(open: bool) -> void:
	sync_visibility(open)


func sync_visibility(_hud_open: bool) -> void:
	## Layer selection persists after the F3 panel closes, matching the other
	## world gizmo layers. F3/G is the selector, not a visibility master.
	var show := BerthApproachLanes.debug_visible
	visible = show
	set_process(show)
	if show:
		_rebuild()
	else:
		_clear_meshes()


func refresh_now() -> void:
	if BerthApproachLanes.debug_visible:
		_rebuild()
	_refresh_clock = REFRESH_SEC


## Find any live drawer in the tree and refresh it (world / port bake hooks).
static func refresh_if_enabled(tree: SceneTree) -> void:
	if tree == null or not BerthApproachLanes.debug_visible:
		return
	for node in tree.get_nodes_in_group("berth_lane_debug"):
		if node.has_method("refresh_now"):
			node.call("refresh_now")


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_clock += delta
	if _refresh_clock < REFRESH_SEC:
		return
	_refresh_clock = 0.0
	_rebuild()


func _rebuild() -> void:
	_clear_meshes()
	if not BerthApproachLanes.is_initialized():
		return
	_draw_polylines(BerthApproachLanes.collect_debug_polylines())


func _draw_polylines(polylines: Array) -> void:
	var seen: Dictionary = {}
	for entry_raw in polylines:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		var points: Array = entry.get("points", []) as Array
		if points.size() < 2:
			continue
		var first := points[0] as Vector3
		var last := points[-1] as Vector3
		var fingerprint := "%s|%s|%.1f,%.1f>%.1f,%.1f" % [
			str(entry.get("port_id", "")), str(entry.get("berth_id", "")),
			first.x, first.z, last.x, last.z,
		]
		if seen.has(fingerprint):
			continue
		seen[fingerprint] = true
		var kind := int(entry.get("slice", 0))
		var verts := PackedVector3Array()
		verts.resize((points.size() - 1) * 2)
		var idx := 0
		for i in range(points.size() - 1):
			verts[idx] = _lift(points[i] as Vector3)
			verts[idx + 1] = _lift(points[i + 1] as Vector3)
			idx += 2
		_add_line_mesh(
			"Lane_%s_%s_%d" % [str(entry.get("port_id", "")), str(entry.get("berth_id", "")), kind],
			verts,
			LANE_COLORS[wrapi(kind, 0, LANE_COLORS.size())],
		)


func _add_line_mesh(name: String, verts: PackedVector3Array, color: Color) -> void:
	if verts.size() < 2:
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var inst := MeshInstance3D.new()
	inst.name = name
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inst.material_override = mat
	_mesh_root.add_child(inst)


func _clear_meshes() -> void:
	if _mesh_root == null:
		return
	for child in _mesh_root.get_children():
		child.queue_free()


static func _lift(p: Vector3) -> Vector3:
	return Vector3(p.x, WaveSurface.WATER_LEVEL + LINE_Y_OFFSET, p.z)
