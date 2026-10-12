extends Node3D

## Set crab pots live here, not on a hull. The company owns the record.
## A buoy in the water is the projection of that record. Recalling the crabber
## does not remove it. Another crabber of the same company can haul it later.
## NPC companies will use the same records. A server can treat snapshot() as the
## authoritative list and send it to clients; this node only draws what it holds.

const CREEL_SCENE := "res://resources/models/parts/coastal_fishing/crab_creel.glb"
const BUOY_SCENE := "res://resources/models/parts/coastal_fishing/pot_rope_buoy.glb"

var _pots: Array[Dictionary] = []


static func ensure(tree: SceneTree) -> Node:
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var existing := host.get_node_or_null("DeployedCrabPots")
	if existing != null:
		return existing
	var node := (load("res://scripts/ship/deployed_crab_pots.gd") as GDScript).new() as Node3D
	node.name = "DeployedCrabPots"
	host.add_child(node)
	return node


func place(owner_id: String, drop: Vector2, depth_m: float, ready_hours: float) -> String:
	var id := "pot-%s" % PlayerData.new_uuid()
	var creel := (load(CREEL_SCENE) as PackedScene).instantiate() as Node3D
	creel.name = "SetCreel"
	creel.top_level = true
	add_child(creel)
	var buoy := _new_buoy(id)
	var rope := _new_rope()
	var timer := _new_timer()
	(buoy.get_meta("marker") as Node3D).add_child(timer)
	var pot := {
		"id": id,
		"owner_id": owner_id,
		"drop": drop,
		"depth_m": depth_m,
		"ready_hours": ready_hours,
		"claim": 0,
		"hauling": false,
		"creel": creel,
		"buoy": buoy,
		"rope": rope,
		"line": FishingLineShape.new(),
		"timer": timer,
	}
	_pots.append(pot)
	_pose(pot)
	return id


func has_pot(id: String) -> bool:
	return not _find(id).is_empty()


func ready_hours(id: String) -> float:
	var pot := _find(id)
	return float(pot.get("ready_hours", 0.0))


func gear(id: String) -> Dictionary:
	var pot := _find(id)
	if pot.is_empty():
		return {}
	return {
		"creel": pot.creel,
		"buoy": pot.buoy,
		"rope": pot.rope,
		"line": pot.line,
	}


func marker_position(id: String) -> Vector3:
	var pot := _find(id)
	if pot.is_empty():
		return Vector3.ZERO
	return (pot.buoy.get_meta("marker") as Node3D).global_position


func drops() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for pot in _pots:
		result.append(pot.drop)
	return result


