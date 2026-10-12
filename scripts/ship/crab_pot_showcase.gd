extends Node3D

const PotWork = preload("res://scripts/ship/crab_pot_work.gd")

var boat: ImportedDraftVessel
var station
var player: CharacterBody3D
var camera: Camera3D


func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("7997a6")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.55
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/fishing_crab.json"))
	boat = ImportedDraftVessel.new()
	boat.configure(data.brick_layout)
	add_child(boat)
	boat.freeze = true
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	boat.freeze = true
	boat.get_node("BoatCamera").set_process(false)
	PlayerVessel.mark_player_ship(boat)
	station = boat.get_node("CrabPotStation")
	station.forced_depth = 18.0
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800, 800)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("225969")
	material.roughness = 0.28
	water.material_override = material
	water.position = Vector3(0, WaveSurface.WATER_LEVEL - 0.05, 0)
	add_child(water)
	player = preload("res://scenes/shared/player.tscn").instantiate()
	add_child(player)
	var creel := station._slots[0].creel as Node3D
	player.global_position = creel.global_position + Vector3(1.35, 0.05, -1.1)
	camera = player.get_node("Camera3D")
	camera.current = true
	var review := Camera3D.new()
	review.name = "HandReview"
	add_child(review)
	GameMenu.set_gameplay_hud_visible(true)
	GameMenu.hide_loading()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.get_cmdline_user_args().has("--crab-review"):
		_review.call_deferred()


func aim_at(target: Vector3) -> void:
	var controls := player.get_node("PlayerCamera") as PlayerCamera
	controls._look_yaw = atan2(-(target.x - player.global_position.x), -(target.z - player.global_position.z))
	player.rotation.y = controls._look_yaw
	camera.global_position = player.global_position + Vector3(0, 1.6, 0)
	camera.look_at(target)
	controls._fp_pitch = camera.rotation.x


func _review() -> void:
	for _i in 90:
		await get_tree().physics_frame
	assert(player.is_on_floor(), "Must start on the crabber deck")
	var creel := station._slots[0].creel as Node3D
	var area := station._slots[0].area as Area3D
	player.global_position = creel.global_position + boat.global_basis * Vector3(2.05, 0.05, -1.7)
	for _i in 20:
		await get_tree().physics_frame
	aim_at(area.global_position)
	print("CRAB AIM ", station.hint())
	Input.action_press("interact")
	await get_tree().physics_frame
	Input.action_release("interact")
	var steps := 0
	var shot := false
	while station.phase_of(0) == PotWork.Phase.CARRYING and steps < 90:
		await get_tree().physics_frame
		steps += 1
		if not shot and float(station._slots[0].work.progress) > 0.98:
			_frame_hands(creel)
			await _capture("crab-hands")
			shot = true
			camera.current = true
	print("CRAB GRAB ", station.phase_of(0), " ", station._message, " hands ", shot)
	assert(shot, station._message)
	steps = 0
	while station.phase_of(0) != PotWork.Phase.DEPLOYED and steps < 900:
		await get_tree().physics_frame
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.DEPLOYED, station.hint())
	assert(steps > 40, "The trap must sink after the throw")
	var drop: Vector2 = station._slots[0].drop_xz
	aim_at(Vector3(drop.x, WaveSurface.WATER_LEVEL + 0.4, drop.y))
	await _capture("crab-buoy")
	var hauler_area := station.hauler.get_node("CrabInteraction") as Area3D
	var haul_shape := hauler_area.get_child(0) as CollisionShape3D
	player.global_position = station.hauler.global_position + boat.global_basis * Vector3(-1.2, 0.05, -0.5)
	for _i in 15:
		await get_tree().physics_frame
	aim_at(haul_shape.global_position)
	WorldClock.set_game_hours_elapsed(float(station._slots[0].ready_hours) + 0.05)
	print("CRAB HAUL PROMPT ", station.hint())
	Input.action_press("interact")
	await get_tree().physics_frame
	Input.action_release("interact")
	steps = 0
	while station.phase_of(0) == PotWork.Phase.DEPLOYED and steps < 45:
		await get_tree().physics_frame
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.HAULING, station.hint())
	var mid := steps
	while station.phase_of(0) != PotWork.Phase.STOWED and steps < 1200:
		await get_tree().physics_frame
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.STOWED)
	assert(steps - mid > 60, "Hauling is not instant")
	await _capture("crab-trap-aboard")
	print("CRAB POT LIVE PASS: grab, throw, sink, haul")
	get_tree().quit()


func _frame_hands(creel: Node3D) -> void:
	var review := get_node("HandReview") as Camera3D
	var handle := creel.find_child("RightHandle", true, false) as Node3D
	var mid := handle.global_position if handle != null else creel.global_position
	var side := player.global_basis.x.normalized()
	review.global_position = mid + side * 0.9 + Vector3.UP * 0.22
	review.look_at(mid)
	review.current = true


func _capture(label: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("crab-%s-%d.png" % [label, Time.get_ticks_usec()])
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
