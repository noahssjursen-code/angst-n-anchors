extends "res://tests/custom_port_transfer_test.gd"

var bulk_captures: Dictionary={}
var minimum_jaw:=1.0
var maximum_jaw:=0.0
var slew_before:=0.0
var maximum_slew_change:=0.0

func _run() -> void:
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"bulk-transfer-fixture"}
	var plots: Array=[{"id":"plot-west","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12.0}]
	var shore:=Transfer._find(snapshot.stores,"bulk-yard")
	shore.lots.append({"id":"coal-stock","commodity_id":"coal","quantity":80000,"unit_mass_kg":1,"attributes":{"slots_per_unit":0}})
	shore.lots.append({"id":"other-ore-shipment","commodity_id":"iron_ore","quantity":20000,"unit_mass_kg":1,"attributes":{"slots_per_unit":0,"consignment_id":"unrelated-ore"}})
	shore.lots.append({"id":"ore-small","commodity_id":"iron_ore","quantity":1000,"unit_mass_kg":1,"attributes":{"slots_per_unit":0,"consignment_id":"small-ore"}})
	state=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Bulk fixture is valid: "+str(state.validation_errors))
	if not state.validation_errors.is_empty():get_tree().quit(1);return
	port=CustomPortPresenter.new()
	add_child(port)
	transfer=Transfer.new()
	add_child(transfer)
	transfer.bind(port)
	transfer.set_process(false)
	transfer.presentation_failed.connect(func(reason: String)->void:animation_errors.append(reason))
	transfer.present(state.to_dict(),state.derived_berths())
	var trader:=Transfer._find(state.to_dict().vessels,"bulk-trader")
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,trader,[]).ok and "bulk-yard" in CustomPortBerths.services_for_vessel(berth,trader,"bulk").store_ids:
			berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"Real bulk vessel has a reachable serviced berth")
	if berth_id.is_empty():get_tree().quit(1);return
	_apply("dock",{"vessel_id":"bulk-trader","berth_id":berth_id})
	await get_tree().process_frame
	_check(port.vessel_nodes.has("bulk-trader"),"Docking projects Coastal Bulk from its actual blueprint")
	if not port.vessel_nodes.has("bulk-trader"):get_tree().quit(1);return
	var ship: BoatBody=port.vessel_nodes["bulk-trader"]
	var crane:=port.placement_nodes["bulk-terminal"].find_child("Crane",true,false) as BulkCrane
	var hold: BulkHoldComponent=ship.get_bulk_holds()[0]
	_check(hold.state.capacity_tonnes_t==120,"Actual imported hold has its authored 120-tonne capacity")
	var coal: Node3D=port.cargo_nodes["coal-stock"]
	var ore: Node3D=port.cargo_nodes["ore-stock"]
	_check(coal!=ore and coal.position.distance_to(ore.position)>3,"Coal and ore occupy separate receiving bays")
	_check(port.cargo_nodes["other-ore-shipment"]==ore,"Equal commodities share one visual pile without merging data lots")
	var coal_position:=coal.global_position
	var coal_scale:=coal.scale
	var ore_position:=ore.global_position
	slew_before=crane.slew_degrees
	target=Vector3(44,6,10)
	camera.position=Vector3(100,52,-55)
	camera.look_at(target)
	label.text="FINITE BULK TRANSFER · Existing grab crane and real 120 t ship hold\nAccepted data stays unchanged while the grab, jaws, stockpile and hold fill animate"
	_block("Review water",Vector3(320,.05,240),Vector3(0,-1.525,-100),"roof_sheet",Color("274958"))
	if native_capture:await _capture("bulk-before")
	if native_capture:
		camera.position=(coal.global_position+ore.global_position)*.5+Vector3(15,30,18)
		camera.look_at((coal.global_position+ore.global_position)*.5)
		await _capture("separated-bulk-stock")
		camera.position=Vector3(100,52,-55)
		camera.look_at(target)
	_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":35000,"reservation_id":"bulk-load"})
	var result:=_apply("load_cargo",{"reservation_id":"bulk-load"})
	_check(str(result.get("result",{}).get("crane_id",""))=="bulk-terminal","Authority selects the compatible bulk crane")
	_check(transfer.bulk.is_busy() and transfer.bulk.total_grabs==2,"35 tonnes use two grabs at the actual 21 t bucket capacity")
	_check(is_equal_approx(hold.state.filled_tonnes_t,35),"The accepted hold state is committed before playback")
	var committed:=JSON.stringify(state.to_dict())
	var hold_committed:=JSON.stringify(hold.state.to_dict())
	var active: Dictionary=transfer.bulk._current
	_check(is_equal_approx(float(active.get("store_before_kg",0)),221000),"Loading animates the combined commodity pile, including untouched consignments")
	_check(not port.cargo_nodes["other-ore-shipment"].visible and port.cargo_nodes["coal-stock"].visible,
		"Only the transferring commodity is replaced by its animated pile")
	_check(active.pile.global_position.distance_to(ore_position)<.01,"The grab targets the ore bay instead of the yard centre")
	transfer.present(state.to_dict(),state.derived_berths(),result.events)
	_check(transfer.bulk._current==active,"Duplicate event leaves the active bulk cycle intact")
	await _finish_bulk("load")
	_check(transfer.bulk.completed_grabs==2 and is_equal_approx(transfer.bulk.presented_kg,35000),"Both grabs account for exactly the accepted 35 tonnes")
	_check(JSON.stringify(state.to_dict())==committed and JSON.stringify(hold.state.to_dict())==hold_committed,"Bulk playback writes neither authority nor the real hold state")
	_check(minimum_jaw<.05 and maximum_jaw>.95 and maximum_slew_change>15,"The real grab closes, opens and slews between endpoints")
	_check(crane.get_bucket_lot().is_empty() and not crane.simulate_bulk_material,"Animation never creates an inventory-bearing grab payload")
	_check(_bulk_proxy_count()==0 and hold._fill_layer.visible,"Completion restores committed fill and removes visual proxies")
	_check(port.cargo_nodes["coal-stock"].global_position==coal_position and port.cargo_nodes["coal-stock"].scale==coal_scale,
		"Unrelated coal stays in place at the same fill level throughout loading")
	if native_capture:
		target=hold.global_position
		camera.position=hold.global_position+Vector3(11,19,-13)
		camera.look_at(target)
		# This test's flat water box has no hull cutout. Hide the backdrop only
		# for the close hold inspection so it cannot cover the real fill mesh.
		subject.get_node("Review water").hide()
		await _capture("bulk-loaded-hold")
		subject.get_node("Review water").show()
	result=_apply("unload_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":12000})
	_check(transfer.bulk.is_busy(),"Accepted unloading animates from hold to the finite stockpile")
	await _finish_bulk("unload")
	_check(is_equal_approx(hold.state.filled_tonnes_t,23) and is_equal_approx(transfer.bulk.presented_kg,12000),"Unloading leaves the exact 23-tonne balance")
	# Interrupt while the loaded grab is suspended. The snapshot remains enough
	# to recover and must not leave a phantom pile or payload behind.
	_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":10000,"reservation_id":"interrupt-bulk"})
	_apply("load_cargo",{"reservation_id":"interrupt-bulk"})
	var steps:=0
	while transfer.is_busy() and transfer.bulk._phase!="travel_drop" and steps<6000:
		transfer._process(.05)
		steps+=1
	_check(transfer.bulk._phase=="travel_drop","Departure test reaches a closed suspended grab")
	_apply("undock",{"vessel_id":"bulk-trader"})
	_check(not transfer.is_busy() and _bulk_proxy_count()==0,"Departure clears all transient grab, grain and pile visuals")
	_check(crane.get_bucket_lot().is_empty() and not port.vessel_nodes.has("bulk-trader"),"Departure leaves no vessel or inventory on the hook")
	var departed:=Transfer._find(state.to_dict().vessels,"bulk-trader")
	_check(is_equal_approx(float(Transfer._find(departed.lots,"ore-stock").quantity),33000),"Departure retains the already committed 33 tonnes")
	_apply("dock",{"vessel_id":"bulk-trader","berth_id":berth_id})
	await get_tree().process_frame
	ship=port.vessel_nodes["bulk-trader"]
	hold=ship.get_bulk_holds()[0]
	_check(not transfer.is_busy() and is_equal_approx(hold.state.filled_tonnes_t,33),"Fresh arrival reconstructs the committed hold without replaying old grabs")
	_apply("unload_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":33000})
	await _finish_bulk("empty-hold")
	_check(hold.state.is_empty() and not is_instance_valid(hold._fill_layer),"Full unload removes the final real hold fill")
	var final_store:=Transfer._find(state.to_dict().stores,"bulk-yard")
	_check(is_equal_approx(float(Transfer._find(final_store.lots,"ore-stock").quantity),200000),"Finite stock returns to its exact original 200 tonnes")
	_check(float(Transfer._find(final_store.lots,"coal-stock").quantity)==80000 and float(Transfer._find(final_store.lots,"other-ore-shipment").quantity)==20000,
		"Other commodities and consignments are unchanged after load, unload and interruption")
	_check(_bulk_proxy_count()==0 and not crane.is_processing(),"Final unload clears every visual and stops the idle crane")
	_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-small","quantity":1000,"reservation_id":"entire-shore-lot"})
	_apply("load_cargo",{"reservation_id":"entire-shore-lot"})
	_check(not port.cargo_nodes.has("ore-small") and transfer.bulk.is_busy() and not port.cargo_nodes["ore-stock"].visible,
		"Removing a whole consignment still hides the surviving shared ore heap during playback")
	await _finish_bulk("whole-lot")
	_check(port.cargo_nodes["ore-stock"].visible and port.cargo_nodes["coal-stock"].visible and _bulk_proxy_count()==0,
		"Whole-lot completion restores both remaining commodities without a duplicate pile")
	_apply("unload_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-small","quantity":1000})
	await _finish_bulk("return-whole-lot")
	_check(port.cargo_nodes["ore-small"]==port.cargo_nodes["ore-stock"] and hold.state.is_empty(),
		"Returning the consignment rejoins its commodity visual while preserving its own data identity")
	_check(animation_errors.is_empty(),"No bulk presentation failures: "+str(animation_errors))
	await _settle_audio_before_exit()
	print("CUSTOM PORT BULK TRANSFER ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _finish_bulk(direction: String) -> void:
	var steps:=0
	while transfer.is_busy() and steps<12000:
		transfer._process(.05)
		steps+=1
		var crane:=port.placement_nodes["bulk-terminal"].find_child("Crane",true,false) as BulkCrane
		minimum_jaw=minf(minimum_jaw,crane.bucket_open)
		maximum_jaw=maxf(maximum_jaw,crane.bucket_open)
		maximum_slew_change=maxf(maximum_slew_change,absf(crane.slew_degrees-slew_before))
		if steps%40==0:await get_tree().process_frame
		if native_capture and (transfer.bulk._phase=="travel_drop" or (transfer.bulk._phase=="dump" and transfer.bulk._timer>.4)):
			var key:=direction+"-"+str(transfer.bulk._phase)
			if not bulk_captures.has(key):
				bulk_captures[key]=true
				target=crane.get_bucket_mouth_global()+Vector3.DOWN*2
				camera.position=target+Vector3(21,13,-24)
				camera.look_at(target)
				await _capture("bulk-"+key)
	_check(not transfer.is_busy(),"Bulk cycle finishes within its bounded motion budget")
	await get_tree().process_frame

func _bulk_proxy_count() -> int:
	var count:=0
	for node in port.find_children("*","Node3D",true,false):
		if node.has_meta("custom_port_bulk_visual"):count+=1
	return count
