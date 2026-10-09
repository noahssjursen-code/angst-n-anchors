extends Node3D

## Real controller + imported rig, on land and the same translating/rolling deck.
## F6 with --shipyard-playtest. --baseline records without enforcing gait thresholds.
var player: CharacterBody3D
var deck: AnimatableBody3D
var camera: Camera3D
var label: Label
var moving := false
var clock := 0.0
var frames: Array[Dictionary] = []
var results: Array[Dictionary] = []
var failures: Array[String] = []
var stage := "Preparing"
var recording := false
var captures: Dictionary = {}
var zero_pose_checked := false
var held_action := ""
var folder := "C:/Users/noahs/Pictures/machinescreenshots/gait-" + str(Time.get_unix_time_from_system()).replace(".", "-")

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	process_physics_priority = -40
	process_priority = 20
	DirAccess.make_dir_recursive_absolute(folder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.34, .45, .55)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.8, .85, 1)
	environment.environment.ambient_light_energy = .55
	add_child(environment)
	deck = AnimatableBody3D.new()
	deck.sync_to_physics = false
	deck.collision_layer = 4
	deck.set_meta("_boat_owner", deck)
	deck.set_meta("align_player_capsule", true)
	add_child(deck)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(160, .4, 160)
	collision.position.y = -.2
	deck.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = collision.shape.size
	mesh.position = collision.position
	mesh.material_override = SurfaceMaterialLibrary.material("deck_grip", Color(.3, .34, .32))
	deck.add_child(mesh)
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.position.y = .05
	add_child(player)
	player.get_node("PlayerCamera").set_process(false)
	camera = Camera3D.new()
	add_child(camera)
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(125, 20)
	label.add_theme_font_size_override("font_size", 21)
	ui.add_child(label)
	player.get_node("BodyMesh").visual.ik.modification_processed.connect(_sample)
	call_deferred("run")

func _physics_process(delta: float) -> void:
	# OS focus changes may release synthetic keys between automation stages.
	# Reassert the explicitly scripted hold before the real controller samples it.
	if not held_action.is_empty(): Input.action_press(held_action)
	if moving:
		clock += delta
		deck.position.x += delta * 6.0
		deck.position.y = sin(clock * 1.3) * .3
		deck.rotation = Vector3(sin(clock * .9) * .07, clock * .035, sin(clock * 1.1) * .13)
		if OS.get_cmdline_user_args().has("--rough"):
			deck.rotation.x = sin(clock * .9) * .30
			deck.rotation.z = sin(clock * 1.1) * .22

func _process(_delta: float) -> void:
	if player == null: return
	player.get_node("Camera3D").current = false
	camera.current = true
	player.get_node("BodyMesh").visible = true
	player.get_node("BodyMesh").visual.set_local_first_person(false)
	camera.global_position = player.global_position + player.global_basis * Vector3(3.0, 1.35, .7)
	camera.look_at(player.global_position + Vector3(0, .9, 0))
	label.text = stage + "\n" + ("Recording baseline" if OS.get_cmdline_user_args().has("--baseline") else "Checking stride, planting, balance and joint lengths")

