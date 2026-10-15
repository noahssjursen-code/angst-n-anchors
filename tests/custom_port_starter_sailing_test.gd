extends "res://tests/custom_port_sailing_test.gd"
## Reuse the established real-input helm harness with the actual starter layout.
func _run() -> void:
	baseline_helmed=BoatController.helmed_count
	workshop=preload("res://scenes/showcases/custom_port_starter_showcase.tscn").instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+60000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	await get_tree().process_frame
	_check(is_instance_valid(workshop.start_choices),"Starter choice is available")
	await workshop._capture("starter-choice-final")
	workshop.starter_ready_button.pressed.emit()
	deadline=Time.get_ticks_msec()+20000
	while workshop.building and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(not workshop.building,"Ready-made option starts on foot")
	boat=workshop.presenter.vessel_nodes.get("starter-fishing-boat")
	_check(is_instance_valid(boat) and boat.gangway.deployed,"First vessel is boardable")
	if not is_instance_valid(boat):await _finish();return
	controller=boat.get_node("BoatController")
	for candidate in boat.get_bridge_stations():
		if candidate._boat_controller==controller:station=candidate;break
	_check(is_instance_valid(station),"First vessel has its working helm")
	if not is_instance_valid(station):await _finish();return
	var original:Dictionary=workshop.state.to_dict().vessels[0]
	_check(original.owner_company_id==workshop.state.to_dict().owner_company_id,"New company owns this vessel")
	workshop.player.set_physics_process(false);workshop.player.set_process(false)
	_check(_aim_at_helm(),"Real camera can target the helm")
	await _tap(KEY_F)
	workshop.player.set_process(true)
	_check(station.is_occupied() and controller._active,"F activates the real helm")
	if not station.is_occupied():await _finish();return
	await _tap(KEY_B)
	_check(workshop.vessel_session.last_result.get("ok",false) and workshop.state.to_dict().vessels[0].berth_id=="","B releases the starter berth through authority")
	_check(not boat.freeze and not boat.gangway.deployed,"Departure releases physics and stows the gangway")
	await _tap(KEY_I);await _tap(KEY_W)
	var from:=boat.global_position
	var forward:Vector3=-boat.global_basis.z
	for frame in 240:await get_tree().physics_frame
	var travelled:float=(boat.global_position-from).dot(forward)
	print("STARTER_SAILING_FORWARD_METRES ",travelled)
	_check(travelled>.25,"Real engine moves the starter boat forward")
	_check(workshop.presenter.vessel_nodes.get("starter-fishing-boat")==boat,"Driving preserves the owned vessel instance")
	capture_pose=Transform3D(Basis.IDENTITY,boat.global_position+Vector3(22,14,-24))
	capture_pose=capture_pose.looking_at(boat.global_position+Vector3.UP*2)
	await _capture("starter-departure")
	await _finish()
