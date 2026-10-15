extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	var workshop := WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 45000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	_check(workshop.ready_for_review, "Actual workshop becomes ready")
	if not workshop.ready_for_review: _finish_viewport(); return
	await get_tree().create_timer(.5).timeout
	workshop._close_map()
	var operations: Array = []
	for z in [4, 12, 20]:
		for x in [-12, -4, 4, 12]:
			var at := Vector3(x, 0, z)
			var world: Vector3 = workshop.site + at
			var depth := maxf(.1, world.y-workshop._support_seabed(Vector2(world.x, world.z)))
			operations.append({"kind":"place_asset", "payload":{"placement":CustomPortCatalog.placement("deck-%d-%d"%[x,z], "foundation_8m", at, 0, {"support_depth_m":depth})}})
	for x in [-14, 14]: operations.append({"kind":"place_asset", "payload":{"placement":CustomPortCatalog.placement("bollard-%d"%x, "quay_bollard", Vector3(x,0,.8))}})
	_check(workshop._command("edit_assets", {"operations":operations}).ok, "Actual player construction makes a berth")
	workshop.open_inspector()
	workshop.inspector.test_vessel_requested.emit("fishing_hook_line")
	workshop.inspector._dock.pressed.emit()
	_check(workshop.presenter.vessel_nodes.size() == 1, "Actual invited vessel docks before layout checks")
	workshop.camera.position = workshop.site+Vector3(-34,25,-35)
	workshop.camera.look_at(workshop.site+Vector3(0,1,8))
	var panel: CustomPortInspector = workshop.inspector
	for frame in 8: await get_tree().process_frame
	_check(panel.visible and not workshop.map.visible, "The real anchored host is visible, not hidden behind the startup map")
	_check(panel._panel_size == Vector2(620,620) and panel.size.y <= 620, "Default hosted panel respects its requested 620px height after live labels settle")
	_check_inside(panel, [panel._dock,panel._undock], "Normal anchored Berths")
	if "--capture" in OS.get_cmdline_user_args(): await workshop._capture("inspector-hosted-docked-vessel")
	# Reproduce the original path: refresh while hidden, then show with populated
	# labels. Hidden containers may still have very narrow old child measurements.
	workshop._close_inspector()
	panel.refresh()
	for frame in 4: await get_tree().process_frame
	workshop.open_inspector()
	for frame in 8: await get_tree().process_frame
	_check(panel.size.y <= 620, "Hidden refresh cannot permanently inflate panel height")
	_check_inside(panel, [panel._dock,panel._undock], "Reopened anchored Berths")
	# Use true small logical bounds, not merely a scaled 1920px canvas.
	get_window().content_scale_size = Vector2i(800,600)
	get_window().size = Vector2i(800,600)
	for frame in 8: await get_tree().process_frame
	_check(get_viewport().get_visible_rect().size.y <= 610, "Resize test actually uses a small UI viewport")
	_check_inside(panel, [panel._dock,panel._undock], "Small resized Berths")
	panel._tabs.current_tab = 1
	for frame in 8: await get_tree().process_frame
	_check_inside(panel, [panel._reserve,panel._unload,panel._load,panel._cancel], "Small resized Cargo")
	if "--capture" in OS.get_cmdline_user_args(): await workshop._capture("inspector-hosted-small-cargo")
	panel._tabs.current_tab = 2
	for frame in 8: await get_tree().process_frame
	_check_inside(panel, [panel._save_storage], "Small resized Storage")
	get_window().content_scale_size = Vector2i(1920,1080)
	get_window().size = Vector2i(1500,950)
	panel.focus_berths()
	for frame in 8: await get_tree().process_frame
	_check_inside(panel, [panel._dock,panel._undock], "Restored normal Berths")
	workshop.queue_free()
	await _settle()
	_finish_viewport()

func _check_inside(panel: CustomPortInspector, actions: Array, label: String) -> void:
	var viewport := get_viewport().get_visible_rect().grow(1)
	_check(viewport.encloses(panel.get_global_rect()), label+" panel is entirely within the viewport")
	for action in actions:
		_check(action.is_visible_in_tree() and viewport.encloses(action.get_global_rect()) and panel.get_global_rect().grow(1).encloses(action.get_global_rect()), label+" keeps "+str(action.text)+" reachable")

func _finish_viewport() -> void:
	for failure in failures: push_error(failure)
	print("CUSTOM PORT INSPECTOR VIEWPORT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
