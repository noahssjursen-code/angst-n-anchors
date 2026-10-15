extends Node3D

## F6: actual player plus the shared NPC body, isolated from captain data.
## --capture archives native screenshots and exits. O switches inspect/play.
const ARCHIVE := "C:/Users/noahs/Pictures/machinescreenshots"
const MOTIONS := ["idle", "walk", "run", "seated"]
var player: CharacterBody3D
var npc: NpcBase
var body: NpcBase
var camera: Camera3D
var ui: CanvasLayer
var status: Label
var inspect := true
var orbit_yaw := -.22
var orbit_pitch := .08
var orbit_distance := 5.5
var orbit_target := Vector3(0, .98, 0)
var npc_motion := "idle"
var capturing := false
var ready_for_review := false
var held_actions: Array[String] = []
var stamp := "%s-%s" % [Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_usec()]

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Open this showcase with --shipyard-playtest until registered as an isolated showcase")
		get_tree().quit(2)
		return
	GameMenu.set_gameplay_hud_visible(false)
	process_physics_priority = -100
	process_priority = 30
	_build_stage()
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.name = "ActualPlayer"
	player.position = Vector3(-.85, .04, 0)
	add_child(player)
	npc = NpcBase.new()
	npc.name = "ActualNpc"
	npc.position = Vector3(.85, 0, 0)
	add_child(npc)
	var npc_look := CharacterAppearance.default_appearance()
	npc_look.skin_color = Color(.36, .22, .14)
	npc.apply_appearance(npc_look)
	camera = Camera3D.new()
	camera.name = "ReviewCamera"
	camera.fov = 37.0
	add_child(camera)
	_build_ui()
	await _frames(3)
	body = player.get_node_or_null("BodyMesh") as NpcBase
	if body == null or body.visual.skeleton == null or npc.visual.skeleton == null:
		status.text = "The new character asset is not imported yet."
		return
	ready_for_review = true
	_set_inspect(true)
	_update_camera()
	if OS.get_cmdline_user_args().has("--fp-capture"):
		capturing = true
		await _capture_first_person()
	elif OS.get_cmdline_user_args().has("--capture"):
		capturing = true
		await _capture_series()

func _build_stage() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(.085, .115, .135)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(.76, .83, .90)
	world.environment.ambient_light_energy = .38
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 155, 0)
	sun.light_color = Color(1.0, .94, .86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.5, 2.8, -2)
	fill.light_color = Color(.63, .76, 1.0)
	fill.light_energy = .8
	fill.omni_range = 10
	add_child(fill)
	var floor_body := StaticBody3D.new()
	floor_body.name = "ReviewFloor"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, .4, 80)
	collision.shape = box
	collision.position.y = -.2
	floor_body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	mesh.mesh = plane
	mesh.material_override = SurfaceMaterialLibrary.material("deck_grip", Color(.24, .28, .29))
	floor_body.add_child(mesh)
	add_child(floor_body)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var title := Label.new()
	title.text = "CREW / BASE CHARACTER"
	title.position = Vector2(26, 22)
	title.add_theme_font_size_override("font_size", 24)
	ui.add_child(title)
	status = Label.new()
	status.position = Vector2(26, 60)
	status.add_theme_color_override("font_color", Color(.75, .82, .85))
	status.add_theme_font_size_override("font_size", 16)
	ui.add_child(status)
	var help := Label.new()
	help.text = "O  Inspect / walk    1–4  NPC idle / walk / run / seated    F12  Save image\nInspect: drag right mouse to orbit · wheel to zoom    Walk: WASD · Shift run · V change view"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(26, get_viewport().get_visible_rect().size.y - 66)
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(.75, .82, .85))
	ui.add_child(help)

func _process(_delta: float) -> void:
	if not ready_for_review:
		return
	if inspect:
		camera.current = true
		body.visible = true
		body.visual.set_local_first_person(false)
		if not capturing:
			_update_camera()
	if not capturing:
		status.text = "Player + NPC share one imported body  ·  NPC: %s  ·  %s" % [npc_motion, "inspect" if inspect else "live player"]

func _physics_process(_delta: float) -> void:
	if not held_actions.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		for action in held_actions:
			Input.action_press(action)

func _unhandled_input(event: InputEvent) -> void:
	if capturing or not ready_for_review:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			_set_inspect(not inspect)
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			npc_motion = MOTIONS[event.keycode - KEY_1]
			npc.animator.set_preview_motion(npc_motion)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F12:
			await _capture("interactive")
			get_viewport().set_input_as_handled()
	if not inspect:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit_yaw -= event.relative.x * .007
		orbit_pitch = clampf(orbit_pitch + event.relative.y * .005, -.15, 1.2)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(1.2, orbit_distance * .9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(14.0, orbit_distance * 1.1)
		get_viewport().set_input_as_handled()

func _set_inspect(value: bool) -> void:
	inspect = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	player.set_process_unhandled_input(not value)
	if value:
		camera.current = true
		orbit_target = (player.global_position + npc.global_position) * .5 + Vector3.UP * .98
	else:
		var player_camera := player.get_node("Camera3D") as Camera3D
		player_camera.current = true
		var controller := player.get_node("PlayerCamera") as PlayerCamera
		controller._apply_mode()

func _update_camera() -> void:
	var offset := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), -cos(orbit_yaw) * cos(orbit_pitch))
	camera.position = orbit_target + offset * orbit_distance
	camera.look_at(orbit_target)

