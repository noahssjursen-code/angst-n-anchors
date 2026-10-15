extends Node3D

## The real player controller and NPC adapter consume the same new imported body.
## Run with --shipyard-playtest; this fixture never opens or modifies a captain.
const REQUIRED_BONES := ["hips", "spine", "chest", "neck", "head",
	"thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
	"upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"]
const MOTIONS := ["idle", "walk", "run", "seated"]
var failures: Array[String] = []
var player: CharacterBody3D
var npc: NpcBase
var player_body: NpcBase
var held_actions: Array[String] = []

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Crew base integration requires --shipyard-playtest")
		get_tree().quit(2)
		return
	process_physics_priority = -100
	GameMenu.set_gameplay_hud_visible(false)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, .4, 100)
	collision.shape = shape
	collision.position.y = -.2
	floor_body.add_child(collision)
	add_child(floor_body)
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.position = Vector3(-1, .05, 0)
	add_child(player)
	npc = NpcBase.new()
	npc.name = "TestNpc"
	npc.position.x = 1
	add_child(npc)
	await _frames(5)
	player_body = player.get_node_or_null("BodyMesh") as NpcBase
	if not _check(player_body != null and npc.visual != null, "Actual player and NPC build their shared visual adapter"):
		_finish()
		return
	if not _check(player_body.visual.skeleton != null and npc.visual.skeleton != null,
			"New imported model supplies both player and NPC skeletons"):
		_finish()
		return
	if not _check(player_body.visual.animation_player != null and npc.visual.animation_player != null,
			"Imported animation players are available"):
		_finish()
		return
	if OS.get_cmdline_user_args().has("--sole-diagnostic"):
		for phase: float in [0.0, .25, .5, .75]:
			_pose(npc.visual, "idle", phase)
			print("CREW SOLES NPC idle phase=", phase, " left/right metres above root=", _sole_heights(npc.visual))
		await _frames(30)
		print("CREW SOLES actual player IK idle root_y=", player.global_position.y, " sole local_y=", _sole_heights(player_body.visual))
		_finish()
		return
	_check_contract(player_body.visual)
	_check_contract(npc.visual)
	print("CREW BASE: shared player/NPC rig and equipment attachment contract checked")
	_check_meshes(npc.visual)
	_check_appearance()
	print("CREW BASE: imported skin, dimensions and per-instance appearance checked")
	await _check_animations()
	await _check_camera_modes()
	print("CREW BASE: NPC motions, replicated walk entry and first/third-person visibility checked")
	if DisplayServer.get_name() == "headless":
		print("CREW BASE: native controller-input check requires a windowed run (headless display cannot capture the mouse)")
	else:
		await _check_player_movement()
	_finish()

func _physics_process(_delta: float) -> void:
	if not held_actions.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		for action in held_actions:
			Input.action_press(action)

func _check_contract(visual: CharacterVisual) -> void:
	var rig := visual.skeleton
	for bone_name: String in REQUIRED_BONES:
		_check(rig.find_bone(bone_name) >= 0, "Rig contains " + bone_name)
	for clip: String in MOTIONS:
		_check(visual.animation_player.has_animation(clip), "Motion clip: " + clip)
	for side: String in ["L", "R"]:
		for segment: String in ["forearm_twist", "index_01", "index_02", "index_03", "middle_01", "middle_02", "middle_03", "ring_01", "ring_02", "ring_03", "little_01", "little_02", "little_03", "thumb_01", "thumb_02"]:
			_check(rig.find_bone(segment + "." + side) >= 0, "Equipment joint: " + segment + "." + side)
		var foot := rig.find_bone("foot." + side)
		if foot >= 0:
			var ankle := rig.get_bone_global_rest(foot).origin
			_check(ankle.y >= .075 and ankle.y <= .17, "Authored ankle matches existing foot-contact height: " + side)
	_check(visual.get_part("Hands") is MeshInstance3D, "Equipment can resolve the authored Hands mesh")
	for side: String in ["left", "right"]:
		var anchor := visual.get_hand_anchor(side)
		_check(anchor != null and anchor.global_transform.is_finite(), "Live hand attachment: " + side)
	_check_finite_rig(rig)

