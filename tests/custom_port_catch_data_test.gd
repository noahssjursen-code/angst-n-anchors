extends "res://tests/custom_port_data_test.gd"

func _run() -> void:
	if not ShipyardPlaytestMode.active():get_tree().quit(1);return
	var initial:=_catch_fixture()
	var state:=_fresh(initial)
	check(state.validation_errors.is_empty(),"Real fishing-vessel fixture validates")
	if not state.validation_errors.is_empty():_finish_catch();return
	initial=state.to_dict()
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok,"Fishing vessel docks at catch-capable equipment")
	_reject_unchanged(state,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":6},"invalid_quantity")
	var whole:=_command(state,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":12.5})
	check(whole.ok,"The complete fish can be landed using its original mass representation")
	check(state.to_dict().vessels[0].lots.is_empty(),"Landing removes the complete specimen from the vessel")
	check(state.to_dict().stores[0].lots==initial.vessels[0].lots,"Landing preserves exact fish identity and custom attributes")
	_reject_unchanged(state,"reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":1},"invalid_quantity")
	check(_command(state,"reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":12.5,"reservation_id":"fish-back"}).ok,"One complete fish can be reserved for collection")
	check(_command(state,"load_cargo",{"reservation_id":"fish-back"}).ok,"Complete fish returns aboard")
	check(state.to_dict().vessels[0].lots==initial.vessels[0].lots,"Roundtrip leaves the specimen unchanged")
	check(_fresh(JSON.parse_string(JSON.stringify(state.to_dict(),"",true,true))).to_dict()==state.to_dict(),"Catch records and receipts reconstruct exactly from JSON")
	var replica:=_fresh(initial)
	# Replay a fresh command sequence rather than overwriting the read model.
	var source:=_fresh(initial)
	var dock:=_command(source,"dock",{"vessel_id":"ship-a","berth_id":source.derived_berths()[0].id})
	var landed:=_command(source,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":12.5})
	for response in [dock,landed]:
		check(response.ok,"Catch replay source action succeeds")
		for event in response.events:check(replica.replay_event(JSON.parse_string(JSON.stringify(event,"",true,true))).ok,"Catch event applies to a second data model")
	check(replica.to_dict()==source.to_dict(),"Receiving data model has identical landed fish")
	var bad:=_catch_fixture()
	bad.stores[0].lots=bad.vessels[0].lots.duplicate(true)
	check(not _fresh(bad).validation_errors.is_empty(),"A specimen cannot exist simultaneously ashore and aboard")
	for value in ["yes",1,[]]:
		bad=_catch_fixture();bad.vessels[0].lots[0].attributes.specimen=value
		check(not _fresh(bad).validation_errors.is_empty(),"Malformed specimen flags reject safely")
	for changes in [{"quality":2},{"quality":"high"},{"caught_game_hours":-1},{"caught_position":[0,"north"]},{"length_cm":-5},{"price_multiplier":-1}]:
		bad=_catch_fixture();bad.stores[0].lots=bad.vessels[0].lots.duplicate(true);bad.vessels[0].lots=[]
		bad.stores[0].lots[0].attributes.merge(changes,true)
		check(not _fresh(bad).validation_errors.is_empty(),"Invalid shore catch metadata cannot become silently clamped physical data")
	bad=_catch_fixture();bad.vessels[0].lots[0].quantity=.05
	check(not _fresh(bad).validation_errors.is_empty(),"Catch below the component mass threshold cannot disappear on reconstruction")
	bad=_catch_fixture();bad.vessels[0].lots[0].quantity=400
	bad.vessels[0].erase("prebuilt_id")
	bad.vessels[0].cargo_holds=[{"id":"a","handling_mode":"catch","capacity_kg":300},{"id":"b","handling_mode":"catch","capacity_kg":300}]
	check(not _fresh(bad).validation_errors.is_empty(),"An individual fish must fit a single actual hold despite spare aggregate capacity")
	var bulk:=_catch_fixture();bulk.vessels[0].lots[0].attributes.specimen=false;bulk.vessels[0].lots[0].quantity=100
	state=_fresh(bulk)
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok,"Bulk catch fixture docks")
	_reject_unchanged(state,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":99.95},"invalid_quantity")
	check(_command(state,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":35}).ok,"Ordinary bulk catch can split without splitting specimens")
	check(is_equal_approx(float(state.to_dict().vessels[0].lots[0].quantity),65) and is_equal_approx(float(state.to_dict().stores[0].lots[0].quantity),35),"Bulk catch mass remains conserved")
	var unit:=_catch_fixture();unit.vessels[0].lots[0].quantity=1;unit.vessels[0].lots[0].unit_mass_kg=12.5
	check(_fresh(unit).validation_errors.is_empty(),"Count-one specimen representation is also valid")
	var reservations:=bad.duplicate(true)
	reservations.stores[0].lots=reservations.vessels[0].lots.duplicate(true)
	reservations.vessels[0].lots=[]
	state=_fresh(reservations)
	check(state.validation_errors.is_empty(),"Shore fish waiting for two small holds validates before reservation")
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok,"Two-compartment fishing vessel docks")
	_reject_unchanged(state,"reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":400},"catch_compartments_exceeded")
	reservations.stores[0].lots=[]
	for index in 3:
		var fish: Dictionary=initial.vessels[0].lots[0].duplicate(true)
		fish.id="halibut-%d"%index;fish.quantity=200
		reservations.stores[0].lots.append(fish)
	state=_fresh(reservations)
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok,"Multiple-specimen reservation fixture docks")
	for index in 2:
		check(_command(state,"reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"halibut-%d"%index,"quantity":200,"reservation_id":"reserved-%d"%index}).ok,"Each reserved fish occupies a real hold")
	_reject_unchanged(state,"reserve_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"halibut-2","quantity":200},"catch_compartments_exceeded")
	check(_command(state,"load_cargo",{"reservation_id":"reserved-0"}).ok,"Loading preserves room for the other reserved specimen")
	check(_command(state,"load_cargo",{"reservation_id":"reserved-1"}).ok,"Second reserved specimen enters its own hold")
	var loaded_ship: Dictionary=state.to_dict().vessels[0]
	var packing:=VESSELS.catch_hold_plan(loaded_ship,loaded_ship.lots)
	check(packing.ok and packing.hold_states.size()==2 and packing.hold_states[0].lots.size()==1 and packing.hold_states[1].lots.size()==1,"Reconstructed hold plan preserves both distinct fish")
	check(packing.allocations==[{"lot_id":"halibut-0","hold_id":"a","mass_kg":200.0},{"lot_id":"halibut-1","hold_id":"b","mass_kg":200.0}],"Per-lot allocations retain identity separately from hydrated hold state")
	var tiny:=_catch_fixture();tiny.vessels[0].lots[0].quantity=1e-7;tiny.vessels[0].lots[0].unit_mass_kg=1e9
	state=_fresh(tiny)
	check(state.validation_errors.is_empty(),"Unit conversion does not impose arbitrary count-unit restrictions")
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok,"Unusual but valid unit conversion fixture docks")
	_reject_unchanged(state,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":5e-8},"invalid_quantity")
	tiny.vessels[0].lots[0].attributes.specimen=false
	state=_fresh(tiny)
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok,"Bulk catch unit-conversion fixture docks")
	check(_command(state,"unload_cargo",{"store_id":"yard","vessel_id":"ship-a","lot_id":"cod-001","quantity":5e-8}).ok,"Small positive quantity of heavy units may move as divisible catch")
	check(state.to_dict().vessels[0].lots.size()==1 and absf(CustomPortState._mass(state.to_dict().vessels[0].lots)-50)<.000001 and absf(CustomPortState._mass(state.to_dict().stores[0].lots)-50)<.000001,"A tiny positive quantity cannot erase fifty kilograms from the source")
	for changes in [{"caught_position":[1e40,0]},{"species_id":" cod "}]:
		bad=_catch_fixture();bad.vessels[0].lots[0].attributes.merge(changes,true)
		check(not _fresh(bad).validation_errors.is_empty(),"Catch metadata cannot become nonfinite or change identity during physical hydration")
	bad=_catch_fixture();bad.vessels[0].lots[0].id=" cod-001 "
	check(not _fresh(bad).validation_errors.is_empty(),"Specimen IDs cannot collide after CatchLot trims whitespace")
	_finish_catch()

func _catch_fixture() -> Dictionary:
	var document:=_fixture()
	document.stores[0].accepted_handling_modes=["catch"]
	document.stores[0].accepted_commodities=["fresh_groundfish"]
	document.stores[0].lots=[]
	var ship:=VESSELS.from_prebuilt("fishing_hook_line","ship-a","company-a")
	ship.lots=[{"id":"cod-001","commodity_id":"fresh_groundfish","quantity":12.5,"unit_mass_kg":1,"attributes":{
		"specimen":true,"species_id":"cod","length_cm":105,"quality":.9,"caught_game_hours":42,"caught_position":[-50,80],
		"size_grade":"Large","value_nok":1200,"custom_label":"Keep this fish"}}]
	document.vessels=[ship]
	return document

func _finish_catch() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT CATCH DATA ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
