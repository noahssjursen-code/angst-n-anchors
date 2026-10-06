extends Node3D

var failed := false


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var graph := PortLayoutGraph.new()
	graph.initial_attributes = {"foundation": {
		"spine": [[-40.0, 0.0], [-20.0, 0.0], [0.0, 12.0], [20.0, 12.0], [40.0, 0.0]],
		"town_inland_m": 18.0, "dock_reach_m": 12.0, "bay_lip_m": 0.0,
	}}
	var visual := PortLayoutGraphVisualizer.new()
	add_child(visual)
	visual.configure(graph)
	for i in 3: await get_tree().physics_frame
	var surface := visual.get_node("HarbourFoundation") as MeshInstance3D
	var top := PortCoastTracer.FOUNDATION_SURFACE_Y_M + PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var triangles: Array[PackedVector2Array] = []
	var faces := surface.mesh.get_faces()
	for index in range(0, faces.size(), 3):
		if absf(faces[index].y-top)>.001 or absf(faces[index+1].y-top)>.001 or absf(faces[index+2].y-top)>.001:
			continue
		triangles.append(PackedVector2Array([
			Vector2(faces[index].x, faces[index].z), Vector2(faces[index+1].x, faces[index+1].z),
			Vector2(faces[index+2].x, faces[index+2].z),
		]))
	var misses: Array[Vector3] = []
	var ghost_support := 0
	var samples := 0
	for x in range(-55, 56):
		for z in range(-20, 36):
			var p := Vector2(x+.37, z+.29)
			var inside := false
			for triangle in triangles:
				inside = inside or Geometry2D.is_point_in_polygon(p, triangle)
			var hit := get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(Vector3(p.x,top+.2,p.y), Vector3(p.x,top-.2,p.y),1))
			if inside:
				samples += 1
				if hit.is_empty(): misses.append(Vector3(p.x,top,p.y))
			elif not hit.is_empty():
				# Ignore only numerical contact tolerance at the visible boundary.
				var near_edge := false
				for triangle in triangles:
					for edge in 3:
						near_edge = near_edge or p.distance_to(Geometry2D.get_closest_point_to_segment(
							p, triangle[edge], triangle[(edge+1)%3])) < .05
				if not near_edge: ghost_support += 1
	print("PORT SURFACE samples=",samples," missing=",misses.size()," outside=",ghost_support)
	if not misses.is_empty(): print("FIRST GAP ",misses[0])
	check(misses.is_empty(), "Every visible asphalt sample must support the player")
	check(ghost_support == 0, "Foundation must not provide invisible floor outside its outline")
	var player := preload("res://scenes/shared/player.tscn").instantiate() as CharacterBody3D
	add_child(player)
	# Bend and shared-edge positions: use the full production capsule and gravity.
	for position in [Vector3(-20.63,top,-10.71),Vector3(-20,top,12),Vector3(0,top,20),Vector3(20,top,-.5)]:
		player.global_position = position + Vector3.UP*.06
		player.velocity = Vector3.ZERO
		for frame in 35: await get_tree().physics_frame
		check(player.is_on_floor() and absf(player.global_position.y-top)<.04, "Actual player stands on bent asphalt at " + str(position))
	player.free()
	visual.free()
	if not failed: print("PORT SURFACE COLLISION PASS")
	get_tree().quit(1 if failed else 0)
