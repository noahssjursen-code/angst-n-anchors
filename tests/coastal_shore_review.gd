extends "res://tests/compact_world_review.gd"

func capture(label: String, _eye: Vector3, _target: Vector3) -> void:
	WeatherLighting.time_of_day = 0.5
	WeatherLighting.cloud_cover = 0.18
	WeatherLighting.precipitation = 0.0
	WeatherLighting.visibility = 1.0
	WeatherLighting.wind_force = 0.12
	WeatherLighting.sea_state = 0.12
	WeatherLighting.convection_index = 0.0
	for definition: PortDefinition in world._generate_definitions():
		if definition.port_id != "port-2": continue
		var frame := Transform3D(Basis(Vector3.UP, definition.rotation_y), definition.world_position)
		var eye: Vector3
		var target: Vector3
		if label == "harbour":
			eye = frame * Vector3(200, 50, -350)
			target = frame * Vector3(0, 20, 250)
		elif label == "channel":
			eye = frame * Vector3(0, 9, -1300)
			target = frame * Vector3(0, 80, 2300)
		else:
			eye = frame * Vector3(800, 150, -1000)
			target = frame * Vector3(0, 50, 1500)
		camera.global_position = eye
		camera.look_at(target)
		player.global_position = Vector3(eye.x, 5.0, eye.z)
		for tick in 10: await get_tree().process_frame
		var forest := world.get_node("WorldForestStreamer") as WorldForestStreamer
		check(await wait_until(func():
			var stats := forest.get_debug_stats()
			return int(stats.world_canopy_pending) == 0 and int(stats.pending) == 0,
			120.0), label + " complete near and distant forest")
		report.get_or_add("forest", {})[label] = forest.get_debug_stats()
		await super.capture(label, eye, target)
		break