func run() -> void:
	await wait_frames(30)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var walk_preview := OS.get_cmdline_user_args().has("--walk-preview")
	if walk_preview: Engine.max_fps = 60
	for mounted in [false, true]:
		if walk_preview and mounted: continue
		if OS.get_cmdline_user_args().has("--deck-only") and not mounted: continue
		if OS.get_cmdline_user_args().has("--land-only") and mounted: continue
		moving = false
		player._clear_ship_mount()
		deck.collision_layer = 4 if mounted else 1
		if mounted: deck.set_meta("_boat_owner", deck)
		else: deck.remove_meta("_boat_owner")
		deck.transform = Transform3D.IDENTITY
		clock = 0
		player.position = Vector3(0, .04, 0)
		player.velocity = Vector3.ZERO
		await wait_frames(30)
		moving = mounted
		var prefix := "deck" if mounted else "land"
		if walk_preview:
			await upper_body_momentum()
			await exercise("land-walk", 2.0, "move_forward")
			continue
		if OS.get_cmdline_user_args().has("--chaos"):
			await irregular(prefix)
			continue
		await exercise(prefix + "-idle", 0, "")
		if prefix == "land":
			await twist_chain()
		if not OS.get_cmdline_user_args().has("--quick"): await exercise(prefix + "-precision", .75, "move_forward")
		await exercise(prefix + "-walk", 2.0, "move_forward")
		await walking_turns(prefix)
		if prefix == "land":
			await upper_body_momentum()
			await look_while_walking()
			await third_person_reverse()
		await exercise(prefix + "-jog", 3.6, "move_forward")
		if OS.get_cmdline_user_args().has("--quick"): continue
		await exercise(prefix + "-backward", 2.0, "move_back")
		await exercise(prefix + "-strafe", 2.0, "move_right")
		await exercise(prefix + "-left-strafe", 2.0, "move_left")
	var out := FileAccess.open(folder + "/measurements.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"cases": results, "failures": failures}, "\t"))
	# Do not freeze the final test pose while compressing a review sequence.
	# Only immutable Image resources go to the worker; the scene stays on main.
	moving = false
	player.set_physics_process(false)
	player.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stage = "Movement checks finished — saving review images"
	var writer := Thread.new()
	writer.start(_save_captures)
	while writer.is_alive(): await get_tree().process_frame
	var export_errors: Array = writer.wait_to_finish()
	for error in export_errors: check(false, str(error))
	print("GAIT RESULT ", failures, " archive ", folder)
	get_tree().quit(0 if failures.is_empty() else 1)

func exercise(title: String, speed: float, action: String) -> void:
	stage = title
	player.walk_speed = speed
	held_action = action
	if not action.is_empty(): Input.action_press(action)
	for frame in 65:
		await get_tree().physics_frame
		if OS.get_cmdline_user_args().has("--film") and frame % 6 == 0:
			await shot(title + "-start-%03d" % frame)
	frames.clear()
	recording = true
	for i in 120:
		await get_tree().physics_frame
		if i % (2 if OS.get_cmdline_user_args().has("--film") else 15) == 0: await shot(title + "-%03d" % i)
	recording = false
	held_action = ""
	if not action.is_empty(): Input.action_release(action)
	var travel := 0.0
	var min_z := INF
	var max_z := -INF
	var max_hip_delta := 0.0
	var max_joint_error := 0.0
	var airborne := 0
	var max_motion := 0.0
	var max_speed := 0.0
	var left_steps := 0
	var right_steps := 0
	var max_plant_error := 0.0
	var min_pace := 1.0
	var max_pace := 0.0
	var unsupported_walk_frames := 0
	var yaw_min := 0.0
	var yaw_max := 0.0
	var prior: Dictionary = {}
	var min_x := INF
	var max_x := -INF
	for sample in frames:
		var foot: Vector3 = sample.local_left
		min_z = minf(min_z, foot.z)
		max_z = maxf(max_z, foot.z)
		min_x = minf(min_x, foot.x)
		max_x = maxf(max_x, foot.x)
		max_joint_error = maxf(max_joint_error, sample.joint_error)
		if not sample.grounded: airborne += 1
		max_motion = maxf(max_motion, sample.motion.length())
		max_speed = maxf(max_speed, sample.speed)
		max_plant_error = maxf(max_plant_error, sample.plant_error)
		min_pace = minf(min_pace, sample.pace)
		max_pace = maxf(max_pace, sample.pace)
		if sample.swing_l and sample.swing_r:
			unsupported_walk_frames += 1
		var yaw_offset := wrapf(float(sample.support_yaw) - float(frames[0].support_yaw), -PI, PI)
		yaw_min = minf(yaw_min, yaw_offset)
		yaw_max = maxf(yaw_max, yaw_offset)
		if not prior.is_empty():
			max_hip_delta = maxf(max_hip_delta, sample.hip.distance_to(prior.hip))
			if sample.swing_l and not prior.swing_l: left_steps += 1
			if sample.swing_r and not prior.swing_r: right_steps += 1
		prior = sample
	# Strafing angles the legs toward travel, so the stride is in both axes.
	travel = maxf(max_z - min_z, max_x - min_x) if action in ["move_right", "move_left"] else max_z - min_z
	var drag := _drag_metrics()
	var result := {"case": title, "stride_excursion_m": travel, "max_hip_frame_delta_m": max_hip_delta, "max_joint_error_m": max_joint_error, "samples": frames.size(), "grounded": player.is_on_floor(), "airborne_samples": airborne, "max_locomotion_speed": max_motion, "max_gait_speed": max_speed, "left_steps": left_steps, "right_steps": right_steps, "max_plant_error_m": max_plant_error}
	var trace := FileAccess.open(folder + "/" + title + "-trace.json", FileAccess.WRITE)
	result["pace_range"] = [min_pace, max_pace]
	result["both_feet_swinging_frames"] = unsupported_walk_frames
	result["support_heading_range_deg"] = rad_to_deg(yaw_max - yaw_min)
	result.merge(drag)
	trace.store_string(JSON.stringify(frames, "\t"))
	results.append(result)
	print("GAIT ", JSON.stringify(result))
	if not OS.get_cmdline_user_args().has("--baseline"):
		check(max_joint_error < .001, title + " fixed limb lengths")
		check(player.is_on_floor(), title + " remains on ground/deck")
		check(airborne == 0, title + " uninterrupted support contact")
		if speed >= .75: check(left_steps >= 1 and right_steps >= 1, title + " both feet must step")
		if title.ends_with("strafe"):
			check(yaw_max - yaw_min < deg_to_rad(10.0), title + " holds a stable facing through sideways travel")
		if speed >= .75 and speed <= 2.0:
			check(unsupported_walk_frames == 0, title + " transfers weight before lifting the other foot")
		if speed >= 1.8: check(travel > (.22 if action in ["move_right", "move_left"] else .38), title + " full strides")
		if speed == 0: check(max_hip_delta < .012, title + " smooth pelvis")
		if speed >= .75:
			check(drag.stance_slide_m < .03, title + " planted feet do not slide")
			check(drag.sole_contact_error_m < .04, title + " supporting sole stays on the surface")
			check(drag.scrape_frames == 0, title + " swinging feet clear the ground")
	for frame in 30:
		await get_tree().physics_frame
		if OS.get_cmdline_user_args().has("--film") and frame % 6 == 0:
			await shot(title + "-stop-%03d" % frame)

func _sample() -> void:
	if not recording: return
	var skeleton: Skeleton3D = player.get_node("BodyMesh").visual.skeleton
	var left := skeleton.find_bone("foot.L")
	var hip := skeleton.find_bone("hips")
	var local_left: Vector3 = player.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
	var error := 0.0
	for bone_name in ["shin.L", "foot.L", "shin.R", "foot.R", "forearm.L", "hand.L", "forearm.R", "hand.R"]:
		var bone := skeleton.find_bone(bone_name)
		error = maxf(error, skeleton.get_bone_pose_position(bone).distance_to(skeleton.get_bone_rest(bone).origin))
	var ik = player.get_node("BodyMesh").visual.ik
	var plant_error := 0.0
	for i in 2:
		if ik._feet[i].swing: continue
		var actual := skeleton.get_bone_global_pose(skeleton.find_bone("foot.L" if i == 0 else "foot.R")).origin
		plant_error = maxf(plant_error, actual.distance_to(ik._ankle(skeleton, i, ik._support.basis.y.normalized())))
	frames.append({"local_left": local_left, "hip": skeleton.get_bone_global_pose(hip).origin, "joint_error": error, "grounded": player.is_on_floor(), "motion": player.locomotion_velocity(), "speed": ik._speed, "phase": ik._phase, "drop": ik._drop, "air": ik._air_blend, "support": ik._support_id, "dt": get_process_delta_time(), "swing_l": ik._feet[0].swing, "swing_r": ik._feet[1].swing, "plant_error": plant_error})
	frames[-1]["pace"] = player.deck_pace_scale()
	frames[-1]["yaw"] = player.rotation.y
	var support_back: Vector3 = ik._support.basis.inverse() * player.global_basis.z
	frames[-1]["support_yaw"] = atan2(support_back.x, support_back.z)
	frames[-1]["moving"] = ik._moving
	frames[-1]["plant_l"] = ik._feet[0].contact
	frames[-1]["plant_r"] = ik._feet[1].contact
	for i in 2:
		var bone := skeleton.find_bone("foot.L" if i == 0 else "foot.R")
		var world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		frames[-1]["ankle_%d" % i] = ik._support.affine_inverse() * world
		frames[-1]["ground_%d" % i] = ik._feet[i].contact.y
		frames[-1]["heel_%d" % i] = ik._feet[i].heel
		frames[-1]["progress_%d" % i] = ik._feet[i].progress
		frames[-1]["lift_%d" % i] = ik._feet[i].lift
		frames[-1]["cycle_%d" % i] = ik._feet[i].cycle_step
		# Measure actual sole points from the solved bone transform. An ankle
		# legitimately travels while a boot rolls; the contacting sole must not.
		var rest := skeleton.get_bone_global_rest(bone)
		var solved := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		for end in ["heel", "toe"]:
			var sole := rest.origin + Vector3(0, -.115, .095 if end == "heel" else -.175)
			frames[-1]["sole_%s_%d" % [end, i]] = ik._support.affine_inverse() * solved * (rest.affine_inverse() * sole)
	frames[-1]["local_right"] = player.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot.R")).origin
	frames[-1]["knee_clearance"] = skeleton.get_bone_global_pose(skeleton.find_bone("shin.L")).origin.x - skeleton.get_bone_global_pose(skeleton.find_bone("shin.R")).origin.x
	if not zero_pose_checked and ik._moving and ik._support_id != 0:
		zero_pose_checked = true
		var before: Array[Transform3D] = []
		for i in skeleton.get_bone_count(): before.append(skeleton.get_bone_global_pose(i))
		var phase: float = ik._phase
		for repeat in 3: ik._process_modification_with_delta(0.0)
		var same := is_equal_approx(phase, ik._phase)
		for i in skeleton.get_bone_count(): same = same and before[i].is_equal_approx(skeleton.get_bone_global_pose(i))
		check(same, "Zero-time reposes do not advance or snap any bone")

## Planted ankles measured in the support frame: horizontal creep within one
## stance, ignoring heel-off rise. Swinging ankles near the floor while still
## travelling count as scraping.
func _drag_metrics() -> Dictionary:
	var stance_slide := 0.0
	var scrape := 0
	var max_heel := 0.0
	var contact_error := 0.0
	for i in 2:
		var key := "swing_l" if i == 0 else "swing_r"
		var anchor := Vector2.INF
		var pivot := ""
		var prior: Dictionary = {}
		for sample in frames:
			var ankle: Vector3 = sample["ankle_%d" % i]
			var heel: Vector3 = sample["sole_heel_%d" % i]
			var toe: Vector3 = sample["sole_toe_%d" % i]
			var end := "heel" if heel.y < toe.y else "toe"
			var sole: Vector3 = heel if end == "heel" else toe
			var flat := Vector2(sole.x, sole.z)
			max_heel = maxf(max_heel, sample["heel_%d" % i])
			if sample[key]:
				anchor = Vector2.INF
				if not prior.is_empty():
					var prev: Vector3 = prior["sole_%s_%d" % [end, i]]
					var moving := flat.distance_to(Vector2(prev.x, prev.z)) > .006
					if moving and sole.y - float(sample["ground_%d" % i]) < .005 and sample["progress_%d" % i] > .15 and sample["progress_%d" % i] < .85:
						scrape += 1
						if OS.get_cmdline_user_args().has("--verbose"):
							print("  scrape foot ", i, " u ", snappedf(sample["progress_%d" % i], .01), " lift ", snappedf(sample["lift_%d" % i], .001), " h ", snappedf(ankle.y - float(sample["ground_%d" % i]), .001), " cycle ", sample["cycle_%d" % i])
			else:
				contact_error = maxf(contact_error, absf(sole.y - float(sample["ground_%d" % i]) - .005))
				if anchor == Vector2.INF or pivot != end:
					anchor = flat
				stance_slide = maxf(stance_slide, flat.distance_to(anchor))
			pivot = end
			prior = sample
	return {"stance_slide_m": stance_slide, "scrape_frames": scrape, "max_heel_m": max_heel, "sole_contact_error_m": contact_error}

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func twist_chain() -> void:
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	var restore_first := not cam.is_third_person()
	if restore_first:
		cam._toggle_mode()
	stage = "land — look turns head, then torso, then legs"
	player.velocity = Vector3.ZERO
	held_action = ""
	var facing: float = player.rotation.y
	cam._orbit_yaw = facing
	await wait_frames(8)
	var skeleton: Skeleton3D = player.get_node("BodyMesh").visual.skeleton
	_pose_now()
	var base_head := _rel_yaw(skeleton, "head", "hips")
	var base_chest := _rel_yaw(skeleton, "chest", "hips")
	cam._orbit_yaw = facing + deg_to_rad(15.0)
	await wait_frames(12)
	_pose_now()
	var head_small := absf(wrapf(_rel_yaw(skeleton, "head", "hips") - base_head, -PI, PI))
	var chest_small := absf(wrapf(_rel_yaw(skeleton, "chest", "hips") - base_chest, -PI, PI))
	var root_small := absf(wrapf(player.rotation.y - facing, -PI, PI))
	cam._orbit_yaw = facing + deg_to_rad(42.0)
	await wait_frames(12)
	_pose_now()
	var head_mid := absf(wrapf(_rel_yaw(skeleton, "head", "hips") - base_head, -PI, PI))
	var chest_mid := absf(wrapf(_rel_yaw(skeleton, "chest", "hips") - base_chest, -PI, PI))
	var root_mid := absf(wrapf(player.rotation.y - facing, -PI, PI))
	# Past the torso limit the legs turn, then keep turning until the twist unwinds.
	var steps := 0
	var was_swing := [false, false]
	cam._orbit_yaw = facing + deg_to_rad(110.0)
	for frame in 150:
		await get_tree().physics_frame
		var ik = player.get_node("BodyMesh").visual.ik
		for i in 2:
			if ik._feet[i].swing and not was_swing[i]:
				steps += 1
			was_swing[i] = ik._feet[i].swing
		if frame % 15 == 0:
			await shot("land-turn-%03d" % frame)
	_pose_now()
	var root_turned := absf(wrapf(player.rotation.y - facing, -PI, PI))
	var head_after := absf(wrapf(_rel_yaw(skeleton, "head", "hips") - base_head, -PI, PI))
	var chest_after := absf(wrapf(_rel_yaw(skeleton, "chest", "hips") - base_chest, -PI, PI))
	print("TWIST small head ", rad_to_deg(head_small), " chest ", rad_to_deg(chest_small), " root ", rad_to_deg(root_small),
		" | mid head ", rad_to_deg(head_mid), " chest ", rad_to_deg(chest_mid), " root ", rad_to_deg(root_mid),
		" | after root ", rad_to_deg(root_turned), " head ", rad_to_deg(head_after), " chest ", rad_to_deg(chest_after), " steps ", steps)
	check(head_small > deg_to_rad(8.0), "small look turns the head")
	check(chest_small < head_small, "small look moves the head more than the chest")
	check(root_small < deg_to_rad(2.0), "small look does not turn the legs")
	check(chest_mid > deg_to_rad(10.0), "further look turns the chest")
	check(head_mid > chest_mid, "head leads the chest")
	check(root_mid < deg_to_rad(4.0), "legs wait for the torso")
	check(root_turned > deg_to_rad(100.0), "legs follow through to the look")
	check(head_after < deg_to_rad(6.0) and chest_after < deg_to_rad(6.0), "body returns to neutral after the turn")
	check(steps >= 2, "feet step around during a turn in place")
	cam._orbit_yaw = player.rotation.y
	if restore_first and cam.is_third_person():
		cam._toggle_mode()
	await wait_frames(10)

func third_person_reverse() -> void:
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	var restore_first := not cam.is_third_person()
	if restore_first:
		cam._toggle_mode()
	stage = "land — third person: S runs toward the camera"
	player.walk_speed = 2.0
	cam._orbit_yaw = player.rotation.y
	held_action = "move_back"
	Input.action_press("move_back")
	await wait_frames(70)
	var facing := absf(wrapf(player.rotation.y - (cam._orbit_yaw + PI), -PI, PI))
	var twist := absf(player.look_twist())
	held_action = ""
	Input.action_release("move_back")
	print("TP-REVERSE facing error ", rad_to_deg(facing), " twist ", rad_to_deg(twist))
	check(facing < deg_to_rad(10.0), "third person S turns the body to face travel")
	check(twist < deg_to_rad(8.0), "running toward the camera keeps the head relaxed")
	await wait_frames(40)
	cam._orbit_yaw = player.rotation.y
	if restore_first and cam.is_third_person():
		cam._toggle_mode()
	await wait_frames(10)

func walking_turns(prefix: String) -> void:
	stage = prefix + " — walking corners and reversals"
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	player.walk_speed = 2.0
	cam.shift_look_yaw(wrapf(player.rotation.y - cam.get_look_yaw(), -PI, PI))
	held_action = "move_forward"
	Input.action_press(held_action)
	await wait_frames(60)
	var fast_crab_frames := 0
	var min_turn_speed := INF
	var final_facing_error := 0.0
	var unsupported_frames := 0
	for corner in [90.0, -90.0, 180.0]:
		cam.shift_look_yaw(deg_to_rad(corner))
		for tick in 100:
			await get_tree().physics_frame
			var ik: CharacterLegIK = player.get_node("BodyMesh").visual.ik
			if ik._feet[0].swing and ik._feet[1].swing: unsupported_frames += 1
			var motion: Vector3 = player.locomotion_velocity().slide(player._mount_up())
			var speed := motion.length()
			if tick < 40: min_turn_speed = minf(min_turn_speed, speed)
			if tick > 12 and speed > 1.4 and motion.normalized().dot(-player.global_basis.z) < cos(deg_to_rad(40.0)):
				fast_crab_frames += 1
			if tick % (3 if OS.get_cmdline_user_args().has("--film") else 20) == 0:
				await shot(prefix + "-corner-%d-%03d" % [int(corner), tick])
		final_facing_error = maxf(final_facing_error, absf(wrapf(player.rotation.y - cam.get_look_yaw(), -PI, PI)))
	held_action = ""
	Input.action_release("move_forward")
	var report := {"case": prefix + "-corners", "fast_crab_frames": fast_crab_frames, "min_turn_speed": min_turn_speed, "final_facing_error_deg": rad_to_deg(final_facing_error), "unsupported_frames": unsupported_frames}
	results.append(report)
	print("CORNERS ", JSON.stringify(report))
	check(fast_crab_frames == 0, prefix + " normal turns do not become sustained fast crab steps")
	check(min_turn_speed < .9, prefix + " sharp turns brake for the feet")
	check(final_facing_error < deg_to_rad(10.0), prefix + " completes corners and resumes forward walking")
	check(unsupported_frames == 0, prefix + " turning steps always retain a supporting foot")
	await wait_frames(40)

func upper_body_momentum() -> void:
	stage = "land — upper body response to starting and braking"
	await wait_frames(65)
	var skeleton: Skeleton3D = player.get_node("BodyMesh").visual.skeleton
	var chest := skeleton.find_bone("chest")
	var pitch_samples: Array[float] = []
	var forward_peak := 0.0
	var brake_min := INF
	var max_pitch_delta := 0.0
	var settled_pitch := 0.0
	var unsupported := 0
	for frame in 150:
		if frame == 0:
			held_action = "move_forward"
			Input.action_press(held_action)
		if frame == 90:
			held_action = ""
			Input.action_release("move_forward")
		await get_tree().physics_frame
		# Physics resumes before the render-time skeleton modifier. Read its
		# solved pose, not the idle animation's freshly restored bind rotation.
		_pose_now()
		var up := skeleton.global_basis * skeleton.get_bone_global_pose(chest).basis.y.normalized()
		var pitch := rad_to_deg(atan2(up.dot(-player.global_basis.z), up.dot(Vector3.UP)))
		pitch_samples.append(pitch)
		if frame > 0: max_pitch_delta = maxf(max_pitch_delta, absf(pitch - pitch_samples[frame - 1]))
		if frame < 90: forward_peak = maxf(forward_peak, pitch)
		else: brake_min = minf(brake_min, pitch)
		if frame == 89: settled_pitch = pitch
		var ik: CharacterLegIK = player.get_node("BodyMesh").visual.ik
		if ik._feet[0].swing and ik._feet[1].swing: unsupported += 1
		if frame % (3 if OS.get_cmdline_user_args().has("--film") else 15) == 0:
			await shot("land-momentum-%03d" % frame)
	var report := {"case": "land-momentum", "peak_forward_deg": forward_peak, "steady_forward_deg": settled_pitch, "brake_min_deg": brake_min, "max_pitch_delta_deg": max_pitch_delta, "unsupported_frames": unsupported}
	results.append(report)
	print("MOMENTUM ", JSON.stringify(report))
	check(forward_peak > 6.0 and settled_pitch > 3.0, "upper body leans into acceleration and walking")
	check(brake_min < settled_pitch - 3.0, "upper body counterbalances braking")
	check(max_pitch_delta < 2.0, "upper body momentum settles without snapping")
	check(unsupported == 0, "starts and stops retain a supporting foot")
	var trace := FileAccess.open(folder + "/land-momentum-pitch.json", FileAccess.WRITE)
	trace.store_string(JSON.stringify(pitch_samples))

func _pose_now() -> void:
	player.get_node("BodyMesh").visual.ik._process_modification_with_delta(0.0)

func _rel_yaw(skeleton: Skeleton3D, bone_name: String, reference: String) -> float:
	return wrapf(_bone_yaw(skeleton, bone_name) - _bone_yaw(skeleton, reference), -PI, PI)

func _bone_yaw(skeleton: Skeleton3D, bone_name: String) -> float:
	var forward := -skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).basis.z
	forward.y = 0.0
	if forward.length_squared() < .0001:
		return 0.0
	return atan2(forward.x, forward.z)

