extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	_check(OS.get_cmdline_user_args().has("--empty-custom-port"),"Empty workshop flag is supplied")
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Empty island workshop starts")
	if not workshop.ready_for_review:_finish();return
	await _settle()
	_check(workshop.map.visible and workshop.choosing_site,"Empty launch prompts for a coastal plot")
	workshop._close_map()
	var initial: Dictionary=workshop.state.to_dict()
	_check(initial.placements.is_empty() and initial.stores.is_empty() and initial.vessels.is_empty(),"New harbour contains no prebuilt structures, free stock or invented visitors")
	_check(initial.plots.size()==1 and initial.id=="my-harbour","Owned starter plot has its own port identity")
	_check(workshop.save_path!=workshop.SAVE_PATH,"Empty harbour cannot overwrite the example save")
	workshop.save_path="user://custom_ports/empty-test-%d.json"%Time.get_ticks_usec()
	workshop.build()
	workshop.choose("foundation")
	workshop.camera.position=workshop.SITE+Vector3(-2,16,76)
	workshop.camera.look_at(workshop.SITE+Vector3(-2,0,78))
	await _settle()
	_check(workshop.preview.get("ok",false),"First foundation can be aimed at on the empty owned shoreline")
	await _mouse(MOUSE_BUTTON_LEFT)
	var built: Dictionary=workshop.state.to_dict()
	_check(built.placements.size()==1,"Mouse input constructs the first foundation")
	if built.placements.size()==1:
		_check(is_zero_approx(float(built.placements[0].position_m[1])),"First structure uses the same fixed sea-referenced plane")
	workshop.save_port()
	_check(FileAccess.file_exists(workshop.save_path),"New harbour saves as a complete document")
	workshop.load_port()
	_check(workshop.state.to_dict()==built,"Empty-to-built harbour restores exactly")
	if OS.get_cmdline_user_args().has("--capture"):
		workshop._set_cursor(true)
		await workshop._capture("empty-harbour-first-foundation")
	workshop.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT EMPTY WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
