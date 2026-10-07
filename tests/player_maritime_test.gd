extends Node3D

var player: CharacterBody3D
var deck: AnimatableBody3D
var failures: Array[String] = []
var moving := false
var clock := 0.0
var label: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest to protect captain saves")
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.24,.33,.42)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7,.8,1)
	env.environment.ambient_light_energy = .6
	add_child(env)
	deck = AnimatableBody3D.new()
	deck.sync_to_physics = false
	deck.collision_layer = 4
	deck.set_meta("_boat_owner",deck)
	add_child(deck)
	box(deck, Vector3(20, .5, 25), Vector3(0,-.25,0))
	box(deck, Vector3(2,.25,2), Vector3(3,.125,-2))
	box(deck, Vector3(.3,3,8), Vector3(5,1.5,0))
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.position = Vector3(0,.1,0)
	add_child(player)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(120,24)
	label.add_theme_font_size_override("font_size",22)
	canvas.add_child(label)
	label.text = "MARITIME PLAYER REVIEW\nWASD walk | Shift jog | Ctrl precision | Alt look around | V view\nSpace hop | F6 scene requires --shipyard-playtest"
	if OS.get_cmdline_user_args().has("--automated"):
		player.set_process_unhandled_input(false)
		call_deferred("run")

func box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	shape.position = at
	parent.add_child(shape)
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	mesh.position = at
	# Test apparatus only; no production asset is authored here.
	parent.add_child(mesh)

func _physics_process(delta: float) -> void:
	if moving:
		clock += delta
		deck.position.x += delta * 3.0
		deck.rotation.y += delta * .08
		deck.position.y = sin(clock) * .15

func wait_frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	label.text = message + (" â€” PASS" if ok else " â€” FAIL")
	if not ok: failures.append(message)

func run() -> void:
	await wait_frames(30)
	check(player.is_on_floor(), "Standing on deck")
	Input.action_press("move_forward")
	await wait_frames(100)
	check(absf(player.velocity.length() - 1.8) < .1, "Walking pace 1.8 m/s")
	Input.action_press("player_precision")
	await wait_frames(70)
	check(absf(player.velocity.length() - .75) < .1, "Precision pace .75 m/s")
	Input.action_release("player_precision")
	Input.action_press("player_jog")
	await wait_frames(70)
	print("JOG ",player.velocity, " POS ",player.position)
	check(absf(player.velocity.length() - 3.8) < .1, "Jogging pace 3.8 m/s")
	Input.action_release("player_jog")
	Input.action_release("move_forward")
	player.position = Vector3(0,.1,0)
	player.velocity = Vector3.ZERO
	await wait_frames(30)
	var local_start := deck.to_local(player.global_position)
	moving = true
	await wait_frames(150)
	moving = false
	check(deck.to_local(player.global_position).distance_to(local_start) < .25, "Translating, turning and heaving deck carries stationary player")
	check(player.velocity.length() < .2, "Deck movement does not trigger walking animation")
	local_start = deck.to_local(player.global_position)
	moving = true
	Input.action_press("jump")
	await wait_frames(6)
	check(not player.is_on_floor(), "Jump leaves deck")
	Input.action_release("jump")
	await wait_frames(60)
	moving = false
	check(player.is_on_floor() and deck.to_local(player.global_position).distance_to(local_start) < .3, "Jump remains with turning moving ship")
	player._remember_safe_footing()
	var safe := deck.to_local(player.global_position)
	player.set_physics_process(false)
	deck.position.x += 20
	player.global_position = Vector3(0,-10,0)
	player.recover_to_safety()
	player.set_physics_process(true)
	print("RECOVER ",deck.to_local(player.global_position)," expected ",safe)
	check(deck.to_local(player.global_position).distance_to(safe) < .2, "Overboard recovery follows moved deck")
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	cam._fp_pitch = -.4
	cam._toggle_mode()
	cam._toggle_mode()
	check(absf(cam._fp_pitch + .4) < .001, "View switch preserves pitch")
	check(player.get_node("BodyMesh").visible, "First-person body visible")
	check(player.get_node("BodyMesh").visual.get_part("Head").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "First-person head hidden but casts shadow")
	Input.action_press("player_freelook")
	var yaw := player.rotation.y
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(120,0)
	cam.handle_input(mouse)
	check(is_equal_approx(yaw,player.rotation.y) and absf(cam._free_yaw) > .1, "Free look leaves movement heading unchanged")
	Input.action_release("player_freelook")
	cam._fp_pitch = -1.25
	player.get_node("Camera3D").current = true
	await wait_frames(20)
	print("BODY camera ",player.get_node("Camera3D").global_position," feet ",player.global_position," head ",player.get_node("BodyMesh").visual.get_part("Head").get_aabb())
	await capture("first-person-body")
	cam._toggle_mode()
	cam._orbit_pitch = .3
	await wait_frames(10)
	await capture("third-person")
	var station := Node3D.new()
	deck.add_child(station)
	station.position = Vector3(0,0,0)
	check(player.try_leave_station(station, Vector3(0,.15,1.2)), "Seat exit finds standing clearance")
	var blocker := StaticBody3D.new()
	deck.add_child(blocker)
	box(blocker,Vector3(5,3,5),Vector3(0,1.5,1))
	await wait_frames(3)
	check(not player.try_leave_station(station, Vector3(0,.15,1.2)), "Blocked seat exit rejected")
	blocker.queue_free()
	await wait_frames(3)
	await test_vessels()
	print("MARITIME PLAYER RESULT: ", failures)
	player.queue_free()
	await wait_frames(4)
	get_tree().quit(0 if failures.is_empty() else 1)

