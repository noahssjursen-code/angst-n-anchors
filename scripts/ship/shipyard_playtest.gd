extends Node3D

const PLAYER := preload("res://scenes/shared/player.tscn")
const RENDERER := preload("res://scripts/world/world_renderer.gd")
var boat: ImportedDraftVessel
var player: CharacterBody3D
var controller: BoatController
var camera: BoatCamera
var status: Label
var start_transform: Transform3D
var spawn_point := Vector3(0, 3.0, 4)
var ready_to_play := false

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Playtest requires isolated launch arguments.")
		get_tree().quit(1)
		return
	get_window().title = "Boat playtest — coast sandbox"
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
	# A bounded coastal sandbox: production terrain/water/habitat, no world boot,
	# port population, settlements, bridge plans or traffic graph.
	var layout := WorldLayoutGenerator.generate(1212599375, WorldLayoutGenerator.DEFAULT_CONFIG_PATH, 10000.0)
	LandField.initialize(layout)
	FishingField.initialize(layout.seed)
	FishingField.configure_habitat(layout)
	var launch := _find_launch(Vector3.ZERO, snapshot)
	var renderer := RENDERER.new()
	add_child(renderer)
	var terrain := WorldTerrainStreamer.new()
	terrain.visual_radius_m = 1800.0
	terrain.collision_radius_m = 1000.0
	terrain.begin_boot_priority(launch)
	add_child(terrain)
	terrain.configure(layout)
	_set_test_weather()
	boat = ImportedDraftVessel.new()
	boat.configure(snapshot)
	boat.process_mode = Node.PROCESS_MODE_PAUSABLE
	boat.freeze = true
	boat.position = launch
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	boat.snap_to_transform(boat.global_transform)
	boat.freeze = true
	start_transform = boat.transform
	controller = boat.get_node("BoatController")
	camera = boat.get_node("BoatCamera")
	PlayerVessel.mark_player_ship(boat)
	_build_ui()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player = PLAYER.instantiate()
	add_child(player)
	GameMenu.set_gameplay_hud_visible(true)
	GameMenu.hide_loading()
	_find_spawn()
	_place_player()
	terrain.end_boot_priority()
	boat.freeze = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	if OS.get_cmdline_user_args().has("--verify-playtest"):
		_verify()

func _find_launch(origin: Vector3, draft: Dictionary) -> Vector3:
	# Check the entire hull footprint, not only its centre; avoid shallow banks.
	var grid := ImportedHullCatalog.make_grid(str(draft.hull))
	var probes := PackedVector2Array([Vector2.ZERO])
	for corner in grid.deck_polygon:
		for fraction in [0.25, 0.5, 0.75, 1.0, 1.5]: probes.append(corner * fraction)
	for radius in range(100, 2100, 50):
		for i in 32:
			var angle := TAU * float(i) / 32.0
			var point := Vector2(origin.x, origin.z) + Vector2(cos(angle), sin(angle)) * radius
			var clear := true
			for probe in probes:
				if FishingField.habitat.bottom(point + probe) > WaveSurface.WATER_LEVEL - 12.0:
					clear = false
					break
			if clear: return Vector3(point.x, 0, point.y)
	push_error("No safe playtest launch found in coastal sandbox")
	get_tree().quit(1)
	return origin

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
	status.offset_top = 350
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.text = "BOAT PLAYTEST · Coast sandbox\nHome · Reset boat\nF8 · Stop playtest / return to builder"
	status.modulate = Color(.8, .9, 1)

func _unhandled_input(event: InputEvent) -> void:
	if not ready_to_play:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_HOME:
		_reset()
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
	controller.set_throttle_stage_idx(1)
	controller._throttle = 0.0
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

	if not player.is_vehicle_occupied() and (player.global_position.y < WaveSurface.WATER_LEVEL - .3 or player.global_position.distance_to(boat.global_position) > 30):
		_place_player()
	if boat.position.y < -15:
		_reset()

func _quit() -> void:
	get_tree().quit()

