extends Node3D

## Real local Docker HTTP/UDP integration, with two independent account/session
## identities and the production remote ship renderer. Never opens captain saves.
## Run: godot --headless --path . res://tests/mp_blueprint_flow_test.tscn -- --shipyard-playtest
## Creates isolated test accounts in the LOCAL development database only.
const VirtualClient = preload("res://scripts/network/testing/virtual_client.gd")
const Gateway = preload("res://scripts/network/world_gateway.gd")
const Drawing = preload("res://scripts/network/replication_drawing_service.gd")
const LOCAL_HTTP := "http://127.0.0.1:8080"
const ORIGIN := Vector3(35000, 0, 35000)
const REPORT := "res://.godot/tests/mp_cargo_manifest_report.json"
class MemorySession extends Node:
	var data := PlayerData.new()
	var save_calls := 0
	func save_now() -> void: save_calls += 1
var _clients: Array[MpVirtualClient] = []
var _checks: Array[Dictionary] = []
var _failed := false
var _drawing: Node3D
var _ship_entity := ""
var _started := 0
var _published: Dictionary = {}
var _captures: Array[String] = []
var _review_owner: ImportedDraftVessel
var _review_camera: Camera3D
var _credentials_path := ""

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Run with -- --shipyard-playtest; captain save isolation is required")
		get_tree().quit(2)
		return
	# This setter cannot persist anything while the isolation flag is active.
	ServerConfig.use_preset("local")
	ServerConfig.is_multiplayer_mode = true
	_credentials_path = "res://.godot/tests/blueprint-credentials-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	RemoteAccountCredentialStore.store_path_override = _credentials_path
	_started = Time.get_ticks_msec()
	call_deferred("_run")

func _check(ok: bool, label: String, detail: String = "") -> bool:
	_checks.append({"passed": ok, "check": label, "detail": detail})
	print("[MP CARGO] %s %s%s" % ["PASS" if ok else "FAIL", label, " — " + detail if not detail.is_empty() else ""])
	if not ok: _failed = true
	return ok

func _run() -> void:
	await _scenario()
	for service in [cargo_owner,cargo_observer]:
		if is_instance_valid(service):
			service.set_process(false)
			service.clear()
	if _drawing != null and is_instance_valid(_drawing): _drawing.queue_free()
	for client in _clients:
		client.close_session()
		await client.send_logout(1)
	RemoteAccountCredentialStore.clear_test_storage()
	RemoteAccountCredentialStore.store_path_override = ""
	ServerConfig.is_multiplayer_mode = false
	await get_tree().process_frame
	await get_tree().process_frame
	var report := {"server": LOCAL_HTTP, "godot": Engine.get_version_info().string,
		"passed": not _failed, "duration_ms": Time.get_ticks_msec() - _started,
		"checks": _checks, "published": _published, "captures": _captures,
		"limitations": ["Two isolated client stacks in one process; not two game windows", "Real NPC Load action and initial automatic crane movement exercised; later hook/landing stages driven explicitly"]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT.get_base_dir()))
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("MP CARGO FLOW %s: %d checks; report %s" % ["FAIL" if _failed else "PASS", _checks.size(), ProjectSettings.globalize_path(REPORT)])
	get_tree().quit(1 if _failed else 0)

