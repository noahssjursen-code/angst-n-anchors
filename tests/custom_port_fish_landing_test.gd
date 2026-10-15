extends "res://tests/custom_port_transfer_test.gd"

const PLANT = preload("res://scripts/port/building/custom_port_fish_landing.gd")
var checks := 0
var plant: Node3D
var store_id := "store:fish-plant"
var event_count := 0
var paid_completions := 0
var phases: Array[String] = []
var caught_metadata: Dictionary = {}

func _fixture() -> Dictionary:
	var world := {"seed":73119,"generation_version":1,"checksum":"fish-landing-fixture"}
	var data := {"schema_version":1,"id":"fish-landing-review","name":"Fish landing review","owner_company_id":"company-visitor",
		"world":world,"origin_m":[0,.5,0],"deck_height_above_sea_m":2,
		"plots":[{"id":"plot-fish","owner_company_id":"company-visitor","rect_m":[-100,-100,200,200]}],
		"placements":[],"stores":[],"vessels":[],"water_regions":[{"rect_m":[-30,-50,100,100],"depth_m":12.0}]}
	for x in range(2,24,4):
		for z in range(2,20,4):
			data.placements.append(CustomPortCatalog.placement("deck-%d-%d"%[x,z],"foundation",Vector3(x,0,z)))
	for x in [2.0,22.0]:data.placements.append(CustomPortCatalog.placement("bollard-"+str(x),"quay_bollard",Vector3(x,0,.75)))
	var vessel := CustomPortVesselProjection.from_prebuilt("fishing_hook_line","fisher","company-visitor")
	vessel.lots=[{"id":"catch-cod","commodity_id":"fresh_groundfish","quantity":300.0,"unit_mass_kg":1.0,
		"attributes":{"species_id":"cod","caught_game_hours":3.5,"caught_position":[140,-360],"quality":.92,"price_multiplier":1.1,"ground_tier":"normal","slots_per_unit":0}},
		{"id":"caught-halibut","commodity_id":"fresh_groundfish","quantity":1,"unit_mass_kg":18.25,
		"attributes":{"specimen":true,"indivisible":true,"species_id":"halibut","length_cm":115.0,"size_grade":"Large","caught_game_hours":4.0,"caught_position":[160,-350],"quality":.87,"price_multiplier":1.2,"slots_per_unit":0}}]
	data.vessels.append(vessel)
	return data

