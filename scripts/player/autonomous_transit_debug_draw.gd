class_name AutonomousTransitDebugDraw
extends Node3D

## F3 debug overlay — orange sea-level polylines for autonomous transit waypoints.

const LINE_COLOR := Color(1.0, 0.52, 0.08, 0.92)
const LINE_Y_OFFSET := 1.8
const REFRESH_SEC := 0.75

var _mesh_inst: MeshInstance3D
var _refresh_clock: float = 0.0


func _ready() -> void:
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "TransitPathLines"
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = LINE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_inst.material_override = mat
	add_child(_mesh_inst)

	var hud := get_node_or_null("/root/DebugHud")
	if hud != null:
		if (
			hud.has_signal("visibility_changed")
			and not hud.visibility_changed.is_connected(_on_debug_visibility)
		):
			hud.visibility_changed.connect(_on_debug_visibility)
		_on_debug_visibility(hud.call("is_open"))
	else:
		visible = false
		set_process(false)


func _on_debug_visibility(open: bool) -> void:
	visible = open
	set_process(open)
	_refresh_clock = REFRESH_SEC
	if open:
		_rebuild_lines()


func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock < REFRESH_SEC:
		return
	_refresh_clock = 0.0
	_rebuild_lines()


func _rebuild_lines() -> void:
	var segments := _collect_segments()
	if segments.is_empty():
		_mesh_inst.mesh = null
		return
	var verts := PackedVector3Array()
	verts.resize(segments.size() * 2)
	var i := 0
	for seg in segments:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		verts[i] = a
		verts[i + 1] = b
		i += 2
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_mesh_inst.mesh = mesh


func _collect_segments() -> Array:
	var out: Array = []
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return out
	var data := session.data as PlayerData
	if data == null:
		return out
	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry_raw as Dictionary
		if not bool(record.get("autonomous_active", false)):
			continue
		var active_at := int(record.get("autonomous_active_at", 0))
		if active_at <= 0:
			continue
		var elapsed := AutonomousSimDebug.scaled_elapsed(active_at)
		var waypoints := AutonomousVesselSim.transit_waypoints_at_elapsed(record, elapsed)
		if waypoints.size() < 2:
			continue
		for j in range(waypoints.size() - 1):
			var p0: Vector3 = waypoints[j]
			var p1: Vector3 = waypoints[j + 1]
			if not _vec3_is_valid(p0) or not _vec3_is_valid(p1):
				continue
			out.append([_lift(p0), _lift(p1)])
	return out


static func _lift(p: Vector3) -> Vector3:
	return Vector3(p.x, WaveSurface.WATER_LEVEL + LINE_Y_OFFSET, p.z)


static func _vec3_is_valid(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < 1.0e8 and absf(v.z) < 1.0e8
