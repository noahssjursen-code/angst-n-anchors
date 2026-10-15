extends Node
## A reproducible data-only play session. No scene inventory, physics, server,
## live saves or invented payments; the exported intent trace can be run again.
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const REPOSITORY = preload("res://scripts/port/state/custom_port_repository.gd")
const VESSELS = preload("res://scripts/port/state/custom_port_vessel_projection.gd")
const BERTHS = preload("res://scripts/port/state/custom_port_berths.gd")
const SEED := 915731
const ROUNDS := 64
const WORLD := {"seed":73119,"generation_version":12,"checksum":"data-session-fixture-v1"}
var failures: Array[String] = []
var checks := 0
var state: CustomPortState
var replica: CustomPortState
var catalog: Dictionary
var initial: Dictionary
var initial_totals: Dictionary
var trace: Array[Dictionary] = []
var journal: Array[Dictionary] = []
var event_ids: Dictionary = {}
var counts: Dictionary = {}
var checkpoints: Array[Dictionary] = []
var sequence := 0
var completed_rounds := 0
var output_directory := "user://custom-port-simulation-test"
var last_accepted_command: Dictionary = {}
var loaded_kg := 0.0
var loaded_containers := 0
var started_usec := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Port simulation requires --shipyard-playtest isolation.")
		get_tree().quit(1); return
	started_usec = Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port-simulation-output="):
			output_directory = argument.trim_prefix("--port-simulation-output=")
	_check(DirAccess.make_dir_recursive_absolute(output_directory)==OK,"Evidence directory can be created")
	catalog = _catalog()
	state = STATE.from_dict(_fixture(),WORLD,catalog)
	_check(state.validation_errors.is_empty(),"Initial port is valid: "+str(state.validation_errors))
	initial = state.to_dict()
	replica = STATE.from_dict(_wire(initial),WORLD,catalog)
	_check(replica.validation_errors.is_empty(),"Independent initial JSON snapshot validates")
	_check(VESSELS.validate_snapshot(initial).ok,"All four ships retain their real installed fitouts")
	initial_totals = _totals(initial)
	var berths := state.derived_berths()
	_check(berths.size()==2,"Compact fixture has two independently usable berths")
	for berth in berths:
		for vessel in initial.vessels:
			var bulk: bool = str(vessel.id).begins_with("bulk")
			_check(BERTHS.fit(berth,vessel,[]).ok,"Real vessel fits berth: "+str(vessel.id))
			_check(("bulk-yard" if bulk else "box-yard") in BERTHS.services_for_vessel(berth,vessel,"bulk" if bulk else "container").store_ids,"Correct crane reaches vessel and finite yard: "+str(vessel.id))
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	if failures.is_empty():
		for round_index in ROUNDS:
			_run_round(round_index,random,berths)
			if not failures.is_empty(): break
			completed_rounds += 1
			if completed_rounds%8==0:
				print("PORT SESSION rounds=",completed_rounds," commands=",trace.size()," revision=",state.revision())
				await get_tree().process_frame
	_check(completed_rounds==ROUNDS,"All planned cargo rounds completed")
	if failures.is_empty():
		_check(_hash(state.to_dict())==_hash(replica.to_dict()),"Authority and event replica finish identical")
		_check(_totals(state.to_dict())==initial_totals,"All original stock and attributes survive the session")
		_check(state.to_dict().reservations.is_empty(),"No abandoned reservation remains")
		for vessel in state.to_dict().vessels:
			_check(vessel.lots.is_empty() and str(vessel.berth_id).is_empty(),"Each visitor departs empty after returning its goods")
		_check(state.revision()==journal.size() and state.to_dict().receipts.size()==journal.size(),"One receipt, revision and event per unique accepted intent")
	var trace_path := output_directory.path_join("command-trace.json")
	_write_json(trace_path,{"format":"custom-port-play-session-v1","seed":SEED,"planned_rounds":ROUNDS,
		"world":WORLD,"catalog":catalog,"initial_snapshot":initial,"commands":trace,
		"events":journal,"checkpoints":checkpoints,"final_state_hash":_hash(state.to_dict())})
	if failures.is_empty(): _repeat_saved_trace(trace_path)
	var summary := {"ok":failures.is_empty(),"seed":SEED,"cargo_rounds":completed_rounds,
		"container_rounds":completed_rounds/2,"bulk_rounds":completed_rounds/2,
		"visiting_vessels":4,"commands":trace.size(),"accepted_events":journal.size(),
		"result_counts":counts,"checkpoints":checkpoints.size(),"loaded_mass_kg":loaded_kg,
		"loaded_container_count":loaded_containers,"account_changes":0,
		"initial_stock":initial_totals,"final_stock":_totals(state.to_dict()),
		"final_state_hash":_hash(state.to_dict()),"replica_state_hash":_hash(replica.to_dict()),
		"checks":checks,"failures":failures,"duration_ms":(Time.get_ticks_usec()-started_usec)/1000.0,
		"trace_file":"command-trace.json","payment_scope":"Cargo has no payment rule; all commands must return zero account changes."}
	_write_json(output_directory.path_join("summary.json"),summary)
	for failure in failures: push_error(failure)
	print("CUSTOM PORT SIMULATION ","PASS" if failures.is_empty() else "FAIL",
		" rounds=",completed_rounds," commands=",trace.size()," events=",journal.size()," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_round(index: int, random: RandomNumberGenerator, berths: Array) -> void:
	var bulk := index%2==1
	var prefix := "bulk" if bulk else "box"
	var pair: Array[String] = [prefix+"-a",prefix+"-b"]
	if random.randi_range(0,1)==1: pair.reverse()
	var first: String = pair[0]
	var second: String = pair[1]
	var store := "bulk-yard" if bulk else "box-yard"
	var lot := "ore-shipment" if bulk else "parts-shipment"
	var total := 150000.0 if bulk else 3.0
	var first_quantity := float(random.randi_range(60000,90000))+.125 if bulk else 2.0
	var second_quantity := total-first_quantity
	var reservation_a := "round-%02d-first" % index
	var reservation_b := "round-%02d-second" % index
	_issue("dock",{"vessel_id":first,"berth_id":berths[0].id},_owner(first))
	if index%8==0:
		var occupied := _issue("dock",{"vessel_id":second,"berth_id":berths[0].id},_owner(second),"vessel_does_not_fit")
		_check("occupied" in occupied.get("details",{}).get("reasons",[]),"Competing arrival is refused because the berth is occupied")
	_issue("dock",{"vessel_id":second,"berth_id":berths[1].id},_owner(second))
	if not failures.is_empty(): return
	if index%8==0:
		_issue("reserve_cargo",_request(store,first,lot,1,"foreign"),"company-intruder","not_vessel_owner")
		var stale := _new_command("reserve_cargo",_request(store,first,lot,1,"stale"),_owner(first))
		stale.expected_revision = state.revision()-1
		_dispatch(stale,"revision_conflict")
		_issue("reserve_cargo",_request(store,first,lot,-1,"negative"),_owner(first),"invalid_quantity")
	_issue("reserve_cargo",_request(store,first,lot,first_quantity,reservation_a),_owner(first))
	_issue("reserve_cargo",_request(store,second,lot,second_quantity+(125 if bulk else 1),reservation_b),_owner(second),"insufficient_stock")
	if index%5==0:
		_issue("undock",{"vessel_id":first},_owner(first),"cargo_reserved")
		_issue("cancel_reservation",{"reservation_id":reservation_a},"company-intruder","not_reservation_owner")
		_issue("cancel_reservation",{"reservation_id":reservation_a},_owner(first))
		# A rival uses the stock released by cancellation; original buyer gets
		# only the remainder. For containers this swaps the 2/1-slot allocation.
		var swapped := first_quantity
		first_quantity = second_quantity
		second_quantity = swapped
		_issue("reserve_cargo",_request(store,second,lot,second_quantity,reservation_b),_owner(second))
		_issue("reserve_cargo",_request(store,first,lot,first_quantity,reservation_a+"-retry"),_owner(first))
		reservation_a += "-retry"
	else:
		_issue("reserve_cargo",_request(store,second,lot,second_quantity,reservation_b),_owner(second))
	if not failures.is_empty(): return
	if index==0:
		_checkpoint("reserved-%02d" % index)
		_dispatch(last_accepted_command.duplicate(true),"already_applied")
	if index%9==0:
		var changed := last_accepted_command.duplicate(true)
		changed.payload.quantity = float(changed.payload.quantity)+1
		_dispatch(changed,"command_id_conflict")
	var first_load := _new_command("load_cargo",{"reservation_id":reservation_a},_owner(first))
	_dispatch(first_load,"applied")
	var second_load := _new_command("load_cargo",{"reservation_id":reservation_b},_owner(second))
	_dispatch(second_load,"applied")
	if not failures.is_empty(): return
	loaded_kg += total if bulk else total*4800
	if not bulk: loaded_containers += int(total)
	_check(_find(state.to_dict().stores,store).lots.is_empty(),"Both visitors exhaust this finite source lot")
	if index in [15,32,47,63]: _checkpoint("loaded-%02d" % index)
	if index%4==0 or index in [15,32,47,63]:
		_dispatch(second_load,"already_applied")
	if index%8==0:
		_issue("load_cargo",{"reservation_id":reservation_b},_owner(second),"reservation_not_found")
		_issue("unload_cargo",_request(store,first,lot,first_quantity+1),_owner(first),"insufficient_cargo")
	_check_hold_projection()
	var unloading: Array = [{"vessel":first,"quantity":first_quantity},{"vessel":second,"quantity":second_quantity}]
	if random.randi_range(0,1)==1: unloading.reverse()
	for shipment: Dictionary in unloading:
		var vessel: String = shipment.vessel
		var quantity: float = shipment.quantity
		var partial := quantity*.25 if bulk else minf(1,quantity)
		_issue("unload_cargo",_request(store,vessel,lot,partial),_owner(vessel))
		if quantity>partial:
			_issue("unload_cargo",_request(store,vessel,lot,quantity-partial),_owner(vessel))
		_issue("undock",{"vessel_id":vessel},_owner(vessel))
	if index%8==0:
		_issue("reserve_cargo",_request(store,first,lot,1,"away"),_owner(first),"not_docked")
	_check(_totals(state.to_dict())==initial_totals,"Round %d returns all exact quantities and attributes" % index)
	_check(VESSELS.validate_snapshot(state.to_dict()).ok,"Completed round retains actual installed capacity evidence")


func _issue(kind: String, payload: Dictionary, actor: String, expected := "applied") -> Dictionary:
	return _dispatch(_new_command(kind,payload,actor),expected)


func _new_command(kind: String, payload: Dictionary, actor: String) -> Dictionary:
	sequence += 1
	return {"command_id":"session-%04d" % sequence,"expected_revision":state.revision(),
		"actor_company_id":actor,"kind":kind,"payload":payload.duplicate(true)}


func _dispatch(command: Dictionary, expected: String) -> Dictionary:
	var before := state.to_dict()
	var result := state.apply(_wire(command))
	var after := state.to_dict()
	var label := "%s %s" % [command.command_id,command.kind]
	_check(str(result.code)==expected,label+" expected "+expected+"; got "+str(result.code)+" "+str(result.get("details",{})))
	_check(result.get("ok") is bool and result.ok==(expected in ["applied","already_applied"]),label+" reports the correct success/rejection status")
	_check(result.get("account_changes",[]).is_empty(),label+" has no invented payment/account side effect")
	counts[result.code] = int(counts.get(result.code,0))+1
	if result.code=="applied":
		_check(result.events.size()==1 and int(after.revision)==int(before.revision)+1,label+" commits one event/revision")
		last_accepted_command = command.duplicate(true)
		for raw: Dictionary in result.events:
			var event: Dictionary = _wire(raw)
			_check(not event_ids.has(event.id),label+" has a new event identity")
			event_ids[event.id] = true
			journal.append(event)
			var replayed := replica.replay_event(event)
			_check(replayed.ok and replayed.code=="applied",label+" replays into independent state")
			if journal.size()%19==0:
				var repeated := replica.replay_event(_wire(event))
				_check(repeated.ok and repeated.code=="already_applied" and repeated.events.is_empty(),"Repeated delivery does not republish a committed event")
	else:
		_check(before==after,label+" rejection/retry leaves every field unchanged")
		_check(result.get("events",[]).is_empty(),label+" emits no duplicate/failed event")
	_check(_totals(after)==initial_totals,label+" conserves quantity, mass and complete lot identity")
	_check(after==replica.to_dict(),label+" authority and event replica converge")
	trace.append({"command":_wire(command),"expected":_response_signature(result),"after_hash":_hash(after)})
	return result


func _checkpoint(label: String) -> void:
	var before := state.to_dict()
	var source_path := output_directory.path_join("checkpoint-"+label+"-authority.json")
	var replica_path := output_directory.path_join("checkpoint-"+label+"-replica.json")
	_check(REPOSITORY.save(source_path,state).ok,"Authority checkpoint saves: "+label)
	_check(REPOSITORY.save(replica_path,replica).ok,"Replica checkpoint saves: "+label)
	var loaded := REPOSITORY.load_state(source_path,WORLD,catalog)
	var loaded_replica := REPOSITORY.load_state(replica_path,WORLD,catalog)
	_check(loaded.ok and loaded_replica.ok,"Both checkpoint files validate: "+label)
	if not loaded.ok or not loaded_replica.ok: return
	state = loaded.state
	replica = loaded_replica.state
	_check(before==state.to_dict() and before==replica.to_dict(),"Save/reload preserves all stock, pending work and receipts: "+label)
	_check(VESSELS.validate_snapshot(state.to_dict()).ok,"Checkpoint retains physically valid ship contents: "+label)
	checkpoints.append({"label":label,"revision":state.revision(),"state_hash":_hash(before),
		"authority_file":source_path.get_file(),"replica_file":replica_path.get_file()})


func _repeat_saved_trace(path: String) -> void:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(document is Dictionary,"Exported command trace is readable JSON")
	if not document is Dictionary: return
	var repeated := STATE.from_dict(document.initial_snapshot,document.world,document.catalog)
	_check(repeated.validation_errors.is_empty(),"Trace contains a complete valid starting fixture")
	var repeated_events: Array = []
	for entry: Dictionary in document.commands:
		var result := repeated.apply(entry.command)
		_check(_wire(_response_signature(result))==entry.expected,"Exact intent trace repeats response: "+str(entry.command.command_id))
		_check(_hash(repeated.to_dict())==entry.after_hash,"Exact intent trace repeats committed state: "+str(entry.command.command_id))
		repeated_events.append_array(result.get("events",[]))
		if not failures.is_empty(): return
	_check(_hash(repeated.to_dict())==str(document.final_state_hash),"Repeated trace finishes at the same complete state hash")
	_check(_wire(repeated_events)==document.events,"Repeated trace emits the same ordered event journal")
	var reconstructed := STATE.from_dict(document.initial_snapshot,document.world,document.catalog)
	for event: Dictionary in document.events:
		_check(reconstructed.replay_event(event).ok,"Saved journal reconstructs independently of commands")
	_check(_hash(reconstructed.to_dict())==str(document.final_state_hash),"Saved event-only reconstruction converges to the same final state")


func _check_hold_projection() -> void:
	for vessel in state.to_dict().vessels:
		if not str(vessel.id).begins_with("bulk"): continue
		var plan := VESSELS.bulk_hold_plan(vessel,vessel.lots)
		_check(plan.ok,"Loaded cargo fits real installed bulk compartments")
		if not plan.ok: continue
		var kilograms := 0.0
		for hold: Dictionary in plan.hold_states:
			kilograms += float(hold.filled_tonnes_t)*1000
			if float(hold.filled_tonnes_t)>0:
				_check(hold.commodity_id=="iron_ore" and hold.consignment_id=="ore-contract-7","Installed hold preserves commodity and consignment identity")
		var expected_kg := 0.0
		for lot in vessel.lots: expected_kg += float(lot.quantity)*float(lot.unit_mass_kg)
		_check(absf(kilograms-expected_kg)<.000001,"Installed holds reconstruct every manifest kilogram")


func _totals(snapshot: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for collection in ["stores","vessels"]:
		for holder in snapshot.get(collection,[]):
			for lot in holder.get("lots",[]):
				var metadata: Dictionary = lot.duplicate(true)
				metadata.erase("quantity")
				var identity := str(lot.id)+":"+_hash(metadata)
				if not totals.has(identity): totals[identity]={"lot_id":lot.id,"identity":metadata,"quantity":0.0,"mass_kg":0.0}
				totals[identity].quantity += float(lot.quantity)
				totals[identity].mass_kg += float(lot.quantity)*float(lot.unit_mass_kg)
	return totals


static func _response_signature(result: Dictionary) -> Dictionary:
	var signature: Dictionary = {}
	for key in ["ok","code","revision","applied_revision","replayed","result","details","account_changes"]:
		if result.has(key): signature[key]=result[key]
	signature.event_ids=[]
	for event in result.get("events",[]): signature.event_ids.append(event.id)
	return signature


static func _wire(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value,"",true,true))


static func _hash(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()


static func _find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if row.id==id: return row
	return {}


static func _owner(vessel: String) -> String:
	return "company-"+vessel


static func _request(store: String, vessel: String, lot: String, quantity: float, reservation := "") -> Dictionary:
	var result := {"store_id":store,"vessel_id":vessel,"lot_id":lot,"quantity":quantity}
	if not reservation.is_empty(): result.reservation_id=reservation
	return result


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	_check(file!=null,"Evidence file opens: "+path.get_file())
	if file!=null: file.store_string(JSON.stringify(value,"\t",true,true))


static func _placement(id: String, asset: String, x: float, z: float, attributes: Dictionary={}) -> Dictionary:
	return {"id":id,"asset_id":asset,"position_m":[x,0,z],"yaw_degrees":0,"attributes":attributes}


static func _catalog() -> Dictionary:
	return {
		"quay":{"footprint_m":[100,40],"kind":"platform","berth_edge":true,"placement_layer":"platform","placement_kind":"platform"},
		"bollard":{"footprint_m":[1,1],"kind":"bollard","mooring":true,"placement_layer":"equipment","requires_support":true},
		"container_crane":{"footprint_m":[4,4],"kind":"crane","placement_layer":"equipment","requires_support":true,
			"reach_max_m":55,"reach_min_m":3,"crane_offset_m":[0,0],"cargo_types":["container"]},
		"bulk_crane":{"footprint_m":[4,4],"kind":"crane","placement_layer":"equipment","requires_support":true,
			"reach_max_m":55,"reach_min_m":3,"crane_offset_m":[0,0],"cargo_types":["bulk"]},
		"yard":{"footprint_m":[20,14],"placement_layer":"equipment","requires_support":true}}


static func _fixture() -> Dictionary:
	var vessels: Array = []
	for id in ["box-a","box-b"]:
		vessels.append(VESSELS.from_prebuilt("28_10_m",id,_owner(id),"Visiting container ship",48000))
	for id in ["bulk-a","bulk-b"]:
		vessels.append(VESSELS.from_prebuilt("coastal_coaster",id,_owner(id),"Visiting bulk ship"))
	return {"schema_version":1,"id":"port-simulation","name":"Finite Cargo Session","owner_company_id":"company-port",
		"world":WORLD.duplicate(true),"origin_m":[1000,.5,-2000],"deck_height_above_sea_m":2,
		"plots":[{"id":"plot-simulation","rect_m":[-100,-100,200,200],"owner_company_id":"company-port"}],
		"placements":[_placement("quay","quay",0,0),_placement("west","bollard",-40,-19),
			_placement("middle","bollard",0,-19),_placement("east","bollard",40,-19),
			_placement("container-crane","container_crane",-6,-10,{"store_ids":["box-yard"]}),
			_placement("bulk-crane","bulk_crane",6,-10,{"store_ids":["bulk-yard"]}),
			_placement("box-pad","yard",-20,6),_placement("bulk-pad","yard",20,6)],
		"water_regions":[{"rect_m":[-100,-160,200,140],"depth_m":8}],
		"stores":[{"id":"box-yard","placement_id":"box-pad","capacity_kg":20000,"capacity_units":4,
			"accepted_handling_modes":["container"],"accepted_container_types":["20ft"],
			"accepted_commodities":["machine_parts"],"public_loading":true,"public_unloading":true,
			"lots":[{"id":"parts-shipment","commodity_id":"machine_parts","quantity":3,"unit_mass_kg":4800,
				"attributes":{"container_type":"20ft","whole_units":true,"slots_per_unit":1,"paint_variant":4,
					"consignment_id":"parts-contract-11","destination_port_id":"shipyard-north","value_nok":32000,
					"custom":{"sealed":true,"batch":"A-17","labels":["glass","keep dry"]}}}]},
			{"id":"bulk-yard","placement_id":"bulk-pad","capacity_kg":200000,"accepted_handling_modes":["bulk"],
				"accepted_commodities":["iron_ore"],"public_loading":true,"public_unloading":true,
				"lots":[{"id":"ore-shipment","commodity_id":"iron_ore","quantity":150000,"unit_mass_kg":1,
					"attributes":{"slots_per_unit":0,"consignment_id":"ore-contract-7","quality":.875,
						"origin_port_id":"mine-west","value_nok_per_kg":1.5,"custom":{"grade":"B","wet":false}}}]}],
		"vessels":vessels,"reservations":[],"receipts":{},"revision":0}
