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
	# Stance phase ankle stays at the authored sole height and cancels forward motion.
	for clip in ["walk", "run"]:
		visual.animation_player.play(clip,0.0)
		var speed := 1.0 if clip == "walk" else 3.75
		var reference_z := 0.0
		for sample in range(3):
			var time := .025 + sample*.05
			visual.animation_player.seek(time,true)
			await get_tree().process_frame
			await get_tree().process_frame
			var foot := visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("foot.L")).origin
			assert(absf(foot.y-.12)<.006, "Planted foot must not bounce: %s t=%s y=%s length=%s" % [clip,time,foot.y,visual.animation_player.current_animation_length])
			if sample == 0: reference_z = foot.z-speed*time
			assert(absf(foot.z-speed*time-reference_z)<.01, "Foot must cancel travel during stance: " + clip)
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
	print("BLENDER CHARACTER PASS: 42-bone rig, palms inward, articulated fingers, planted stance, distance phase, clips, morphs, coverage and save round-trip")
	get_tree().quit()
