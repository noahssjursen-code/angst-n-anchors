extends "res://tests/custom_port_transfer_test.gd"

## Separate yard placement with the production cargo-pad component. A crane
## linked in authority data serves it; no crane is parented beneath this yard.
class LinkedYardProjection extends CustomPortPresenter:
	func _add_placement(row: Dictionary) -> void:
		super._add_placement(row)
		if str(row.id)!="quay--20": return
		var pad:=preload("res://scripts/port/port_cargo_yard.gd").container_pad(Vector2(4,8))
		pad.name="CargoPad"
		pad.position.y=.035
		pad.rotation.y=PI*.5
		placement_nodes[str(row.id)].add_child(pad)

func _run() -> void:
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"linked-yard-transfer-fixture"}
	var plots: Array=[{"id":"plot-west","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12.0}]
	var remote_lot: Dictionary=snapshot.stores[0].lots[0].duplicate(true)
	remote_lot.id="separate-yard-parts"
	remote_lot.quantity=1
	remote_lot.attributes.paint_variant=5
	snapshot.stores.append({"id":"linked-yard","name":"Separate quay cargo pad","placement_id":"quay--20","capacity_kg":24000,"capacity_units":1,
		"accepted_handling_modes":["container"],"accepted_container_types":["20ft"],"accepted_commodities":["machine_parts"],"public_loading":true,"public_unloading":true,"lots":[remote_lot]})
	for row in snapshot.placements:
		if str(row.id)=="container-terminal": row.attributes.store_ids=["linked-yard"]
	state=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Cross-linked fixture is valid: "+str(state.validation_errors))
	if not state.validation_errors.is_empty():get_tree().quit(1);return
	port=LinkedYardProjection.new()
	add_child(port)
	transfer=Transfer.new()
	add_child(transfer)
	transfer.bind(port)
	transfer.set_process(false)
	transfer.presentation_failed.connect(func(reason: String)->void:animation_errors.append(reason))
	transfer.present(state.to_dict(),state.derived_berths())
	var trader:=Transfer._find(state.to_dict().vessels,"trader")
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,trader,[]).ok and "linked-yard" in CustomPortBerths.services_for_vessel(berth,trader,"container").store_ids:
			berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"Authority links the separate pad to an actual cargo berth")
	if berth_id.is_empty():get_tree().quit(1);return
	_apply("dock",{"vessel_id":"trader","berth_id":berth_id})
	await get_tree().process_frame
	_check(port.vessel_nodes.has("trader"),"Linked-yard fixture projects the actual docked ship")
	if not port.vessel_nodes.has("trader"):get_tree().quit(1);return
	_check(port.placement_nodes["quay--20"].find_child("Crane",true,false)==null,"The stock placement has no crane child")
	_check(_visible_containers(port.placement_nodes["quay--20"])==1,"The separate pad renders its one finite unit")
	_apply("reserve_cargo",{"store_id":"linked-yard","vessel_id":"trader","lot_id":remote_lot.id,"quantity":1,"reservation_id":"linked-load"})
	var result:=_apply("load_cargo",{"reservation_id":"linked-load"})
	_check(str(result.get("result",{}).get("crane_id",""))=="container-terminal","Authority issues the separate handling crane identity")
	_check(transfer.is_busy(),"Cross-linked load animates despite no crane under its stock placement")
	_check(transfer._current.get("crane")==port.placement_nodes["container-terminal"].find_child("Crane",true,false),"Presentation uses exactly the issued crane")
	var committed:=JSON.stringify(state.to_dict())
	target=Vector3(-22,6,4)
	camera.position=Vector3(-72,42,-40)
	camera.look_at(target)
	label.text="CROSS-LINKED YARD · One separate pad, the authority-selected crane\nThe stock placement has no crane child; the actual Harbour Cargo receives its recorded unit"
	_block("Review water",Vector3(320,.05,240),Vector3(0,-1.525,-100),"roof_sheet",Color("274958"))
	await _finish_motion()
	_check(JSON.stringify(state.to_dict())==committed,"Cross-linked playback leaves all cargo authority unchanged")
	_check(_visible_containers(port.vessel_nodes.trader)==1 and _visible_containers(port.placement_nodes["quay--20"])==0,"Loading empties the separate pad and fills the real vessel slot")
	result=_apply("unload_cargo",{"store_id":"linked-yard","vessel_id":"trader","lot_id":remote_lot.id,"quantity":1})
	_check(str(result.get("result",{}).get("crane_id",""))=="container-terminal" and transfer.is_busy(),"Cross-linked unloading uses its issued crane too")
	await _finish_motion()
	_check(_visible_containers(port.vessel_nodes.trader)==0 and _visible_containers(port.placement_nodes["quay--20"])==1,"Unloading restores exactly one unit to the separate pad")
	_check(_visual_proxy_count()==0 and _hook_empty(),"Cross-linked round trip leaves no ghost containers")
	_check(animation_errors.is_empty(),"Valid linked-yard transfers have no presentation errors: "+str(animation_errors))
	# Even a malformed/mismatched presentation event must not guess another
	# crane. Keep the accepted snapshot visible when a selected rig is unsuitable.
	_apply("reserve_cargo",{"store_id":"linked-yard","vessel_id":"trader","lot_id":remote_lot.id,"quantity":1,"reservation_id":"bad-presentation-rig"})
	sequence+=1
	result=state.apply({"command_id":"transfer-%d"%sequence,"kind":"load_cargo","actor_company_id":"company-visitor","expected_revision":state.revision(),"payload":{"reservation_id":"bad-presentation-rig"}})
	_check(bool(result.get("ok",false)),"Control commit remains a legal container transfer")
	var bad_events: Array=result.events.duplicate(true)
	bad_events[0].receipt.result.crane_id="bulk-terminal"
	transfer.present(result.snapshot,state.derived_berths(),bad_events)
	_check(not transfer.is_busy() and animation_errors.size()==1,"A bulk rig cannot masquerade as the issued container crane")
	_check(_visible_containers(port.vessel_nodes.trader)==1 and _visual_proxy_count()==0,"Unsupported visual rig preserves committed cargo without guessing")
	await _settle_audio_before_exit()
	print("CUSTOM PORT LINKED YARD TRANSFER ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
