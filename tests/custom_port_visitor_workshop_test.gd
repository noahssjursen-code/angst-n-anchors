extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	_check(OS.get_cmdline_user_args().has("--empty-custom-port"),"Native visitor review starts from an empty parcel")
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Empty workshop starts")
	if not workshop.ready_for_review:_finish_visitors();return
	workshop._close_map()
	_check(workshop.state.to_dict().vessels.is_empty(),"No visitor is silently invented at startup")
	# Author a minimal32x24m quay using the same batched construction command as
	# painted player foundations. The actual terrain survey decides berth fitness.
	var operations: Array=[]
	for z in [4,12,20]:
		for x in [-12,-4,4,12]:
			var at:=Vector3(x,0,z)
			var world: Vector3=workshop.site+at
			var depth:=maxf(.1,world.y-workshop._support_seabed(Vector2(world.x,world.z)))
			operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("deck-%d-%d"%[x,z],"foundation_8m",at,0,{"support_depth_m":depth})}})
	for x in [-14,14]:operations.append({"kind":"place_asset","payload":{"placement":CustomPortCatalog.placement("bollard-%d"%x,"quay_bollard",Vector3(x,0,.8))}})
	_check(workshop._command("edit_assets",{"operations":operations}).ok,"A new quay and its bollards are built through data commands")
	_check(workshop.state.derived_berths().size()==1,"Constructed waterfront derives one berth")
	workshop.open_inspector()
	var count_before: int=workshop.state.to_dict().vessels.size()
	# Emit the public inspector intent, exactly as the opt-in Invite button does.
	workshop.inspector.test_vessel_requested.emit("fishing_hook_line")
	_check(workshop.state.to_dict().vessels.size()==count_before+1,"Workshop consumes Invite and admits an actual prebuilt projection")
	var snapshot: Dictionary=workshop.state.to_dict()
	if snapshot.vessels.is_empty():workshop.queue_free();await _settle();_finish_visitors();return
	var visitor: Dictionary=snapshot.vessels.back()
	_check(visitor.lots.is_empty() and visitor.berth_id=="","Invited ship arrives empty and awaiting berth")
	_check(workshop.presenter.vessel_nodes.is_empty(),"Invitation alone does not spawn an offshore duplicate")
	_check(workshop.inspector._selected(workshop.inspector._vessel)==visitor.id,"New visitor is selected in the actual records panel")
	workshop.inspector._dock_selected()
	_check(workshop.presenter.vessel_nodes.has(visitor.id),"Dock action reconstructs invited Nordlys alongside the player's new quay")
	_check(not str(workshop.state.to_dict().vessels.back().berth_id).is_empty(),"Derived berth occupancy is committed")
	workshop._close_inspector()
	workshop.camera.position=workshop.site+Vector3(-34,25,-35)
	workshop.camera.look_at(workshop.site+Vector3(0,1,8))
	workshop.overlays.hide()
	await get_tree().create_timer(.5).timeout
	workshop.open_inspector()
	for frame in 4:await get_tree().process_frame
	var viewport:=get_viewport().get_visible_rect().grow(1)
	_check(viewport.encloses(workshop.inspector.get_global_rect()),"The actual anchored records panel stays wholly inside the viewport")
	_check(workshop.inspector.size.y<=620,"Visible populated labels do not inflate the default hosted panel")
	for action in [workshop.inspector._dock,workshop.inspector._undock]:
		_check(action.is_visible_in_tree() and viewport.encloses(action.get_global_rect()),"The actual hosted "+str(action.text)+" action remains onscreen")
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("new-harbour-invited-fishing-visitor")
	workshop._close_inspector()
	var saved: Dictionary=workshop.state.to_dict()
	workshop.save_path="user://custom_ports/visitor-workshop-%d.json"%Time.get_ticks_usec()
	workshop.save_port();workshop.load_port()
	_check(workshop.state.to_dict()==saved,"Player-built quay, invited fitout and occupancy survive JSON save/load")
	_check(workshop.presenter.vessel_nodes.size()==1,"Reload leaves exactly one physical visitor")
	workshop.queue_free();await _settle();_finish_visitors()

func _finish_visitors() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT VISITOR WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
