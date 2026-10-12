extends Node3D
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var layout := WorldLayoutGenerator.generate(42)
	var features := layout.skerry_features()
	features.sort_custom(func(a: Dictionary,b: Dictionary): return a.radius < b.radius)
	var sampled := 0
	for index in [0,features.size()/2,features.size()-1]:
		var feature: Dictionary = features[index]
		var at: Vector2 = feature.position
		var mesh := WorldTerrainStreamer.build_chunk_mesh_data(layout,WorldTerrainStreamer.world_to_chunk(at),25,[],0)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(WorldTerrainStreamer.collision_faces(mesh))
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var space := get_world_3d().direct_space_state
		for angle in 8:
			var point := at + Vector2.from_angle(angle*TAU/8)*float(feature.width)*.15
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,100,point.y),Vector3(point.x,-10,point.y)))
			assert(not hit.is_empty(),"Physical exposed skerry must stop a downward probe")
			assert(hit.position.y >= WaveSurface.WATER_LEVEL,"Dry rock collision stays above mean sea level")
			sampled += 1
		body.queue_free()
		await get_tree().physics_frame
	print("Skerry live physics collision: PASS probes=",sampled)
	get_tree().quit()
