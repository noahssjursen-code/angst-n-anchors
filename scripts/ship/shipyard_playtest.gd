extends Node3D

const PLAYER := preload("res://scenes/shared/player.tscn")
const RENDERER := preload("res://scripts/world/world_renderer.gd")
var boat: ImportedDraftVessel
var player: CharacterBody3D
var controller: BoatController
var camera: BoatCamera
var status: Label
var prompt: Label
var start_transform: Transform3D
var spawn_point := Vector3(0, 3.0, 4)
var ready_to_play := false

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Playtest requires isolated launch arguments.")
		get_tree().quit(1)
		return
	get_window().title = "Boat playtest — isolated ocean"
	get_tree().auto_accept_quit = true
	var snapshot := {"version":1, "hull":"trawler_hull_14m", "parts":[]}
	var path := ShipyardPlaytestMode.snapshot_path()
	if not path.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not ImportedHullCatalog.has(str(parsed.get("hull", ""))) or not parsed.get("parts") is Array:
			push_error("Cannot read the playtest snapshot.")
			get_tree().quit(1)
			return
		snapshot = parsed
		# Only dispose snapshots made by our launcher, never arbitrary supplied drafts.
		var cache := OS.get_cache_dir().path_join("angst-n-anchors-playtest")
		if path.get_base_dir() == cache and path.get_file().begins_with("draft-"):
			DirAccess.remove_absolute(path)
	# This world has no ports, authority backend, company, or saved captain.
	_set_test_weather()
	var renderer := RENDERER.new()
	renderer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(renderer)
	boat = ImportedDraftVessel.new()
	boat.configure(snapshot)
	boat.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	start_transform = boat.transform
	controller = boat.get_node("BoatController")
	camera = boat.get_node("BoatCamera")
	PlayerVessel.mark_player_ship(boat)
	_build_ui()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player = PLAYER.instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	_find_spawn()
	_place_player()
	ready_to_play = true
	if OS.get_cmdline_user_args().has("--verify-playtest"):
		_verify()

func _set_test_weather() -> void:
	WorldClock.set_game_hours_elapsed(12.0)
	WorldWeather.set_blend_to_lighting_paused(true)
	var weather := WeatherState.new()
	weather.wind_speed_ms = 6.0
	weather.wind_force = .35
	weather.sea_state = .35
	weather.significant_wave_height_m = .8
	weather.wind_direction = Vector3(.7, 0, -.7).normalized()
	weather.wind_velocity_ms = weather.wind_direction * weather.wind_speed_ms
	weather.cloud_cover = .25
	weather.visibility = 1.0
	weather.precipitation = 0.0
	weather.zone_label = "Playtest ocean"
	WeatherLighting.set_weather_drives_waves(true)
	WeatherLighting.apply_weather_state(weather)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	layer.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -350
	status.offset_right = -20
	status.offset_top = 145
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.text = "BOAT PLAYTEST · Daylight / moderate waves\nHome · Reset boat\nEsc · Menu / return to builder"
	status.modulate = Color(.8, .9, 1)
	prompt = Label.new()
	layer.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -180
	prompt.offset_right = 180
	prompt.offset_top = -92
	prompt.offset_bottom = -48
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)

func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_play:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_HOME:
		_reset()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		var door := _looked_at_door()
		if door != null:
			door.request_door_from(player.global_position)
			get_viewport().set_input_as_handled()