func _scenario() -> void:
	if not _check(ServerConfig.get_http_base_url() == LOCAL_HTTP, "Only the local Docker endpoint is used"): return
	var suffix := Crypto.new().generate_random_bytes(6).hex_encode()
	for label in ["builder", "observer"]:
		var client: MpVirtualClient = VirtualClient.new()
		client.setup(label, LOCAL_HTTP, "127.0.0.1", 7777)
		add_child(client)
		_clients.append(client)
		var account := await client.login_or_register("blueprint-%s-%s@integration.local" % [label, suffix], "local-blueprint-tests-only-2026")
		if not _check(bool(account.ok), label + " authenticated independent account", str(account.get("message", ""))): return
		var captain := await client.ensure_captain("Blueprint " + label)
		if not _check(bool(captain.ok), label + " has its own captain", str(captain.get("message", ""))): return
		if not await _open_isolated_session(client): return
		if not _check(bool(client.udp_start().ok), label + " opened authenticated UDP socket"): return
	var owner := _clients[0]
	var observer := _clients[1]
	owner.set_avatar(ORIGIN)
	observer.set_avatar(ORIGIN + Vector3(12000, 0, 0))
	var layout := _custom_layout()
	if not _check(ImportedVesselLayout.valid(layout, str(layout.hull), true), "Custom authoring layout is valid and has a helm"): return
	var memory := MemorySession.new()
	memory.data.captain_id = owner.captain_id()
	add_child(memory)
	if not _check(RemoteAccountCredentialStore.set_session(LOCAL_HTTP, owner.account_token, owner.account), "VesselSync uses isolated test credentials"): return
	_check(memory.data.owned_vessels.is_empty(), "New captain ledger starts empty")
	var registered := await _push(memory, {"uid": "custom-" + suffix,
		"hull_id": layout.hull, "registration_id": "", "shaft_power_kw": 700,
		"name": "E2E Custom Harbour", "brick_layout": layout}, true)
	if not _check(not registered.is_empty(), "Production registration publishes custom ship from empty ledger"): return
	_check(memory.data.owned_vessels.size() == 1 and memory.save_calls == 1, "Accepted registration inserts and persists one ledger row")
	memory.save_calls = 0
	var row := await _fetch_owner(str(registered.server_vessel_id))
	if not _check(not row.is_empty(), "Registered vessel can be fetched independently"): return
	var response: Dictionary
	var vid := str(row.get("id", ""))
	var cid := str(row.get("construction_id", ""))
	if not _check(not vid.is_empty() and cid.length() == 64, "Vessel has durable ID and immutable construction hash"): return
	_published = {"vessel_id": vid, "original_construction_id": cid}
	var absent_row := await _fetch_owner("00000000-0000-0000-0000-000000000000")
	_check(absent_row.is_empty(), "Unpublished vessel fetch fails without local-draft fallback")
	response = await observer._http(HTTPClient.METHOD_GET, "/v2/constructions?id=" + cid, null, "")
	if not _http_ok(response, "Cold observer fetches an unknown immutable construction"): return
	var construction: Dictionary = response.payload
	if not _check(VesselSync.construction_matches(cid, construction), "Client and server construction/catalog contract agrees"): return
	_check((construction.cargo_slots as Array).size() == 2, "Capacity is derived as two supported container positions")
	_check(construction.layout.hull_colors == layout.hull_colors and construction.layout.engine_preset == layout.engine_preset, "Accepted blueprint retains custom paint and installed engine")
	var custom_found := false
	for part: Dictionary in construction.layout.parts:
		if part.get("instance_id") == "custom-starboard-vent": custom_found = part.position == [2.5, 3.6, 9.5]
	_check(custom_found, "Custom equipment placement survives server normalization")
	var fetched := await _fetch_owner(vid)
	if not _check(not fetched.is_empty() and fetched.brick_layout == construction.layout, "Owner deployment fetches accepted construction instead of local draft"): return
	fetched["uid"] = str(registered.uid)
	fetched["server_vessel_id"] = vid
	fetched["name"] = str(fetched.get("display_name", ""))
	PlayerSession.data.active_vessel = fetched.duplicate(true)
	LocalPlayerView._session = PlayerSession
	memory.data.upsert_owned_vessel(fetched)
	memory.data.set_active_vessel(fetched)
	var owner_boat := VesselSpawn.instantiate_from_record(fetched) as ImportedDraftVessel
	if not _check(owner_boat != null, "Production owner builder reconstructs fetched construction"): return
	owner_boat.freeze = true
	owner_boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(owner_boat)
	PlayerVessel.mark_player_ship(owner_boat)
	_verify_assembly(owner_boat, construction, "owner")
	_review_owner = owner_boat
	_review_owner.position = ORIGIN + Vector3(0, 0, 34)
	_ship_entity = "ship:" + (owner.captain_id() + "|" + suffix).sha256_text().substr(0, 32)
	owner.set_ship_entity(_ship_entity, str(layout.hull), ORIGIN, _meta(row))
	await get_tree().create_timer(1.2).timeout
	_check(not observer.has_seen_entity(_ship_entity), "Out-of-range observer receives no vessel")
	observer.set_avatar(ORIGIN + Vector3(50, 0, 0))
	var entity := await observer.await_snapshot_entity(_ship_entity)
	if not _check(not entity.is_empty(), "Moving into range discovers vessel via real UDP snapshots"): return
	_check(str(entity.meta).contains("vid=" + vid) and str(entity.meta).contains("cid=" + cid), "Discovery identifies authoritative vessel and exact construction version")
	# Request an impossible public build identity but change position so this
	# cannot pass by accidentally inspecting the previous cached snapshot.
	owner.set_ship_entity(_ship_entity, "hull_88x14", ORIGIN + Vector3(1, 0, 0), "vid=%s;lh=%s;cid=%s" % [vid, "0".repeat(64), "0".repeat(64)])
	var canonical := await observer.await_snapshot_entity(_ship_entity, 8, func(e: Dictionary) -> bool: return float(e.pos.x) > ORIGIN.x + 0.9)
	_check(not canonical.is_empty() and str(canonical.meta).contains("cid=" + cid) and str(canonical.type) == "ship_" + str(layout.hull), "Server canonicalizes forged build hash and hull from accepted vessel record")
	owner.set_ship_entity(_ship_entity, str(layout.hull), ORIGIN, _meta(row))
	var impostor_id := "ship:impostor-" + suffix
	observer.set_ship_entity(impostor_id, str(layout.hull), ORIGIN, _meta(row))
	await get_tree().create_timer(1.2).timeout
	_check(not owner.has_seen_entity(impostor_id), "Another captain cannot publish transforms for the owner's vessel")
	observer.drop_entity_silently(impostor_id)
	_drawing = Drawing.new()
	add_child(_drawing)
	var replica := await _render_discovery(observer, cid)
	if not _check(replica != null and replica.visible, "Production remote renderer downloads and assembles cold unseen ship"): return
	_verify_assembly(replica, construction, "observer")
	await _cargo_scenario(owner, observer, owner_boat, replica, vid)

