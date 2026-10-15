extends "res://tests/custom_port_showcase_input_test.gd"

## Human-order review: all construction uses the live library and LMB path.
## Camera positioning is deterministic so screenshots remain reviewable.
func _run() -> void:
	_check(OS.get_cmdline_user_args().has("--empty-custom-port"), "Review starts on an empty isolated coast")
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+60000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not workshop.ready_for_review:_check(false,"Workshop did not become ready");_done();return
	await _settle()
	workshop._close_map()
	_check(workshop.state.to_dict().placements.is_empty(),"No prefabricated port is injected")
	for z in [4,12,20,28,36]:
		for x in [-12,-4,4,12]:
			if not await _build_piece(workshop,"foundation_8m",Vector3(x,0,z)):_done();return
	for z in range(42,88,4):
		if not await _build_piece(workshop,"quay",Vector3(-4,0,z)):_done();return
	for x in [-12,12]:
		if not await _build_piece(workshop,"bollard",Vector3(x,0,.5)):_done();return
	_check(not workshop.state.derived_berths().is_empty(),"Placed bollards derive a waterfront berth")
	for row in [
		["workshop_door_4m",Vector3(6,0,24),0],
		["workshop_window_4m",Vector3(10,0,24),0],
		["workshop_wall_4m",Vector3(4,0,26),90],
		["workshop_window_4m",Vector3(4,0,30),90],
		["workshop_wall_4m",Vector3(12,0,26),90],
		["workshop_wall_4m",Vector3(12,0,30),90],
		["workshop_wall_4m",Vector3(6,0,32),0],
		["workshop_wall_4m",Vector3(10,0,32),0],
		["workshop_roof_4m",Vector3(6,0,26),0],
		["workshop_roof_4m",Vector3(10,0,26),0],
		["workshop_roof_4m",Vector3(6,0,30),0],
		["workshop_roof_4m",Vector3(10,0,30),0],
		["fish_landing_plant",Vector3(0,0,12),0],
		["tractor_tire_fender",Vector3(-8,0,0),0],
		["tractor_tire_fender",Vector3(8,0,0),0],
		["quay_ladder",Vector3(0,0,0),0],
		["port_clerk",Vector3(-12,0,12),0]]:
		if not await _build_piece(workshop,row[0],row[1],row[2]):_done();return
	_check(workshop.state.to_dict().stores.size()==1 and workshop.state.to_dict().stores[0].lots.is_empty(),"Plant creates exactly one empty store")
	workshop.camera.position=workshop.site+Vector3(-29,24,-22)
	workshop.camera.look_at(workshop.site+Vector3(0,2,20))
	workshop._set_cursor(true)
	workshop.overlays.hide()
	await _settle()
	await get_tree().create_timer(4.0).timeout
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("from-empty-complete-fishing-pier")
	workshop.walk()
	deadline=Time.get_ticks_msec()+20000
	while workshop.building and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(not workshop.building and workshop.player.is_physics_processing(),"Finished construction enters walking on prepared ground")
	_check(workshop.player.global_position.y>=workshop.site.y,"The safe walking position is above the shared deck")
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("from-empty-first-walk")
	workshop.queue_free();await _settle();_done()

func _build_piece(workshop: Node, asset: String, at: Vector3, yaw:=0.0) -> bool:
	if not workshop.library._buttons.has(asset):
		_check(false,"Asset missing from real library: "+asset);return false
	workshop.library._buttons[asset].pressed.emit()
	while not is_equal_approx(fposmod(workshop.build_yaw_degrees,360),yaw):await _key(KEY_R)
	workshop.camera.position=workshop.site+at+Vector3(-1,11,-5)
	workshop.camera.look_at(workshop.site+at)
	await _settle()
	var proposal: Dictionary=workshop.preview.duplicate(true)
	if not proposal.get("ok",false):
		_check(false,"Place "+asset+" at "+str(at)+" failed: "+str(proposal));return false
	var count: int=workshop.state.to_dict().placements.size()
	await _mouse(MOUSE_BUTTON_LEFT)
	var added: bool=workshop.state.to_dict().placements.size()==count+1
	_check(added,"LMB places "+asset+" at "+str(at))
	if added:
		var actual: Dictionary=workshop.state.to_dict().placements.back()
		_check(is_zero_approx(float(actual.position_m[1])),"Shared plane stays fixed for "+asset)
	return added

func _done() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT FROM EMPTY REVIEW ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
