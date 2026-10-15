extends "res://tests/custom_port_transfer_test.gd"

## Actual accepted office-door events must not land a suspended load instantly.
const FISH_EXAMPLE = preload("res://scripts/port/building/custom_port_fishing_example.gd")
var checks := 0
var mode := ""
var vessel_id := ""
var store_id := ""
var door_id := ""
var berth_id := ""
var before_transfer: Dictionary = {}
var committed_transfer: Dictionary = {}
var committed_events: Array = []

func _run() -> void:
	_block("Review water",Vector3(320,.05,240),Vector3(0,-1.525,-100),"roof_sheet",Color("274958"))
	for family in ["container","bulk","catch"]:
		await _install(family)
		if not state.validation_errors.is_empty():break
		await _stage()
		var active: Variant = _token()
		var progress := _progress()
		var stock: Array = state.to_dict().stores
		var fleet: Array = state.to_dict().vessels
		var result := _door_event()
		_check(result.ok,"Actual owner door command is accepted during " + mode)
		_check(transfer.is_busy() and _token()==active,"Opening an unrelated office door preserves the same active " + mode + " playback")
		_check(_progress()==progress,"Opening a door does not reset " + mode + " progress")
		_check(port.record.revision==state.revision() and bool(Transfer._find(port.record.placements,door_id).attributes.door_open),"New door revision is visibly applied immediately")
		_check(state.to_dict().stores==stock and state.to_dict().vessels==fleet,"Door playback preservation cannot change committed stock or manifests")
		if mode=="catch":
			var renamed:=_issue("rename_port",{"name":"New fishing pier name"},str(state.to_dict().owner_company_id))
			_check(renamed.ok and transfer.is_busy() and _token()==active and _progress()==progress,"Renaming the harbour preserves the same live hose and progress")
			_check(port.record.name=="New fishing pier name","The preserved playback still applies the new harbour name")
		if native_capture and mode=="catch":
			camera.position=Vector3(-26,24,-26);camera.look_at(Vector3(0,2,14))
			label.text="OFFICE DOOR OPEN · FISH LANDING CONTINUES\nThe accepted door update keeps the same hose and pumping progress"
			await _capture("door-update-fish-pump")
		await _finish_active()
		_check(_proxy_count()==0,"Finishing "+mode+" removes all temporary cargo")
		_check((mode=="container" and transfer.completed_units==2) or (mode=="bulk" and transfer.bulk.completed_grabs==2) or (mode=="catch" and transfer.catch_transfer.completed_mass_kg==100),"Preserved "+mode+" playback completes its exact accepted amount")
		await _restart()
		await _stage()
		var old_token: Variant=_token()
		_issue("undock",{"vessel_id":vessel_id})
		_check(not transfer.is_busy() and not port.vessel_nodes.has(vessel_id),"Departure still interrupts "+mode+" playback")
		await get_tree().process_frame
		_check(_proxy_count()==0 and (mode=="catch" or not is_instance_valid(old_token)),"Departure clears temporary "+mode+" cargo rather than abandoning it")
		if mode!="catch":
			await _restart();await _stage()
			var equipment: Node3D=port.placement_nodes["container-terminal" if mode=="container" else "bulk-terminal"]
			var old_crane: Node3D=equipment.find_child("Crane",true,false)
			var frame:=old_crane.transform
			equipment.remove_child(old_crane);old_crane.free()
			var new_crane: Node3D=ProvisionCrane.new() if mode=="container" else BulkCrane.new()
			if new_crane is BulkCrane:new_crane.show_operator=false;new_crane.simulate_bulk_material=false
			new_crane.name="Crane";new_crane.transform=frame;equipment.add_child(new_crane)
			new_crane.set_process(false)
			_door_event()
			await get_tree().process_frame
			_check(not transfer.is_busy() and _proxy_count()==0,"Freed/replaced "+mode+" crane clears every stale job and visual safely")
	await _unsafe_catch_updates()
	_check(animation_errors.is_empty(),"No presentation failures: "+str(animation_errors))
	await _settle_audio_before_exit()
	print("CUSTOM PORT TRANSFER UPDATE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _install(family: String) -> void:
	if is_instance_valid(transfer):transfer.reset();transfer.free()
	if is_instance_valid(port):port.free()
	mode=family
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"transfer-update-fixture"}
	var plots: Array=[{"id":"plot","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot: Dictionary=FISH_EXAMPLE.build(Vector3(0,.5,0),plots,world) if family=="catch" else CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12.0}]
	state=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Valid "+mode+" fixture: "+str(state.validation_errors))
	port=CustomPortPresenter.new();add_child(port)
	transfer=Transfer.new();add_child(transfer);transfer.bind(port);transfer.set_process(false)
	transfer.presentation_failed.connect(func(reason:String)->void:animation_errors.append(reason))
	transfer.present(state.to_dict(),state.derived_berths())
	vessel_id={"container":"trader","bulk":"bulk-trader","catch":"nordlys"}[mode]
	store_id={"container":"container-yard","bulk":"bulk-yard","catch":"fish-receiver"}[mode]
	door_id=""
	for row in snapshot.placements:
		if str(row.asset_id)=="workshop_door_4m":door_id=str(row.id);break
	var vessel:=Transfer._find(state.to_dict().vessels,vessel_id)
	berth_id=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,vessel,[]).ok and store_id in CustomPortBerths.services_for_vessel(berth,vessel).store_ids:berth_id=str(berth.id);break
	_check(not berth_id.is_empty() and not door_id.is_empty(),"Fixture has an actual served ship berth and office door")
	_issue("dock",{"vessel_id":vessel_id,"berth_id":berth_id})
	for frame in 3:await get_tree().process_frame
	if mode!="catch":
		_issue("reserve_cargo",{"store_id":store_id,"vessel_id":vessel_id,"lot_id":"parts-for-shipyard" if mode=="container" else "ore-stock","quantity":2 if mode=="container" else 35000,"reservation_id":"pending"})
	before_transfer=state.to_dict()
	var moved:=_issue("unload_cargo",{"store_id":store_id,"vessel_id":vessel_id,"lot_id":"morning-catch","quantity":100}) if mode=="catch" else _issue("load_cargo",{"reservation_id":"pending"})
	committed_transfer=state.to_dict();committed_events=moved.events.duplicate(true)
	_check(transfer.is_busy(),"Accepted "+mode+" transfer starts playback")

func _issue(kind: String,payload: Dictionary,owner := "company-visitor",present := true) -> Dictionary:
	sequence+=1
	var result:=state.apply({"command_id":"update-%d"%sequence,"kind":kind,"actor_company_id":owner,"expected_revision":state.revision(),"payload":payload})
	_check(result.ok,"Authority accepts "+kind+": "+str(result.get("details",{})))
	if result.ok and present:transfer.present(result.snapshot,state.derived_berths(),result.events)
	return result

func _door_event(present := true) -> Dictionary:
	var row:=Transfer._find(state.to_dict().placements,door_id)
	var replacement:=row.duplicate(true)
	replacement.attributes.door_open=not bool(replacement.attributes.get("door_open",false))
	return _issue("edit_assets",{"operations":[{"kind":"remove_asset","payload":{"placement_id":door_id,"expected_placement":row}},{"kind":"place_asset","payload":{"placement":replacement}}]},str(state.to_dict().owner_company_id),present)

func _stage() -> void:
	var steps:=0
	while transfer.is_busy() and steps<6000:
		if mode=="container" and transfer._phase=="travel_drop":break
		if mode=="bulk" and transfer.bulk._phase=="travel_drop":break
		if mode=="catch" and transfer.catch_transfer._current.pump.projection_progress()>.1:break
		transfer._process(.05);steps+=1
		if steps%100==0:await get_tree().process_frame
	_check(transfer.is_busy() and steps<6000,"Actual "+mode+" reaches suspended/pumping playback")

func _token() -> Variant:
	if mode=="container":return transfer._current.get("proxy")
	if mode=="bulk":return transfer.bulk._current.get("grab")
	return transfer.catch_transfer._current.get("pump")

func _progress() -> float:
	if mode=="container":return transfer._timer
	if mode=="bulk":return transfer.bulk._timer
	var pump: FishLandingPump=transfer.catch_transfer._current.get("pump")
	return pump.projection_progress() if is_instance_valid(pump) else -1.0

func _finish_active() -> void:
	var steps:=0
	while transfer.is_busy() and steps<12000:
		transfer._process(.05);steps+=1
		if steps%100==0:await get_tree().process_frame
	_check(not transfer.is_busy(),mode+" finishes in a bounded cycle")
	await get_tree().process_frame

func _restart() -> void:
	transfer.reset()
	transfer.present(before_transfer,CustomPortState.from_dict(before_transfer,before_transfer.world,CustomPortCatalog.definitions()).derived_berths())
	for frame in 2:await get_tree().process_frame
	state=CustomPortState.from_dict(committed_transfer,committed_transfer.world,CustomPortCatalog.definitions())
	transfer.present(committed_transfer,state.derived_berths(),committed_events)
	_check(transfer.is_busy(),"Focused interruption scenario starts actual committed playback")

func _unsafe_catch_updates() -> void:
	# Fresh actual playback for each different discontinuity. This does not
	# repeatedly rerun port authority suites or manufacture inventory changes.
	await _restart();await _stage()
	_door_event(false)
	var second:=_door_event(false)
	transfer.present(second.snapshot,state.derived_berths(),second.events)
	_check(not transfer.is_busy(),"A missed intermediate revision still interrupts rather than guessing continuity")
	_check(_catch_cleared(),"Gap leaves no hose or interpolated bank fill")
	await _restart();await _stage()
	var snapshot_only:=_door_event(false)
	transfer.present(snapshot_only.snapshot,state.derived_berths())
	_check(not transfer.is_busy() and _catch_cleared(),"An unaccompanied replacement snapshot interrupts playback")
	await _restart();await _stage()
	var pump: FishLandingPump=transfer.catch_transfer._current.pump
	var prior_progress:=pump.projection_progress()
	_issue("unload_cargo",{"store_id":store_id,"vessel_id":vessel_id,"lot_id":"morning-catch","quantity":10})
	_check(transfer.is_busy() and transfer.catch_transfer.total_mass_kg==10 and pump.projection_progress()<prior_progress,"A newly committed transfer replaces playback with its own exact ten kilograms")
	await _restart();await _stage()
	var ship: Node3D=port.vessel_nodes[vessel_id]
	ship.position.x+=1
	_door_event()
	_check(not transfer.is_busy() and _catch_cleared(),"An externally moved source vessel invalidates otherwise unrelated door continuity")
	await _restart();await _stage()
	var door_node: Node3D=port.placement_nodes[door_id]
	door_node.global_position=port.placement_nodes.landing.global_position
	_door_event()
	_check(not transfer.is_busy() and _catch_cleared(),"A door swing crossing the active handling envelope interrupts safely")
	await _restart();await _stage()
	var old: Node3D=port.placement_nodes.landing
	var replacement:=CustomPortPresenter.asset_visual(CustomPortCatalog.definition("fish_landing_plant"))
	replacement.transform=old.transform
	port.remove_child(old);old.free();port.add_child(replacement)
	port.placement_nodes.landing=replacement
	replacement.apply_store(Transfer._find(state.to_dict().stores,store_id))
	_door_event()
	_check(not transfer.is_busy() and _catch_cleared(),"Same-ID rebuilt pump nodes cannot inherit an old hose job")
	await _restart();await _stage()
	# A real reserve then cancel while this subscriber misses the reserve must
	# still clear playback. Neither command changes the already committed fish.
	_issue("reserve_cargo",{"store_id":store_id,"vessel_id":vessel_id,"lot_id":"morning-catch","quantity":1,"reservation_id":"cancel-during-playback"},"company-visitor",false)
	_issue("cancel_reservation",{"reservation_id":"cancel-during-playback"})
	_check(not transfer.is_busy() and _catch_cleared(),"Cancellation restores committed fish presentation and removes the hose")

func _catch_cleared() -> bool:
	var plant: Node3D=port.placement_nodes.get("landing")
	return is_instance_valid(plant) and not plant.pump.is_projecting() and not plant.pump._hose_root.visible and plant.bank._presented_mass_kg<0

func _proxy_count() -> int:
	var count:=0
	for node in port.find_children("*","Node3D",true,false):
		if node.has_meta("custom_port_transfer_visual") or node.has_meta("custom_port_bulk_visual"):count+=1
	return count

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)
