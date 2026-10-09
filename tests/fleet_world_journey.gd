extends Node3D
## Real generated world, NPC callbacks, authority, physical cargo and mooring.
## Only ownership, fishing catch and voyage teleport are test fixtures.
var world: Node3D
var camera: Camera3D
var player: CharacterBody3D
var ship: BoatBody
var current: Dictionary = {}
var report: Dictionary = {"schema": 1, "seed": 424242, "cases": [], "status": "running",
	"scope": {"authority":"local", "interaction":"NPC callbacks and panel buttons", "voyage":"teleported", "cargo_physics":"real", "vessel_motion":"frozen while testing cargo", "catch":"controlled 500 kg fixture"}}
var output := ""
var started := 0
var cycles := 2
var filter := ""
var speed := 8.0
var container_count := 0
var stage_label: Label
var checks_label: Label
var camera_subject: Node3D
var camera_equipment: Node3D
var stage := "Preparing world"
var stage_started := 0
var observed_job: QuayEquipmentJob

func _process(_delta: float) -> void:
	if is_instance_valid(camera) and is_instance_valid(camera_subject):
		var target := camera_subject.global_position + Vector3(0,3,0)
		var reach := 45.0
		if is_instance_valid(camera_equipment):
			var other := camera_equipment.global_position
			reach = maxf(75.0,target.distance_to(other)*.9)
			target = (target+other)*.5 + Vector3(0,15,0)
		var direction := Vector3(1,0,1).normalized()
		if is_instance_valid(ship) and ship.get_moored_berth() is QuayBerthSlot:
			var berth := ship.get_moored_berth() as QuayBerthSlot
			direction = (berth.global_basis*berth.water_dir_local).normalized()
		camera.global_position = target + direction*reach + Vector3(0,reach*.7,0)
		camera.look_at(target)
		camera.make_current()
	if is_instance_valid(stage_label):
		var progress: String = ""
		if is_instance_valid(observed_job) and observed_job.has_method("progress_label"):
			progress = str(observed_job.call("progress_label"))
		stage_label.text = "FLEET JOURNEY TEST  |  %s\n%s\n%s  |  %.1f s  |  %s" % [str(current.get("name","World boot")), stage, str(current.get("status","running")).to_upper(), (Time.get_ticks_msec()-stage_started)/1000.0, progress]
		stage_label.modulate = Color("ff8a7a") if current.get("status", "") == "failed" else Color("bfe6e5")

func set_stage(value: String) -> void:
	stage = value
	stage_started = Time.get_ticks_msec()
	current["stage"] = value
	write_report()

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Fleet journeys require --shipyard-playtest; refusing captain save access")
		get_tree().quit(2)
		return
	call_deferred("run")

func check(ok: bool, label: String, details: Dictionary = {}) -> bool:
	current.get_or_add("checks", []).append({"ok": ok, "check": label, "details": details, "elapsed_s": (Time.get_ticks_msec()-started)/1000.0})
	print("FLEET ", current.get("id", "boot"), " ", "PASS " if ok else "FAIL ", label, " ", details)
	if not ok: current["status"] = "failed"
	if is_instance_valid(checks_label):
		var lines := PackedStringArray()
		var checks: Array = current.get("checks",[])
		for item in checks.slice(maxi(0,checks.size()-7)):
			lines.append(("PASS  " if item.ok else "FAIL  ") + str(item.check))
		checks_label.text = "\n".join(lines)
	write_report()
	return ok

func write_report() -> void:
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))

