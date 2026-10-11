extends Node3D

## Side and front views of the player IK: standing, walking, and a rolled deck.
## Run with -- --shipyard-playtest. Saves PNGs and checks the feet stay under the body.

var player: CharacterBody3D
var deck: AnimatableBody3D
var camera: Camera3D
var failures: Array[String] = []
var folder := "C:/Users/noahs/Pictures/machinescreenshots/ik-review-" + str(Time.get_unix_time_from_system()).replace(".", "-")


func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest to protect captain saves")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.84)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	deck = AnimatableBody3D.new()
	deck.sync_to_physics = false
	deck.collision_layer = 4
	deck.set_meta("_boat_owner", deck)
	add_child(deck)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.4, 12)
	shape.shape = box
	shape.position = Vector3(0, -0.2, 0)
	deck.add_child(shape)
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = box.size
	mesh.mesh = geometry
	mesh.position = shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.28, 0.22)
	mesh.material_override = mat
	deck.add_child(mesh)
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.position = Vector3(0, 0.1, 0)
	add_child(player)
	call_deferred("run")


var _solved_hip := Vector3.ZERO
var _solved_feet := Vector2.ZERO


func run() -> void:
	await wait_frames(20)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var skeleton := _skeleton()
	var visual: CharacterVisual = player.get_node("BodyMesh").visual
	visual.set_local_first_person(false)
	visual.ik.modification_processed.connect(_on_ik_solved)
	check(skeleton != null, "Player skeleton")
	check(visual.uses_balance_ik(), "Balance IK attached")
	_look_at_player(Vector3(1.7, 1.05, 1.5))
	await wait_frames(10)
	var stand := _solved_feet
	print("STAND feet ", stand, " hip ", _solved_hip)
	check(_feet_under_body(stand), "Standing feet stay under the body")
	await _shot("ik-stand")
	Input.action_press("move_forward")
	var worst := 0.0
	for _i in 40:
		await get_tree().physics_frame
		worst = maxf(worst, _solved_feet.y)
	print("WALK speed ", player.velocity.length(), " worst trail ", worst, " feet ", _solved_feet, " hip ", _solved_hip)
	check(player.velocity.length() > 1.0, "Walk input moves the player")
	check(worst > .2 and worst < .65, "Walking feet take full strides within leg reach")
	_look_at_player(Vector3(1.8, 0.85, 0.15))
	await _shot("ik-walk-side")
	_look_at_player(Vector3(0.15, 1.05, 1.8))
	await _shot("ik-walk-front")
	Input.action_release("move_forward")
	player.velocity = Vector3.ZERO
	await wait_frames(25)
	var before := _solved_hip
	deck.rotation.z = deg_to_rad(16.0)
	await wait_frames(20)
	print("ROLL hip before ", before, " after ", _solved_hip, " feet ", _solved_feet)
	check(absf(_solved_hip.x - before.x) > 0.02, "Rolled deck shifts weight uphill")
	_look_at_player(Vector3(1.9, 0.9, 0.8))
	await _shot("ik-roll")
	print("IK VISUAL RESULT: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func _on_ik_solved() -> void:
	var skeleton := _skeleton()
	if skeleton == null:
		return
	_solved_hip = _bone_local(skeleton, "hips")
	var left := _bone_local(skeleton, "foot.L")
	var right := _bone_local(skeleton, "foot.R")
	_solved_feet = Vector2(maxf(absf(left.x), absf(right.x)), maxf(absf(left.z), absf(right.z)))


func _skeleton() -> Skeleton3D:
	return player.get_node("BodyMesh").visual.skeleton


func _foot_locals(skeleton: Skeleton3D) -> Vector2:
	skeleton.force_update_all_bone_transforms()
	var left := _bone_local(skeleton, "foot.L")
	var right := _bone_local(skeleton, "foot.R")
	return Vector2(maxf(absf(left.x), absf(right.x)), maxf(absf(left.z), absf(right.z)))


func _trail(locals: Vector2) -> float:
	return locals.y


func _feet_under_body(locals: Vector2) -> bool:
	return locals.x < 0.4 and locals.y < 0.4


func _bone_local(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	var world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return player.global_transform.affine_inverse() * world


func _look_at_player(offset: Vector3) -> void:
	var player_camera := player.get_node_or_null("Camera3D") as Camera3D
	if player_camera != null:
		player_camera.current = false
	camera.current = true
	camera.global_position = player.global_position + offset
	camera.look_at(player.global_position + Vector3(0, 0.85, 0), Vector3.UP)


func wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP SHOT ", tag)
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/" + tag + ".png"
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("CAPTURE ", path)