func _http_ok(response: Dictionary, label: String) -> bool:
	return _check(bool(response.ok), label, "HTTP %d %s" % [int(response.status), str(response.get("message", ""))])

func _open_isolated_session(client: MpVirtualClient) -> bool:
	if client.gateway == null:
		client.gateway = WorldGateway if client.label == "builder" else Gateway.new()
		if client.gateway != WorldGateway: client.add_child(client.gateway)
		client.gateway.command_completed.connect(func(id: String, result: Dictionary): client.command_results[id] = result)
	var backend := RemoteWorldBackend.new()
	backend.configure(LOCAL_HTTP)
	client.gateway.use_backend(backend, true)
	backend.start_session(client.captain_id(), client.label, "mp-blueprint-flow-test", client.account_token)
	var deadline := Time.get_ticks_msec() + 14000
	while not client.gateway.is_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _check(client.gateway.is_ready(), client.label + " opened isolated reliable authority session")

func _verify_remote_door(owner: MpVirtualClient, observer: MpVirtualClient, replica: ImportedDraftVessel) -> void:
	for part in replica.part_roots:
		if BrickCatalog.get_entry(str(part.get_meta("asset_id", ""))).get("style", "") != "door": continue
		var door := part.get_node("PartState") as ShipPartState
		var binding: WorldStateBinding = replica.get_node("DoorInteraction").ensure_binding(door)
		binding.set_gateway(observer.gateway)
		await observer.ensure_interests(["entity:" + binding.entity_id])
		var sender := owner.make_state_binding(binding.entity_id, "door")
		for opened in [true, false]:
			var request_id := sender.request("open" if opened else "close", {"open": opened, "swing": 1.0}, false)
			var result := await owner.await_command_result(request_id)
			_check(bool(result.get("ok", false)), "Docker accepts imported door command within receipt ID limit", str(result.get("message", "")))
			var deadline := Time.get_ticks_msec() + 6000
			while Time.get_ticks_msec() < deadline:
				if bool(door.state.door_open) == opened and absf(door.current_door - (1.0 if opened else 0.0)) < .01: break
				await get_tree().physics_frame
			_check(bool(door.state.door_open) == opened and absf(door.current_door - (1.0 if opened else 0.0)) < .01, "Observer door animates server open=%s" % opened)
		sender.queue_free()
		return
	_check(false, "Fixture must contain a real door")