func look_while_walking() -> void:
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	var restore_first := not cam.is_third_person()
	if restore_first:
		cam._toggle_mode()
	stage = "land — look around while walking"
	player.walk_speed = 2.0
	held_action = "move_forward"
	Input.action_press("move_forward")
	await wait_frames(40)
	frames.clear()
	recording = true
	var base_yaw: float = cam._orbit_yaw
	for i in 120:
		cam._orbit_yaw = base_yaw + sin(float(i) / 120.0 * TAU * 2.0) * .55
		await get_tree().physics_frame
		if i % 15 == 0:
			await shot("land-look-%03d" % i)
	recording = false
	held_action = ""
	Input.action_release("move_forward")
	var steps := 0
	var planted := 0
	var max_slide := 0.0
	var prior: Dictionary = {}
	for sample in frames:
		if prior.is_empty():
			prior = sample
			continue
		if sample.swing_l and not prior.swing_l:
			steps += 1
		if sample.swing_r and not prior.swing_r:
			steps += 1
		if not sample.swing_l and not prior.swing_l:
			planted += 1
			max_slide = maxf(max_slide, sample.plant_l.distance_to(prior.plant_l))
		if not sample.swing_r and not prior.swing_r:
			planted += 1
			max_slide = maxf(max_slide, sample.plant_r.distance_to(prior.plant_r))
		prior = sample
	var report := {"case": "land-look", "steps": steps, "planted_samples": planted, "max_plant_slide_m": max_slide}
	results.append(report)
	print("LOOK ", JSON.stringify(report))
	if not OS.get_cmdline_user_args().has("--baseline"):
		check(steps >= 2 and steps <= 16, "looking around keeps a walking cadence")
		check(planted > 40, "feet stay planted while the camera orbits")
		check(max_slide < .01, "looking around does not drag a planted foot")
	if restore_first and cam.is_third_person():
		cam._toggle_mode()
	await wait_frames(20)

