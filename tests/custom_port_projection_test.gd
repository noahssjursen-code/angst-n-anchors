extends Node

## Complete JSON -> actual installed equipment, with no live company services.
var state: CustomPortState
var presenter: CustomPortPresenter
var sequence:=0
var failures: Array[String]=[]
var checks:=0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var world: Dictionary={"seed":73119,"generation_version":1,"checksum":"projection-fixture"}
	var plots: Array=[{"id":"plot","rect_m":[-124,-108,200,200],"owner_company_id":CustomPortExample.OWNER}]
	var snapshot:=CustomPortExample.build(Vector3(0,.5,0),plots,world)
	snapshot.erase("_site_yaw")
	snapshot.water_regions=[{"rect_m":[-128,-104,232,168],"depth_m":12}]
	snapshot.stores[1].public_unloading=true
	state=CustomPortState.from_dict(snapshot,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Actual construction fixture validates: "+str(state.validation_errors))
	if not state.validation_errors.is_empty(): _finish(); return
	presenter=CustomPortPresenter.new()
	add_child(presenter)
	presenter.load_record(state.to_dict(),state.derived_berths())
	for slot in presenter.berth_nodes.values():
		_check(slot.bollards().size()==2,"Every inferred berth has two real mooring components")
	var bulk: Dictionary=_find(state.to_dict().vessels,"bulk-trader")
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,bulk,[]).ok and "bulk-yard" in CustomPortBerths.services_for_vessel(berth,bulk).store_ids:
			berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"Actual 32m bulk vessel has a crane-served berth")
	if berth_id.is_empty(): _finish(); return
	_apply("dock",{"vessel_id":"bulk-trader","berth_id":berth_id})
	await get_tree().process_frame
	var boat: BoatBody=presenter.vessel_nodes.get("bulk-trader")
	_check(is_instance_valid(boat),"Bulk vessel is physically reconstructed")
	var original_id:=boat.get_instance_id()
	var excessive:=_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":220000,"reservation_id":"too-much"},false)
	_check(not excessive.ok,"Cannot reserve more than port stock")
	var over_hold:=_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":125000,"reservation_id":"over-hold"},false)
	_check(not over_hold.ok,"Cannot overfill the real 120t hold")
	_apply("reserve_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":50000,"reservation_id":"bulk-load"})
	_apply("load_cargo",{"reservation_id":"bulk-load"})
	_check(presenter.vessel_nodes["bulk-trader"].get_instance_id()==original_id,"Manifest updates preserve the existing ship instance")
	var holds:=BulkHoldComponent.get_all_for_ship(boat)
	_check(holds.size()==1 and is_equal_approx(holds[0].state.filled_tonnes_t,50),"Actual rendered hold contains the 50t manifest")
	_check(is_equal_approx(float(_find(_find(state.to_dict().stores,"bulk-yard").lots,"ore-stock").quantity),150000),"Port stock lost exactly the loaded 50t")
	_apply("unload_cargo",{"store_id":"bulk-yard","vessel_id":"bulk-trader","lot_id":"ore-stock","quantity":20000})
	_check(is_equal_approx(holds[0].state.filled_tonnes_t,30),"Unloading updates the existing hold to 30t")
	# Recreated crane model must repopulate unchanged stock from the snapshot.
	var recreated:=state.to_dict()
	for row in recreated.placements:
		if row.id=="container-terminal":row.attributes.presentation_review="rebuild"
	presenter.load_record(recreated,state.derived_berths())
	_check(_container_count(presenter.placement_nodes["container-terminal"])==20,"Recreated yard rehydrates all unchanged containers")
	# A new client can restore the data without remembering any renderer state.
	var second:=CustomPortPresenter.new()
	add_child(second)
	second.load_record(state.to_dict(),state.derived_berths())
	var restored_holds:=BulkHoldComponent.get_all_for_ship(second.vessel_nodes["bulk-trader"])
	_check(restored_holds.size()==1 and is_equal_approx(restored_holds[0].state.filled_tonnes_t,30),"Fresh projection reconstructs identical bulk contents")
	second.load_record(_without_docked(state.to_dict()),state.derived_berths())
	_apply("undock",{"vessel_id":"bulk-trader"})
	_check(presenter.vessel_nodes.is_empty(),"Departure removes the visible ship")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(boat),"Departure frees the ship without deferred lifecycle work")
	await _test_compartment_projection()
	_finish()

