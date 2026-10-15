extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"The actual workshop starts for site selection")
	if not workshop.ready_for_review:_finish();return
	var old: Dictionary=workshop.state.to_dict()
	var old_path: String=workshop.save_path
	var old_budget: Dictionary=workshop.simulated_accounts.duplicate(true)
	workshop.open_new_harbour()
	_check(workshop.map.visible and workshop.choosing_site and not workshop.camera.flying,"New harbour opens coastline selection and pauses flight")
	_check(workshop.state.to_dict()==old and workshop.simulated_accounts==old_budget,"Opening the picker neither deletes nor purchases anything")
	workshop._close_map()
	_check(not workshop.choosing_site and workshop.state.to_dict()==old and workshop.save_path==old_path,"Cancelling site selection preserves the current build and save destination")
	workshop.open_new_harbour()
	var result: Dictionary=await workshop._start_selected_harbour("not-a-real-plot")
	_check(not result.ok and workshop.state.to_dict()==old,"A forged plot ID cannot replace the harbour")
	result=await workshop._start_selected_harbour(str(old.plots[0].id))
	_check(not result.ok and workshop.state.to_dict()==old,"A new harbour cannot overlap the current owned plot")
	var chosen: Dictionary=workshop.plot_index.plot_at(Vector2(76,1668))
	_check(not chosen.is_empty(),"The independent second coastline is indexed")
	if chosen.is_empty():workshop.queue_free();await _settle();_finish();return
	workshop.map.selected_plot=str(chosen.id)
	workshop.map.camera.focus_harbour(Vector2(76,1668),1200)
	workshop._refresh_plot_map()
	await _settle()
	_check(workshop._new_site_content(chosen).action_enabled,"A different coastline can be selected explicitly")
	if OS.get_cmdline_user_args().has("--capture"):
		await get_tree().create_timer(.6).timeout
		await workshop._capture("choose-new-coastline")
	result=await workshop._start_selected_harbour(str(chosen.id))
	_check(result.ok,"The chosen coastal plot creates a new complete document")
	if not result.ok:workshop.queue_free();await _settle();_finish();return
	var snapshot: Dictionary=workshop.state.to_dict()
	var retained: Dictionary=workshop.REPOSITORY.load_state(result.previous_path,workshop.world_identity,workshop.catalog)
	_check(retained.ok and retained.snapshot==old,"The old harbour is retained with exact cargo, plots and receipts")
	var retained_hash:=FileAccess.get_sha256(result.previous_path)
	_check(snapshot.id!=old.id and workshop.save_path!=old_path,"The new build has its own identity and save file")
	_check(snapshot.placements.is_empty() and snapshot.stores.is_empty() and snapshot.vessels.is_empty() and snapshot.reservations.is_empty(),"A new site invents no structures, stock or visitor ships")
	_check(snapshot.plots.size()==1 and snapshot.plots[0].id==chosen.id,"The only acquired plot is the one selected")
	_check(workshop.site.distance_to(workshop.SITE)>1000 and is_equal_approx(workshop.site.y,.5),"The harbour moves to the other coastline on the same sea-relative plane")
	_check(workshop.presenter.position==workshop.site and workshop.player.position.distance_to(workshop.site)<160,"Both real presentation and player relocate to the selected plot")
	_check(not snapshot.water_regions.is_empty(),"A real incremental water survey supplies the new harbour depths")
	_check(workshop.simulated_accounts[workshop.owner_company_id].balance_nok==workshop.WORKSHOP_BUDGET_NOK,"Only the isolated workshop allowance resets for the new document")
	_check(not workshop.map.visible and not workshop.choosing_site and not workshop.survey_busy,"Selection and survey finish without leaving an input-blocking panel")
	var bounds:=ChartPlotLayer.plot_rect(chosen)
	# Choose a fully owned 8 m cell near the actual shoreline, not the high
	# island centre or a cell whose snapped footprint crosses the plot boundary.
	var center:=bounds.get_center()
	var coast_score:=INF
	for z in range(-92,93,8):
		for x in range(-92,93,8):
			var candidate:=Vector2(workshop.site.x+x,workshop.site.z+z)
			var score: float=absf(workshop._water_seabed(candidate)-.5)
			if score<coast_score:coast_score=score;center=candidate
	_check(bounds.has_point(Vector2(workshop.player.position.x,workshop.player.position.z)),"Empty-plot home is inside the owned land")
	_check(workshop.player.position.y>WaveSurface.WATER_LEVEL+1.2,"The walking home is on dry terrain rather than buried at deck height")
	workshop.choose("foundation_8m")
	# Use the actual preview/place route. It always intersects the fixed plane,
	# including where the real island terrain rises above that plane.
	workshop.camera.position=Vector3(center.x-4,maxf(50,workshop._water_seabed(center)+30),center.y-6)
	workshop.camera.look_at(Vector3(center.x,.5,center.y))
	await _settle()
	_check(workshop.preview.get("ok",false),"A first foundation can be aimed at on the new plot")
	workshop._place()
	var built: Dictionary=workshop.state.to_dict()
	_check(built.placements.size()==1 and is_zero_approx(float(built.placements[0].position_m[1])),"The first foundation is added at the shared deck datum")
	workshop.save_port()
	workshop.load_port()
	_check(workshop.state.to_dict()==built,"New-site construction survives exact save/load")
	_check(FileAccess.get_sha256(result.previous_path)==retained_hash,"Working on the new harbour does not modify the retained harbour")
	workshop.open_map()
	_check(workshop.map.data.port_info(str(built.id)).get("source","")=="custom" and workshop.map.data.port_info(str(old.id)).is_empty(),"The map follows the new document without a stale old harbour")
	workshop._close_map()
	workshop.walk()
	deadline=Time.get_ticks_msec()+45000
	while (workshop.building or not workshop.player.is_on_floor()) and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	_check(not workshop.building and workshop.player.is_on_floor(),"Walking waits for the new terrain/collider and lands on the built foundation")
	_check(absf(workshop.player.position.y-.5)<.5,"The player stands on the fixed deck at the chosen coast")
	if OS.get_cmdline_user_args().has("--capture"):
		workshop.build()
		var home: Vector3=workshop.site+workshop.home_local
		workshop.camera.position=home+Vector3(-18,22,-20)
		workshop.camera.position.y=maxf(workshop.camera.position.y,workshop._water_seabed(Vector2(workshop.camera.position.x,workshop.camera.position.z))+12)
		workshop.camera.look_at(home)
		workshop._set_cursor(true)
		await get_tree().create_timer(.6).timeout
		await workshop._capture("new-coast-first-foundation")
	var new_path: String=workshop.save_path
	var new_hash:=FileAccess.get_sha256(new_path)
	var opened: Dictionary=workshop.open_port_document(str(result.previous_path))
	_check(opened.ok and workshop.state.to_dict()==old,"The retained old harbour opens exactly through the workshop file route")
	_check(workshop.site==workshop.SITE and workshop.presenter.position==workshop.SITE,"Opening a different harbour relocates origin and real models together")
	_check(FileAccess.get_sha256(result.previous_path)==retained_hash and FileAccess.get_sha256(new_path)==new_hash,"Opening another document changes neither source nor previous working save")
	_check(workshop.save_path!=result.previous_path and workshop.save_path!=new_path,"An opened document gets a separate writable copy")
	var restored_new: Dictionary=workshop.REPOSITORY.load_state(opened.previous_path,workshop.world_identity,workshop.catalog)
	_check(restored_new.ok and restored_new.snapshot==built,"Opening the old harbour also preserves the newly constructed one")
	var unchanged: Dictionary=workshop.state.to_dict()
	var unchanged_path: String=workshop.save_path
	var rejected: Dictionary=workshop.open_port_document("user://no-such-port-document.json")
	_check(not rejected.ok and workshop.state.to_dict()==unchanged and workshop.save_path==unchanged_path,"An invalid open leaves the current harbour and save destination intact")
	workshop.open_document_picker()
	_check(workshop.document_picker.visible and not workshop.camera.flying,"The actual file picker pauses freecam")
	workshop.document_picker.hide()
	workshop.document_picker.canceled.emit()
	_check(workshop.cursor_mode and not workshop.camera.flying,"Cancelling the file picker restores the previous library cursor")
	# An empty saved harbour at a different origin must select dry terrain;
	# it cannot inherit Nordvik's entrance or the unbuilt sea-level origin.
	var blank: Dictionary=workshop.SITE_PLAN.plan(str(chosen.id),workshop.plot_index,workshop.world_identity,"empty-reopen-%d"%Time.get_ticks_usec(),workshop.owner_company_id,"Empty reopen")
	var blank_state:=CustomPortState.from_dict(blank.snapshot,workshop.world_identity,workshop.catalog)
	var blank_path:="user://custom_ports/blank-reopen-%d.json"%Time.get_ticks_usec()
	var blank_saved: Dictionary=workshop.REPOSITORY.save(blank_path,blank_state)
	_check(blank_saved.ok and workshop.open_port_document(blank_path).ok,"A truly empty saved harbour reopens through the same document route")
	_check(workshop.player.position.y>WaveSurface.WATER_LEVEL+1.2 and workshop._site_needs_home,"Empty-document arrival uses a terrain-aware home")
	workshop.home_local=Vector3(0,-1000,0)
	workshop.return_home()
	_check(workshop.player.position.y>WaveSurface.WATER_LEVEL+1.2 and workshop.home_local.y>-1000,"Home is recomputed from current ground rather than a stale stored point")
	workshop.queue_free()
	await _settle()
	_finish()

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT SITE WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