func _verify() -> void:
	assert(GameMenu._gameplay and GameMenu._hud_layer.visible, "Production HUD must be enabled")
	assert(FishingField.habitat.layout != null, "Production fishing habitat must exist")
	assert(FishingField.habitat.bottom(Vector2(boat.position.x, boat.position.z)) < WaveSurface.WATER_LEVEL - 12.0, "Launch must clear seabed")
	assert(get_tree().get_nodes_in_group("world").is_empty(), "Sandbox must not boot the global world")
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
	get_tree().paused = true
	var paused_position := boat.global_position
	for i in range(12):
		await get_tree().process_frame
	assert(boat.global_position.is_equal_approx(paused_position), "Pausing the test must pause simulation")
	GameMenu._set_screen(GameMenu.Screen.NONE)
	get_tree().paused = false
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
	var deck_rod := boat.get_node_or_null("RodFishingStation") as RodFishingStation
	if deck_rod != null:
		Input.action_press("fishing_rod")
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("fishing_rod")
		assert(deck_rod.session.phase == "stowed" and not deck_rod.working, "Helm must never operate the deck rod")
	var sonar := boat.get_node_or_null("ShipSounder")
	assert(sonar != null, "Every ship needs a sounder, regardless of equipment")
	for i in 40: await get_tree().physics_frame
	var voyage := LocalPlayerView.get_voyage_snapshot()
	assert(voyage.has("sonar") and voyage.sonar.sounder, "Helm snapshot must expose enabled sonar")
	assert(not voyage.sonar.history.is_empty() and float(voyage.sonar.history[-1].depth_m) > 0, "Sonar must sample real depth")
	assert(GameMenu._hud._fishing.visible and GameMenu._hud._fishing.data.get("sonar_view",false), "Sonar must actually be visible in helm HUD")
	print("SONAR HUD PASS: visible at helm, enabled by default, real depth ",voyage.sonar.history[-1].depth_m)
	var fishing_systems:=boat.get_fishing_systems()
	if not fishing_systems.is_empty():
		await _tap_g()
		assert(fishing_systems[0].trawling and fishing_systems[0].imported_rig.net.visible,"Normal G input must deploy the imported net")
		for i in 90:await get_tree().physics_frame
		var progress:float=fishing_systems[0].imported_rig.deployment_fraction
		assert(progress>0 and progress<1,"Deployment must take time")
		await _tap_g()
		assert(not fishing_systems[0].trawling and fishing_systems[0].imported_rig.net.visible,"G again must begin continuous recovery")
		for i in 240:
			await get_tree().physics_frame
			if not fishing_systems[0].imported_rig.is_transitioning():break
		assert(not fishing_systems[0].imported_rig.net.visible,"Recovery must finish in the deck cradle")
		print("TRAWL INPUT PASS: real G continuous deployment/reversal/recovery from occupied helm")
	controller.toggle_engine()
	assert(boat.get_node("PropulsionComponent").engine_running)
	controller.set_throttle_stage_idx(4)
	for i in range(360):
		await get_tree().physics_frame
	assert(boat.global_position.distance_to(initial) > 1.0, "Shared propulsion must move the draft")
	assert(boat.linear_velocity.length() > .5)
	var stern_gear := boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
	assert(stern_gear.signed_rpm > 0, "Powered ahead propulsion must animate the installed screw")
	var old_yaw := boat.rotation.y
	Input.action_press("move_right")
	# Larger hulls have a longer yaw response; allow proportional travel time,
	# keeping the same minimum actual heading change and full real helm input.
	var turn_frames := ceili(240.0 * maxf(1.0,boat.length_m/14.0))
	for i in range(turn_frames):
		await get_tree().physics_frame
	assert(stern_gear.steering_degrees > 1, "Installed rudder must follow actual helm input")
	Input.action_release("move_right")
	print("HELM CHECK: yaw=",angle_difference(old_yaw,boat.rotation.y)," speed=",boat.linear_velocity.length()," input=",boat.get_node("RudderComponent").rudder_input," force=",boat.get_node("RudderComponent").lateral_force_n," inertia=",boat.inertia)
	assert(absf(angle_difference(old_yaw, boat.rotation.y)) > .02, "Shared rudder must turn the draft")
	camera._mode = BoatCamera.Mode.THIRD_PERSON
	for i in range(120):
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var output := args.find("--capture")
	if output >= 0 and output + 1 < args.size():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[output + 1])
		if not fishing_systems.is_empty():
			await _tap_g()
			camera._zoom_target=42;camera._pitch=.65;camera._yaw=boat.rotation.y+.55
			for i in 960:
				await get_tree().physics_frame
				if not fishing_systems[0].imported_rig.is_transitioning():break
			assert(is_equal_approx(fishing_systems[0].imported_rig.deployment_fraction,1.0))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(args[output+1].get_basename()+"-trawling.png")
			await _tap_g()
			for i in 1200:
				await get_tree().physics_frame
				if not fishing_systems[0].imported_rig.is_transitioning():break
			assert(not fishing_systems[0].imported_rig.net.visible and fishing_systems[0].imported_rig.bundle.visible)
			boat._sync_moving_part_colliders()
			for item in boat.moving_colliders:
				if item.get("fishing_stow",false):assert(not item.collision.disabled)
			print("TRAWL RECOVERY PASS: full recovery on moving wave-driven vessel restores stowed gear and collision")
	_press_f()
	assert(not helm.is_occupied() and not player.is_vehicle_occupied())
	assert(not controller._active, "Leaving the helm chair must release vessel controls")
	_place_player()
	for i in range(120):
		await get_tree().physics_frame
	assert(player.is_on_floor(), "Player must remain aboard while the vessel coasts")
	if deck_rod != null:
		boat.freeze = true
		boat.linear_velocity = Vector3.ZERO
		var view := player.get_node("Camera3D") as Camera3D
		view.current = true
		for i in 16:
			var angle := TAU * float(i) / 16
			player.global_position = deck_rod.authored_station.global_position + boat.global_basis * Vector3(cos(angle)*1.2, .1, sin(angle)*1.2)
			view.global_position = player.global_position + Vector3(0,1.6,0)
			view.look_at(deck_rod._interaction.global_position)
			if deck_rod.can_interact(): break
		assert(deck_rod.can_interact(), "Installed rod must be reachable from deck")
		_press_f()
		assert(deck_rod.working, "F must start deck fishing")
		var look:=player.get_node("PlayerCamera") as PlayerCamera
		var target:=view.global_position+boat.global_basis.x*30-Vector3.UP*3
		look._look_yaw=atan2(-(target.x-player.global_position.x),-(target.z-player.global_position.z))
		player.rotation.y=look._look_yaw
		view.look_at(target);look._fp_pitch=view.rotation.x
		Input.action_press("fishing_rod")
		for i in 45:await get_tree().physics_frame
		Input.action_release("fishing_rod")
		for i in 65:await get_tree().physics_frame
		assert(deck_rod.session.phase == "fishing", "Deck rod input must cast: "+deck_rod.session.message)
		Input.action_press("move_back")
		for i in 8:await get_tree().physics_frame
		Input.action_release("move_back")
		assert(deck_rod.working and deck_rod.session.phase == "fishing", "Walking away must keep the carried rod and line")
		assert(not deck_rod._rod_parts.is_empty(), "Rod mesh must leave its holder")
		assert(helm._boarding_player() == null, "Return rod before taking helm")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/noahs/Pictures/machinescreenshots/carried-rod-%d.png"%Time.get_unix_time_from_system())
		print("DECK ROD PASS: helm rejected, aimed pickup, deck cast, carried rod retained, helm blocked")
	_reset()
	assert(not controller._active and controller.get_throttle_stage_idx() == 1)
	assert(boat.position.distance_to(start_transform.origin) < .1)
	print("PLAYTEST PASS: isolated session, real F-to-helm and seats, doors, walking, pause, drive, rudder and reset")
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

func _tap_g() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_G;event.physical_keycode=KEY_G;event.pressed=true
	Input.parse_input_event(event)
	for i in 4:await get_tree().physics_frame
	event=InputEventKey.new();event.keycode=KEY_G;event.physical_keycode=KEY_G;event.pressed=false
	Input.parse_input_event(event)
	for i in 4:await get_tree().physics_frame

func _press_f() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event, true)
	event = InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	get_viewport().push_input(event, true)
