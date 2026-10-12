extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	GameSettings.map_generation_seed=424242
	GameSettings.map_layout_checksum=""
	GameSettings.map_world_size_m=40000
	PlayerSession.data.home_port_id="port-home"
	var start := Time.get_ticks_msec()
	var world := preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await world.boot_finished
	var plots := 0
	for child in world.get_children():
		if child is PortPlot: plots+=1
	var loader := world.get_node("ProximityLoader")
	print("WORLD BOOT elapsed_ms=",Time.get_ticks_msec()-start," loaded_port_models=",plots," registered_distant_ports=",loader._entries.size())
	assert(plots==1,"Only the home port should instantiate before the player camera is ready")
	if OS.get_cmdline_user_args().has("--wait-bridges"):
		var bridges := world.get_node("CoastalBridges") as CoastalBridges
		var deadline := Time.get_ticks_msec()+120000
		while bridges.is_processing() and Time.get_ticks_msec()<deadline:
			await get_tree().create_timer(.1).timeout
		assert(not bridges.is_processing() and not bridges.report.structures.is_empty())
		assert(bridges.get_child_count()==bridges.report.structures.size()+1)
		for structure: Dictionary in bridges.report.structures:
			var at: Vector3 = structure.approaches[0]
			assert(ForestField.inside_flatten_zones(Vector2(at.x,at.z).lerp(structure.a,.1),ForestField._flatten_zones))
		print("WORLD BRIDGES PASS structures=",bridges.report.structures.size())
	for event in Telemetry.load_events: print("BOOT_STAGE ",JSON.stringify(event))
	print("PORT WORLD BOOT PASS")
	world.queue_free()
	for frame in 5: await get_tree().process_frame
	get_tree().quit()
