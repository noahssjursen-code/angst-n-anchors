extends "res://tests/custom_port_showcase_input_test.gd"

func _run() -> void:
	var source:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port-document="):source=argument.trim_prefix("--port-document=")
	_check(not source.is_empty(),"A port document is supplied")
	if source.is_empty():_finish();return
	var source_bytes:=FileAccess.get_file_as_bytes(source)
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Imported port opens on its generated world")
	if not workshop.ready_for_review:_finish();return
	var imported:=CustomPortRepository.load_state(source,workshop.world_identity,workshop.catalog)
	_check(imported.ok and workshop.state.to_dict()==imported.snapshot,"Authority data matches the supplied document exactly")
	if not imported.ok:workshop.queue_free();_finish();return
	_check(workshop.site==CustomPortCatalog.vector3(imported.snapshot.origin_m),"Camera and terrain streaming use the imported port origin")
	_check(workshop.owner_company_id==str(imported.snapshot.owner_company_id) and workshop.editor.actor_company_id==workshop.owner_company_id,
		"Workshop build permissions use the imported owner")
	_check(workshop.presenter.placement_nodes.size()==imported.snapshot.placements.size(),"Every saved placement is reconstructed")
	_check(workshop.presenter.record.origin_m==imported.snapshot.origin_m,"Scene projection uses the saved origin")
	_verify_docked_vessels(workshop.presenter,imported.snapshot)
	_check(workshop.save_path.begins_with("user://custom_ports/imported-"),"Edits save separately from the supplied source")
	workshop.save_port()
	_check(FileAccess.get_file_as_bytes(source)==source_bytes,"Saving edits never overwrites the source document")
	_verify_deck_plane_boundary(workshop,imported.snapshot)
	_verify_vessel_projection_boundary(workshop,imported.snapshot)
	if OS.get_cmdline_user_args().has("--capture"):
		workshop.library.hide();workshop.overlays.hide()
		await workshop._capture("json-injected-port")
	workshop.queue_free()
	await get_tree().process_frame
	_finish()

func _verify_vessel_projection_boundary(workshop: Node,snapshot: Dictionary) -> void:
	var bulk_index:=-1
	for index in snapshot.vessels.size():
		var vessel: Dictionary=snapshot.vessels[index]
		if not str(vessel.get("prebuilt_id","")).is_empty() and float(vessel.get("handling_capacity_kg",{}).get("bulk",0))>0:
			bulk_index=index;break
	_check(bulk_index>=0,"Import fixture includes an actual bulk vessel")
	if bulk_index<0:return
	var original_state: CustomPortState=workshop.state
	var original_presenter_record: Dictionary=workshop.presenter.record.duplicate(true)
	for missing in [false,true]:
		var forged:=snapshot.duplicate(true)
		var vessel: Dictionary=forged.vessels[bulk_index]
		if missing:
			vessel.erase("cargo_holds")
		else:
			for hold in vessel.cargo_holds:
				if str(hold.handling_mode)=="bulk":hold.capacity_kg=float(hold.capacity_kg)*2
			vessel.capacity_kg=float(vessel.capacity_kg)*2
			vessel.handling_capacity_kg.bulk=float(vessel.handling_capacity_kg.bulk)*2
		var generic:=CustomPortState.from_dict(forged,workshop.world_identity,workshop.catalog)
		_check(generic.validation_errors.is_empty(),"Generic authority retains abstract declared fitout support")
		var path:="user://custom_ports/invalid-fitout-%d-%d-%s.json"%[OS.get_process_id(),Time.get_ticks_usec(),str(missing)]
		var saved:=CustomPortRepository.save(path,generic)
		_check(saved.ok,"Generic JSON file can carry an independently declared fitout")
		if saved.ok:
			_check(not workshop._load_workshop_document(path).ok,"Physical import rejects missing or forged installed hold evidence")
			_check(workshop.state==original_state and workshop.presenter.record==original_presenter_record,"Rejected import leaves active authority and physical contents untouched")

func _verify_deck_plane_boundary(workshop: Node,snapshot: Dictionary) -> void:
	var original_state: CustomPortState=workshop.state
	var original_path: String=workshop.save_path
	var original_origin: Vector3=workshop.presenter.position
	_check(workshop._load_workshop_document(original_path).ok,"The workshop accepts its saved sea-referenced plane")
	for matching_height in [false,true]:
		var changed:=snapshot.duplicate(true)
		changed.origin_m[1]=float(changed.origin_m[1])+5
		if matching_height:changed.deck_height_above_sea_m=float(changed.deck_height_above_sea_m)+5
		var path:="user://custom_ports/invalid-plane-%d-%d-%s.json"%[OS.get_process_id(),Time.get_ticks_usec(),str(matching_height)]
		var file:=FileAccess.open(path,FileAccess.WRITE)
		_check(file!=null,"The isolated plane-validation fixture can be written")
		if file==null:continue
		file.store_string(JSON.stringify(changed,"",true,true));file.close()
		var generic:=CustomPortRepository.load_state(path,workshop.world_identity,workshop.catalog)
		_check(generic.ok,"Generic data authority remains independent of this workshop's sea datum")
		var rejected: Dictionary=workshop._load_workshop_document(path)
		_check(not rejected.ok and rejected.code=="incompatible_deck_plane",
			"Import rejects a second plane" if matching_height else "Import rejects an origin inconsistent with the declared sea-relative deck")
		workshop.save_path=path
		workshop.load_port()
		_check(workshop.state==original_state and workshop.state.to_dict()==snapshot and workshop.presenter.position==original_origin,
			"Rejected Load leaves the active harbour and cargo untouched")
		workshop.save_path=original_path
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	workshop.feedback.text="Saved harbour restored · vessels and cargo verified"

