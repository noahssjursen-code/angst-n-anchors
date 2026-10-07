extends Node
func _ready() -> void: call_deferred("export_cranes")
func export_cranes() -> void:
	assert(ShipyardPlaytestMode.active())
	assert(DisplayServer.get_name() != "headless", "MultiMesh source export requires real renderer transform readback")
	var host:=Node3D.new();add_child(host)
	for kind in ["provision","bulk"]:
		var source:=ImpostorWarmup._build_crane_bake_source(kind)
		host.add_child(source)
		for frame in 5:await get_tree().process_frame
		var clone:=source.duplicate() as Node3D
		ImpostorCache._strip_scripts_recursive(clone)
		ImpostorCache._strip_physics_recursive(clone)
		ImpostorCache._strip_lights_and_cameras(clone)
		host.add_child(clone)
		expand_instances(clone)
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		assert(document.append_from_scene(clone,state)==OK)
		assert(document.write_to_filesystem(state,"res://resources/models/_source/port_distance/"+kind+"_source.glb")==OK)
		clone.free();source.free()
	print("CRANE SOURCES EXPORTED")
	host.free();get_tree().quit()

func expand_instances(node: Node) -> void:
	for child in node.get_children(): expand_instances(child)
	if node is MultiMeshInstance3D:
		var batch := node as MultiMeshInstance3D
		for i in batch.multimesh.instance_count:
			var mesh := MeshInstance3D.new()
			mesh.name = str(batch.name) + "_" + str(i)
			mesh.mesh = batch.multimesh.mesh
			mesh.material_override = batch.material_override
			mesh.transform = batch.transform * batch.multimesh.get_instance_transform(i)
			batch.get_parent().add_child(mesh)
		batch.get_parent().remove_child(batch)
		batch.free()
