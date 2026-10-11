extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var actor := NpcBase.new()
	add_child(actor)
	var other := NpcBase.new()
	add_child(other)
	var visual := actor.visual
	assert(visual.skeleton.get_bone_count() == 42)
	assert(visual.get_hand_anchor("left") != null)
	assert(visual.get_hand_anchor("right") != null)
	for clip in ["idle", "walk", "run", "seated"]:
		assert(visual.animation_player.has_animation(clip))
	var appearance := CharacterCatalog.appearance_preset("dock_worker")
	appearance.build = 1.0
	appearance.belly = 1.0
	appearance.frame = 1.0
	appearance.age = 80
	appearance.skin_color = Color(.25,.13,.08)
	actor.apply_appearance(appearance)
	assert(appearance.to_dict() == CharacterAppearance.from_json_string(appearance.to_json_string()).to_dict())
	assert(not visual.get_part("Body_Torso").visible)
	assert(not visual.get_part("Body_Arms").visible)
	assert(not visual.get_part("Body_Legs").visible)
	assert(not visual.get_part("Body_Feet").visible)
	assert(not visual.get_part("Base_Shorts").visible)
	assert(visual.get_part("Headwear_Hardhat").visible)
	assert(not visual.get_part("Headwear_Cap").visible)
	assert(not visual.get_part("Hair_Crop").visible)
	for item in visual.find_children("*", "MeshInstance3D", true, false):
		assert(item.skin != null, "Every component must share the authored rig")
		assert(item.mesh.get_blend_shape_count() == 4)
		for i in range(4): assert(is_equal_approx(item.get_blend_shape_value(i),1.0))
	var head := visual.get_part("Head") as MeshInstance3D
	var other_head := other.visual.get_part("Head") as MeshInstance3D
	assert(head.get_surface_override_material(0) != other_head.get_surface_override_material(0))
	assert(head.get_surface_override_material(0).albedo_color != other_head.get_surface_override_material(0).albedo_color)
	actor.set_motion_speed(2.0,.1)
	assert(visual.animation_player.current_animation == "walk")
	visual.animation_player.advance(.25)
	await get_tree().process_frame
	await get_tree().process_frame
	visual.skeleton.force_update_all_bone_transforms()
	var first := visual.skeleton.get_bone_pose_rotation(visual.skeleton.find_bone("thigh.L"))
	visual.animation_player.advance(.25)
	await get_tree().process_frame
	await get_tree().process_frame
	visual.skeleton.force_update_all_bone_transforms()
	var second := visual.skeleton.get_bone_pose_rotation(visual.skeleton.find_bone("thigh.L"))
	assert(not first.is_equal_approx(second), "Walk must deform the skeleton")
	# Check authored wrist axes, not just the presence of a named bone.
	visual.animation_player.play("idle",0.0)
	visual.animation_player.speed_scale = 0.0
	visual.animation_player.seek(0.0,true)
	await get_tree().process_frame
	await get_tree().process_frame
	for side in ["L", "R"]:
		var bone := visual.skeleton.find_bone("hand."+side)
		var rest := visual.skeleton.get_bone_global_rest(bone).basis
		var pose := visual.skeleton.get_bone_global_pose(bone).basis
		var sign := 1.0 if side == "L" else -1.0
		var bind_axis := Vector3(sign*.07,-.215,-.02).normalized()
		var bind_normal := Quaternion(bind_axis,sign*PI/2.0) * Vector3(0,0,-1)
		var nails := (pose * rest.inverse() * bind_normal).normalized()
		var outward := Vector3.RIGHT if side == "L" else Vector3.LEFT
		assert(nails.dot(outward) > .75, "Palms must face thighs at rest: " + side)
		assert(visual.skeleton.find_bone("forearm_twist."+side) >= 0)
		assert(visual.skeleton.find_bone("index_02."+side) >= 0)
	# Imported clips must keep the bind lengths through the entire cycle. This
	# catches the old translated elbow/wrist animation, including at loop seams.
	var rig := visual.skeleton
	for clip in ["idle", "walk", "run", "seated"]:
		visual.animation_player.play(clip,0.0)
		var duration := visual.animation_player.get_animation(clip).length
		var previous: Array[Quaternion] = []
		var initial: Array[Quaternion] = []
		for frame in range(int(round(duration*60.0))+1):
			visual.animation_player.seek(minf(frame/60.0,duration),true)
			rig.force_update_all_bone_transforms()
			for bone in range(rig.get_bone_count()):
				var rest := rig.get_bone_rest(bone)
				var pose := rig.get_bone_pose(bone)
				var name := rig.get_bone_name(bone)
				assert(pose.basis.get_scale().distance_to(Vector3.ONE)<.001, "No animated bone scaling: "+name)
				if name != "hips":
					assert(rest.origin.distance_to(pose.origin)<.001, "No animated joint translations: "+name)
				var rotation := rig.get_bone_pose_rotation(bone)
				if frame == 0:
					initial.append(rotation)
					previous.append(rotation)
				elif name.begins_with("upper_arm") or name.begins_with("forearm") or name.begins_with("hand"):
					assert(previous[bone].angle_to(rotation)<.20, "Continuous arm motion: "+clip+"/"+name)
				if frame == int(round(duration*60.0)):
					assert(initial[bone].angle_to(rotation)<.005, "Clip joins without a pose jump: "+clip+"/"+name)
				previous[bone] = rotation
	# Heel/toe roll can lift the ankle; horizontal stance still cancels travel.
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/characters/animation_contract.json"))
	for clip in ["walk", "run"]:
		visual.animation_player.play(clip,0.0)
		visual.animation_player.seek(0.0,true)
		rig.force_update_all_bone_transforms()
		var start_hand := rig.get_bone_global_pose(rig.find_bone("hand.L")).origin.z
		var start_foot := rig.get_bone_global_pose(rig.find_bone("foot.L")).origin.z
		visual.animation_player.seek(visual.animation_player.get_animation(clip).length*.5,true)
		rig.force_update_all_bone_transforms()
		var end_hand := rig.get_bone_global_pose(rig.find_bone("hand.L")).origin.z
		var end_foot := rig.get_bone_global_pose(rig.find_bone("foot.L")).origin.z
		assert((end_hand-start_hand)*(end_foot-start_foot)<0.0, "Arm and leg swing oppose on each side: "+clip)
		var speed: float = contract[clip+"_stride_m"] / visual.animation_player.get_animation(clip).length
		var reference_z := 0.0
		for sample in range(3):
			var time := .025 + sample*.05
			visual.animation_player.seek(time,true)
			await get_tree().process_frame
			await get_tree().process_frame
			var foot := visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("foot.L")).origin
			assert(foot.y>=.114 and foot.y<.20, "Ankle stays within heel/toe contact envelope: %s y=%s" % [clip,foot.y])
			if sample == 0: reference_z = foot.z-speed*time
			assert(absf(foot.z-speed*time-reference_z)<.01, "Foot must cancel travel during stance: " + clip)
	# Exercise the gameplay selector and its crossfades, not only isolated clips.
	actor.set_idle()
	visual.animation_player.play("idle",0.0)
	visual.animation_player.advance(0.0)
	var arm_previous: Dictionary = {}
	for frame in 300:
		var speed := 1.8 if frame<100 else (3.8 if frame<200 else 0.0)
		actor.set_motion_speed(speed,1.0/60.0)
		visual.animation_player.advance(1.0/60.0)
		rig.force_update_all_bone_transforms()
		for side in ["L","R"]:
			for segment in ["upper_arm.","forearm.","hand."]:
				var name: String = segment+side
				var rotation := rig.get_bone_pose_rotation(rig.find_bone(name))
				if arm_previous.has(name):
					assert(arm_previous[name].angle_to(rotation)<.4,"Gameplay transition cannot snap arm: "+name)
				arm_previous[name] = rotation
	actor.set_walk_distance(1.25)
	assert(is_equal_approx(visual.animation_player.current_animation_position,.25))
	appearance.top_id = "none"
	appearance.trousers_id = "none"
	appearance.footwear_id = "none"
	actor.apply_appearance(appearance)
	assert(visual.get_part("Body_Torso").visible)
	assert(visual.get_part("Body_Arms").visible)
	assert(visual.get_part("Body_Legs").visible)
	assert(visual.get_part("Body_Feet").visible)
	assert(visual.get_part("Base_Shorts").visible)
	assert(not visual.get_part("Top_Sweater").visible)
	for folder in ["res://resources/data/models/characters", "res://resources/data/meshes/characters"]:
		assert(not DirAccess.dir_exists_absolute(folder), "Do not restore retired JSON geometry")
	print("BLENDER CHARACTER PASS: 42 bones, fixed joint positions/scales, continuous FK arms, seamless loops, palms inward, foot travel, morphs, coverage and save round-trip")
	get_tree().quit()