## Expectations come from the imported save, including empty/undocked documents.
## Inspect installed equipment contents, not the presenter's copy of the manifest.
func _verify_docked_vessels(presenter: CustomPortPresenter,snapshot: Dictionary) -> void:
	var docked_count:=0
	for vessel in snapshot.get("vessels",[]):
		var id:=str(vessel.id)
		var berth_id:=str(vessel.get("berth_id",""))
		if berth_id.is_empty():
			_check(not presenter.vessel_nodes.has(id),id+": an undocked record has no harbour ship")
			continue
		docked_count+=1
		var boat: BoatBody=presenter.vessel_nodes.get(id)
		_check(is_instance_valid(boat),id+": the saved docked vessel is reconstructed")
		if not is_instance_valid(boat):continue
		var berth: QuayBerthSlot=presenter.berth_nodes.get(berth_id)
		_check(is_instance_valid(berth),id+": the saved berth is reconstructed")
		if is_instance_valid(berth):
			var expected: Transform3D=berth.transform*berth.ship_dock_local(float(vessel.beam_m)*.5,float(vessel.length_m))
			expected.origin.y=WaveSurface.WATER_LEVEL-float(vessel.draft_m)-presenter.position.y
			_check(boat.transform.is_equal_approx(expected),id+": saved berth and draft determine the restored ship pose")
		_verify_vessel_contents(boat,vessel)
	_check(presenter.vessel_nodes.size()==docked_count,"Only the document's docked vessels are instantiated")

func _verify_vessel_contents(boat: BoatBody,vessel: Dictionary) -> void:
	var id:=str(vessel.id)
	var expected_containers: Dictionary={}
	var expected_bulk: Dictionary={}
	var expected_catch: Dictionary={}
	for lot in vessel.get("lots",[]):
		var attrs: Dictionary=lot.get("attributes",{})
		if attrs.has("container_type"):
			for index in int(lot.quantity):
				var key:=_container_key(str(lot.commodity_id),str(attrs.container_type),float(lot.unit_mass_kg),
					str(attrs.get("destination_port_id","")),int(attrs.get("paint_variant",index%8)))
				expected_containers[key]=int(expected_containers.get(key,0))+1
		else:
			var mode:=CustomPortState._handling_mode(lot)
			var masses: Dictionary=expected_catch if mode=="catch" else expected_bulk
			var commodity:=str(lot.commodity_id)
			masses[commodity]=float(masses.get(commodity,0))+float(lot.quantity)*float(lot.unit_mass_kg)
	var pads:=boat.get_cargo_pads()
	if vessel.has("container_beds"):
		_check(pads.size()==vessel.container_beds.size(),id+": installed container beds match the saved fitout")
	var actual_containers: Dictionary={}
	var actual_units:=0
	for pad in pads:
		for unit in pad.get_containers():
			actual_units+=1
			var key:=_container_key(unit.commodity_id,unit.container_type,unit.mass_kg,unit.destination_port_id,unit.paint_variant)
			actual_containers[key]=int(actual_containers.get(key,0))+1
	_check(actual_containers==expected_containers,id+": installed containers preserve quantities, type, commodity, mass, destination and paint")
	var visible_units:=0
	for node in boat.find_children("*","Node3D",true,false):
		if node is ContainerNode and node.is_visible_in_tree():
			visible_units+=1
			_check(CargoSlotPadComponent.find_pad_for_node(node) in pads,id+": each visible container belongs to an installed ship bed")
	_check(visible_units==actual_units,id+": every installed container has a visible model")
	var actual_bulk: Dictionary={}
	var actual_catch: Dictionary={}
	var bulk_capacity:=0.0
	var catch_capacity:=0.0
	for hold in boat.get_bulk_holds():
		bulk_capacity+=hold.state.capacity_tonnes_t*1000.0
		if not hold.state.is_empty():
			var commodity:=hold.state.commodity_id
			actual_bulk[commodity]=float(actual_bulk.get(commodity,0))+hold.state.filled_tonnes_t*1000.0
	for hold in boat.get_catch_holds():
		catch_capacity+=hold.state.capacity_kg
		for lot in hold.state.lots:
			actual_catch[lot.product_id]=float(actual_catch.get(lot.product_id,0))+lot.mass_kg
	_check(_same_masses(actual_bulk,expected_bulk),id+": installed bulk holds restore the manifest's commodity and mass")
	_check(_same_masses(actual_catch,expected_catch),id+": installed catch holds restore the manifest's commodity and mass")
	if vessel.has("cargo_holds"):
		var expected_bulk_capacity:=0.0
		var expected_catch_capacity:=0.0
		for hold in vessel.cargo_holds:
			if str(hold.handling_mode)=="bulk":expected_bulk_capacity+=float(hold.capacity_kg)
			elif str(hold.handling_mode)=="catch":expected_catch_capacity+=float(hold.capacity_kg)
		_check(is_equal_approx(bulk_capacity,expected_bulk_capacity) and is_equal_approx(catch_capacity,expected_catch_capacity),
			id+": real hold capacities match the saved fitout")
	print("IMPORTED VESSEL ",id," containers=",actual_units," bulk_kg=",actual_bulk," catch_kg=",actual_catch)

func _container_key(commodity: String,type: String,mass: float,destination: String,paint: int) -> String:
	return JSON.stringify([commodity,type,mass,destination,paint])

func _same_masses(actual: Dictionary,expected: Dictionary) -> bool:
	if actual.size()!=expected.size():return false
	for commodity in expected:
		if not actual.has(commodity) or not is_equal_approx(float(actual[commodity]),float(expected[commodity])):return false
	return true

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT DOCUMENT INJECTION ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
