extends "res://scripts/ship/rod_fishing_showcase.gd"
## Bounded native handline review using production equipment and fixed-length IK.
func _ready()->void:
	super._ready()
	_review.call_deferred()
func _review()->void:
	for frame in 90:await get_tree().physics_frame
	_prepare_harpe()
	for frame in 12:await get_tree().physics_frame
	station.working=true
	station._carry(true)
	aim_at(camera.global_position+Vector3(20,0,0))
	player.set_process(false);player.set_physics_process(false)
	var visual:CharacterVisual=player.get_node("BodyMesh").visual
	visual.skeleton.skeleton_updated.connect(_record_review_hands.bind(visual.skeleton))
	var controller:PlayerCamera=player.get_node("PlayerCamera")
	var contacts:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CharacterVisual.HAND_CONTACTS_PATH))
	var worst:=0.0
	for third in [false,true]:
		if controller.is_third_person()!=third:controller._toggle_mode()
		for pitch in [-.8,0.0,.65]:
			camera.rotation.x=pitch
			for frame in 12:await get_tree().process_frame
			for side in ["L","R"]:
				var c:Array=contacts[side].palm_contact
				var actual:Vector3=_review_hand_poses[side]*Vector3(c[0],c[1],c[2])
				var grip:Node3D=station._hand_pose.right_grip if side=="L" else station._hand_pose.left_grip
				var error:=actual.distance_to(grip.global_position);worst=maxf(worst,error)
				assert(error<.012,"Harpe hand anchor must remain reachable")
			if pitch==0.0:await capture("crew-harpe-%s"%("third-person" if third else "first-person"))
	print("HARPE HAND CONTACT PASS FP/TP three pitch angles; worst error mm=",worst*1000)
	get_tree().quit()
