extends Node3D

## Construction overlays only: no collision, saved geometry or painted yard.
## The ring describes horizontal reach; authority still checks the whole vessel,
## handling mode, store pairing, water and permission for each cargo operation.
const HEIGHT := .12
var _key := ""
var reach: Dictionary = {}

func present(proposal: Dictionary, catalog: Dictionary) -> void:
	var placement: Dictionary = proposal.get("placement", {})
	var spec: Dictionary = catalog.get(str(placement.get("asset_id", "")), {})
	reach = reach_geometry(placement, spec)
	if reach.is_empty(): hide(); return
	var key := JSON.stringify([reach, bool(proposal.get("ok", false))])
	if key != _key:
		_key = key
		for child in get_children(): remove_child(child); child.queue_free()
		var colour := Color(.58, .9, .94, .8) if proposal.get("ok", false) else Color(.97, .43, .35, .8)
		var pivot: Vector2 = reach.pivot
		var contours: Array[PackedVector2Array] = [_circle(pivot, float(reach.maximum))]
		if float(reach.minimum) > .01: contours.append(_circle(pivot, float(reach.minimum)))
		add_child(outline(contours, colour))
		var label := Label3D.new()
		label.text = "%s reach · %s m" % ["Hose" if str(spec.get("id","")) == "fish_landing_plant" else "Crane", "%.0f–%.0f" % [reach.minimum,reach.maximum] if float(reach.minimum) > .01 else "%.0f" % reach.maximum]
		label.font_size = 24
		label.outline_size = 5
		label.fixed_size = true
		label.pixel_size = .00125
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(pivot.x, 3, pivot.y)
		label.no_depth_test = true
		label.modulate = colour
		add_child(label)
	show()

static func reach_geometry(placement: Dictionary, spec: Dictionary) -> Dictionary:
	if placement.is_empty() or str(spec.get("kind", "")) != "crane": return {}
	var meta := spec.duplicate(true)
	meta.merge(placement.get("attributes", {}), true)
	var minimum := maxf(0, float(meta.get("reach_min_m", 0)))
	var maximum := float(meta.get("reach_max_m", 0))
	if not is_finite(maximum) or maximum <= minimum: return {}
	var offset: Array = meta.get("crane_offset_m", [])
	var pivot := Vector2.ZERO
	if offset.size() == 2: pivot = Vector2(float(offset[0]),float(offset[1]))
	elif offset.size() == 3: pivot = Vector2(float(offset[0]),float(offset[2]))
	var at := CustomPortCatalog.vector3(placement.position_m)
	pivot = pivot.rotated(-deg_to_rad(float(placement.get("yaw_degrees", 0)))) + Vector2(at.x,at.z)
	return {"pivot":pivot, "minimum":minimum, "maximum":maximum}

static func berth_outline(berth: Dictionary) -> MeshInstance3D:
	var polygon := PackedVector2Array()
	for point in berth.get("mooring_polygon_m", []):
		polygon.append(Vector2(float(point[0]),float(point[1])))
	return outline([polygon], Color(.48,.85,.91,.6) if berth.get("water_verified",false) else Color(.95,.45,.36,.6))

static func outline(contours: Array, colour: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 11
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for polygon in contours:
		if polygon.size() < 2: continue
		for i in polygon.size():
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i+1)%polygon.size()]
			var normal := (b-a).orthogonal().normalized()*.065
			for point in [a-normal,a+normal,b+normal,a-normal,b+normal,b-normal]:
				mesh.surface_add_vertex(Vector3(point.x,HEIGHT,point.y))
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual

static func _circle(pivot: Vector2, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 128: result.append(pivot + Vector2.from_angle(TAU*float(i)/128)*radius)
	return result