func _test_compartment_projection() -> void:
	var snapshot:=state.to_dict()
	var small:=CustomPortVesselProjection.from_prebuilt("bulk_small","two-holds","company-visitor")
	small.lots=[
		{"id":"small-coal","commodity_id":"coal","quantity":1000,"unit_mass_kg":1,"attributes":{}},
		{"id":"small-ore","commodity_id":"iron_ore","quantity":2000,"unit_mass_kg":1,"attributes":{}}]
	snapshot.vessels.append(small)
	state=CustomPortState.from_dict(snapshot,snapshot.world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Two-commodity manifest validates against the actual two-hold fitout")
	if not state.validation_errors.is_empty():return
	var berth_id:=""
	for berth in state.derived_berths():
		if CustomPortBerths.fit(berth,small,[]).ok:
			berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"Small bulk vessel has a compatible berth")
	if berth_id.is_empty():return
	_apply("dock",{"vessel_id":"two-holds","berth_id":berth_id})
	await get_tree().process_frame
	var boat: BoatBody=presenter.vessel_nodes.get("two-holds")
	_check(is_instance_valid(boat),"Actual two-hold ship is reconstructed")
	if not is_instance_valid(boat):return
	_check_compartment_contents(boat,_find(state.to_dict().vessels,"two-holds"),"Different commodities")
	var restored:=CustomPortState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict(),"",true,true)),snapshot.world,CustomPortCatalog.definitions())
	_check(restored.validation_errors.is_empty(),"Mixed-hold manifest survives complete JSON reconstruction")
	var fresh:=CustomPortPresenter.new()
	add_child(fresh)
	fresh.load_record(restored.to_dict(),restored.derived_berths())
	_check_compartment_contents(fresh.vessel_nodes["two-holds"],_find(restored.to_dict().vessels,"two-holds"),"Fresh JSON projection")
	fresh.queue_free()
	# Same commodity is still segregated when its shipments have different ids.
	snapshot=state.to_dict()
	var row:=_find(snapshot.vessels,"two-holds")
	row.lots[1].commodity_id="coal"
	state=CustomPortState.from_dict(snapshot,snapshot.world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Two separate coal consignments fit separate holds")
	presenter.load_record(state.to_dict(),state.derived_berths())
	_check_compartment_contents(boat,row,"Distinct consignments")
	# Explicitly shared shipment identity may use the same physical compartment.
	snapshot=state.to_dict()
	row=_find(snapshot.vessels,"two-holds")
	for lot in row.lots:lot.attributes.consignment_id="one-shipment"
	state=CustomPortState.from_dict(snapshot,snapshot.world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Explicitly shared coal consignment validates")
	presenter.load_record(state.to_dict(),state.derived_berths())
	_check_compartment_contents(boat,row,"Shared consignment")
	_apply("undock",{"vessel_id":"two-holds"})
	await get_tree().process_frame

func _check_compartment_contents(boat: BoatBody,vessel: Dictionary,label: String) -> void:
	var expected:=CustomPortState._bulk_plan(vessel,vessel.lots)
	var actual: Array[Dictionary]=[]
	var mass_kg:=0.0
	for hold in boat.get_bulk_holds():
		actual.append(hold.state.to_dict())
		mass_kg+=hold.state.filled_tonnes_t*1000.0
	_check(expected.ok and actual==expected.hold_states,label+": authority packing matches each real hold's id, commodity, consignment and contents")
	_check(is_equal_approx(mass_kg,CustomPortState._mass(vessel.lots)),label+": all accepted mass is installed aboard")

func _apply(kind: String,payload: Dictionary,expected_ok:=true) -> Dictionary:
	sequence+=1
	var result:=state.apply({"command_id":"projection-%d"%sequence,"kind":kind,"actor_company_id":"company-visitor","expected_revision":state.revision(),"payload":payload})
	if expected_ok:_check(result.ok,"Accepted "+kind+": "+str(result.get("code","")))
	if result.ok:presenter.load_record(result.snapshot,state.derived_berths())
	return result

func _without_docked(snapshot: Dictionary) -> Dictionary:
	for vessel in snapshot.vessels:vessel.berth_id=""
	return snapshot

func _find(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id",""))==id:return row
	return {}

func _container_count(root: Node) -> int:
	var count:=0
	for node in root.find_children("*","Node3D",true,false):
		if node is ContainerNode:count+=1
	return count

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT PROJECTION ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