func _fetch_owner(vid: String) -> Dictionary:
	var result := {"finished": false, "row": {}}
	VesselSync.fetch_vessel_record(self, vid, func(row: Dictionary) -> void:
		result.row = row
		result.finished = true)
	var deadline := Time.get_ticks_msec() + 26000
	while not result.finished and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return result.row

func _push(session: MemorySession, record: Dictionary, registration: bool = false) -> Dictionary:
	var result := {"finished": false, "row": {}}
	var callback := func(row: Dictionary) -> void:
		result.row = row
		result.finished = true
	if registration:
		VesselSync.ensure_vessel_registered(session, record, callback)
		_check(session.data.owned_vessels.is_empty(), "Registration leaves ledger empty while awaiting server acceptance")
	else:
		VesselSync.push_brick_layout(session, record, callback)
	var deadline := Time.get_ticks_msec() + 15000
	while not result.finished and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	_check(bool(result.finished), "Production vessel save completes callback")
	return result.row

func _render_discovery(client: MpVirtualClient, cid: String) -> ImportedDraftVessel:
	var deadline := Time.get_ticks_msec() + 22000
	while Time.get_ticks_msec() < deadline:
		if client.snapshot_entities.has(_ship_entity):
			var entity: Dictionary = client.snapshot_entities[_ship_entity].entity
			_drawing.apply_entities([entity], client.captain_id(), {}, [], Time.get_ticks_msec(), 15000)
			var state: Dictionary = _drawing.get_visible_entities().get(_ship_entity, {})
			var ship: Variant = state.get("node")
			if ship is ImportedDraftVessel and str(ship.get_meta("construction_id", "")) == cid:
				return ship as ImportedDraftVessel
		await get_tree().process_frame
	return null

func _meta(row: Dictionary) -> String:
	return "vid=%s;lh=%s;cid=%s" % [row.id, row.layout_hash, row.construction_id]

func _custom_layout() -> Dictionary:
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/28_10_m.json"))
	var layout: Dictionary = stock.brick_layout.duplicate(true)
	layout.hull_colors.upper = [0.07, 0.38, 0.34]
	var engines := MarineEngineCatalog.options(str(layout.hull))
	layout.engine_preset = str(engines.back().id)
	for part: Dictionary in layout.parts:
		if part.asset_id == "deck_mushroom_vent":
			part.position = [2.5, 3.6, 9.5]
			part.instance_id = "custom-starboard-vent"
			part.colors = {"wall": [0.12, 0.32, 0.67]}
		if part.asset_id == "passenger_seat": part.yaw_degrees = 90
	return layout

