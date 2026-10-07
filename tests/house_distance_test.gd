extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	assert(ShipyardPlaytestMode.active())
	create_timer(30).timeout.connect(func():quit(1))
	var triangles:=0
	for variant in LandDecorCache.VARIANT_COUNT:
		var source:=LandDecorCache.house_instance(variant,0,0)
		var mesh:=LandDecorCache.house_distance_mesh(variant)
		assert(mesh==LandDecorCache.house_distance_mesh(variant))
		assert(mesh.get_surface_count()==1)
		assert(mesh.get_aabb().is_equal_approx(ImpostorCache.compute_local_aabb(source)))
		var arrays:=mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var cursor:=0
		for child:MeshInstance3D in source.get_children():
			var original:=child.mesh.surface_get_arrays(0)
			for i in original[Mesh.ARRAY_VERTEX].size():
				assert(vertices[cursor].is_equal_approx(original[Mesh.ARRAY_VERTEX][i]))
				assert(normals[cursor].distance_to(original[Mesh.ARRAY_NORMAL][i])<.001,"Normal changed beyond packed GPU precision")
				var expected:Color=child.material_override.albedo_color
				for channel in 4: assert(absf(colors[cursor][channel]-expected[channel])<=1.0/255.0,"Vertex color exceeds GPU byte quantization")
				cursor+=1
		assert(cursor==vertices.size() and cursor/3<100)
		triangles+=cursor/3
		var paint:=mesh.surface_get_material(0) as StandardMaterial3D
		assert(paint.vertex_color_is_srgb and paint.vertex_color_use_as_albedo)
		ImpostorCache.register_geometry("house-test",mesh)
		var proxy:=ImpostorCache.instance("house-test")
		assert(proxy.get_child_count()==1)
		assert((proxy.get_child(0) as MeshInstance3D).mesh==mesh)
		var ghost:=ImpostorCache.instance("house-test",true)
		assert(ghost.get_child_count()==2 and ghost.has_node("FootprintGhost"))
		ghost.free()
		LandDecorCache.clear();ImpostorCache.clear()
		assert((proxy.get_child(0) as MeshInstance3D).mesh.get_surface_count()==1)
		proxy.free();source.free()
	print("HOUSE DISTANCE PASS: eight variants, exact geometry/bounds, packed normals/colors, one shared surface, cache eviction; triangles=",triangles)
	quit()
