extends "res://tests/custom_port_document_injection_test.gd"

const FISH_EXAMPLE=preload("res://scripts/port/building/custom_port_fishing_example.gd")
const FISH_WORKSHOP=preload("res://scenes/showcases/custom_port_fishing_showcase.tscn")

func _run() -> void:
	var workshop:=FISH_WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Generated-world workshop starts for a compact fishing pier")
	if not workshop.ready_for_review:_finish_fishing();return
	_check(workshop.state.to_dict().id=="fishing-pier" and workshop.presenter.vessel_nodes.has("nordlys"),"Fishing scene starts with its own pier and arrived Nordlys")
	var snapshot: Dictionary=FISH_EXAMPLE.build(workshop.site,workshop.state.to_dict().plots,workshop.world_identity,workshop._support_seabed)
	CustomPortExample.survey(snapshot,workshop._water_seabed,WaveSurface.WATER_LEVEL)
	var authority:=CustomPortState.from_dict(snapshot,workshop.world_identity,workshop.catalog)
	_check(authority.validation_errors.is_empty(),"The compact one-plot fishing pier is valid: "+str(authority.validation_errors))
	if not authority.validation_errors.is_empty():workshop.queue_free();await _settle();_finish_fishing();return
	_check(authority.derived_berths().size()==1,"Its two waterfront bollards derive one usable berth")
	var dock:=authority.apply({"command_id":"arrival","expected_revision":0,"actor_company_id":"company-visitor","kind":"dock",
		"payload":{"vessel_id":"nordlys","berth_id":authority.derived_berths()[0].id}})
	_check(dock.ok,"Real Nordlys fits the derived pier and surveyed depth")
	if not dock.ok:workshop.queue_free();await _settle();_finish_fishing();return
	var path:="user://custom_ports/fishing-pier-review-%d.json"%Time.get_ticks_usec()
	_check(CustomPortRepository.save(path,authority).ok,"Complete fishing pier writes to a JSON document")
	var opened: Dictionary=workshop.open_port_document(path)
	_check(opened.ok,"The workshop reconstructs the saved pier through its actual Open route")
	if not opened.ok:workshop.queue_free();await _settle();_finish_fishing();return
	var boat: BoatBody=workshop.presenter.vessel_nodes.get("nordlys")
	_check(is_instance_valid(boat),"The saved fishing boat is rendered alongside")
	if is_instance_valid(boat):_verify_vessel_contents(boat,workshop.state.to_dict().vessels[0])
	var plant: Node3D=workshop.presenter.placement_nodes.get("landing")
	var bank: ShoreRswTankBank
	for node in plant.find_children("*","Node3D",true,false):
		if node is ShoreRswTankBank:bank=node;break
	_check(is_instance_valid(bank) and is_zero_approx(bank.total_mass_kg()),"Installed receiving tanks begin empty")
	_check(workshop.library._catalog.has("fish_landing_plant"),"The same fish plant is available in the build library")
	workshop.camera.position=workshop.site+Vector3(-42,38,-45)
	workshop.camera.look_at(workshop.site+Vector3(0,2,16))
	workshop.overlays.hide()
	await get_tree().create_timer(.5).timeout
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("fishing-pier-arrival")
	_export("--fishing-arrival-output=",workshop.state.to_dict())
	workshop.camera.position=workshop.site+Vector3(-23,17,-19)
	workshop.camera.look_at(workshop.site+Vector3(0,2,9))
	# Use the actual inspector action and its state_changed signal, as a player does.
	var operator: Node=workshop.presenter.placement_nodes["landing-operator"]
	operator._on_interact()
	_check(workshop.inspector.visible and workshop.inspector._selected(workshop.inspector._store)=="fish-receiver" and workshop.inspector._selected(workshop.inspector._vessel)=="nordlys","The actual fish operator opens its own store and served vessel")
	for pair in [["morning-catch",420.0],["large-halibut",6.0]]:
		var chosen:=-1
		for index in workshop.inspector._unload_lot.item_count:
			if str(workshop.inspector._unload_lot.get_item_metadata(index))==str(pair[0]):chosen=index;break
		_check(chosen>=0,"Inspector lists the actual onboard lot "+str(pair[0]))
		if chosen<0:continue
		workshop.inspector._unload_lot.select(chosen)
		workshop.inspector._refresh_unload_action()
		workshop.inspector._quantity.value=float(pair[1])
		workshop.inspector._unload_selected()
		_check(workshop.transfers.is_busy(),"Accepted landing starts the pump presentation")
		var committed: Dictionary=workshop.state.to_dict()
		workshop._begin_move("landing")
		_check(workshop.moving_id.is_empty() and workshop.state.to_dict()==committed,"Equipment cannot move during its committed hose presentation")
		workshop._close_inspector()
		deadline=Time.get_ticks_msec()+30000
		var captured:=false
		while workshop.transfers.is_busy() and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
			if not captured and OS.get_cmdline_user_args().has("--capture") and str(workshop.transfers.status()).to_lower().contains("pump"):
				await workshop._capture("fishing-pier-pumping-"+str(pair[0]));captured=true
		_check(not workshop.transfers.is_busy(),"Landing presentation finishes")
		_check(workshop.state.to_dict()==committed,"Pump animation never mutates accepted data")
		operator._on_interact()
	workshop._close_inspector()
	var landed: Dictionary=workshop.state.to_dict()
	_check(landed.vessels[0].lots.is_empty() and landed.stores[0].lots.size()==2,"Both finite lots are ashore and the vessel is empty")
	_check(is_instance_valid(bank) and absf(bank.total_mass_kg()-458.5)<.000001,"Actual receiving tanks show exactly 458.5kg")
	var reposition: Dictionary=workshop.editor.preview_transform("landing",Vector3(4,0,12),0)
	_check(reposition.ok,"The stocked plant can move four metres on this same 32-metre pier")
	var moved: Dictionary=workshop.editor.transform(reposition)
	_check(moved.ok,"Moving the stocked plant is one accepted construction command")
	if moved.ok:
		workshop._on_state_changed(workshop.state.to_dict(),moved)
		_check(workshop.state.to_dict().stores==landed.stores,"Moving the plant preserves exact store IDs, permissions, lots and fish metadata")
		plant=workshop.presenter.placement_nodes["landing"]
		bank=null
		for node in plant.find_children("*","Node3D",true,false):
			if node is ShoreRswTankBank:bank=node;break
		_check(is_instance_valid(bank) and absf(bank.total_mass_kg()-458.5)<.000001,"The moved physical receiving bank still contains exactly458.5kg")
		var undone: Dictionary=workshop.editor.undo()
		_check(undone.ok,"One undo puts the stocked plant back")
		if undone.ok:workshop._on_state_changed(workshop.state.to_dict(),undone)
		_check(workshop.state.to_dict().placements==landed.placements and workshop.state.to_dict().stores==landed.stores,"Undo restores the plant geometry without rolling back catch")
	landed=workshop.state.to_dict()
	workshop.save_port();workshop.load_port()
	_check(workshop.state.to_dict()==landed,"Landed catch and its metadata survive Save/Load")
	_verify_docked_vessels(workshop.presenter,landed)
	_export("--fishing-landed-output=",landed)
	if OS.get_cmdline_user_args().has("--capture"):await workshop._capture("fishing-pier-complete")
	workshop.queue_free();await _settle();_finish_fishing()

func _export(prefix: String,snapshot: Dictionary) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with(prefix):continue
		var file:=FileAccess.open(arg.trim_prefix(prefix),FileAccess.WRITE)
		_check(file!=null,"Portable fishing harbour output opens")
		if file!=null:file.store_string(JSON.stringify(snapshot,"\t",true,true));file.close()

func _finish_fishing() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT FISHING WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