func irregular(prefix: String) -> void:
	stage = prefix + " — reversals, opposing keys, circles and jumps"
	player.walk_speed = 2.0
	frames.clear()
	recording = true
	var actions := ["move_forward", "move_back", "move_left", "move_right", "jump"]
	var patterns := [[0], [1], [2], [3], [0,2], [1,3], [0,1,2,3], [0,4], [1,3], [2], [0], [3], [1], [],
		[0], [0,3], [3], [1,3], [1], [1,2], [2], [0,2], [0,1], [2,3], [2,4], [3]]
	for cycle in 3:
		if cycle == 1: player.get_node("PlayerCamera")._toggle_mode()
		for step in patterns.size():
			for action in actions: Input.action_release(action)
			for index in patterns[step]: Input.action_press(actions[index])
			for tick in 9:
				await get_tree().physics_frame
				if OS.get_cmdline_user_args().has("--film") and tick % 3 == 0:
					await shot(prefix + "-chaos-%d-%02d-%d" % [cycle,step,tick])
			if not OS.get_cmdline_user_args().has("--film") and step % 3 == 0:
				await shot(prefix + "-chaos-%d-%02d" % [cycle,step])
	for action in actions: Input.action_release(action)
	await wait_frames(45)
	recording = false
	held_action = ""
	var crossings := 0
	var min_clearance := INF
	var max_joint_error := 0.0
	var max_foot_jump := 0.0
	var min_knee_clearance := INF
	var airborne := 0
	var prior: Dictionary = {}
	for sample in frames:
		var clearance: float = sample.local_left.x - sample.local_right.x
		min_clearance = minf(min_clearance, clearance)
		if clearance < .07: crossings += 1
		max_joint_error = maxf(max_joint_error, sample.joint_error)
		min_knee_clearance = minf(min_knee_clearance, sample.knee_clearance)
		if not sample.grounded: airborne += 1
		if not prior.is_empty():
			max_foot_jump = maxf(max_foot_jump, sample.local_left.distance_to(prior.local_left))
			max_foot_jump = maxf(max_foot_jump, sample.local_right.distance_to(prior.local_right))
		prior = sample
	var report := {"case": prefix + "-irregular", "crossing_frames": crossings, "min_ankle_clearance_m": min_clearance, "max_foot_frame_delta_m": max_foot_jump, "max_joint_error_m": max_joint_error, "min_knee_clearance_m": min_knee_clearance, "airborne_samples": airborne}
	results.append(report)
	print("IRREGULAR ", JSON.stringify(report))
	var file := FileAccess.open(folder + "/" + prefix + "-irregular-trace.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(frames, "\t"))
	check(crossings == 0, prefix + " opposing inputs never cross legs")
	check(min_knee_clearance > .05, prefix + " knees remain separated through pivots")
	check(max_foot_jump < .3, prefix + " rapid changes do not fling feet")
	check(max_joint_error < .001, prefix + " fixed joints during rapid turns and jumps")
	check(player.is_on_floor(), prefix + " lands after mixed-input jumps")
	check(airborne > 10, prefix + " mixed-input sequence actually exercised jumps")
	if player.get_node("PlayerCamera").is_third_person(): player.get_node("PlayerCamera")._toggle_mode()

func wait_frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--no-captures"): return
	await RenderingServer.frame_post_draw
	captures[folder + "/" + tag + ".png"] = get_viewport().get_texture().get_image()

func _save_captures() -> Array[String]:
	var errors: Array[String] = []
	for path: String in captures:
		var result: Error = captures[path].save_png(path)
		if result != OK: errors.append("Capture write failed: " + path + " (" + str(result) + ")")
	return errors