func wait_until(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if is_instance_valid(ship):
		camera.global_position = ship.global_position + Vector3(45,35,45)
		camera.look_at(ship.global_position + Vector3(0,3,0))
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(str(current.id)+"-"+label+".png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err == OK: current.get_or_add("captures", []).append(path)
	write_report()

func run() -> void:
	started = Time.get_ticks_msec()
	output = "C:/Users/noahs/Pictures/machinescreenshots/fleet-journeys-" + str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var ui := CanvasLayer.new()
	ui.layer = 100
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	panel.custom_minimum_size = Vector2(610,230)
	ui.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	stage_label = Label.new()
	stage_label.add_theme_font_size_override("font_size",20)
	column.add_child(stage_label)
	checks_label = Label.new()
	column.add_child(checks_label)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vessel="): filter = arg.trim_prefix("--vessel=")
		if arg.begins_with("--cycles="): cycles = maxi(1, int(arg.trim_prefix("--cycles=")))
		if arg.begins_with("--seed="): report.seed = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--speed="): speed = clampf(float(arg.trim_prefix("--speed=")),1.0,16.0)
		if arg.begins_with("--containers="): container_count = maxi(0, int(arg.trim_prefix("--containers=")))
	if container_count > 0:
		report.scope["container_booking"] = "Generated route with controlled %d-unit consignment; normal acceptance and physical handling" % container_count
	# Accelerate simulated time while retaining the normal physical timestep.
	Engine.physics_ticks_per_second = int(60*speed)
	Engine.max_physics_steps_per_frame = int(8*speed)
	Engine.time_scale = speed
	report["speed"] = speed
	# Test-local authority uses the same event wiring as a normal local session.
	var backend := LocalWorldBackend.new()
	WorldGateway.add_child(backend)
	WorldGateway._backend = backend
	backend.session_started.connect(WorldGateway._on_session_started)
	backend.session_ended.connect(WorldGateway._on_session_ended)
	backend.event_received.connect(WorldGateway._on_world_event)
	backend.command_finished.connect(WorldGateway._on_command_finished)
	backend.projections_received.connect(WorldGateway._on_projections_received)
	backend.start_session("fleet-test", "Fleet Test", "")
	GameSettings.map_generation_seed = int(report.seed)
	GameSettings.map_layout_checksum = ""
	GameSettings.map_world_size_m = 40000
	PlayerSession.data.home_port_id = "port-home"
	PlayerSession.data.tutorial_seen["welcome"] = true
	world = preload("res://scenes/world.tscn").instantiate()
	var booted := [false]
	world.boot_finished.connect(func(): booted[0] = true)
	add_child(world)
	if not await wait_until(func(): return booted[0], 90):
		report.status = "boot_timeout"
		write_report()
		get_tree().quit(2)
		return
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	camera = Camera3D.new()
	camera.far = 12000
	add_child(camera)
	camera.make_current()
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.set_process(false)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5
	WeatherLighting.precipitation = 0
	WeatherLighting.sea_state = .1
	var entries := PrebuiltVesselCatalog.for_sale_entries()
	for entry in entries:
		if not filter.is_empty() and str(entry.prebuilt_id) != filter: continue
		current = {"id": entry.prebuilt_id, "name": entry.display, "status": "running", "checks": []}
		report.cases.append(current)
		await journey(entry)
		if current.status == "running": current.status = "passed"
		await capture("final")
		if is_instance_valid(ship):
			var mc := ship.find_child("MooringComponent", true, false) as MooringComponent
			if mc: cast_off(mc)
		PlayerVessel.despawn_all_ships(get_tree())
		ship = null
		FreightService.restore_contracts([])
		await get_tree().process_frame
	report.status = "passed" if not report.cases.is_empty() else "no_cases"
	for item in report.cases:
		if item.status != "passed": report.status = "failed"
	report["elapsed_s"] = (Time.get_ticks_msec()-started)/1000.0
	write_report()
	print("FLEET REPORT ", output.path_join("report.json"), " ", report.status)
	get_tree().quit(0 if report.status == "passed" else 1)

func load_port(id: String) -> PortPlot:
	set_stage("Streaming port " + id)
	camera_subject = null
	camera_equipment = null
	var p := PortCatalog.get_port_position(id)
	player.global_position = p + Vector3(0,5,0)
	camera.global_position = p + Vector3(0,40,-100)
	camera.look_at(p)
	var found := await wait_until(func():
		var h := HarbourRegistry.controller(id)
		return h != null and not h.berths().is_empty(), 30)
	if not found: return null
	for node in world.get_children():
		if node is PortPlot and node.port_id == id:
			for i in 3: await get_tree().process_frame
			return node
	return null

func record_for(entry: Dictionary) -> Dictionary:
	return VesselSpawn.normalize_record({"uid": "journey-"+str(entry.prebuilt_id), "name":entry.display,
		"hull_id":entry.hull_id, "brick_layout":entry.prebuilt_layout.duplicate(true),
		"shaft_power_kw":entry.get("shaft_power_kw",1.0)})

func npc_of(plot: Node, script: Script) -> Node:
	for node in plot.find_children("*", "", true, false):
		if node.get_script() == script: return node
	return null

func journey(entry: Dictionary) -> void:
	var record := record_for(entry)
	var families := HarbourDeploy.terminal_families_for_record(record)
	var fishing := families.has("fishing")
	var origin: PortPlot
	var candidates := PortCatalog.get_port_ids()
	# Use the real catalog. Do not manufacture a convenient quay or cargo offer.
	for id in candidates:
		var info := PortCatalog.get_port_info(id)
		if fishing and not (info.get("features",[]) as Array).has("Fish Landing"): continue
		if not fishing:
			var offers := FreightService._generated_offers(id, 0)
			var matching := false
			for offer in offers:
				if str(offer.handling_mode) == "bulk" and families.has("bulk_ore"): matching = true
				if str(offer.handling_mode) in ["general","container"] and families.has("container"): matching = true
			if not matching: continue
		var plot := await load_port(id)
		if plot == null: continue
		var slots := HarbourDeploy.compatible_slots_for(plot.harbour_controller(), record, plot.port_data().max_ship_class)
		if slots.is_empty(): continue
		if fishing and slots[0].family != "fishing": continue
		if families.has("bulk_ore") and slots[0].family not in ["bulk_ore","bulk_grain"]: continue
		origin = plot
		break
	if not check(origin != null, "generated origin supports vessel", {"families": Array(families)}): return
	var master := npc_of(origin, preload("res://scripts/npc/harbour_master_npc.gd")) as HarbourMasterNpc
	if not check(master != null, "harbourmaster exists"): return
	PlayerSession.data.set_active_vessel(record)
	master._on_interact()
	master._deploy_fleet_vessel(record)
	if not check(await wait_until(func(): return PlayerVessel.find_active_ship(get_tree()) != null, 10), "harbourmaster deploys ship"): return
	ship = PlayerVessel.find_active_ship(get_tree())
	camera_subject = ship
	set_stage("Checking harbourmaster deployment")
	ship.freeze = true
	master._dialogue.hide_panel()
	master.close_ui()
	# Dismiss the walk-up conversation through normal input before reviewing
	# the ship. Otherwise the service panel obscures every cargo capture.
	if GameMenu.is_modal_open():
		var close := InputEventAction.new()
		close.action = "ui_cancel"
		close.pressed = true
		Input.parse_input_event(close)
		await get_tree().process_frame
		close.pressed = false
		Input.parse_input_event(close)
	var mc := ship.find_child("MooringComponent", true, false) as MooringComponent
	if not check(mc != null, "mooring component exists"): return
	check(await wait_until(func(): return mc.bow_line_tied and mc.stern_line_tied, 5), "deployment ties both lines")
	var slot := ship.get_moored_berth() as QuayBerthSlot
	if not check(slot != null, "deployment assigns a berth"): return
	var local := slot.to_local(ship.global_position)
	check(local.dot(slot.water_dir_local) >= slot.face_offset_m + ship.get_half_beam_m(), "spawn clears quay face", {"position":str(ship.global_position),"port":origin.port_id,"berth":slot.berth_id,"family":slot.family})
	check(str(ship.get_meta("vessel_uid", "")) == str(record.uid), "spawn preserves vessel identity")
	var assignment: Dictionary = WorldGateway.projection("vessel_berth",HarbourController.ship_id_of(ship)).get("state",{})
	check(str(assignment.get("berth_id","")) == slot.berth_id, "authority agrees with physical spawn berth")
	var expected := slot.global_transform * slot.ship_dock_local(ship.get_half_beam_m())
	check(absf(ship.global_basis.z.normalized().dot(expected.basis.z.normalized())) > .99, "ship lies along quay")
	check(get_tree().get_nodes_in_group(PlayerVessel.GROUP).size() == 1, "one active vessel")
	await get_tree().physics_frame
	check_spawn_clearance()
	await capture("deployed")
	for trip in cycles:
		if fishing:
			if not await fish_trip(record, mc, trip): return
		else:
			if not await freight_trip(record, mc, trip): return

func cast_off(mc: MooringComponent) -> void:
	if mc.bow_line_tied: mc.toggle_line_from_post(mc._front_post)
	if mc.stern_line_tied: mc.toggle_line_from_post(mc._rear_post)

func arrive(record: Dictionary, mc: MooringComponent, id: String, family: String, commodity: String = "") -> PortPlot:
	set_stage("Casting off for " + id)
	cast_off(mc)
	if not check(not mc.is_moored, "cast off releases both lines"): return null
	# Retain normal scene ownership. ProximityLoader pins a port containing the
	# active ship; reparenting would spuriously run its teardown during a voyage.
	var plot := await load_port(id)
	if not check(plot != null, "destination streams in", {"port":id}): return null
	var slot: QuayBerthSlot
	for candidate in HarbourDeploy.compatible_slots_for(plot.harbour_controller(),record,plot.port_data().max_ship_class):
		if candidate.family != family and not (family == "container" and candidate.family == "general"): continue
		if not commodity.is_empty() and not candidate.commodities.has(commodity): continue
		if plot.harbour_controller().moored_ship(candidate.berth_id) == null: slot = candidate; break
	if not check(slot != null, "destination has compatible free berth", {"family":family,"commodity":commodity}): return null
	# Teleport only the voyage. Arrival must claim occupancy via actual rope actions.
	ship.dock_at_berth(slot)
	camera_subject = ship
	set_stage("Attaching destination mooring lines")
	var posts := slot.bollards()
	posts.sort_custom(func(a,b): return a.global_position.distance_squared_to(ship.global_position) < b.global_position.distance_squared_to(ship.global_position))
	for post in posts:
		if not mc.is_mooring_line_tied_from_post(post): mc.toggle_line_from_post(post)
		if mc.bow_line_tied and mc.stern_line_tied: break
	if not check(mc.bow_line_tied and mc.stern_line_tied, "destination bollards attach both lines", {"reason":mc.last_mooring_reject}): return null
	check(ship.get_harbour_port_id() == id and ship.get_moored_berth_id() == slot.berth_id, "arrival updates harbour occupancy")
	var assignment: Dictionary = WorldGateway.projection("vessel_berth",HarbourController.ship_id_of(ship)).get("state",{})
	check(str(assignment.get("port_id","")) == id and bool(assignment.get("bow_line",false)) and bool(assignment.get("stern_line",false)), "authority confirms destination and both ropes")
	return plot

func run_equipment(plot: PortPlot, mode: String) -> bool:
	# Each walk-up operator owns one crane. Visit the next serving operator
	# after its work envelope is exhausted, as a player on a long quay would.
	for batch in maxi(1, plot.harbour_controller().equipment_ids_on_berth(ship.get_moored_berth_id()).size()):
		if not await run_operator(plot, mode): return false
		if serving_operator(plot, ship.get_moored_berth_id(), mode) == null: return true
	return true

func run_operator(plot: PortPlot, mode: String) -> bool:
	set_stage("Finding " + mode + " operator")
	camera_subject = ship
	var berth_id := ship.get_moored_berth_id()
	# The real LOD loader can create detailed equipment after the port's berth
	# registry is ready. Move the observer to the operation and allow it to settle.
	await wait_until(func(): return serving_operator(plot,berth_id,mode) != null, 12)
	var npc := serving_operator(plot,berth_id,mode)
	if not check(npc != null, "NPC equipment can " + mode, {"port":plot.port_id,"berth":berth_id,"equipment":plot.harbour_controller().snapshot()}): return false
	var job := plot.harbour_controller().get_equipment(npc.equip_id)
	observed_job = job
	camera_subject = ship
	camera_equipment = job.get_parent() as Node3D
	set_stage("Cargo " + mode + " — waiting for physical transfer")
	var completed := [false]
	job.job_completed.connect(func(_ctx,_report): completed[0] = true, CONNECT_ONE_SHOT)
	var cycle_observer := func(_operation, count):
		var manifests: Array = []
		for movement in FreightService.active_contracts():
			manifests.append({"id": movement.id, "quantity": movement.quantity, "issued": movement.get("issued_quantity", 0), "loaded": movement.loaded_quantity, "delivered": movement.delivered_quantity})
		var transfer := {"mode": mode, "equipment": job.equipment_id(), "cycle": count, "manifests": manifests}
		current.get_or_add("transfers", []).append(transfer)
		write_report()
		print("FLEET transfer ", transfer)
	var operator: ProvisionCraneAutoOperator
	if job is ProvisionCraneEquipmentJob:
		operator = (job.get_parent() as ProvisionCrane).get_auto_operator()
		operator.cycle_completed.connect(cycle_observer)
	npc._on_interact()
	var button: Button = npc._panel._btn_load if mode == "load" else npc._panel._btn_unload
	if not check(not button.disabled, "operator enables " + mode): npc._on_ui_cancel(); return false
	button.pressed.emit()
	npc._on_ui_cancel()
	await capture(mode+"-started-"+str(current.get("checks",[]).size()))
	var simulation_budget := 180.0
	if job is ProvisionCraneEquipmentJob:
		var units := 0.0
		for movement in FreightService.active_contracts():
			units += float(movement.quantity) - float(movement.get("loaded_quantity" if mode == "load" else "delivered_quantity", 0.0))
		simulation_budget = maxf(simulation_budget,60.0+60.0*units)
	if job is BulkCraneEquipmentJob:
		var tonnes := ship.cargo_mass / 1000.0
		if mode == "load":
			for movement in FreightService.active_contracts():
				tonnes += maxf(0.0,float(movement.quantity)-float(movement.loaded_quantity))
		var grab_t := (job.get_parent() as BulkCrane).bucket_capacity_tonnes_t()
		simulation_budget = maxf(simulation_budget,60.0+60.0*ceilf(tonnes/grab_t))
	var done := await wait_until(func(): return completed[0] or not job.is_job_active(), maxf(10.0,simulation_budget/speed))
	var ok := check(done and completed[0] and not job.is_job_active(), "equipment completes " + mode, {"status":Array(job.status_lines()),"equipment":job.equipment_id(),"failure":job.last_failure if job is BulkCraneEquipmentJob or job is ProvisionCraneEquipmentJob else ""})
	if not ok: plot.harbour_controller().stop_equipment(job.equipment_id())
	if operator != null: operator.cycle_completed.disconnect(cycle_observer)
	observed_job = null
	return ok

func serving_operator(plot: PortPlot, berth_id: String, mode: String) -> CraneOperatorNpc:
	var npc: CraneOperatorNpc
	for node in plot.find_children("*", "", true, false):
		if node is CraneOperatorNpc and node.berth_id == berth_id:
			var job := plot.harbour_controller().get_equipment(node.equip_id)
			if job != null and job.can_serve(ship, mode): npc = node; break
	return npc

func freight_trip(record: Dictionary, mc: MooringComponent, trip: int) -> bool:
	var plot := await load_port(ship.get_harbour_port_id())
	camera_subject = ship
	set_stage("Trip %d / %d — booking freight" % [trip+1,cycles])
	var agent := npc_of(plot, preload("res://scripts/npc/cargo_agent_npc.gd")) as CargoAgentNpc
	if not check(agent != null, "cargo agent exists"): return false
	var offers := FreightService.eligible_offers_at(plot.port_id, ship)
	if not check(not offers.is_empty(), "cargo agent offers compatible freight", {"trip":trip}): return false
	var offer := offers[0].duplicate(true)
	if container_count > 0 and str(offer.handling_mode) in ["general", "container"]:
		offer["pay_marks"] = int(round(float(offer.pay_marks) * container_count / float(offer.quantity)))
		offer["quantity"] = float(container_count)
		offer["id"] += ":capacity-fixture"
	var marks := PlayerSession.data.marks
	agent._on_interact()
	agent._accept(offer)
	agent._on_ui_cancel()
	if not check(not FreightService.active_contracts().is_empty(), "cargo agent accepts movement", {"offer":offer}): return false
	for i in 5: await get_tree().process_frame
	if not await run_equipment(plot,"load"): return false
	var contract := FreightService.active_contracts()[0]
	if not check(float(contract.loaded_quantity) >= float(contract.quantity), "physical loading updates manifest", {"manifest":contract,"cargo_mass":ship.cargo_mass}): return false
	var units: Array = []
	var bulk_lots: Array[BulkCargoLot] = []
	if str(offer.handling_mode) == "bulk":
		var tonnes := 0.0
		for hold in ship.get_bulk_holds():
			if hold.state.is_empty(): continue
			var restored := BulkHoldState.from_dict(hold.state.to_dict())
			check(restored.consignment_id == str(contract.consignment.consignment_id), "hold preserves shipment through serialization")
			var lot := BulkCargoLot.create(restored.commodity_id, restored.filled_tonnes_t, restored.consignment_id)
			bulk_lots.append(lot)
			tonnes += lot.tonnes_t
			check(not FreightService.record_bulk_delivered(lot,plot.port_id,ship), "origin rejects bulk delivery")
		check(is_equal_approx(tonnes,float(offer.quantity)), "physical bulk tonnes equal booking")
	for pad in ship.get_cargo_pads(): units.append_array(pad.get_containers())
	if str(offer.handling_mode) in ["general","container"]:
		check(units.size() == int(offer.quantity), "loaded container count matches booking")
		for unit in units:
			check(unit.freight_contract_id == str(offer.id), "container retains contract identity")
			check(not FreightService.can_deliver_unit(unit,plot.port_id,ship), "origin cannot settle destination cargo")
	await capture("loaded-"+str(trip))
	var family := "bulk_ore" if offer.handling_mode == "bulk" else "container"
	var dest := await arrive(record, mc, str(offer.destination_port_id), family, str(offer.commodity_id))
	if dest == null: return false
	if not await run_equipment(dest,"unload"): return false
	if not check(FreightService.active_contracts().is_empty(), "unloading completes manifest"): return false
	check(PlayerSession.data.marks == marks + int(offer.pay_marks), "exact freight payment once")
	check(ship.cargo_mass < .1, "delivery empties vessel cargo mass")
	for unit in units:
		check(not FreightService.record_unit_delivered(unit,dest.port_id,ship), "duplicate delivery rejected")
	for lot in bulk_lots:
		check(not FreightService.record_bulk_delivered(lot,dest.port_id,ship), "duplicate bulk delivery rejected")
	check(PlayerSession.data.marks == marks + int(offer.pay_marks), "duplicate delivery cannot pay twice")
	await capture("delivered-"+str(trip))
	if offer.handling_mode == "bulk" and trip + 1 < cycles:
		# Ore receivers need not export ore. Return empty to the real supplier.
		if await arrive(record,mc,str(offer.origin_port_id),"bulk_ore",str(offer.commodity_id)) == null: return false
	return true

func fish_trip(record: Dictionary, mc: MooringComponent, trip: int) -> bool:
	var holds := ship.get_catch_holds()
	if not check(not holds.is_empty(), "fishing ship has catch hold"): return false
	var origin := ship.get_harbour_port_id()
	cast_off(mc)
	# Controlled catch fixture; catching fish at sea is a separate test domain.
	holds[0].accept_lot(CatchLot.create({"lot_id":"journey-catch-"+str(trip),"species_id":"cod","mass_kg":500.0,"caught_game_hours":WorldClock.get_game_hours_elapsed()}))
	check(holds[0].get_state().total_mass_kg() > 499, "catch fixture enters hold")
	var destination := ""
	for id in PortCatalog.get_port_ids():
		if id != origin and (PortCatalog.get_port_info(id).get("features",[]) as Array).has("Fish Landing"):
			destination = id; break
	if not check(not destination.is_empty(), "another fishing destination exists"): return false
	var dest := await arrive(record,mc,destination,"fishing")
	if dest == null: return false
	var marks := PlayerSession.data.marks
	if not await run_equipment(dest,"unload"): return false
	check(holds[0].get_state().is_empty(), "landing empties catch hold")
	check(PlayerSession.data.marks > marks, "fish landing pays captain")
	await capture("landed-"+str(trip))
	return true


func check_spawn_clearance() -> void:
	# Probe the hull's middle at deck level, excluding the vessel's own fittings.
	# A berth-face distance alone cannot detect an adjacent pad crossing the hull.
	var shape := BoxShape3D.new()
	shape.size = Vector3(ship.beam_m * .8, 1.0, ship.length_m * .75)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = ship.global_transform * Transform3D(Basis.IDENTITY,Vector3(0,ship.depth_m-.5,0))
	query.collision_mask = 1
	var excluded: Array[RID] = [ship.get_rid()]
	for node in ship.find_children("*","CollisionObject3D",true,false): excluded.append(node.get_rid())
	query.exclude = excluded
	var obstructions: Array = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query,32):
		var collider := hit.collider as Node
		if collider != null: obstructions.append(str(collider.get_path()))
	if not obstructions.is_empty():
		var plot := ship.get_parent() as PortPlot
		current["obstructed_port_plan"] = plot._layout_graph.initial_attributes.get("berth_plan",{})
	check(obstructions.is_empty(), "hull clears neighbouring port collisions", {"obstructions":obstructions})