func _verify_assembly(boat: ImportedDraftVessel, construction: Dictionary, label: String) -> void:
	_check(boat.draft == construction.layout, label + " reconstructs the complete accepted envelope")
	_check(boat.part_roots.size() == (construction.layout.parts as Array).size(), label + " instantiates every authored part")
	var matched := 0
	for record: Dictionary in construction.layout.parts:
		for part: Node3D in boat.part_roots:
			if str(part.get_meta("instance_id", "")) != str(record.instance_id): continue
			var position: Array = record.position
			if part.position.distance_to(Vector3(position[0], position[1], position[2])) < 0.002 and str(part.get_meta("asset_id")) == str(record.asset_id): matched += 1
	_check(matched == boat.part_roots.size(), label + " model identities and physical positions match server blueprint")
	_check(_hull_paint_matches(boat, construction.layout.hull_colors.upper), label + " visible hull material uses saved paint")
	var engine := MarineEngineCatalog.resolve(str(construction.layout.hull), str(construction.layout.engine_preset))
	_check(is_equal_approx(boat.physics_profile.shaft_power_kw, float(engine.power_kw)), label + " installs saved engine power")
	var pads := boat.get_cargo_pads()
	_check(pads.size() == (construction.cargo_slots as Array).size(), label + " runtime cargo capacity agrees with server")
	var slots_matched := 0
	for slot: Dictionary in construction.cargo_slots:
		for pad in pads:
			if str(pad.get_meta("authority_slot_id", "")) != str(slot.id): continue
			var p: Array = slot.local_position
			if boat.to_local(pad.global_position).distance_to(Vector3(p[0], p[1], p[2])) < 0.002: slots_matched += 1
	_check(slots_matched == pads.size(), label + " stable cargo IDs and CargoDatum coordinates agree")

func _hull_paint_matches(boat: ImportedDraftVessel, rgb: Array) -> bool:
	var expected := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	var matched := 0
	for mesh: MeshInstance3D in boat.get_node("HullVisual").find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(index)
			if source == null or not source.resource_name.begins_with("Paint_HullUpper"): continue
			var material := mesh.get_active_material(index)
			if material == null: return false
			var colour: Color = material.get_shader_parameter("base_color") if material is ShaderMaterial else material.albedo_color
			if not colour.is_equal_approx(expected): return false
			matched += 1
	return matched > 0

func _capture_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"

func _capture(_replica: ImportedDraftVessel, stage: String) -> void:
	if not _capture_enabled(): return
	if _review_camera == null:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.07, 0.105, 0.14)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.8, 0.88, 1)
		environment.environment.ambient_light_energy = 0.7
		add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -40, 0)
		light.light_energy = 1.7
		add_child(light)
		_review_camera = Camera3D.new()
		_review_camera.fov = 42
		add_child(_review_camera)
		_review_camera.position = ORIGIN + Vector3(36, 29, 44)
		_review_camera.look_at(ORIGIN + Vector3(-5, 5, 0))
		_review_camera.current = true
		var hud := CanvasLayer.new()
		add_child(hud)
		var title := Label.new()
		title.text = "CARGO REPLICATION THROUGH LOCAL DOCKER\nObserver: server manifest drives cargo and crane\nOriginal owner objects hidden for these captures"
		title.position = Vector2(22, 18)
		title.add_theme_font_size_override("font_size", 21)
		hud.add_child(title)
	if stage == "hook":
		var job := remote_port.all_equipment()[0] as ProvisionCraneEquipmentJob
		var focus := job._crane._hook.global_position
		for node: ContainerNode in cargo_observer._nodes.values():
			if node.get_meta("cargo_location", "") == "hook": focus = node.global_position + Vector3.UP * 1.3
		_review_camera.position = focus + Vector3(14, 0, 18)
		_review_camera.look_at(focus + Vector3(0,-1,0))
	else:
		_review_camera.position = ORIGIN + Vector3(-30,24,35)
		_review_camera.look_at(ORIGIN + Vector3(-5,3,0))
	for frame in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("mp-cargo-%s-%d-%s.png" % [Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id(), stage])
	var saved := get_viewport().get_texture().get_image().save_png(path)
	_check(saved == OK, "Archived actual engine capture: " + stage)
	if saved == OK: _captures.append(path)

class EmptyDrawing extends Node:
	func get_visible_entities() -> Dictionary: return {}
	func find_remote_ship_by_vessel_id(_id: String) -> BoatBody: return null

class TestView extends Node:
	var ship: BoatBody
	func get_active_ship() -> BoatBody: return ship

var cargo_owner: CargoManifestReplication
var cargo_observer: CargoManifestReplication
var remote_port: HarbourController

