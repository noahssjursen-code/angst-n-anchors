extends "res://tests/compact_world_review.gd"
## Actual generated terrain/forest/ports and production renderer. Paired views
## retain the old zero-clear-air fog response solely for visual comparison.
## Run with --shipyard-playtest --size=40000; all saves/captures are isolated.

func capture(label: String, eye: Vector3, target: Vector3) -> void:
	var diagnostic := OS.get_cmdline_user_args().has("--water-diagnostic")
	if diagnostic and label != "channel": return
	var forest_diagnostic := OS.get_cmdline_user_args().has("--forest-diagnostic")
	if forest_diagnostic and label != "coast": return
	if OS.get_cmdline_user_args().has("--mainland"):
		for definition: PortDefinition in world._generate_definitions():
			if definition.port_id != "port-2": continue
			var frame := Transform3D(Basis(Vector3.UP, definition.rotation_y), definition.world_position)
			if label == "harbour":
				eye = frame * Vector3(160, 90, -350)
				target = frame * Vector3(0, 40, 300)
			elif label == "channel":
				eye = frame * Vector3(0, 9, -1700)
				target = frame * Vector3(0, 220, 5000)
			else:
				eye = frame * Vector3(0, 400, -4500)
				target = frame * Vector3(0, 400, 6500)
			break
	var states := [{"id": "clear", "time": .5, "cloud": .05, "visibility": 1.0, "rain": 0.0}]
	if label == "channel":
		states.append_array([
			{"id": "sunset", "time": .91, "cloud": .12, "visibility": 1.0, "rain": 0.0},
			{"id": "night", "time": .0, "cloud": .25, "visibility": 1.0, "rain": 0.0},
			{"id": "rain", "time": .5, "cloud": .8, "visibility": .76, "rain": .65},
			{"id": "fog", "time": .5, "cloud": .8, "visibility": .35, "rain": .2},
		])
	var renderer := get_tree().get_first_node_in_group("world_renderer") as WorldRenderer
	if forest_diagnostic:
		WeatherLighting.time_of_day=.5;WeatherLighting.cloud_cover=.05
		WeatherLighting.visibility=1.0;WeatherLighting.precipitation=0.0
		await super.capture("forest-terrain-before",eye,target)
		var terrain := world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
		report["terrain_before"]=terrain.get_debug_stats()
		terrain.visual_radius_m=40000
		terrain._last_request_xz=Vector2(INF,INF)
		await super.capture("forest-terrain-40km",eye,target)
		report["terrain_after"]=terrain.get_debug_stats()
		return
	if diagnostic:
		WeatherLighting.time_of_day=.5;WeatherLighting.cloud_cover=.05
		WeatherLighting.visibility=1.0;WeatherLighting.precipitation=0.0
		WeatherLighting.wind_force=.12;WeatherLighting.sea_state=.12
		await super.capture("diagnostic-normal",eye,target)
		var terrain := world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
		terrain.visible=false
		await super.capture("diagnostic-no-terrain",eye,target)
		terrain.visible=true
		renderer.set_ocean_ring_debug(true)
		await super.capture("diagnostic-water-tiers",eye,target)
		renderer.set_ocean_ring_debug(false)
		renderer._ocean_clipmap.visible=false
		await super.capture("diagnostic-no-water",eye,target)
		renderer._ocean_clipmap.visible=true
		return
	for state in states:
		WeatherLighting.time_of_day = state.time
		WeatherLighting.cloud_cover = state.cloud
		WeatherLighting.visibility = state.visibility
		WeatherLighting.precipitation = state.rain
		WeatherLighting.wind_force = .12
		WeatherLighting.sea_state = .12
		WeatherLighting.convection_index = 0
		renderer._apply_weather_lighting()
		# Weather has been frozen by the parent fixture, so direct assignments
		# survive through the measurement without updating the actual game API.
		var env := renderer._environment
		var current := [env.fog_density, env.fog_aerial_perspective, env.fog_sky_affect]
		var fog := 1.0 - float(state.visibility)
		env.fog_density = .009 * pow(fog, 2.15)
		env.fog_aerial_perspective = .24 * fog
		env.fog_sky_affect = .30 * pow(fog, 2.15)
		await super.capture(label + "-" + state.id + "-before", eye, target)
		env.fog_density = current[0]
		env.fog_aerial_perspective = current[1]
		env.fog_sky_affect = current[2]
		await super.capture(label + "-" + state.id + "-after", eye, target)
		report.get_or_add("atmosphere", {})[label + "-" + state.id] = {
			"density": env.fog_density, "aerial": env.fog_aerial_perspective,
			"camera": str(eye), "target": str(target), "state": state,
			"viewport": str(get_viewport().get_visible_rect().size),
		}
