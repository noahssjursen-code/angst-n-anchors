extends "res://scripts/ship/rod_fishing_showcase.gd"

var checks := 0
var failures: Array[String] = []
var captain_client: MpVirtualClient
var observer: MpVirtualClient

func _ready() -> void:
	super._ready()
	call_deferred("run_network_test")

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("MP FISHING ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func open_client(label: String, primary: bool) -> MpVirtualClient:
	var client := MpVirtualClient.new()
	client.setup(label,"http://127.0.0.1:8080","127.0.0.1",7777)
	add_child(client)
	var login := await client.login_or_register("fish-%s@integration.local" % PlayerData.new_uuid(),"local-fishing-test-2026")
	assert(login.ok)
	var captain := await client.ensure_captain("Fishing Test")
	assert(captain.ok)
	client.gateway = WorldGateway if primary else preload("res://scripts/network/world_gateway.gd").new()
	if not primary: client.add_child(client.gateway)
	client.gateway.command_completed.connect(func(id: String, result: Dictionary): client.command_results[id] = result)
	var backend := RemoteWorldBackend.new()
	backend.configure(client.base_url)
	client.gateway.use_backend(backend,true)
	backend.start_session(client.captain_id(),label,"mp-fishing-test",client.account_token)
	var deadline := Time.get_ticks_msec()+15000
	while not client.gateway.is_ready() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	assert(client.gateway.is_ready())
	return client

func wait_lots(hold: CatchHoldComponent, count: int) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	while hold.state.lots.size()!=count and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	return hold.state.lots.size()==count

func run_network_test() -> void:
	captain_client = await open_client("captain_client",true)
	observer = await open_client("observer",false)
	var purchase := await captain_client._http(HTTPClient.METHOD_POST,"/v1/vessels/purchase",{"captain_id":captain_client.captain_id(),"stock_id":"fishing_hook_line","vessel_name":"Fishing Integration","request_id":PlayerData.new_uuid(),"expected_price_nok":3200},"account")
	assert(purchase.ok, str(purchase))
	var rows := await captain_client._http(HTTPClient.METHOD_GET,"/v1/vessels?captain_id="+captain_client.captain_id(),null,"account")
	var record := VesselSync._merge_server_row(PlayerData.new(),rows.payload[0])
	PlayerSession.data = PlayerData.new()
	PlayerSession.data.captain_id = captain_client.captain_id()
	PlayerSession.data.owned_vessels.assign([record])
	PlayerSession.data.active_vessel = record
	LocalPlayerView._session = PlayerSession
	VesselSpawn.apply_identity(boat,record)
	WorldGateway.fishing_catches = FishingCatchReplication.new()
	WorldGateway.add_child(WorldGateway.fishing_catches)
	WorldGateway.fishing_catches.setup(WorldGateway)
	var scope := "vessel:"+str(record.server_vessel_id)
	assert((await captain_client.ensure_interests([scope])).ok)
	assert((await observer.ensure_interests([scope])).ok)
	player.global_position=station.authored_station.global_position+Vector3(-1.1,.1,0)
	for i in 12: await get_tree().physics_frame
	aim_at(station._interaction.global_position)
	check(station.can_interact(),"Owned MP boat equipment is reachable with real raycast")
	press_f()
	check(station.working and is_instance_valid(station._carried),"F picks up rod on deck")
	check(LocalPlayerView.get_voyage_snapshot().get("fishing",{}).get("working",false),"Multiplayer fishing HUD receives live state")
	station.session.drop(35,600)
	Input.action_press("fishing_lower")
	for i in 20: await get_tree().physics_frame
	Input.action_release("fishing_lower")
	var lowered := station.session.depth_m
	check(lowered > 0,"MP physics tick pays out fishing line")
	Input.action_press("fishing_reel")
	for i in 10: await get_tree().physics_frame
	Input.action_release("fishing_reel")
	check(station.session.depth_m < lowered,"MP physics tick reels line back in")
	station.session.recover()
	var hold := boat.get_catch_holds()[0]
	var fish := {"species_id":"cod","mass_kg":2.0,"length_cm":60.0,"specimen":true,"school_id":school.id,"fish_id":"integration-cod"}
	station._store_catch(fish)
	check(hold.state.lots.is_empty(),"No speculative local fish before server confirmation")
	check(await wait_lots(hold,1),"Server-confirmed rod catch fills authored crate: "+station.session.message)
	# Exercise the six individual store calls made by the harpe's batch result.
	for i in 6:
		fish.fish_id="harpe-%d"%i
		station._store_catch(fish)
	check(await wait_lots(hold,7),"Six-hook batch survives queued server commands")
	var id := str(record.server_vessel_id)+"/"+hold.hold_id
	observer.gateway.query_projections("fishing_hold",id)
	var deadline := Time.get_ticks_msec()+10000
	while observer.gateway.projection("fishing_hold",id).get("state",{}).get("lots",[]).size()!=7 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(observer.gateway.projection("fishing_hold",id).get("state",{}).get("lots",[]).size()==7,"Independent client fetches all seven specimens")
	var body := {"vessel_id":record.server_vessel_id,"hold_id":hold.hold_id,"lot":hold.state.lots[0].to_dict()}
	var replay := await captain_client.await_command("fishing.catch.store",body)
	check(replay.get("ok",false) and replay.get("data",{}).get("hold",{}).get("lots",[]).size()==7,"Replayed specimen cannot duplicate catch")
	var foreign := await observer.await_command("fishing.catch.store",body)
	check(not foreign.get("ok",false),"Server rejects other captain writing this crate")
	station.session.recover()
	player.global_position=station.authored_station.global_position+Vector3(-1.1,.1,0)
	aim_at(station._interaction.global_position)
	press_f()
	check(not station.working,"F returns equipment to mount")
	var reachable:=false
	for i in 16:
		var a:=TAU*float(i)/16
		player.global_position=hold._inspect_area.global_position+Vector3(cos(a)*1.8,-.5,sin(a)*1.8)
		aim_at(hold._inspect_area.global_position)
		if hold.can_inspect(): reachable=true;break
	check(reachable,"MP catch crate can be inspected with real raycast")
	press_f()
	await get_tree().process_frame
	check(GameMenu._screen==GameMenu.Screen.CATCH and GameMenu._catch_library.data.items.size()==7,"F opens fish library with server specimens")
	GameMenu._set_screen(GameMenu.Screen.NONE)
	# A newly created component must hydrate even when its projection was cached.
	var replacement:=CatchHoldComponent.new()
	replacement.configure(hold.hold_id,600)
	boat.add_child(replacement)
	check(await wait_lots(replacement,7),"Reconstructed crate hydrates durable inventory")
	replacement.queue_free()
	await get_tree().process_frame
	var port_id:="landing-test-"+PlayerData.new_uuid()
	var vessel_id:=str(record.server_vessel_id)
	var before:=await captain_client._http(HTTPClient.METHOD_GET,"/v2/captains?id="+captain_client.captain_id(),null,"account")
	var balance_before:=int(before.payload.captain.marks)
	var quote:=FishingLandingService.quote([hold.state])
	check((await captain_client.await_command("vessel.berth.claim",{"vessel_id":vessel_id,"port_id":port_id,"candidates":[port_id+"/fish-berth"]})).get("ok",false),"Landing berth assigned")
	check((await captain_client.await_command("vessel.mooring.set",{"vessel_id":vessel_id,"port_id":port_id,"berth_id":port_id+"/fish-berth","bow_line":true,"stern_line":true})).get("ok",false),"Landing vessel moored")
	var operation:=PlayerData.new_uuid()
	check((await captain_client.await_command("port.operation.request",{"operation_id":operation,"vessel_id":vessel_id,"port_id":port_id,"berth_id":port_id+"/fish-berth","equipment_id":"fish-pump","mode":"unload"})).get("ok",false),"Server pump operation started")
	assert((await observer.ensure_interests([scope,"port:"+port_id])).ok)
	var pump:=FishLandingPump.new();add_child(pump);pump.global_position=boat.global_position
	var bank:=ShoreRswTankBank.new();add_child(bank);pump.bind_receiver(bank)
	var job:=FishLandingEquipmentJob.new();add_child(job);job.setup("fish-pump","equip_fish_landing_pump",port_id+"/fish-berth");job.bind_plant(pump,bank)
	check(job.start_job(boat,"unload","",{"operation_id":operation,"owner_actor_id":captain_client.captain_id()}),"Real pump starts on MP catch hold")
	var lot_ids:Array[String]=[]
	for lot in hold.state.lots:lot_ids.append(lot.lot_id)
	check(await wait_lots(hold,0),"Server landing clears seven caught fish")
	var receipt:=await observer.await_projection("port_fish_landing",operation)
	check(not receipt.is_empty(),"Observer receives port fish landing receipt")
	var emptied:=await observer.await_projection("fishing_hold",vessel_id+"/"+hold.hold_id,func(p):return p.get("state",{}).get("lots",[1]).is_empty())
	check(not emptied.is_empty(),"Observer sees empty ship crate")
	var after:=await captain_client._http(HTTPClient.METHOD_GET,"/v2/captains?id="+captain_client.captain_id(),null,"account")
	check(int(after.payload.captain.marks)==balance_before+int(quote.value_marks),"Database balance credited at server species prices")
	var retry:=await captain_client.await_command("fishing.catch.land",{"operation_id":operation,"vessel_id":vessel_id,"lot_ids":lot_ids})
	check(retry.get("ok",false),"Landing receipt survives retry with another request id")
	after=await captain_client._http(HTTPClient.METHOD_GET,"/v2/captains?id="+captain_client.captain_id(),null,"account")
	check(int(after.payload.captain.marks)==balance_before+int(quote.value_marks),"Retry does not double-pay")
	await captain_client.await_command("port.operation.stop",{"operation_id":operation})
	await captain_client.await_command("vessel.berth.release",{"vessel_id":vessel_id})
	print("MP FISHING ","PASS" if failures.is_empty() else "FAIL",": ",checks," checks")
	get_tree().quit(0 if failures.is_empty() else 1)
