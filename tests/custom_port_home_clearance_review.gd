extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Actual isolated empty workshop ready")
	await _settle();workshop._close_map()
	var operations: Array=[]
	operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("first-floor","foundation_8m",Vector3(4,0,4),0,{"support_depth_m":30})}})
	operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("wall-on-first-centre","workshop_wall_4m",Vector3(4,0,4))}})
	var result: Dictionary=workshop._command("edit_assets",{"operations":operations})
	_check(result.ok,"Legal wall can cross the first foundation's centre")
	await _settle();await get_tree().physics_frame
	workshop.build()
	await _key(KEY_H)
	var hits:=_player_overlaps(workshop.player)
	print("HOME_CLEARANCE_POSITION ",workshop.player.global_position-workshop.site," OVERLAPS ",hits)
	_check(hits.is_empty(),"Home player capsule must not overlap solid port equipment: "+str(hits))
	workshop.camera.position=workshop.site+Vector3(0,4,-4)
	workshop.camera.look_at(workshop.site+Vector3(4,1,4))
	workshop._set_cursor(true)
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("home-clearance-wall-diagnostic")
	workshop.walk()
	deadline=Time.get_ticks_msec()+10000
	while workshop.building and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	await get_tree().physics_frame
	print("HOME_CLEARANCE_AFTER_WALK ",workshop.player.global_position-workshop.site," OVERLAPS ",_player_overlaps(workshop.player))
	_check(_player_overlaps(workshop.player).is_empty(),"Walk keeps the chosen home capsule clear")
	workshop.build()
	workshop.player.global_position=workshop.site+Vector3(4,.15,4)
	_check(not workshop._player_ground_is_safe(),"Standing in a newly built wall is not classified as safe just because a floor exists")
	operations=[{"kind":"remove_asset","payload":{"placement_id":"wall-on-first-centre"}}]
	for x in [-4,4,12]:
		for z in [4,12,20]:
			if x==4 and z==4:continue
			operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("floor-%d-%d"%[x,z],"foundation_8m",Vector3(x,0,z),0,{"support_depth_m":30})}})
	operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("plant","fish_landing_plant",Vector3(4,0,12))}})
	operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("open-door","workshop_door_4m",Vector3(-4,0,20),0,{"door_open":true})}})
	result=workshop._command("edit_assets",{"operations":operations})
	_check(result.ok,"Real plant and a decorative door with legacy saved attributes form the clearance scenario: "+str(result.get("errors",[])))
	await _settle();await get_tree().physics_frame
	workshop.player.global_position=workshop.site+Vector3(7.2,.15,12)
	_check(workshop._player_ground_is_safe(),"The real 1.75m pump aisle remains safe for a standing player")
	workshop.player.global_position=workshop.site+Vector3(-4,.15,20)
	_check(not workshop._player_ground_is_safe(),"A decorative door remains solid even if an old save requests it open")
	workshop.player.global_position=workshop.site+Vector3(0,.15,14.35)
	_check(not workshop._player_ground_is_safe(),"The actual tank cylinder blocks a standing capsule")
	workshop.walk()
	deadline=Time.get_ticks_msec()+10000
	while workshop.building and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	await get_tree().physics_frame
	_check(_player_overlaps(workshop.player).is_empty(),"Walk relocates a player inside newly built equipment to a clear home")
	workshop.queue_free();await _settle()
	for failure in failures:push_error(failure)
	print("CUSTOM PORT HOME CLEARANCE REVIEW ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _player_overlaps(player: CharacterBody3D) -> Array[String]:
	var collider:=player.get_node("CollisionShape3D") as CollisionShape3D
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=collider.shape
	query.transform=collider.global_transform
	query.collision_mask=player.collision_mask
	query.exclude=[player.get_rid()]
	var result: Array[String]=[]
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query,32):
		var node: Node=hit.collider
		result.append(str(node.get_path()))
	return result