func _check_meshes(visual: CharacterVisual) -> void:
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty(), "New body has visible imported geometry")
	var bounds := AABB()
	var has_bounds := false
	var count := 0
	for node: Node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			_check(false, "Mesh resource is present: " + str(mesh_node.name))
			continue
		_check(mesh_node.skin != null, "Mesh uses the shared skin: " + str(mesh_node.name))
		var local_transform := visual.global_transform.affine_inverse() * mesh_node.global_transform
		var part_bounds: AABB = local_transform * mesh_node.mesh.get_aabb()
		bounds = bounds.merge(part_bounds) if has_bounds else part_bounds
		has_bounds = true
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights := PackedFloat32Array()
			var bindings := PackedInt32Array()
			if arrays[Mesh.ARRAY_WEIGHTS] != null:
				weights = arrays[Mesh.ARRAY_WEIGHTS]
			if arrays[Mesh.ARRAY_BONES] != null:
				bindings = arrays[Mesh.ARRAY_BONES]
			var stride := int(weights.size() / maxi(1, vertices.size()))
			var valid := stride in [4, 8] and bindings.size() == weights.size()
			for index in vertices.size():
				count += 1
				valid = valid and vertices[index].is_finite()
				if stride not in [4, 8]:
					continue
				var total := 0.0
				for influence in stride:
					var offset := index * stride + influence
					var weight := weights[offset]
					total += weight
					valid = valid and is_finite(weight) and weight >= 0.0
					if weight > .00001 and mesh_node.skin != null:
						valid = valid and bindings[offset] >= 0 and bindings[offset] < mesh_node.skin.get_bind_count()
				valid = valid and absf(total - 1.0) < .015
			_check(valid, "Finite vertices and normalized valid skin weights: %s surface %d" % [mesh_node.name, surface])
	_check(count > 0, "Imported vertex data is populated")
	_check(bounds.position.y >= -.06 and bounds.position.y <= .08, "Body sole datum stays at ground level")
	_check(bounds.size.y > 1.65 and bounds.size.y < 1.95, "Body remains within the 1.8 m gameplay scale")
	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	_check(collision.shape is CapsuleShape3D and is_equal_approx(collision.shape.height, 1.8), "Existing player collision dimensions remain unchanged")

func _skin_material(visual: CharacterVisual) -> StandardMaterial3D:
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for index in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(index) as StandardMaterial3D
			if material != null and material.resource_name.to_lower().contains("skin"):
				return material
	return null

func _check_appearance() -> void:
	var original := _skin_material(player_body.visual)
	var before := original.albedo_color if original != null else Color.WHITE
	var look := CharacterAppearance.default_appearance()
	look.skin_color = Color(.24, .12, .07)
	look.top_id = "legacy_sweater_id"
	look.body_id = "legacy_body_id"
	npc.apply_appearance(look)
	var tint := _skin_material(npc.visual)
	_check(original != null and tint != null, "Both actors expose their skin material")
	if original != null and tint != null:
		_check(original != tint, "Skin materials are independently owned by each actor")
		_check(original.albedo_color.is_equal_approx(before), "NPC tint does not recolour the player")
		_check(tint.albedo_color.is_equal_approx(look.skin_color), "NPC appearance colour reaches the new body")
	_check(look.to_dict() == CharacterAppearance.from_json_string(look.to_json_string()).to_dict(), "Appearance data and unknown saved IDs survive round-trip")
	npc.apply_appearance(CharacterAppearance.default_appearance())

func _pose(visual: CharacterVisual, motion: String, phase: float) -> void:
	var animation := visual.animation_player
	animation.play(motion, 0.0)
	animation.speed_scale = 0.0
	animation.seek(animation.get_animation(motion).length * phase, true)
	animation.advance(0.0)
	visual.skeleton.force_update_all_bone_transforms()