func unclaimed(owner_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pot in _pots:
		if str(pot.owner_id) != owner_id or _claim_alive(pot):
			continue
		result.append({
			"id": pot.id,
			"drop": pot.drop,
			"depth_m": pot.depth_m,
			"ready_hours": pot.ready_hours,
		})
	return result


func claim(id: String, station: Node) -> bool:
	var pot := _find(id)
	if pot.is_empty() or station == null:
		return false
	if _claim_alive(pot) and int(pot.claim) != station.get_instance_id():
		return false
	pot.claim = station.get_instance_id()
	_write(pot)
	return true


func unclaim(id: String) -> void:
	var pot := _find(id)
	if pot.is_empty():
		return
	pot.claim = 0
	pot.hauling = false
	_write(pot)


func release_claims(station: Node) -> void:
	if station == null:
		return
	var instance := station.get_instance_id()
	for pot in _pots:
		if int(pot.claim) == instance:
			pot.claim = 0
			pot.hauling = false
			_write(pot)


func set_hauling(id: String, hauling: bool) -> void:
	var pot := _find(id)
	if pot.is_empty():
		return
	pot.hauling = hauling
	_write(pot)


func remove(id: String) -> void:
	for index in _pots.size():
		var pot: Dictionary = _pots[index]
		if str(pot.id) != id:
			continue
		for key in ["creel", "buoy", "rope"]:
			var node := pot[key] as Node
			if node != null and is_instance_valid(node):
				node.queue_free()
		_pots.remove_at(index)
		return


func snapshot() -> Array:
	var result: Array = []
	for pot in _pots:
		var drop: Vector2 = pot.drop
		result.append({
			"id": pot.id,
			"owner_id": pot.owner_id,
			"x": drop.x,
			"z": drop.y,
			"depth_m": pot.depth_m,
			"ready_hours": pot.ready_hours,
		})
	return result


func _process(delta: float) -> void:
	for pot in _pots:
		if bool(pot.hauling):
			continue
		_pose(pot)
		_draw_rope(pot, delta)
		_show_timer(pot)


func _pose(pot: Dictionary) -> void:
	var drop: Vector2 = pot.drop
	var surface := WaveSurface.sample_at(drop.x, drop.y).height
	var creel := pot.creel as Node3D
	creel.top_level = true
	creel.global_transform = Transform3D(Basis.IDENTITY, Vector3(drop.x, surface - float(pot.depth_m), drop.y))
	var buoy := pot.buoy as Node3D
	var marker := buoy.get_meta("marker") as Node3D
	buoy.global_position += Vector3(drop.x, surface, drop.y) + Vector3.UP * 0.2 - marker.global_position
	buoy.show()


func _show_timer(pot: Dictionary) -> void:
	var label := pot.timer as Label3D
	var left := maxf(0.0, float(pot.ready_hours) - _game_hours())
	label.text = "Ready" if left <= 0.0 else "%d h" % int(ceil(left))
	label.visible = true


func _draw_rope(pot: Dictionary, delta: float) -> void:
	var creel := pot.creel as Node3D
	var buoy := pot.buoy as Node3D
	var marker := buoy.get_meta("marker") as Node3D
	var bridle := creel.find_child("BridleSocket", true, false) as Node3D
	var end := bridle.global_position if bridle != null else creel.global_position + Vector3.UP * 0.55
	var points := (pot.line as FishingLineShape).advance(delta, marker.global_position, end, 0.35)
	var rope := pot.rope as MeshInstance3D
	rope.show()
	var mesh := rope.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var view := get_viewport().get_camera_3d()
	if view == null or points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var tangent := points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]
		var side := tangent.cross(view.global_position - points[i]).normalized()
		if side.length_squared() < 0.5:
			side = Vector3.RIGHT
		var radius := clampf(view.global_position.distance_to(points[i]) * 0.0012, 0.012, 0.045)
		mesh.surface_add_vertex(points[i] - side * radius)
		mesh.surface_add_vertex(points[i] + side * radius)
	mesh.surface_end()


func _find(id: String) -> Dictionary:
	for pot in _pots:
		if str(pot.id) == id:
			return pot
	return {}


func _write(pot: Dictionary) -> void:
	for index in _pots.size():
		if str(_pots[index].id) == str(pot.id):
			_pots[index] = pot
			return


func _claim_alive(pot: Dictionary) -> bool:
	var instance := int(pot.get("claim", 0))
	if instance == 0:
		return false
	var node := instance_from_id(instance)
	return node != null and is_instance_valid(node)


func _game_hours() -> float:
	var clock: Node = get_node_or_null("/root/WorldClock")
	if clock == null:
		return 0.0
	return float(clock.call("get_game_hours_elapsed"))


func _new_buoy(id: String) -> Node3D:
	var root := (load(BUOY_SCENE) as PackedScene).instantiate() as Node3D
	SurfaceMaterialLibrary.apply(root)
	root.name = "SetBuoy"
	root.top_level = true
	add_child(root)
	var marker := root.find_child("Marker buoy", true, false) as Node3D
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = mesh == marker
	root.set_meta("marker", marker)
	var area := Area3D.new()
	area.name = "CrabInteraction"
	area.collision_layer = 16
	area.collision_mask = 0
	area.set_meta("crab_role", "buoy")
	area.set_meta("crab_index", -1)
	area.set_meta("crab_pot_id", id)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	area.add_child(shape)
	marker.add_child(area)
	root.set_meta("area", area)
	return root


func _new_rope() -> MeshInstance3D:
	var rope := MeshInstance3D.new()
	rope.mesh = ImmediateMesh.new()
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rope.top_level = true
	var filament := StandardMaterial3D.new()
	filament.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	filament.albedo_color = Color(0.33, 0.42, 0.30)
	filament.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope.material_override = filament
	add_child(rope)
	rope.global_transform = Transform3D.IDENTITY
	return rope


func _new_timer() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 16
	label.modulate = Color(1.0, 0.93, 0.62)
	label.position = Vector3(0.0, 0.55, 0.0)
	return label
