extends Node3D

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	# Exercise the production loader, including its detailed/distance children.
	for item in [["harbour_authority_20m", "Office render", "exterior_render"],
		["loaded_storage_rack", "Office render", "packing_cardboard"],
		["lng_terminal_tank_24m", "Office render", "tank_cladding"],
		["insulated_gas_vessel", "Light diffuser", "tank_cladding"]]:
		var root := HarbourEnvironmentKit.model(self, "res://resources/models/parts/port_facilities/"+item[0]+".glb", Vector3.ZERO)
		var found := 0
		for raw in SurfaceMaterialLibrary.meshes(root):
			var mesh := raw as MeshInstance3D
			for index in mesh.mesh.get_surface_count():
				var original := mesh.mesh.surface_get_material(index)
				if original.resource_name.get_slice(".", 0) != item[1]: continue
				assert(original is StandardMaterial3D, "Finishing mutated the imported shared mesh")
				var active := mesh.get_active_material(index)
				assert(active.get_meta("marine_profile", "") == item[2], "Wrong physical surface assignment")
				found += 1
		assert(found > 0, "Expected surface disappeared: "+item[0])
		root.free()
	# Batched quay pieces must carry overrides after their prototype is freed.
	var batches := Node3D.new()
	add_child(batches)
	HarbourEnvironmentKit.repeated(batches, "quay_coping_2m", [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY,Vector3(2,0,0))])
	assert(batches.get_child_count()>0)
	for child in batches.get_children():
		var batch := child as MultiMeshInstance3D
		assert(batch.multimesh.instance_count==2)
		assert(batch.multimesh.mesh.surface_get_material(0).has_meta("marine_profile"))
	batches.free()
	# Common rest coordinates join, but following a moving vessel cannot alter
	# their UV phase. This is the seam/swimming regression boundary.
	var fixture := Node3D.new()
	add_child(fixture)
	var mesh := MeshInstance3D.new()
	mesh.mesh=BoxMesh.new()
	fixture.add_child(mesh)
	SurfaceMaterialLibrary.map_frame(fixture,Transform3D(Basis.IDENTITY,Vector3(2,0,0)))
	var phase:Vector4=mesh.get_instance_shader_parameter("finish_x")
	assert(phase==Vector4(1,0,0,2))
	fixture.position=Vector3(4300,5,-2800)
	fixture.rotation.y=1.4
	assert(mesh.get_instance_shader_parameter("finish_x")==phase)
	fixture.free()
	for id in SurfaceMaterialLibrary.profiles():
		var finish:=SurfaceMaterialLibrary.material(id,Color.WHITE)
		for channel in ["colour_map","normal_map","roughness_map"]:
			assert(finish.get_shader_parameter(channel) is Texture2D, id+" missing "+channel)
	print("SURFACE MATERIAL LIBRARY PASS: asset semantics, imported resources, batch overrides, moving rest frame and all profile maps")
	get_tree().quit()