func _check_animations() -> void:
	var visual := npc.visual
	for clip: String in MOTIONS:
		if not visual.animation_player.has_animation(clip):
			return
	_pose(visual, "idle", .1)
	var thigh := visual.skeleton.find_bone("thigh.L")
	if thigh < 0:
		return
	var idle_rotation := visual.skeleton.get_bone_pose_rotation(thigh)
	for motion: String in MOTIONS:
		var first := Quaternion.IDENTITY
		var changed := false
		for index in 9:
			_pose(visual, motion, float(index) / 10.0)
			_check_finite_rig(visual.skeleton)
			_check_skinned_vertices(visual)
			var rotation := visual.skeleton.get_bone_pose_rotation(thigh)
			if index == 0:
				first = rotation
			else:
				changed = changed or first.angle_to(rotation) > .03
		if motion in ["walk", "run"]:
			_check(changed, motion + " genuinely deforms the legs across its cycle")
		if motion == "seated":
			_check(idle_rotation.angle_to(visual.skeleton.get_bone_pose_rotation(thigh)) > .45, "Seated clip bends the thighs rather than capturing idle")
	visual.animation_player.speed_scale = 1.0
	npc.set_motion_speed(1.2, 1.0)
	_check(visual.animation_player.current_animation == "walk", "NPC locomotion chooses walk")
	npc.set_motion_speed(4.5, 1.0)
	_check(visual.animation_player.current_animation == "run", "NPC locomotion chooses run")
	npc.set_idle()
	_check(visual.animation_player.current_animation == "idle", "NPC locomotion returns to idle")
	# This is the exact distance-driven entry used for replicated players.
	npc.set_walk_distance(.25)
	visual.animation_player.advance(.3)
	_check(is_equal_approx(visual.animation_player.current_animation_position,
		visual.animation_player.get_animation("walk").length * .25), "Replicated distance-driven walk retains the exact clip contract")
	npc.set_idle()
	await _frames(2)

func _check_camera_modes() -> void:
	var camera_controller := player.get_node("PlayerCamera") as PlayerCamera
	player_body.visual.set_local_first_person(false)
	var model := player_body.visual.get("_model") as Node3D
	var authored := model.transform
	if camera_controller.get_mode() != PlayerCamera.CameraMode.FIRST_PERSON:
		camera_controller._toggle_mode()
	else:
		camera_controller._apply_mode()
	await _frames(2)
	var first_person := model.transform
	player_body.visual.set_local_first_person(true)
	_check(model.transform == first_person, "Repeated first-person application does not accumulate visual offset")
	var head := player_body.visual.get_part("Head") as MeshInstance3D
	_check(head != null, "New head remains addressable for first-person visibility")
	if head != null:
		_check(head.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"First-person head is hidden while preserving its shadow")
	_check(player_body.visible, "First-person body remains visible")
	camera_controller._toggle_mode()
	await _frames(2)
	_check(model.transform == authored, "Third person restores the exact authored model transform")
	if head != null:
		_check(head.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"Third-person view restores the head")

func _check_player_movement() -> void:
	await _frames(30)
	_check(player.is_on_floor(), "Actual player stands on the fixture floor")
	_check(player_body.visual.uses_balance_ik(), "Actual player attaches existing leg and deck IK")
	var start := player.global_position
	held_actions = ["move_forward"]
	await _frames(75)
	_check(player.global_position.distance_to(start) > 1.0, "Actual controller walks the new visible character")
	var walking_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(walking_speed > float(player.get("walk_speed")) * .7, "Normal controller walking speed is preserved")
	_check_finite_rig(player_body.visual.skeleton)
	_check_skinned_vertices(player_body.visual)
	held_actions.append("player_jog")
	await _frames(75)
	var running_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(running_speed > walking_speed * 1.1, "Actual controller running remains faster than walking")
	_check_finite_rig(player_body.visual.skeleton)
	_check_skinned_vertices(player_body.visual)
	_release_inputs()
	await _frames(40)
	_check(Vector2(player.velocity.x, player.velocity.z).length() < .15, "Player stops cleanly when input is released")
	print("CREW BASE: actual controller walk %.2f m/s, run %.2f m/s, stop and live IK checked" % [walking_speed, running_speed])
	var controller := player.get_node("PlayerCamera") as PlayerCamera
	controller._toggle_mode()
	held_actions = ["move_forward"]
	await _frames(70)
	var first_person_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(first_person_speed > walking_speed * .9, "First-person visual setback preserves normal walking")
	_check_finite_rig(player_body.visual.skeleton)
	_check_skinned_vertices(player_body.visual)
	_release_inputs()
	print("CREW BASE: first-person walk %.2f m/s with visual setback and live IK checked" % first_person_speed)

