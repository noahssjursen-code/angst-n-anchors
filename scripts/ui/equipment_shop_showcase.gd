extends Node3D
## Isolated shop using the real NPC, purchase adapter, panel and captain ledger.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	PlayerSession.begin_new_captain("Shop Review",CharacterAppearance.default_appearance(),"test-port","shop-review",424242,"Review Shipping",Color.WHITE,"")
	var ship:=CompanyService.build_starter_vessel_record("fishing")
	ship.uid="shop-review-ship";ship.name="Mail Boat"
	PlayerSession.data.upsert_owned_vessel(ship);PlayerSession.data.set_active_vessel(ship)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("426573")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6;add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);add_child(sun)
	var npc:=HarbourMasterNpc.new();npc.port_id="test-port";add_child(npc)
	var player:=CharacterBody3D.new();player.add_to_group("player");player.position=Vector3(0,0,2.5);add_child(player)
	var camera:=Camera3D.new();add_child(camera);camera.position=Vector3(1.1,1.5,3.5);camera.look_at(Vector3(2.0,1,0));camera.current=true
	var layer:=CanvasLayer.new();add_child(layer)
	var panel:=VoyagePanel.new();layer.add_child(panel)
	panel.close_requested.connect(func():get_tree().quit())
	await get_tree().process_frame
	panel.show_service(npc);panel._show_equipment()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--capture"):
		var before:=PlayerSession.data.marks
		panel._send("equipment:crab_trap",{"request_id":"ui-trap"})
		assert(PlayerSession.data.marks==before-650,"NPC shop charges exact price")
		assert(VesselEquipment.count(LocalPlayerView.get_active_vessel_record(),"crab_trap")==1)
		for i in 20:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path:="C:/Users/noahs/Pictures/machinescreenshots/equipment-shop-%d.png"%Time.get_ticks_usec()
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOP UI PASS: NPC purchase, balance, ship quantity, refreshed panel. CAPTURE ",path)
		get_tree().quit()
