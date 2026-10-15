extends "res://tests/custom_port_showcase_input_test.gd"

const GUIDES = preload("res://scripts/port/building/custom_port_build_guides.gd")

func _run() -> void:
	var cargo:=OS.get_cmdline_user_args().has("--cargo-guides")
	var workshop:=WORKSHOP.instantiate()
	workshop.example_kind=0 if cargo else 1
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Actual workshop ready")
	if not workshop.ready_for_review:_finish_guides();return
	var before: Dictionary=workshop.state.to_dict()
	var placement_id:="container-terminal" if cargo else "landing"
	var target:=Vector3(-24,0,24) if cargo else Vector3(0,0,12)
	var shift:=-4.0 if cargo else 4.0
	var radius:=float(workshop.catalog.container_crane_bay.reach_max_m) if cargo else 24.0
	workshop.build()
	workshop.camera.position=workshop.site+target+Vector3(44,39,-46)
	workshop.camera.look_at(workshop.site+target)
	await _settle()
	workshop._begin_move(placement_id)
	await _settle()
	workshop.camera.position.x+=shift
	await _settle()
	_check(workshop.preview.get("ok",false),"Moving equipment one cell has a valid preview: "+str(workshop.preview.get("errors",[])))
	_check(workshop.build_guides.visible and workshop.build_guides.reach.maximum==radius,"The actual build camera shows equipment reach")
	var service: Dictionary={}
	for berth in workshop.state.derived_berths():
		for candidate in berth.crane_services:
			if str(candidate.crane_id)==placement_id:service=candidate
	_check(not service.is_empty(),"Fixture has the authoritative equipment service")
	if not service.is_empty():
		var pivot:=CustomPortCatalog.vector3(service.pivot_m)
		_check(workshop.build_guides.reach.pivot.is_equal_approx(Vector2(pivot.x+shift,pivot.z)),"Guide follows the actual service pivot when moved, not the package centre")
	_check(workshop.build_guides.position==workshop.site,"Port world origin is applied exactly once")
	var label: Label3D=workshop.build_guides.get_child(1)
	_check(label.text.begins_with("Crane reach" if cargo else "Hose reach"),"Only the measured horizontal reach is advertised")
	for turns in 4:
		var placement:=CustomPortCatalog.placement("rotated","fish_landing_plant",Vector3(4,0,16),float(turns)*90)
		var guide:=GUIDES.reach_geometry(placement,workshop.catalog.fish_landing_plant)
		var offset:=Vector3(5.18,0,-4.72).rotated(Vector3.UP,deg_to_rad(turns*90.0))+Vector3(4,0,16)
		_check(guide.pivot.is_equal_approx(Vector2(offset.x,offset.z)),"Rotated equipment pivot follows Godot geometry %d"%turns)
	var mesh_id: int=workshop.build_guides.get_child(0).get_instance_id()
	await _settle()
	_check(mesh_id==workshop.build_guides.get_child(0).get_instance_id(),"Unchanged preview reuses its guide mesh")
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("build-crane-reach-and-berths" if cargo else "build-hose-reach-and-berth")
	await _key(KEY_G)
	_check(not workshop.build_guides.visible,"G hides reach with the other construction overlays")
	await _key(KEY_G)
	_check(workshop.build_guides.visible,"G restores the overlay")
	await _key(KEY_TAB)
	_check(not workshop.build_guides.visible,"Library cursor hides the active placement guide")
	await _key(KEY_TAB)
	_check(workshop.build_guides.visible,"Returning to the build camera restores the guide")
	workshop._cancel_move()
	workshop.choose("foundation")
	await _settle()
	_check(not workshop.build_guides.visible,"Ordinary foundation placement has no equipment ring")
	_check(workshop.state.to_dict()==before,"Construction overlays never mutate port records or stock")
	workshop.queue_free();await _settle();_finish_guides()

func _finish_guides() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT BUILD GUIDES ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