func _pose(motion: String, phase: float) -> bool:
	var animation := npc.visual.animation_player
	if animation == null or not animation.has_animation(motion):
		push_error("Missing review animation: " + motion)
		return false
	# Zero transition before freezing; a paused crossfade otherwise captures idle.
	animation.play(motion, 0.0)
	animation.speed_scale = 0.0
	animation.seek(animation.get_animation(motion).length * phase, true)
	animation.advance(0.0)
	npc.visual.skeleton.force_update_all_bone_transforms()
	return true

func _frame_npc(offset: Vector3, target_height: float, size: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.global_position = npc.global_position + offset
	camera.look_at(npc.global_position + Vector3.UP * target_height)

func _capture_series() -> void:
	ui.visible = false
	await _frames(30)
	await _capture("player-and-npc")
	body.visible = false
	# _process normally keeps the real player visible during inspection.
	ready_for_review = false
	var look := CharacterAppearance.default_appearance()
	npc.apply_appearance(look)
	_pose("idle", .1)
	_frame_npc(Vector3(.5, 1.15, -4), .95, 2.08)
	await _capture("front")
	_frame_npc(Vector3(3.1, 1.2, -3), .95, 2.08)
	await _capture("three-quarter")
	_frame_npc(Vector3(0, 1.15, 4), .95, 2.08)
	await _capture("back")
	_frame_npc(Vector3(4, 1.15, 0), .95, 2.08)
	await _capture("side")
	var rig := npc.visual.skeleton
	var head_index := rig.find_bone("head")
	if head_index >= 0:
		var head_point := rig.to_global(rig.get_bone_global_pose(head_index).origin) + Vector3.UP * .08
		camera.size = .48
		camera.global_position = head_point + Vector3(.30, .03, -1.0)
		camera.look_at(head_point)
		await _capture("head")
	for side: String in ["L", "R"]:
		var hand_index := rig.find_bone("hand." + side)
		if hand_index < 0:
			continue
		var hand_pose := rig.global_transform * rig.get_bone_global_pose(hand_index)
		var target := hand_pose.origin + hand_pose.basis.y.normalized() * .085
		camera.size = .32
		camera.global_position = target + hand_pose.basis.z.normalized() * .55 + Vector3(0, .08, -.10)
		camera.look_at(target)
		await _capture("hand-" + side)
	var thigh := rig.find_bone("thigh.L")
	var idle_thigh := rig.get_bone_pose_rotation(thigh) if thigh >= 0 else Quaternion.IDENTITY
	for motion: String in ["walk", "run", "seated"]:
		if not _pose(motion, .24):
			get_tree().quit(1)
			return
		if thigh >= 0 and idle_thigh.angle_to(rig.get_bone_pose_rotation(thigh)) < .02:
			push_error("Review pose did not change from idle: " + motion)
			get_tree().quit(1)
			return
		_frame_npc(Vector3(2.1, 1.4, -3.5), .95, 2.12)
		await _capture(motion)
	_pose("idle", .1)
	npc.visible = false
	body.visible = true
	player.position = Vector3(0, .04, 0)
	player.velocity = Vector3.ZERO
	var controller := player.get_node("PlayerCamera") as PlayerCamera
	var player_camera := player.get_node("Camera3D") as Camera3D
	inspect = false
	player_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if controller.get_mode() != PlayerCamera.CameraMode.FIRST_PERSON:
		controller._toggle_mode()
	controller._fp_pitch = -1.05
	controller._apply_mode()
	await _frames(25)
	await _capture("first-person")
	controller._toggle_mode()
	controller._orbit_pitch = .18
	await _frames(20)
	await _capture("third-person")
	held_actions = ["move_forward"]
	await _frames(60)
	await _capture("player-walking")
	held_actions.append("player_jog")
	await _frames(60)
	await _capture("player-running")
	for action in held_actions:
		Input.action_release(action)
	held_actions.clear()
	print("CREW BASE REVIEW: completed native player, NPC, pose and hand captures: ", stamp)
	get_tree().quit()

func _capture_first_person() -> void:
	ui.visible = false
	ready_for_review = false
	npc.visible = false
	player.position = Vector3(0, .04, 0)
	player.velocity = Vector3.ZERO
	_set_inspect(false)
	var controller := player.get_node("PlayerCamera") as PlayerCamera
	if controller.get_mode() != PlayerCamera.CameraMode.FIRST_PERSON:
		controller._toggle_mode()
	for pitch: float in [-.9, -1.05, -1.5]:
		controller._fp_pitch = pitch
		controller._apply_mode()
		await _frames(25)
		await _capture("fp-clearance-%d-deg" % roundi(rad_to_deg(-pitch)))
	controller._toggle_mode()
	await _frames(20)
	await _capture("fp-clearance-restored-third-person")
	print("CREW BASE: first-person clearance review completed ", stamp)
	get_tree().quit()

func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame

func _capture(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ARCHIVE)
	var path := ARCHIVE.path_join("crew-base-%s-%s-%s.png" % [stamp, label, Time.get_ticks_usec()])
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not archive screenshot: " + path)
	else:
		print("CREW BASE CAPTURE ", path)