func _run() -> void:
	var snapshot := _fixture()
	state=CustomPortState.from_dict(snapshot,snapshot.world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Isolated fish fixture is valid: "+str(state.validation_errors))
	if not state.validation_errors.is_empty():get_tree().quit(1);return
	var editor := CustomPortEditor.new()
	editor.configure(state,CustomPortCatalog.definitions(),"company-visitor")
	for yaw in [0,90,180,270]:
		var p:=editor.preview("fish_landing_plant",Vector3(-3,70,-7),yaw)
		_check(p.placement.position_m==[-4.0,0,-8.0] and p.snap_m==4.0,"Negative-coordinate equipment snap keeps 4m positioning at each quarter turn "+str(yaw))
	var placed := editor.place_asset("fish_landing_plant",Vector3(12,77,8))
	_check(placed.ok,"Place bundle on its fixed supported plane: "+str(placed.get("errors",[])))
	if not placed.ok:get_tree().quit(1);return
	var row:Dictionary=placed.snapshot.placements.back()
	store_id="store:"+str(row.id)
	_check(placed.snapshot.stores.size()==1 and placed.snapshot.stores[0].lots.is_empty() and float(placed.snapshot.stores[0].capacity_kg)==40000,"New plant creates one empty finite 40t store")
	port=CustomPortPresenter.new();add_child(port)
	transfer=Transfer.new();add_child(transfer);transfer.bind(port);transfer.set_process(false)
	transfer.presentation_failed.connect(func(reason:String):animation_errors.append(reason))
	transfer.phase_changed.connect(func(phase:String):phases.append(phase))
	transfer.present(state.to_dict(),state.derived_berths())
	plant=port.placement_nodes[str(row.id)]
	plant.pump.transfer_completed.connect(func(_report:Dictionary):paid_completions+=1)
	plant.bank.inventory_changed.connect(func(_data:Dictionary):event_count+=1)
	await get_tree().physics_frame
	_check(plant.pump._connection_marker.global_position.distance_to(port.to_global(Vector3(17.18,1.35,3.28)))<.002,"Authored suction socket matches the declared service origin")
	_check(plant.pump._receiver==null,"Presentation pump has no mutable receiving inventory")
	_check(plant.find_children("*","CollisionShape3D",true,false).size()==7,"Plant has equipment-shaped collision, without a solid plot blocker")
	var bounds:=_mesh_bounds(plant)
	_check(bounds.position.x>=-10 and bounds.end.x<=10 and bounds.position.z>=-8 and bounds.end.z<=8 and bounds.position.y>=-.001 and bounds.end.y<=5.35+.001,"All static machinery meshes stay inside the advertised20x16x5.35m footprint: "+str(bounds))
	var ghost:=CustomPortPresenter.asset_visual(CustomPortCatalog.definition("fish_landing_plant"),true,false)
	add_child(ghost)
	_check(ghost.find_children("*","CollisionShape3D",true,false).is_empty(),"Plant preview creates no hidden collision")
	var preview_mesh:MeshInstance3D=SurfaceMaterialLibrary.meshes(ghost)[0]
	_check(preview_mesh.material_override is StandardMaterial3D and preview_mesh.material_override.albedo_color.r>.9,"Invalid placement preview remains visibly red")
	ghost.queue_free()
	await _check_access()
	if native_capture:
		target=plant.global_position+Vector3(0,2,0)
		camera.position=target+Vector3(25,19,-24);camera.look_at(target)
		label.text="COMPACT FISH LANDING · 20 × 16 m\nExisting vacuum plant, refrigerated tanks and clear working aisle · empty 40 t store"
		await _capture("fish-plant-empty")
	var berth_id:=""
	for berth in state.derived_berths():
		if store_id in CustomPortBerths.services_for_vessel(berth,state.to_dict().vessels[0],"catch").store_ids:berth_id=str(berth.id);break
	_check(not berth_id.is_empty(),"The real fishing vessel has a pump-served berth")
	if berth_id.is_empty():get_tree().quit(1);return
	_apply("dock",{"vessel_id":"fisher","berth_id":berth_id})
	await get_tree().process_frame
	var ship:BoatBody=port.vessel_nodes.fisher
	_check(is_instance_valid(ship),"Docking instantiates actual fishing boat")
	var hold:CatchHoldComponent=ship.get_catch_holds()[0]
	var hold_plan:=CustomPortVesselProjection.catch_hold_plan(state.to_dict().vessels[0],state.to_dict().vessels[0].lots)
	_check(hold_plan.ok and hold_plan.hold_states[0].hold_id==hold.hold_id and hold_plan.allocations[0].hold_id==hold.hold_id,"Canonical catch allocation identity matches the actual installed tank")
	_check(is_equal_approx(hold.state.total_mass_kg(),318.25),"Actual tank reconstructs bulk catch and a whole specimen")
	caught_metadata=Transfer._find(state.to_dict().vessels[0].lots,"caught-halibut").attributes.duplicate(true)
	var before:=state.to_dict()
	var result:=_apply("unload_cargo",{"store_id":store_id,"vessel_id":"fisher","lot_id":"catch-cod","quantity":200})
	_check(transfer.is_busy(),"Committed catch unload starts the assigned actual pump")
	_check(result.result.crane_id==row.id and result.result.store_id==store_id,"Authority receipt assigns this plant and its fixed-pipe shore bank")
	var committed:=JSON.stringify(state.to_dict())
	_check(is_equal_approx(plant.bank.total_mass_kg(),200) and is_equal_approx(hold.state.total_mass_kg(),118.25),"Both inventories immediately represent committed data during visual playback")
	transfer._process(.5)
	var elapsed:float=plant.pump._elapsed
	transfer.present(state.to_dict(),state.derived_berths(),result.events)
	_check(plant.pump._elapsed==elapsed,"Duplicate receipt delivery does not restart a connected hose")
	var forged:Array=result.events.duplicate(true)
	forged[0].receipt.result.crane_id="unrelated-pump"
	_check(transfer.catch_transfer.capture(before,result.snapshot,forged).is_empty(),"Forged receipt assignment cannot start a visual transfer")
	await _finish_catch("unload",hold)
	_check(JSON.stringify(state.to_dict())==committed,"Pump playback never changes the authority snapshot")
	_check(phases.has("Pumping catch ashore"),"Unloading has an explicit ashore direction")
	_check(plant.bank._presented_mass_kg<0 and not plant.pump._hose_root.visible,"Completed unloading restores committed sight glasses and removes its hose")
	_apply("unload_cargo",{"store_id":store_id,"vessel_id":"fisher","lot_id":"caught-halibut","quantity":1})
	await _finish_catch("specimen",hold)
	var specimen:=_bank_lot("caught-halibut")
	_check(specimen.specimen and is_equal_approx(specimen.mass_kg,18.25) and specimen.species_id=="halibut" and specimen.quality==caught_metadata.quality and specimen.length_cm==caught_metadata.length_cm and specimen.size_grade==caught_metadata.size_grade,"Whole specimen identity, species, weight, size and quality survive landing")
	var reloaded:=CustomPortPresenter.new();add_child(reloaded)
	reloaded.simulate_vessels=false
	reloaded.load_record(state.to_dict(),state.derived_berths())
	var reloaded_plant:Node3D=reloaded.placement_nodes[str(row.id)]
	_check(reloaded_plant.bank.snapshot().inventory==plant.bank.snapshot().inventory,"Fresh snapshot reconstructs the identical shore catch library")
	reloaded.queue_free()
	await get_tree().process_frame
	_apply("reserve_cargo",{"store_id":store_id,"vessel_id":"fisher","lot_id":"catch-cod","quantity":125,"reservation_id":"return-cod"})
	_check(not transfer.is_busy(),"Reserving catch does not start the pump or withdraw inventory")
	_apply("load_cargo",{"reservation_id":"return-cod"})
	await _finish_catch("load",hold)
	_check(phases.has("Pumping catch aboard"),"Reverse transfer says aboard rather than showing an ashore label")
	_check(is_equal_approx(plant.bank.total_mass_kg(),93.25) and is_equal_approx(hold.state.total_mass_kg(),225),"Reverse transfer preserves total mass and projects both inventories")
	_apply("reserve_cargo",{"store_id":store_id,"vessel_id":"fisher","lot_id":"caught-halibut","quantity":1,"reservation_id":"return-specimen"})
	_apply("load_cargo",{"reservation_id":"return-specimen"})
	await _finish_catch("specimen-return",hold)
	var returned:Dictionary=Transfer._find(state.to_dict().vessels[0].lots,"caught-halibut")
	_check(returned.attributes==caught_metadata and returned.quantity==1,"Returning the indivisible fish preserves every saved custom attribute")
	_apply("unload_cargo",{"store_id":store_id,"vessel_id":"fisher","lot_id":"catch-cod","quantity":25})
	transfer._process(1.5)
	_check(plant.pump.is_projecting() and plant.pump._hose_root.visible,"Interruption reaches a visible hose connected to the actual boat")
	_apply("undock",{"vessel_id":"fisher"})
	_check(not transfer.is_busy() and not plant.pump._hose_root.visible and plant.bank._presented_mass_kg<0,"Departure cancels only playback and leaves no ghost hose or stale fill")
	_check(is_equal_approx(plant.bank.total_mass_kg(),100),"Departure retains already committed shore catch")
	_apply("dock",{"vessel_id":"fisher","berth_id":berth_id})
	# Gap snapshots reconstruct latest data without reenacting unseen transfers.
	var gap_before:=state.to_dict()
	sequence+=1
	var silent:=state.apply({"command_id":"gap-%d"%sequence,"kind":"unload_cargo","actor_company_id":"company-visitor","expected_revision":state.revision(),"payload":{"store_id":store_id,"vessel_id":"fisher","lot_id":"catch-cod","quantity":10}})
	_check(silent.ok,"Authority can commit catch while a subscriber is away")
	sequence+=1
	var latest:=state.apply({"command_id":"gap-%d"%sequence,"kind":"unload_cargo","actor_company_id":"company-visitor","expected_revision":state.revision(),"payload":{"store_id":store_id,"vessel_id":"fisher","lot_id":"catch-cod","quantity":10}})
	_check(latest.ok and transfer.catch_transfer.capture(gap_before,latest.snapshot,latest.events).is_empty(),"A revision gap does not invent historical hose operations")
	transfer.present(latest.snapshot,state.derived_berths(),latest.events)
	_check(not transfer.is_busy() and is_equal_approx(plant.bank.total_mass_kg(),120),"Gap snapshot updates latest tank contents without replay")
	var bank_before:Dictionary=plant.bank.snapshot()
	var overflowing:Dictionary=bank_before.inventory.duplicate(true)
	overflowing.lots[0].mass_kg=40001
	_check(not plant.bank.apply_projection(overflowing) and plant.bank.snapshot()==bank_before,"Bank refuses overflow without truncating or replacing committed contents")
	_check(event_count==0 and paid_completions==0,"Playback emits no production inventory or payment completion hooks")
	_check(animation_errors.is_empty(),"No projection failures: "+str(animation_errors))
	if native_capture:
		target=plant.global_position+Vector3(0,2,0);camera.position=target+Vector3(24,16,-23);camera.look_at(target)
		label.text="FISH LANDING COMPLETE · Finite shore stock\n120 kg cod saved ashore · individual halibut returned intact aboard · no sale or payment performed"
		await _capture("fish-landing-complete")
	await _settle_audio_before_exit()
	print("CUSTOM PORT FISH LANDING ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check_access() -> void:
	var space:=get_world_3d().direct_space_state
	var aisle_from:=plant.to_global(Vector3(3.2,1, -7))
	var aisle_to:=plant.to_global(Vector3(3.2,1,7))
	var ray:=PhysicsRayQueryParameters3D.create(aisle_from,aisle_to,1)
	_check(space.intersect_ray(ray).is_empty(),"Central 1.75m aisle has no hidden collision wall")
	var tank_ray:=PhysicsRayQueryParameters3D.create(plant.to_global(Vector3(-4,2,-7)),plant.to_global(Vector3(-4,2,7)),1)
	_check(not space.intersect_ray(tank_ray).is_empty(),"Physical tank blocks passage through its shell")
	# Headless DisplayServer cannot capture the mouse, and production movement
	# deliberately ignores input then. Exercise real walking in the native run.
	if DisplayServer.get_name()=="headless":return
	var walker:CharacterBody3D=preload("res://scenes/shared/player.tscn").instantiate()
	add_child(walker)
	walker.set_physics_process(false)
	walker.global_position=plant.to_global(Vector3(3.2,.05,6.8))
	walker.rotation.y=0
	var player_camera:Node=walker.get_node("PlayerCamera")
	player_camera.shift_look_yaw(-player_camera.get_look_yaw())
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for frame in 20:
		await get_tree().physics_frame
		walker._physics_process(1.0/60)
	Input.action_press("move_forward")
	for frame in 280:
		await get_tree().physics_frame
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		walker._physics_process(1.0/60)
		if plant.to_local(walker.global_position).z < -6.7: break
	Input.action_release("move_forward")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	print("FISH_AISLE_DIAGNOSTIC ",plant.to_local(walker.global_position)," grounded=",walker.is_on_floor())
	_check(plant.to_local(walker.global_position).z < -6.5 and walker.is_on_floor(),"Actual player walks the working aisle under the pipe without jumping")
	camera.make_current()
	walker.queue_free()
	await get_tree().process_frame
	if native_capture:
		target=plant.to_global(Vector3(1.8,1.7,0))
		camera.global_position=plant.to_global(Vector3(10,6,-10))
		camera.look_at(target)
		label.text="WORKING AISLE · Actual player traversed without jumping\nBrushed steel and painted machinery ·1.75m clear route · overhead transfer pipe"
		await _capture("fish-plant-working-aisle-close")

func _finish_catch(tag:String,hold:CatchHoldComponent)->void:
	var captured:=false
	var guard:=0
	while transfer.is_busy() and guard<500:
		transfer._process(.05)
		guard+=1
		if plant.pump.state_label()==FishLandingPump.STATE_PUMPING and not captured:
			captured=true
			_check(plant.pump._ship_connection_world().distance_to(hold.get_hose_drop_world())<.001,"Hose ends at the exact accepted catch compartment "+tag)
			if native_capture and tag in ["unload","load"]:
				target=plant.pump.focus_position()+Vector3(0,1,0)
				camera.position=target+Vector3(16,13,-22);camera.look_at(target)
				label.text="COMMITTED CATCH · "+("ABOARD" if tag=="load" else "ASHORE")+"\nExisting hose and separator · exact fish lot / installed tank assignment · authority remains unchanged"
				await _capture("fish-landing-"+tag+"-hose")
		if guard%30==0:await get_tree().process_frame
	_check(not transfer.is_busy(),"Catch pump finishes bounded playback "+tag)
	await get_tree().process_frame

func _bank_lot(id:String)->Dictionary:
	for lot in plant.bank.snapshot().inventory.lots:
		if lot.lot_id==id:return lot
	return {}

func _mesh_bounds(root:Node3D)->AABB:
	var bounds:=AABB()
	var first:=true
	for mesh in SurfaceMaterialLibrary.meshes(root):
		if mesh.mesh==null or not mesh.visible:continue
		var local:Transform3D=root.global_transform.affine_inverse()*mesh.global_transform
		var box:AABB=local*mesh.mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	return bounds

func _check(ok:bool,message:String)->void:
	checks+=1
	super._check(ok,message)
