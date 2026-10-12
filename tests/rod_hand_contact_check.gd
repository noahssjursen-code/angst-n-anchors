extends RefCounted
## Checks final modifier poses and actual weighted hand vertices, not rest bones.
var poses:Array[Transform3D]=[]
func record(skeleton:Skeleton3D)->void:
	poses.clear()
	for bone in skeleton.get_bone_count():poses.append(skeleton.get_bone_global_pose(bone))

func run(scene:Node3D)->void:
	for frame in 90:await scene.get_tree().physics_frame
	var player:CharacterBody3D=scene.player
	var station:RodFishingStation=scene.station
	var visual:CharacterVisual=player.get_node("BodyMesh").visual
	var hands:MeshInstance3D=visual.get_part("Hands")
	var skeleton:=visual.skeleton
	skeleton.skeleton_updated.connect(record.bind(skeleton))
	var controller:PlayerCamera=player.get_node("PlayerCamera")
	player.set_process(false);player.set_physics_process(false)
	station.working=true;station._carry(true)
	var contacts:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/characters/hand_contacts.json"))
	var worst:=0.0
	for third in [false,true]:
		if controller.is_third_person()!=third:controller._toggle_mode()
		for angle in [-.8,0.0,.65]:
			for crank in [0.0,PI*.5,PI,PI*1.5]:
				scene.camera.rotation.x=angle;station._crank.rotation.x=crank
				for frame in 5:await scene.get_tree().process_frame
				assert(poses.size()==50)
				for side in ["L","R"]:
					var contact:Vector3=Vector3(contacts[side].palm_contact[0],contacts[side].palm_contact[1],contacts[side].palm_contact[2])
					for index in hands.mesh.get_blend_shape_count():
						var key:=str(hands.mesh.get_blend_shape_name(index));var delta:Array=contacts[side].morph_deltas[key]
						contact+=Vector3(delta[0],delta[1],delta[2])*hands.get_blend_shape_value(index)
					var hand:int=skeleton.find_bone("hand."+side)
					var actual:Vector3=skeleton.global_transform*poses[hand]*contact
					var socket:Node3D=station._hand_pose.right_grip if side=="L" else station._hand_pose.left_grip
					var expected:=socket.global_position+(station._rod_root.global_basis.y*.012 if side=="R" else Vector3.ZERO)
					var error:=actual.distance_to(expected);worst=maxf(worst,error)
					if error>=.012:
						print("GRIP FAIL shoulder=",skeleton.to_global(poses[skeleton.find_bone("upper_arm."+side)].origin)," wrist=",skeleton.to_global(poses[hand].origin)," socket=",expected," contact=",actual," local_contact=",contact," rod=",station._rod_root.global_transform," skeleton=",skeleton.global_transform)
					assert(error<.012,"Hand must stay on equipment: side %s, TP %s, pitch %.2f, crank %.2f, error %.3fm"%[side,third,angle,crank,error])
					for segment in [["upper_arm","forearm"],["forearm","hand"]]:
						var a:=skeleton.find_bone(segment[0]+"."+side);var b:=skeleton.find_bone(segment[1]+"."+side)
						var length:=skeleton.get_bone_global_rest(a).origin.distance_to(skeleton.get_bone_global_rest(b).origin)
						assert(absf(poses[a].origin.distance_to(poses[b].origin)-length)<.001,"Arm length must not stretch")
	# Continually changing aim must not leave the hands one frame behind the rod.
	controller._toggle_mode()
	for frame in 90:
		scene.camera.rotation.x=sin(frame*.1)*.5
		station._crank.rotation.x=frame*.15
		await scene.get_tree().process_frame
		var data:Array=contacts.L.palm_contact
		var contact:=Vector3(data[0],data[1],data[2])
		for index in hands.mesh.get_blend_shape_count():
			var delta:Array=contacts.L.morph_deltas[str(hands.mesh.get_blend_shape_name(index))]
			contact+=Vector3(delta[0],delta[1],delta[2])*hands.get_blend_shape_value(index)
		var actual:=skeleton.global_transform*poses[skeleton.find_bone("hand.L")]*contact
		assert(actual.distance_to(station._hand_pose.right_grip.global_position)<.012,"Moving aim must not detach hand from rod")
	controller._toggle_mode()
	# Inspect the actual imported skinned mesh at a neutral crank angle.
	station._crank.rotation.x=0
	for frame in 5:await scene.get_tree().process_frame
	_check_skin(station,hands,skeleton)
	var heavy:=visual.appearance.duplicate()
	heavy.build=1;heavy.belly=1;heavy.frame=1;heavy.age=80;visual.apply_appearance(heavy)
	for frame in 5:await scene.get_tree().process_frame
	_check_skin(station,hands,skeleton)
	# Every appearance still resolves its Blender-authored palm anchor.
	for side in ["L","R"]:
		var data:Array=contacts[side].palm_contact;var contact:=Vector3(data[0],data[1],data[2])
		for index in hands.mesh.get_blend_shape_count():
			var delta:Array=contacts[side].morph_deltas[str(hands.mesh.get_blend_shape_name(index))]
			contact+=Vector3(delta[0],delta[1],delta[2])*hands.get_blend_shape_value(index)
		var actual:=skeleton.global_transform*poses[skeleton.find_bone("hand."+side)]*contact
		var socket:Node3D=station._hand_pose.right_grip if side=="L" else station._hand_pose.left_grip
		var target:=socket.global_position+(station._rod_root.global_basis.y*.012 if side=="R" else Vector3.ZERO)
		assert(actual.distance_to(target)<.012,"Maximum body morph must keep palm contact")
	station.working=false;station._carry(false)
	for frame in 5:await scene.get_tree().process_frame
	assert(not is_instance_valid(station._hand_pose),"Stowing releases equipment pose")
	print("HAND CONTACT PASS: first/third person, three pitch angles, full crank rotation, fixed arm lengths, stow; worst contact error %.2f mm"%(worst*1000))
	skeleton.skeleton_updated.disconnect(record.bind(skeleton))
	scene.get_tree().quit()

