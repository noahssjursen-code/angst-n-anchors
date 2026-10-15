extends Node

var failures:Array[String]=[]
var stamp:=""
var full:=false

func _ready()->void:
	assert(ShipyardPlaytestMode.active())
	stamp="home-onboarding-%d-%d"%[Time.get_unix_time_from_system(),OS.get_process_id()]
	full=OS.get_cmdline_user_args().has("--full-world")
	if OS.get_cmdline_user_args().has("--shop-only"):_shop_review.call_deferred()
	else:_run.call_deferred()

func check(ok:bool,label:String)->void:
	print("ONBOARDING ","PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func capture(suffix:String)->void:
	if DisplayServer.get_name()=="headless":return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join(stamp+"-"+suffix+".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("ONBOARDING_CAPTURE ",path)

func _run()->void:
	WorldBootstrap.apply_seed(72482)
	PlayerSession.begin_new_captain("Onboarding review",null,HomePortService.PENDING,"review-home",72482,"Littlehaven Maritime",Color("326e71"),"fishing","review-home")
	var backend:=LocalWorldBackend.new()
	WorldGateway.use_backend(backend,false)
	backend.start_session("review-home","Review","")
	await HomePortService.prepare()
	var setup=load("res://scenes/ui/new_home_setup.tscn").instantiate()
	add_child(setup)
	var deadline:=Time.get_ticks_msec()+120000
	while setup.chart==null or setup.chart.selected_plot.is_empty():
		if Time.get_ticks_msec()>deadline:check(false,"map has an eligible coastal plot");get_tree().quit(1);return
		await get_tree().process_frame
	check(setup.available.size()>0,"map has a surveyed coastal plot")
	await get_tree().create_timer(3).timeout
	await capture("choose-plot")
	var plot:String=setup.chart.selected_plot
	var command:={"plot_id":plot,"company_id":str(PlayerSession.data.company.id)}
	var result:=await HomePortService.request("port.home.claim",command)
	check(result.get("ok",false),"authority claims plot")
	if not result.get("ok",false):print(result);get_tree().quit(1);return
	var again:=await HomePortService.request("port.home.claim",command)
	check(again.data.port.id==result.data.port.id,"retry keeps same port")
	check(PlayerSession.data.personal_inventory.slots.filter(func(i):return i.get("item_id","")=="fishing_rod").size()==1,"retry grants exactly one rod")
	var document:Dictionary=result.data.port
	var restored:=PlayerData.from_dict(JSON.parse_string(JSON.stringify(PlayerSession.data.to_dict(),"",true,true)))
	var restored_state:=CustomPortState.from_dict(restored.home_port_document,document.world,CustomPortCatalog.definitions())
	check(restored_state.validation_errors.is_empty() and restored.home_port_document.placements.size()==document.placements.size() and restored.home_port_document.id==document.id,"captain JSON retains valid complete home")
	HomePortService.adopt(document)
	await HomePortService.prepare()
	setup.queue_free()
	await get_tree().process_frame
	if full:
		get_tree().current_scene=null
		HomePortService.welcome=true
		WorldBootstrap.enter_world(get_tree(),false,true)
		while get_tree().get_first_node_in_group("player")==null:await get_tree().process_frame
		var world:=get_tree().get_first_node_in_group("world")
		await world.boot_finished
		await get_tree().create_timer(3).timeout
		check(world._home_plot() is PlayerPortPlot,"normal world uses the player's custom home")
	else:
		var environment:=WorldEnvironment.new();environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color("7197ab")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7
		add_child(environment)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-30,0);add_child(sun)
		var stream:=CustomPortStreamer.new();stream.live_services=true;add_child(stream)
		stream.configure(document.world)
		check(stream.upsert_record(document).ok,"same streamer reconstructs port")
		var port:=stream.load_now(str(document.id))
		var services:=port.get_node("Services") as PlayerPortPlot
		var player:=load("res://scenes/shared/player.tscn").instantiate() as Node3D
		add_child(player);player.global_position=services.get_spawn_position()
		await get_tree().physics_frame
	await capture("welcome")
	GameMenu._set_screen(GameMenu.Screen.NONE)
	await capture("arrive")
	var service:=LocalPlayerView.get_tablet_harbour()
	check(service!=null,"tablet discovers home harbour")
	check(get_tree().get_nodes_in_group("port_service_npc").is_empty(),"no physical service characters")
	var fleet:Array=LocalPlayerView.get_company_summary().get("vessels",[])
	check(fleet.size()==1,"one fishing boat in fleet")
	GameMenu.open_tablet()
	GameMenu._panel._tablet.open_page("Shipyard")
	await capture("shipyard")
	var market:=LocalPlayerView.get_tablet_vessel_market()
	var item:Dictionary=market.items[0]
	GameMenu._panel._tablet._market_selection=item
	GameMenu._panel._tablet.render()
	await get_tree().create_timer(1).timeout
	await capture("shipyard-model")
	PlayerSession.earn_marks(int(item.price),"test_fixture","Isolated review funds")
	var before:=PlayerSession.get_marks()
	var purchase:=await LocalPlayerView.buy_tablet_vessel({"stock_id":str(item.id),"vessel_name":"Review purchase","request_id":"review-purchase","expected_price_nok":int(item.price)})
	check(purchase.get("ok",false) and LocalPlayerView.get_company_summary().vessels.size()==2,"tablet purchase adds owned vessel")
	check(PlayerSession.get_marks()==before-int(item.price),"tablet purchase debits exact price")
	GameMenu.open_berth_picker(str(fleet[0].uid))
	await get_tree().process_frame
	var picker:BerthPicker=GameMenu._berth_picker
	check(is_instance_valid(picker),"fleet opens berth camera")
	if is_instance_valid(picker):
		check(not picker.available.is_empty(),"fishing boat fits available berth")
		await capture("choose-berth")
		if not picker.available.is_empty():
			var target:QuayBerthSlot=picker.available[0]
			var click:=InputEventMouseButton.new()
			click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
			var polygon:=picker._polygon(target)
			for point in polygon:click.position+=point/polygon.size()
			picker._gui_input(click)
			check(picker.selected==target and not picker.confirm.disabled,"click selects the visible berth")
			picker._deploy()
			await get_tree().create_timer(3).timeout
			check(LocalPlayerView.has_active_ship(),"selected berth deploys actual boat")
			await capture("deployed")
			await _after_deploy()
	print("ONBOARDING_RESULT failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _shop_review()->void:
	PlayerSession.begin_new_captain("Preview",null,"test-home","review-preview",72482,"Coastal Maritime",Color.WHITE,"fishing")
	GameMenu.open_tablet()
	var tablet:KontorTablet=GameMenu._panel._tablet
	tablet.open_page("Shipyard")
	tablet._market_selection=LocalPlayerView.get_tablet_vessel_market().items[0]
	tablet.render()
	await get_tree().create_timer(2).timeout
	await capture("shipyard-model")
	get_tree().quit()

func _after_deploy() -> void:
	pass
