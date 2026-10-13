extends "res://scripts/ship/rod_fishing_showcase.gd"

func _ready() -> void:
	super._ready()
	call_deferred("run_test")

func run_test() -> void:
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
	station.set_physics_process(false)
	player.set_physics_process(false)
	station.working = true
	station._carry(true)
	var remote := Node3D.new()
	var body := NpcBase.new()
	body.name = "BodyMesh"
	remote.add_child(body)
	add_child(remote)
	remote.global_position = player.global_position + Vector3(3,0,0)
	for frame in 10: await get_tree().process_frame
	var fish := {"species_id":"cod", "length_cm":90.0, "mass_kg":6.0, "hook_index":0, "fish_id":"test"}
	station.session.phase = "fighting"
	station.session.catch_data = fish
	station.session.depth_m = 1
	station.session.progress = .7
	for frame in 4: await get_tree().process_frame
	var encoded := FishingVisualReplication.encode(station, player)
	assert(not FishingVisualReplication.decode(encoded).is_empty())
	FishingVisualReplication.apply(remote, encoded)
	for frame in 10: await get_tree().process_frame
	var replica := remote.get_node("RemoteFishingVisual") as RodFishingStation
	assert(is_instance_valid(replica._hand_pose))
	assert(replica._line.visible and replica._fish.visible)
	assert(replica._fish_species == "cod")
	assert(replica._carried.global_position.distance_to(remote.to_global(FishingVisualReplication.decode(encoded).pose.origin)) < .01)
	var folder := "C:/Users/noahs/Pictures/machinescreenshots/fishing-replica-" + str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(folder)
	var observer := Camera3D.new()
	add_child(observer)
	observer.global_position = remote.global_position + Vector3(2.5,2,-3)
	observer.look_at(remote.global_position + Vector3(0,1,0))
	observer.current = true
	for frame in 10: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("rod-fish.png"))
	station.session.phase = "landed"
	FishingVisualReplication.apply(remote,FishingVisualReplication.encode(station,player))
	for frame in 10: await get_tree().process_frame
	assert(replica._fish.visible and replica._fish.global_position.distance_to(remote.global_position)<2)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("landed-fish.png"))
	station._carry(false)
	station.working = false
	station.set_equipment("harpe")
	station.working = true
	station._carry(true)
	station.session.phase = "fighting"
	station.session.catch_data = fish
	for i in 6:
		var item := fish.duplicate()
		item.hook_index = i
		item.fish_id = str(i)
		station.session.catches.append(item)
	for frame in 4: await get_tree().process_frame
	encoded = FishingVisualReplication.encode(station,player)
	assert(encoded.length() == 72)
	var metadata := "cid=12345678-1234-1234-1234-123456789012;app=123456789012;deck=12345678-1234-1234-1234-123456789012;dpos=-499.000,-499.000,-499.000;dyaw=-3.1416;fv=" + encoded
	assert(metadata.to_utf8_buffer().size() <= 255)
	FishingVisualReplication.apply(remote,encoded)
	for frame in 10: await get_tree().process_frame
	assert(replica.session is HarpeFishingSession)
	assert(replica._harpe_rig._fish.size() == 6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("harpe-six-fish.png"))
	FishingVisualReplication.apply(remote, "")
	await get_tree().process_frame
	assert(remote.get_node_or_null("RemoteFishingVisual") == null)
	assert(FishingVisualReplication.decode("AAAA").is_empty())
	if OS.get_cmdline_user_args().has("--live-server"):
		var clients: Array[MpVirtualClient] = []
		for label in ["fishing-sender", "fishing-observer"]:
			var client := MpVirtualClient.new()
			client.setup(label,"http://127.0.0.1:8080","127.0.0.1",7777)
			add_child(client)
			assert((await client.login_or_register("visual-%s@integration.local" % PlayerData.new_uuid(),"local-visual-test-2026")).ok)
			assert((await client.ensure_captain(label)).ok)
			client.gateway = preload("res://scripts/network/world_gateway.gd").new()
			client.add_child(client.gateway)
			var backend := RemoteWorldBackend.new()
			backend.configure(client.base_url)
			client.gateway.use_backend(backend,true)
			backend.start_session(client.captain_id(),label,"mp-fishing-test",client.account_token)
			var deadline := Time.get_ticks_msec()+12000
			while not client.gateway.is_ready() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
			assert(client.gateway.is_ready())
			assert(client.udp_start().ok)
			client.set_avatar(Vector3(100,0,100))
			clients.append(client)
		clients[0]._outbound[clients[0].captain_id()].meta = metadata
		var received := await clients[1].await_snapshot_entity(clients[0].captain_id(),10,func(e):return e.get("meta","")==metadata)
		assert(not received.is_empty(),"Server must preserve all six fish and deck metadata")
		var drawings := preload("res://scripts/network/replication_drawing_service.gd").new()
		add_child(drawings)
		FishingVisualReplication.apply(remote,str(drawings._parse_meta_map(received.meta).fv))
		for frame in 4: await get_tree().process_frame
		assert(remote.get_node("RemoteFishingVisual")._harpe_rig._fish.size()==6)
		clients[0]._outbound[clients[0].captain_id()].meta = "name=stowed"
		received = await clients[1].await_snapshot_entity(clients[0].captain_id(),10,func(e):return e.get("meta","")=="name=stowed")
		assert(not received.is_empty())
		FishingVisualReplication.apply(remote,str(drawings._parse_meta_map(received.meta).get("fv","")))
		assert(remote.get_node_or_null("RemoteFishingVisual")==null)
		for client in clients: client.close_session()
		print("LIVE UDP FISHING PASS: two authenticated clients, six fish, stow")
	print("FISHING VISUAL REPLICATION PASS: rod, hand pose, line, cod, six-hook harpe, packet budget, stow cleanup. ", folder)
	get_tree().quit()
