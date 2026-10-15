extends "res://tests/custom_port_data_test.gd"
const VISITORS=preload("res://scripts/port/building/custom_port_test_visitors.gd")

func _run() -> void:
	var initial:=_fixture()
	initial.vessels=[]
	var state:=_fresh(initial)
	var replica:=_fresh(initial)
	check(state.validation_errors.is_empty(),"Empty harbour accepts later fleet projections")
	var trusted:=CustomPortVesselProjection.from_prebuilt("fishing_hook_line","arriving-fisher","company-a")
	trusted.lots=[{"id":"cod-carried-in","commodity_id":"fresh_groundfish","quantity":1,"unit_mass_kg":7.25,
		"attributes":{"specimen":true,"species_id":"cod","quality":.95,"length_cm":85,"value_nok":1425,"tag":"Existing fleet catch"}}]
	var context:={"vessel_records":{trusted.id:trusted}}
	var command:={"command_id":"arrival-reference","expected_revision":0,"actor_company_id":"company-a","kind":"admit_vessel","payload":{"vessel_id":trusted.id}}
	_reject_unchanged(state,"admit_vessel",command.payload,"authority_vessel_unavailable")
	_reject_unchanged(state,"admit_vessel",command.payload,"authority_vessel_unavailable","company-a",{"vessel_records":[]})
	_reject_unchanged(state,"admit_vessel",{"vessel_id":trusted.id,"vessel":trusted},"invalid_vessel_reference","company-a",context)
	_reject_unchanged(state,"admit_vessel",command.payload,"not_vessel_owner","intruder",context)
	var bad:=context.duplicate(true)
	bad.vessel_records[trusted.id].capacity_kg=999999
	_reject_unchanged(state,"admit_vessel",command.payload,"invalid_authority_vessel","company-a",bad)
	bad=context.duplicate(true);bad.vessel_records[trusted.id].berth_id="forged-berth"
	_reject_unchanged(state,"admit_vessel",command.payload,"vessel_already_docked","company-a",bad)
	bad=context.duplicate(true);bad.vessel_records[trusted.id].id="another-ship"
	_reject_unchanged(state,"admit_vessel",command.payload,"invalid_authority_vessel","company-a",bad)
	var accepted:=state.apply(command,context)
	check(accepted.ok and accepted.events.size()==1,"Trusted existing fitout enters via one accepted revisioned event")
	check(state.to_dict().vessels==CustomPortState._canonical([trusted]),"All authoritative construction/contents survive their canonical JSON admission exactly")
	check(context.vessel_records[trusted.id]==trusted,"Admission never mutates its supplied fleet projection")
	check(state.to_dict().vessels[0].berth_id=="","Admission cannot occupy a berth")
	check(accepted.account_changes.is_empty(),"Admission is not a purchase or a payment")
	var retry:=state.apply(command,{})
	check(retry.ok and retry.replayed and retry.events.is_empty(),"Retry needs no refreshed context and cannot duplicate the vessel")
	_reject_unchanged(state,"admit_vessel",command.payload,"vessel_already_known","company-a",context)
	check(replica.replay_event(JSON.parse_string(JSON.stringify(accepted.events[0],"",true,true))).ok,"A receiving client admits it from the authority event")
	check(replica.to_dict()==state.to_dict(),"Source and event-only replica match")
	check(_fresh(JSON.parse_string(JSON.stringify(state.to_dict(),"",true,true))).to_dict()==state.to_dict(),"Admitted fitout and receipt roundtrip through JSON")
	var before:=state.to_dict()
	check(not VISITORS.invite(state,"not-a-blueprint").ok and state.to_dict()==before,"Unknown scenario choices cannot mutate the port")
	for preset in VISITORS.options():
		var invited:=VISITORS.invite(state,preset.id)
		check(invited.ok,"Available prebuilt can be explicitly invited: "+str(preset.id))
		if not invited.ok:continue
		var added: Dictionary=state.to_dict().vessels.back()
		check(added.lots.is_empty() and added.berth_id=="","A test visitor invents neither cargo nor berth occupancy")
		check(CustomPortVesselProjection.validate_vessel(added).ok,"Test visitor capacities match its actual model")
		check(replica.replay_event(invited.events[0]).ok,"Visitor uses ordinary event reconstruction")
	check(replica.to_dict()==state.to_dict(),"Multiple distinct visitors reconstruct identically")
	for failure in failures:push_error(failure)
	print("CUSTOM PORT VISITORS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