func _find_spawn() -> void:
	# Capsule clearance includes rails, roofs, console and furniture; stern first.
	var capsule := CapsuleShape3D.new()
	capsule.radius = .36
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = BoatBody.LAYER_BOAT_WALK
	var grid := ImportedHullCatalog.make_grid(str(boat.draft.hull))
	for z in range(int(boat.length_m)-3, -int(boat.length_m)+3, -1):
		for x in [0.0, -1.0, 1.0, -1.8, 1.8]:
			var candidate := Vector3(x, boat.depth_m + .08, float(z) * .5)
			if not Geometry2D.is_point_in_polygon(Vector2(candidate.x,candidate.z),grid.deck_polygon): continue
			var over_opening := false
			for opening in grid.deck_openings:
				if Geometry2D.is_point_in_polygon(Vector2(candidate.x,candidate.z),opening): over_opening = true
			if over_opening: continue
			query.transform = boat.global_transform * Transform3D(Basis(), candidate + Vector3(0, .9, 0))
			if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				spawn_point = candidate
				return
	# Fully occupied lower decks: find the highest walkable surface from above.
	var ray := PhysicsRayQueryParameters3D.create(boat.to_global(Vector3(0, 60, 0)), boat.to_global(Vector3(0, boat.depth_m-.1, 0)), BoatBody.LAYER_BOAT_WALK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		spawn_point = boat.to_local(hit.position) + Vector3(0, .1, 0)

func _place_player() -> void:
	player.global_position = boat.to_global(spawn_point)
	player.rotation.y = boat.rotation.y
	player.velocity = boat.linear_velocity

func _reset() -> void:
	for interaction in boat.get_bridge_stations():
		if interaction.is_occupied():
			interaction._exit()
	controller.deactivate()
	boat.snap_to_transform(start_transform)
	boat.fill_tank()
	_set_test_weather()
	_place_player()
	GameMenu._set_screen(GameMenu.Screen.NONE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if not ready_to_play or get_tree().paused:
		return
	prompt.text = "Press F to open / close door" if _looked_at_door() != null else ""
	if not player.is_vehicle_occupied() and (player.global_position.y < WaveSurface.WATER_LEVEL - .3 or player.global_position.distance_to(boat.global_position) > 30):
		_place_player()
	if Vector2(boat.position.x, boat.position.z).length() > 1500 or boat.position.y < -15:
		_reset()

func _looked_at_door() -> ShipPartState:
	if not is_instance_valid(player) or player.is_vehicle_occupied() or GameMenu._screen != GameMenu.Screen.NONE:
		return null
	var view := get_viewport().get_camera_3d()
	var ray := PhysicsRayQueryParameters3D.create(view.global_position, view.global_position - view.global_basis.z * 3.0, BoatBody.LAYER_BOAT_WALK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return null
	# Map the actual hit shape to its moving door mesh, so walls occlude interaction.
	var body := hit.collider as CollisionObject3D
	var shape := body.shape_owner_get_owner(body.shape_find_owner(hit.shape))
	for item in boat.moving_colliders:
		if item.collision == shape:
			var node: Node = item.mesh
			while node != boat:
				var state := node.get_node_or_null("PartState") as ShipPartState
				if state != null:
					return state
				node = node.get_parent()
	return null

func _quit() -> void:
	get_tree().quit()

func _verify() -> void:
	assert(WeatherLighting.daylight_factor() > .8)
	assert(is_equal_approx(WeatherLighting.sea_state, .35))
	assert(WaveSurface.wave_intensity > WeatherLighting.calm_wave_intensity)
	assert(not PlayerSession._persistent_io_enabled)
	assert(NetworkManager.client == null)
	WorldGateway.begin_session_with_identity(true, "playtest-must-not-connect")
	assert(WorldGateway.get("_backend") == null)
	assert(boat.part_roots.size() == boat.draft.get("parts", []).size())
	var snapshot_before := JSON.stringify(boat.draft)
	for part in boat.part_roots:
		var state := part.get_node_or_null("PartState") as ShipPartState
		if state != null and not part.find_children("DoorLeafPivot*", "Node3D", true, false).is_empty():
			state.request("door_open", true)
	for i in range(120):
		await get_tree().physics_frame
	assert(player.is_on_floor(), "Player must stand on the imported deck")
	for item in boat.moving_colliders:
		assert(item.collision.transform.is_equal_approx(boat._relative_transform(item.mesh)), "Door collision must follow hinge")
	assert(JSON.stringify(boat.draft) == snapshot_before, "Playtest interactions must not edit the snapshot")
	GameMenu._set_screen(GameMenu.Screen.PAUSE)
	var paused_position := boat.global_position
	for i in range(12):
		await get_tree().process_frame
	assert(boat.global_position.is_equal_approx(paused_position), "Playtest menu must pause simulation")
	GameMenu._set_screen(GameMenu.Screen.NONE)
	var initial := boat.global_position
	var helm: BridgeInteractable
	var seat: ImportedSeatInteractable
	for interaction in boat.get_bridge_stations():
		if interaction is ImportedSeatInteractable:
			if interaction.drives_ship:
				helm = interaction
			else:
				seat = interaction
		elif helm == null:
			helm = interaction
	if seat != null:
		_aim_at_interaction(seat)
		assert(seat._boarding_player() == player, "Seat must be targetable")
		_press_f()
		assert(seat.is_occupied() and player.is_vehicle_occupied(), "F event must board the targeted seat")
		assert(not controller._active, "Passenger seats must not drive the vessel")
		_press_f()
		assert(not seat.is_occupied() and not player.is_vehicle_occupied())
	assert(helm != null, "Verification fixture needs a helm")
	_aim_at_interaction(helm)
	assert(helm._boarding_player() == player, "Helm chair or wheel must be targetable")
	_press_f()
	assert(helm.is_occupied() and controller._active, "F must enter the real helm")
	if helm is ImportedSeatInteractable:
		assert(helm.state_driver.state["occupied"], "Helm chair must report seated occupancy")
	assert(controller._ship_hud != null and controller._hud_layer.visible, "Use normal game HUD")
	controller.set_throttle_stage_idx(4)
	for i in range(360):
		await get_tree().physics_frame
	assert(boat.global_position.distance_to(initial) > 1.0, "Shared propulsion must move the draft")
	assert(boat.linear_velocity.length() > .5)
	var stern_gear := boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
	assert(stern_gear.signed_rpm > 0, "Powered ahead propulsion must animate the installed screw")
	var old_yaw := boat.rotation.y
	Input.action_press("move_right")
	for i in range(240):
		await get_tree().physics_frame
	Input.action_release("move_right")
	assert(absf(angle_difference(old_yaw, boat.rotation.y)) > .02, "Shared rudder must turn the draft")
	assert(stern_gear.steering_degrees > 1, "Installed rudder must follow actual helm input")
	camera._mode = BoatCamera.Mode.THIRD_PERSON
	for i in range(120):
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var output := args.find("--capture")
	if output >= 0 and output + 1 < args.size():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[output + 1])
	_press_f()
	assert(not helm.is_occupied() and not player.is_vehicle_occupied())
	assert(not controller._active, "Leaving the helm chair must release vessel controls")
	_place_player()
	for i in range(120):
		await get_tree().physics_frame
	assert(player.is_on_floor(), "Player must remain aboard while the vessel coasts")
	_reset()
	assert(not controller._active and controller.get_throttle_stage_idx() == 1)
	assert(boat.position.distance_to(start_transform.origin) < .1)
	print("PLAYTEST PASS: isolated session, real F-to-helm and seats, normal HUD, doors, walking, pause, drive, rudder and reset")
	# Parent launch test can distinguish a completed verification from a crashed child.
	var verification_path := ShipyardPlaytestMode.snapshot_path()
	if not verification_path.is_empty():
		var marker := FileAccess.open(verification_path + ".verified", FileAccess.WRITE)
		if marker != null:
			marker.store_string("passed")
	_quit()

func _aim_at_interaction(interaction: BridgeInteractable) -> void:
	var target := interaction._interact_area.global_position
	var view := player.get_node("Camera3D") as Camera3D
	for i in range(8):
		var angle := float(i) * TAU / 8.0
		var offset := interaction.global_basis * Vector3(sin(angle), .25, cos(angle)) * .9
		player.global_position = target + offset - Vector3(0, 1.6, 0)
		view.global_position = target + offset
		view.look_at(target)
		if interaction._boarding_player() == player:
			return

func _press_f() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event, true)
	event = InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	get_viewport().push_input(event, true)