func _until(predicate: Callable, label: String, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	return _check(predicate.call(),label,cargo_owner.last_error if cargo_owner != null else "")

func _make_port(pid: String, bid: String) -> HarbourController:
	var port := HarbourController.new()
	port.setup(pid)
	add_child(port)
	var berth := QuayBerthSlot.new()
	berth.berth_id=bid
	add_child(berth)
	port.register_berth(berth)
	var crane := ProvisionCrane.new()
	add_child(crane)
	crane.position=ORIGIN+Vector3(-12,0,0)
	crane.set_meta("equipment_id",pid+"/crane")
	crane.set_meta("berth_id",bid)
	var auto := ProvisionCraneAutoOperator.new()
	auto.name="AutoOperator"
	crane.add_child(auto)
	var job := ProvisionCraneEquipmentJob.new()
	job.setup(pid+"/crane","provision_crane",bid)
	port.add_child(job)
	job.bind_crane(crane)
	port.register_equipment(job,bid)
	return port

func _cargo_scenario(owner: MpVirtualClient, observer: MpVirtualClient, boat: ImportedDraftVessel, replica: ImportedDraftVessel, vid: String) -> void:
	var pid := "cargo-test-"+vid.substr(0,8)
	var bid := pid+"/berth"
	var result := await owner.await_command("vessel.berth.claim",{"vessel_id":vid,"port_id":pid,"candidates":[bid]})
	if not _check(result.get("ok",false),"Owner obtains server berth",str(result)): return
	boat.set_meta("harbour_port_id",pid)
	boat.set_meta("harbour_berth_id",bid)
	var port := _make_port(pid,bid)
	HarbourRegistry.register(port)
	remote_port=_make_port(pid,bid)
	var source_job := port.get_equipment(pid+"/crane") as ProvisionCraneEquipmentJob
	var target_job := remote_port.get_equipment(pid+"/crane") as ProvisionCraneEquipmentJob
	var yard := CargoSlotPadComponent.new()
	yard.is_quay_yard_pad=true
	yard.affects_boat_cargo_mass=false
	add_child(yard)
	yard.position=ORIGIN+Vector3(-8,0,0)
	var contract_id := "freight-"+vid
	FreightService._active.append({"id":contract_id,"vessel_uid":str(boat.get_meta("vessel_uid")),
		"status":"accepted","quantity":2,"issued_quantity":2,"loaded_quantity":0,
		"origin_port_id":pid,"destination_port_id":"destination-test","commodity_id":"provisions",
		"consignment":{"consignment_id":"consignment-"+vid}})
	# Staging must correspond to a saved active booking, just as in a real voyage.
	var booking_save := await owner._http(HTTPClient.METHOD_PUT, "/v2/captain-state", {
		"contract_version":1,"captain_id":owner.captain_id(),"expected_revision":0,
		"format_version":6,"state":{"accepted_contracts":FreightService.active_contracts()}}, "account")
	if not _http_ok(booking_save,"Booking persisted before quay cargo publication"): return
	var originals: Array[ContainerNode]=[]
	for i in 2:
		var unit := ContainerUnit.create("cargo-"+vid+"-"+str(i),"provisions",3200)
		unit.freight_contract_id=contract_id
		unit.origin_port_id=pid
		unit.destination_port_id="destination-test"
		unit.consignment_id="consignment-"+vid
		unit.paint_variant=i+2
		unit.delivery_value_marks=12345
		yard.add_container(unit)
	for node in yard.iter_container_nodes(): originals.append(node)
	if not _check(originals.size()==2,"Two real containers staged on owner's quay"): return
	var owner_view := TestView.new()
	owner_view.ship=boat
	add_child(owner_view)
	cargo_owner=CargoManifestReplication.new()
	add_child(cargo_owner)
	cargo_owner.setup(owner.gateway,owner_view,_drawing)
	var observer_view := TestView.new()
	add_child(observer_view)
	cargo_observer=CargoManifestReplication.new()
	add_child(cargo_observer)
	cargo_observer.port_lookup=func(_pid: String): return remote_port if _pid==pid else null
	var empty_drawing := EmptyDrawing.new()
	add_child(empty_drawing)
	cargo_observer.setup(observer.gateway,observer_view,empty_drawing)
	observer.gateway.retain_interest("port:"+pid,self)
	if not await _until(func():return cargo_observer._nodes.size()==2,"Observer renders both quay containers through real server events"): return
	_check(cargo_observer._interests.is_empty(),"Quay cargo arrives from port interest before vessel discovery")
	cargo_observer.drawing=_drawing
	var first_key := vid+"/"+originals[0].unit.id
	var remote_box: ContainerNode=cargo_observer._nodes[first_key]
	_check(remote_box.unit.destination_port_id=="destination-test" and remote_box.unit.delivery_value_marks==12345 and remote_box.unit.paint_variant==2,"Destination, value, paint and identity survive publication")
	_check(remote_box.global_position.distance_to(originals[0].global_position)<.01,"Quay placement matches source")
	boat.hide()
	source_job._crane.hide()
	for original in originals: original.hide()
	await _capture(replica,"quay")
	_check(not remote_box.is_in_group(ContainerNode.GROUP),"Observer containers cannot be picked up by a second local crane")
	yard.set_meta("berth_id", bid)
	yard.set_meta("equipment_id", pid+"/crane")
	port.register_yard(yard,bid)
	port.plug_ship(bid,boat)
	port.activate()
	var npc := CraneOperatorNpc.new()
	npc.configure(port,bid,pid+"/crane")
	add_child(npc)
	if not _check(source_job.can_serve(boat,QuayEquipmentJob.MODE_LOAD),"Real NPC crane can serve staged freight",source_job.serve_hint(boat,"load")): return
	var initial_slew := source_job._crane.slew_degrees
	var initial_hoist := source_job._crane.hoist_length_m
	npc._on_request_load()
	if not await _until(func():return not source_job.operation_id().is_empty(),"NPC Load obtains a server operation before starting the crane"):
		print("NPC TRACE ", {"owns":port._authority_bridge._owns_vessel(vid),"context":source_job.authority_context(),"failure":source_job.last_failure,"ready":WorldGateway.is_ready(),"operations":WorldGateway.projections("port_operation"),"same_ship":port.moored_ship(bid)==boat,"can_serve":source_job.can_serve(boat,"load")})
		return
	var operation_id := source_job.operation_id()
	_check(str(source_job.replication_context.get("vessel_id", ""))==vid,"Real job supplies vessel identity to crane publisher")
	if not await _until(func():return absf(source_job._crane.slew_degrees-initial_slew)>.2 or absf(source_job._crane.hoist_length_m-initial_hoist)>.2,"Actual automatic crane moves after NPC request"): return
	if not await _until(func():return absf(target_job._crane.slew_degrees-initial_slew)>.1 or absf(target_job._crane.hoist_length_m-initial_hoist)>.1,"Observer follows actual automatic crane movement"): return
	# Freeze the operator only after the real NPC/authority/automatic movement
	# path has passed; remaining checks isolate hook and landing transitions.
	source_job._crane.get_auto_operator().set_process(false)
	_check(source_job._crane.attach_container(originals[0]),"Real crane attaches original container")
	source_job._crane.slew_degrees=35
	source_job._crane.trolley_z_m=10
	source_job._crane.hoist_length_m=18
	if not await _until(func():return remote_box.get_parent()==target_job._crane._hook,"Same observer container moves from quay onto crane hook"): return
	await _until(func():return absf(target_job._crane.slew_degrees-35)<.1 and absf(target_job._crane.hoist_length_m-18)<.1,"Observer crane joints follow owner")
	_check(cargo_observer._nodes.size()==2,"Transfer never duplicates cargo")
	await _capture(replica,"hook")
	source_job._crane.slew_degrees=-25
	source_job._crane.hoist_length_m=8
	await _until(func():return absf(target_job._crane.slew_degrees+25)<.1,"Observer crane follows a second moving pose")
	var pads := boat.get_cargo_pads()
	if not _check(pads.size()>=2,"Custom ship has two cargo positions"): return
	originals[0].global_position=pads[0].slot_drop_world_for_free(originals[0].unit.footprint_cells(pads[0].cell_size_m))
	if pads[0].show_pad_visual: originals[0].global_position+=pads[0].global_basis.y*ContainerNode.floor_offset_y()
	_check(source_job._crane.release_container_on_pad(pads[0],pads[0].slot_drop_world_for_free())==originals[0],"Actual crane release places first container on deck")
	source_job._crane.attach_container(originals[1])
	originals[1].global_position=pads[1].slot_drop_world_for_free(originals[1].unit.footprint_cells(pads[1].cell_size_m))
	if pads[1].show_pad_visual: originals[1].global_position+=pads[1].global_basis.y*ContainerNode.floor_offset_y()
	_check(source_job._crane.release_container_on_pad(pads[1],pads[1].slot_drop_world_for_free())==originals[1],"Actual crane release places second container on deck")
	if not await _until(func():return cargo_observer._nodes.size()==2 and cargo_observer._nodes.values().all(func(n):return n.get_parent()==replica),"Both loaded containers appear aboard observer ship"): return
	for original in originals:
		var copy: ContainerNode=cargo_observer._nodes[vid+"/"+original.unit.id]
		_check(copy.position.distance_to(boat.to_local(original.global_position))<.01,"Deck container preserves ship-local placement")
	await _capture(replica,"deck")
	replica.rotation.y=.7
	replica.position+=Vector3(20,2,10)
	_check(remote_box.global_position.distance_to(replica.to_global(remote_box.position))<.001,"Cargo travels and rotates with replicated hull")
	cargo_observer.clear()
	cargo_observer.queue_free()
	await get_tree().process_frame
	observer.gateway.stop_session()
	if not await _open_isolated_session(observer): return
	cargo_observer=CargoManifestReplication.new()
	add_child(cargo_observer)
	cargo_observer.port_lookup=func(_pid: String):return remote_port if _pid==pid else null
	cargo_observer.setup(observer.gateway,observer_view,_drawing)
	if not await _until(func():return cargo_observer._nodes.size()==2 and cargo_observer._nodes.values().all(func(n):return n.get_parent()==replica),"Fresh observer session reconstructs already-loaded deck cargo"): return
	cargo_observer.drawing=empty_drawing
	await _until(func():return cargo_observer._nodes.is_empty(),"Leaving vessel range removes deck replicas")
	cargo_observer.drawing=_drawing
	await _until(func():return cargo_observer._nodes.size()==2,"Returning to vessel range rebuilds deck manifest")
	for original in originals:
		var pad := CargoSlotPadComponent.find_pad_for_node(original)
		pad.take_container_node(original)
		original.queue_free()
	await _until(func():return cargo_observer._nodes.is_empty(),"Removing cargo removes all observer copies")
	_check(cargo_owner.last_error.is_empty(),"Publisher finishes without rejected commands",cargo_owner.last_error)
	# Cancellation must remove staging without the active-ship publisher helping.
	var cancelled_unit := ContainerUnit.create("cancel-"+vid,"provisions",3200)
	cancelled_unit.freight_contract_id=contract_id
	yard.add_container(cancelled_unit)
	if not await _until(func():return cargo_observer._nodes.size()==1,"Cancellation fixture reaches observer quay"): return
	cargo_owner.set_process(false)
	FreightService._active.clear()
	var cancelled_save := await owner._http(HTTPClient.METHOD_PUT,"/v2/captain-state",{
		"contract_version":1,"captain_id":owner.captain_id(),"expected_revision":1,
		"format_version":6,"state":{"accepted_contracts":[]}},"account")
	if not _http_ok(cancelled_save,"Cancellation saved while vessel publisher is inactive"): return
	if not await _until(func():return cargo_observer._nodes.is_empty(),"Server removes cancelled cargo from observer without owner publishing"): return
	_check(yard.get_containers().is_empty(),"Server cleanup also releases owning client's physical pad")

	port.deactivate()
	cargo_owner.set_process(false)
	cargo_observer.set_process(false)
	cargo_owner.clear()
	cargo_observer.clear()
	FreightService._active.clear()
	HarbourRegistry.unregister_controller(port)