func _check_skin(station:RodFishingStation,hands:MeshInstance3D,skeleton:Skeleton3D)->void:
	var rows:Array=[]
	var bind_transforms:Array[Transform3D]=[]
	for bind in hands.skin.get_bind_count():
		var bone:=skeleton.find_bone(hands.skin.get_bind_name(bind))
		if bone<0:bone=hands.skin.get_bind_bone(bind)
		bind_transforms.append(poses[bone]*hands.skin.get_bind_pose(bind))
	for surface in hands.mesh.get_surface_count():
		var arrays:=hands.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var shapes:=hands.mesh.surface_get_blend_shape_arrays(surface)
		for index in vertices.size():
			var vertex:=vertices[index]
			for key in shapes.size():vertex+=(shapes[key][Mesh.ARRAY_VERTEX][index]-vertices[index])*hands.get_blend_shape_value(key)
			var point:=Vector3.ZERO
			for influence in 4:point+=(bind_transforms[bones[index*4+influence]]*vertex)*weights[index*4+influence]
			var rod_point:=station._rod_root.to_local(skeleton.to_global(point))
			rows.append([rod_point.x,rod_point.y,rod_point.z,vertices[index].x,surface])
	var dump:=FileAccess.open("res://.codex/posed_hand_vertices.json",FileAccess.WRITE);dump.store_string(JSON.stringify(rows));dump.close()
	for side in [1,-1]:
		var bounds:=AABB();var first:=true
		for row:Array in rows:
			if row[3]*side<=0:continue
			var point:=Vector3(row[0],row[1],row[2])
			if first:bounds=AABB(point,Vector3.ZERO);first=false
			else:bounds=bounds.expand(point)
		assert(bounds.size.length()<.27,"Gripped hand must retain human proportions across body morphs")
		var near:=0;var minimum:=INF
		for point:Array in rows:
			if point[3]*side<=0:continue
			var radius:float
			if side==1:
				if point[2]<-.07 or point[2]>.1:continue
				radius=Vector2(point[0],point[1]).length()
			else:
				if point[0]<-.116 or point[0]>-.071:continue
				radius=Vector2(point[1]+.09,point[2]-.055).length()
			minimum=minf(minimum,radius)
			if radius>=.01 and radius<.016:near+=1
		assert(minimum>=.010,"Actual skinned hand must not intersect handle by more than 2 mm")
		assert(near>=20,"Actual skin must contact the handle, not merely an invisible socket")
		print("SKIN CONTACT ",side," minimum radius=",minimum," near-surface vertices=",near)