func _check_skinned_vertices(visual: CharacterVisual) -> void:
	var valid := true
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item.skin == null or item.mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		for index in item.skin.get_bind_count():
			var bone := item.skin.get_bind_bone(index)
			var bind_name := item.skin.get_bind_name(index)
			if not bind_name.is_empty():
				bone = visual.skeleton.find_bone(bind_name)
			if bone < 0 or bone >= visual.skeleton.get_bone_count():
				valid = false
				transforms.append(Transform3D.IDENTITY)
			else:
				transforms.append(visual.skeleton.get_bone_global_pose(bone) * item.skin.get_bind_pose(index))
		for surface in item.mesh.get_surface_count():
			var arrays := item.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_WEIGHTS] == null or arrays[Mesh.ARRAY_BONES] == null:
				valid = false
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var stride := int(weights.size() / maxi(1, vertices.size()))
			for vertex in range(0, vertices.size(), maxi(1, int(vertices.size() / 48))):
				var deformed := Vector3.ZERO
				for influence in stride:
					var offset := vertex * stride + influence
					if bones[offset] < 0 or bones[offset] >= transforms.size():
						valid = false
						continue
					deformed += (transforms[bones[offset]] * vertices[vertex]) * weights[offset]
				valid = valid and deformed.is_finite() and deformed.length() < 4.0
	_check(valid, "Sampled skinned vertices remain finite and within the character envelope", true)

func _sole_heights(visual: CharacterVisual) -> Vector2:
	var heights := Vector2(INF, INF)
	var rig := visual.skeleton
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item.skin == null or item.mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		for index in item.skin.get_bind_count():
			var bone := item.skin.get_bind_bone(index)
			var bind_name := item.skin.get_bind_name(index)
			if not bind_name.is_empty():
				bone = rig.find_bone(bind_name)
			transforms.append(rig.get_bone_global_pose(bone) * item.skin.get_bind_pose(index) if bone >= 0 else Transform3D.IDENTITY)
		for surface in item.mesh.get_surface_count():
			var arrays := item.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_WEIGHTS] == null or arrays[Mesh.ARRAY_BONES] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var stride := int(weights.size() / maxi(1, vertices.size()))
			for vertex in vertices.size():
				if vertices[vertex].y > .17:
					continue
				var deformed := Vector3.ZERO
				for influence in stride:
					var offset := vertex * stride + influence
					deformed += (transforms[bones[offset]] * vertices[vertex]) * weights[offset]
				deformed = visual.to_local(rig.to_global(deformed))
				if vertices[vertex].x > 0:
					heights.x = minf(heights.x, deformed.y)
				else:
					heights.y = minf(heights.y, deformed.y)
	return heights

func _check_finite_rig(rig: Skeleton3D) -> void:
	var finite := true
	for index in rig.get_bone_count():
		var pose := rig.get_bone_global_pose(index)
		finite = finite and pose.is_finite() and absf(pose.basis.determinant()) > .01
	_check(finite, "All posed joint transforms stay finite and nonsingular", true)

func _check(ok: bool, message: String, quiet_success := true) -> bool:
	if not quiet_success or not ok:
		print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)
	return ok

func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame

func _release_inputs() -> void:
	for action in held_actions:
		Input.action_release(action)
	held_actions.clear()

func _finish() -> void:
	_release_inputs()
	print("CREW BASE INTEGRATION: ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
