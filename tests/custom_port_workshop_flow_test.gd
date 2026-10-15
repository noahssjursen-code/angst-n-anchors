extends "res://tests/custom_port_showcase_input_test.gd"

var workshop: Node

func _run() -> void:
	workshop=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	_check(workshop.ready_for_review,"Actual island workshop started")
	if not workshop.ready_for_review: _finish();return
	workshop.save_path="user://custom_ports/flow-test-%d.json"%Time.get_ticks_usec()
	workshop.build()
	workshop.choose("foundation")
	workshop.camera.position=workshop.SITE+Vector3(2,16,-4)
	workshop.camera.look_at(workshop.SITE+Vector3(2,0,-2))
	await _settle()
	_check(workshop.preview.get("ok",false),"4m foundation snaps beside the existing quay")
	var count: int=workshop.state.to_dict().placements.size()
	await _mouse(MOUSE_BUTTON_LEFT)
	_check(workshop.state.to_dict().placements.size()==count+1,"Actual mouse input places one foundation")
	var added: Dictionary={}
	for row in workshop.state.to_dict().placements:
		if str(row.id).contains(":build:") or (is_equal_approx(float(row.position_m[0]),2) and is_equal_approx(float(row.position_m[2]),-2)):
			added=row
	_check(not added.is_empty() and is_zero_approx(float(added.position_m[1])) and float(added.attributes.get("support_depth_m",0))>4,
		"Foundation stays on the fixed plane and extends to the real seabed")
	await _control_key(KEY_Z)
	_check(workshop.state.to_dict().placements.size()==count,"Ctrl+Z removes the construction stroke")
	workshop._set_cursor(true)
	var initial: Dictionary=workshop.state.to_dict()
	var frontier: Array=workshop.plot_index.neighbour_ids(str(initial.plots[0].id))
	_check(not frontier.is_empty(),"Real coastline provides adjoining purchaseable plots")
	var before_water: int=initial.water_regions.size()
	if not frontier.is_empty():
		var next_plot: Dictionary=workshop.plot_index.get_plot(str(frontier[0]))
		workshop.open_map()
		await _settle()
		_check(workshop.map.layers.is_visible("plots") and workshop.map.plot_panel.visible,"Expansion map opens with its plots and purchase panel visible")
		_check(workshop.map.renderer.plots.plot_status(str(initial.plots[0].id))=="owned" and workshop.map.renderer.plots.plot_status(str(next_plot.id))=="available","Map distinguishes owned coast from available adjoining plots")
		var center:=ChartPlotLayer.plot_rect(next_plot).get_center()
		var ctx: Dictionary=workshop.map.last_ctx
		var screen: Vector2=ctx.chart_rect.position+(center-ctx.world_bounds.position)/ctx.world_bounds.size*ctx.chart_rect.size
		workshop.map._click_chart(screen)
		_check(workshop.map.selected_plot==str(next_plot.id) and workshop.state.to_dict().plots.size()==1,"Selecting a plot inspects it without buying")
		_check(is_equal_approx(float(workshop.simulated_accounts[CustomPortExample.OWNER].balance_nok),250000),"Map selection does not debit the budget")
		_check(workshop.map.plot_action.visible and not workshop.map.plot_action.disabled and workshop.map.plot_body.text.contains("25000"),"The selected plot has a clear enabled purchase action and price")
		if OS.get_cmdline_user_args().has("--capture"):
			await workshop._capture("plot-purchase-review")
		workshop.map.plot_action.pressed.emit()
		while workshop.survey_busy: await get_tree().process_frame
		_check(workshop.state.to_dict().plots.size()==2,"Explicit Buy plot action purchases the adjoining coastline")
		_check(is_equal_approx(float(workshop.simulated_accounts[CustomPortExample.OWNER].balance_nok),225000),"Purchase debits the workshop budget once")
		_check(workshop.state.to_dict().water_regions.size()>before_water,"New coast receives real surveyed water cells")
		_check(not workshop.survey_busy,"Survey releases the construction controls")
	workshop.save_port()
	_check(FileAccess.file_exists(workshop.save_path),"Save writes a real complete port document")
	var saved:=JSON.stringify(workshop.state.to_dict(),"",true)
	var saved_snapshot: Dictionary=workshop.state.to_dict()
	# Inject an unsaved cosmetic build through the same editor, then load.
	var proposal: Dictionary=workshop.editor.preview("pallet_stack",Vector3(8,0,48))
	_check(proposal.ok,"A supported free point accepts a port detail")
	if proposal.ok:
		workshop.preview=proposal
		workshop._place()
	workshop.load_port()
	var loaded: Dictionary=workshop.state.to_dict()
	if JSON.stringify(loaded,"",true)!=saved:
		print("FLOW_LOAD_FEEDBACK ",workshop.feedback.text)
		for key in saved_snapshot:
			if saved_snapshot[key]!=loaded.get(key):
				print("FLOW_LOAD_DIFFERENCE ",key)
				if saved_snapshot[key] is Array:
					for i in mini(saved_snapshot[key].size(),loaded[key].size()):
						if saved_snapshot[key][i]!=loaded[key][i]:
							print("BEFORE ",JSON.stringify(saved_snapshot[key][i],"",true,true))
							print("AFTER ",JSON.stringify(loaded[key][i],"",true,true));break
	_check(loaded==saved_snapshot,"Load restores the exact port data")
	_check(is_equal_approx(float(workshop.simulated_accounts[CustomPortExample.OWNER].balance_nok),225000),"Reload does not reset spent plot funds")
	# Talk uses the real NPC interaction signal and the same inspector.
	var npc: Node=workshop.presenter.placement_nodes["harbour-clerk"]
	npc.interaction_requested.emit()
	_check(workshop.inspector.visible,"Placed harbour NPC opens its port records")
	workshop.inspector.close_requested.emit()
	# Two ships use independent berth occupancy; the caller is the selected
	# fixture vessel's company, not an all-powerful player mutation.
	var panel: CustomPortInspector=workshop.inspector
	_select(panel._vessel,"trader")
	panel._refresh_vessel()
	var selected_berth:=""
	var ship: Dictionary=_record(workshop.state.to_dict().vessels,"trader")
	for berth in workshop.state.derived_berths():
		if "container-yard" in CustomPortBerths.services_for_vessel(berth,ship).store_ids:
			selected_berth=str(berth.id);break
	_select(panel._berth,selected_berth)
	panel._refresh_fit()
	panel._dock.pressed.emit()
	_check(workshop.presenter.vessel_nodes.has("trader"),"Dock button reconstructs the selected vessel")
	_select(panel._store,"container-yard")
	panel._refresh_store()
	_select(panel._lot,"parts-for-shipyard")
	panel._quantity.value=2
	panel._reserve.pressed.emit()
	_check(workshop.state.to_dict().reservations.size()==1,"Reserve button reserves finite shore cargo")
	panel._load.pressed.emit()
	_check(workshop.transfers.is_busy(),"Load button starts the real crane projection")
	var steps:=0
	workshop.transfers.set_process(false)
	while workshop.transfers.is_busy() and steps<12000:
		workshop.transfers._process(.05)
		steps+=1
		if steps%40==0:await get_tree().process_frame
	_check(not workshop.transfers.is_busy(),"Crane completes both accepted lifts")
	var onboard: Dictionary=_record(workshop.state.to_dict().vessels,"trader")
	_check(int(_record(onboard.lots,"parts-for-shipyard").get("quantity",0))==2,"Completed cargo appears in the same vessel manifest")
	# A second company vessel can use a separate serviced berth while the first
	# remains alongside with its already loaded containers.
	_select(panel._vessel,"bulk-trader")
	panel._refresh_vessel()
	var bulk_ship: Dictionary=_record(workshop.state.to_dict().vessels,"bulk-trader")
	var bulk_berth:=""
	for berth in workshop.state.derived_berths():
		if CustomPortBerths.fit(berth,bulk_ship,panel._occupancy()).ok and "bulk-yard" in CustomPortBerths.services_for_vessel(berth,bulk_ship,"bulk").store_ids:
			bulk_berth=str(berth.id);break
	_check(not bulk_berth.is_empty(),"A separate compatible bulk berth remains available")
	_select(panel._berth,bulk_berth)
	panel._refresh_fit()
	panel._dock.pressed.emit()
	_check(workshop.presenter.vessel_nodes.size()==2,"Two actual vessels can remain docked together")
	_select(panel._store,"bulk-yard")
	panel._refresh_store()
	_select(panel._lot,"ore-stock")
	panel._quantity.value=35000
	panel._reserve.pressed.emit()
	panel._load.pressed.emit()
	_check(workshop.transfers.bulk.is_busy(),"Bulk load starts the real grab crane")
	steps=0
	while workshop.transfers.is_busy() and steps<12000:
		workshop.transfers._process(.05)
		steps+=1
		if steps%40==0:await get_tree().process_frame
	_check(not workshop.transfers.is_busy() and workshop.transfers.bulk.completed_grabs==2,"Both finite-capacity bulk grabs complete")
	bulk_ship=_record(workshop.state.to_dict().vessels,"bulk-trader")
	_check(is_equal_approx(float(_record(bulk_ship.lots,"ore-stock").get("quantity",0)),35000),"Bulk vessel manifest records exactly 35 tonnes")
	_check(is_equal_approx(workshop.presenter.vessel_nodes["bulk-trader"].get_bulk_holds()[0].state.filled_tonnes_t,35),"Rendered vessel hold matches its manifest")
	var completed: Dictionary=workshop.state.to_dict()
	var saved_result:=CustomPortRepository.save(workshop.save_path,workshop.state)
	_check(saved_result.ok,"Complete operating harbour saves with both ships and their cargo")
	workshop.load_port()
	_check(workshop.state.to_dict()==completed and workshop.presenter.vessel_nodes.size()==2,"Reload reconstructs both occupied berths and cargo records")
	print("WORKSHOP_COMPLETED_DOCUMENT ",ProjectSettings.globalize_path(workshop.save_path))
	if OS.get_cmdline_user_args().has("--capture"):
		workshop.inspector.hide()
		workshop.overlays.hide()
		workshop.library.hide()
		workshop.camera.current=true
		workshop.camera.position=workshop.site+Vector3(-105,78,-100)
		workshop.camera.look_at(workshop.site+Vector3(0,6,12))
		await workshop._capture("workshop-complete-flow")
		var bulk_node: BoatBody=workshop.presenter.vessel_nodes["bulk-trader"]
		var hold: BulkHoldComponent=bulk_node.get_bulk_holds()[0]
		workshop.camera.global_position=hold.global_position+Vector3(4,12,-4)
		workshop.camera.look_at(hold.global_position)
		await workshop._capture("bulk-hold-real-ocean")
	# Explicitly drain active audio before headless shutdown: the sound mixer
	# runs on wall time, whereas dozens of test frames can elapse instantly.
	for node in workshop.find_children("*","AudioStreamPlayer3D",true,false):node.stop()
	workshop.queue_free()
	await get_tree().create_timer(.1).timeout
	_finish()

func _control_key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true;event.ctrl_pressed=true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event=event.duplicate();event.pressed=false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _select(selector: OptionButton,id: String) -> void:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index))==id:selector.select(index);return
	_check(false,"Selector contains "+id)

func _record(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id",""))==id:return row
	return {}

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT WORKSHOP FLOW ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
