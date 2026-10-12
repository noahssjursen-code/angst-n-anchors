extends "res://tests/harbour_performance_probe.gd"

func run() -> void:
	PlayerSession.data = PlayerData.new()
	PlayerSession.data.company = {"development_captain":true}
	PlayerSession.data.home_port_id = "port-home"
	var layout := WorldLayoutGenerator.generate(1212599375)
	var definitions := CoastalPortPlacer.place_ports(layout, 35, PackedStringArray(WorldPortNames.NAMES))
	var best_score := -1.0
	for definition in definitions:
		if definition.region_kind == PortDefinition.RegionKind.ARCHIPELAGO: continue
		var score := 0.0
		for other in definitions:
			if definition.world_position.distance_to(other.world_position) < 4800: score += 1
		if score > best_score:
			best_score = score
			PlayerSession.data.home_port_id = definition.port_id
	print("DENSE LOCATION ",PlayerSession.data.home_port_id," nearby ports=",best_score)
	WorldBootstrap.apply_seed(1212599375,8,"",3,40000)
	world = preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await world.boot_finished
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	camera = player.get_node("Camera3D")
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var origin := player.global_position
	var port := world.get_node("HomePort") as Node3D
	var offsets := [Vector3(30,0,0),Vector3.ZERO,Vector3(-30,0,0),Vector3.ZERO,Vector3(0,0,25),Vector3.ZERO]
	var heading := port.global_basis.x
	var avoidance_count := 0
	var waypoint := 0
	var previous := origin
	var travelled := 0.0
	var samples: Array = []
	var start := Time.get_ticks_usec()
	var last := start
	var elapsed := 0.0
	var blocked_for := 0.0
	var captures := 0
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	while elapsed < 75.0:
		if not clear_walk(player, heading):
			var found := false
			for angle in [PI/2,-PI/2,PI,PI/4,-PI/4]:
				var candidate := heading.rotated(Vector3.UP,angle)
				if clear_walk(player,candidate):
					heading = candidate
					found = true
					avoidance_count += 1
					break
			if not found:
				print("INVALID WALK: no clear route; stopping rather than measuring a stuck player")
				get_tree().quit(2)
				return
		var aim := atan2(-heading.x,-heading.z) + sin(elapsed*.75)*.15
		var yaw: float = player._player_camera.get_look_yaw()
		player._player_camera.shift_look_yaw(clampf(angle_difference(yaw,aim),-.04,.04))
		if absf(angle_difference(yaw,aim)) < .3: Input.action_press("move_forward")
		else: Input.action_release("move_forward")
		if int(elapsed/8)%2 == 1: Input.action_press("player_jog")
		else: Input.action_release("player_jog")
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		elapsed = (now-start)/1000000.0
		var distance := player.global_position.distance_to(previous)
		blocked_for = blocked_for + (now-last)/1000000.0 if distance < 0.001 else 0.0
		if blocked_for > 1.5:
			heading = heading.rotated(Vector3.UP,PI/2)
			blocked_for = 0.0
		travelled += distance
		previous = player.global_position
		samples.append({"elapsed":elapsed,"frame_ms":(now-last)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"position":[previous.x,previous.y,previous.z],"travelled_m":travelled})
		last = now
		if elapsed > (captures+1)*15:
			captures += 1
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(archive.path_join("walking-profile-%d-%d.png" % [Time.get_unix_time_from_system(),captures]))
			print("WALKING_PROBE elapsed=",elapsed," travel=",travelled," position=",player.global_position)
	Input.action_release("move_forward")
	Input.action_release("player_jog")
	var output := "C:/Users/noahs/Documents/Codex/2026-10-11/referenced-chatgpt-conversation-this-is-an/outputs/harbour-walking-performance.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"samples":samples,"telemetry":Telemetry.generate_report()},"\t"))
	print("WALKING_PROBE DONE ",travelled," metres")
	get_tree().quit()

func clear_walk(player: CharacterBody3D, heading: Vector3) -> bool:
	if player.test_move(player.global_transform,heading*3.0): return false
	var point := player.global_position+heading*3.0
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*3,1|4)
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
