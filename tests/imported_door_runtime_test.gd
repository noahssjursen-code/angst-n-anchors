extends Node3D

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(ShipyardPlaytestMode.active())
	var boat := ImportedDraftVessel.new()
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/fishing_trawler.json"))
	boat.configure(stock.brick_layout)
	boat.freeze = true
	add_child(boat)
	for frame in 5: await get_tree().physics_frame
	var interaction := boat.get_node("DoorInteraction")
	var door: ShipPartState
	var leaf: MeshInstance3D
	for part in boat.part_roots:
		if BrickCatalog.get_entry(str(part.get_meta("asset_id", ""))).get("style", "") != "door": continue
		door = part.get_node("PartState")
		for item in boat.moving_colliders:
			if part.is_ancestor_of(item.mesh):
				leaf = item.mesh
				break
		break
	assert(door != null and leaf != null)
	var actor := CharacterBody3D.new()
	actor.add_to_group("player")
	add_child(actor)
	var camera := Camera3D.new()
	actor.add_child(camera)
	camera.current = true
	var center := leaf.to_global(leaf.get_aabb().get_center())
	var normal := door.visual.global_basis.x
	# Exercise actual physics targeting from both sides of the closed leaf.
	for side in [-1.0,1.0]:
		actor.global_position = center+normal*side*1.2
		camera.look_at(center)
		for frame in 3: await get_tree().physics_frame
		assert(interaction.looked_at_door(actor) == door, "Runtime camera must target door from both sides")
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.8,.8,.8)
	shape.shape = box
	blocker.add_child(shape)
	add_child(blocker)
	blocker.global_position = camera.global_position.lerp(center,.5)
	for frame in 3: await get_tree().physics_frame
	assert(interaction.looked_at_door(actor) == null, "World walls must occlude doors")
	blocker.queue_free()
	for frame in 3: await get_tree().physics_frame
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	interaction._unhandled_input(event)
	for frame in 60: await get_tree().physics_frame
	assert(door.state.door_open and door.current_door > .95)
	if OS.get_cmdline_user_args().has("--capture-doors"):
		await capture_door(camera, center, normal, "open")
	interaction.interact(door,center+normal)
	for frame in 60: await get_tree().physics_frame
	assert(not door.state.door_open and door.current_door < .01)
	if OS.get_cmdline_user_args().has("--capture-doors"):
		await capture_door(camera, center, normal, "closed")
	# Late registered identity binds the same assembled door, without mutating
	# it while the authority connection is unavailable.
	boat.set_meta("server_vessel_id", "door-test-vessel")
	var binding: WorldStateBinding = interaction.ensure_binding(door)
	assert(binding != null)
	interaction.interact(door,center+normal)
	assert(not door.state.door_open)
	binding._apply_projection({"revision":4,"state":{"state":{"open":true,"swing":-1.0}}},{})
	assert(door.state.door_open and door.state.door_swing == -1.0)
	binding._apply_projection({"revision":3,"state":{"state":{"open":false}}},{})
	assert(door.state.door_open, "Stale authority replay must not close the door")
	print("PASS imported live doors: shared assembly, ray targeting, occlusion, open/close, late identity and authoritative replay")
	get_tree().quit()

func capture_door(camera: Camera3D, center: Vector3, normal: Vector3, tag: String) -> void:
	if get_node_or_null("ReviewEnvironment") == null:
		var environment := WorldEnvironment.new()
		environment.name = "ReviewEnvironment"
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(.13,.17,.20)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = .5
		add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35,-45,0)
		light.shadow_enabled = true
		add_child(light)
	camera.global_position = center+normal*3+Vector3(0,1.0,2)
	camera.look_at(center)
	for frame in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "C:/Users/noahs/Pictures/machinescreenshots/door-runtime-"+str(Time.get_unix_time_from_system()).replace(".","-")+"-"+tag+".png"
	assert(get_viewport().get_texture().get_image().save_png(output)==OK)
	print("CAPTURE ",output)
