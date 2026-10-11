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
	for event in Telemetry.load_events: print("BOOT_STAGE ",JSON.stringify(event))
	print("PORT WORLD BOOT PASS")
	world.queue_free()
	for frame in 5: await get_tree().process_frame
	get_tree().quit()