func test_vessels() -> void:
	deck.position = Vector3(100,0,0)
	for id in ["fishing_trawler", "coastal_coaster"]:
		var path: String = "res://resources/data/vessels/prebuilt/" + id + ".json"
		if not FileAccess.file_exists(path):
			check(false,"Missing stock " + id)
			continue
		var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var boat := ImportedDraftVessel.new()
		boat.configure(stock.brick_layout)
		boat.freeze = true
		add_child(boat)
		await wait_frames(10)
		var ray := PhysicsRayQueryParameters3D.create(Vector3(1,20,-4),Vector3(1,-10,-4),4)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(), id + " walkable deck")
		if not hit.is_empty():
			player.global_position = hit.position + Vector3.UP * .1
			player.velocity = Vector3.ZERO
			await wait_frames(30)
			check(player.is_on_floor(), id + " actual player stands on imported deck")
			var local_point := boat.to_local(player.global_position)
			print("SUPPORT ",player._air_deck.get_ref() if player._air_deck != null else null, " deck ",boat.get_walk_deck().global_position, " boat ",boat.global_position, " actor ",player.global_position)
			for i in 120:
				boat.position.x += .025
				boat.rotation.y += .001
				boat.rotation.z = sin(i * .025) * .03
				# Frozen fixture bypasses rigid-body integration, which normally syncs this.
				boat._sync_walk_deck_transform()
				await get_tree().physics_frame
			print("AFTER deck ",boat.get_walk_deck().global_position, " boat ",boat.global_position," player ",player.global_position," support ",player._air_deck.get_ref() if player._air_deck != null else null)
			print("DECK DRIFT ",id, " ",boat.to_local(player.global_position).distance_to(local_point)," grounded ",player.is_on_floor())
			check(boat.to_local(player.global_position).distance_to(local_point) < .4, id + " player follows moving, rolling vessel")
			local_point = boat.to_local(player.global_position)
			Input.action_press("jump")
			for i in 80:
				boat.position.x += .1
				boat.rotation.y += .001
				boat._sync_walk_deck_transform()
				if i == 8: Input.action_release("jump")
				await get_tree().physics_frame
			check(player.is_on_floor() and boat.to_local(player.global_position).distance_to(local_point) < .35, id + " jump lands at same deck location at 6 m/s")
			await capture(id + "-deck")
		boat.queue_free()
		await wait_frames(5)

func capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/player-" + str(int(Time.get_unix_time_from_system())) + "-" + tag + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ",path)
