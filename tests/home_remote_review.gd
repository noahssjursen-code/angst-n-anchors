extends Node
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	print("REMOTE_HOME ","PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func _ready()->void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()
func _run()->void:
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--home-fixture="):path=arg.trim_prefix("--home-fixture=")
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	WorldBootstrap.apply_seed(72482,0,"",3,40000,"standard")
	PlayerSession.begin_new_captain("Remote home review",null,HomePortService.PENDING,str(fixture.b.id),72482,"Review company",Color.WHITE,"fishing",str(fixture.b.company))
	PlayerSession.data.company.id=str(fixture.b.company)
	var remote:=RemoteWorldBackend.new();remote.configure(fixture.url)
	WorldGateway.use_backend(remote,true)
	remote.start_session(fixture.b.id,"Review","",fixture.b.token)
	var other=load("res://scripts/network/world_gateway.gd").new();add_child(other)
	var observer:=RemoteWorldBackend.new();observer.configure(fixture.url)
	other.use_backend(observer,true)
	observer.start_session(fixture.a.id,"Observer","",fixture.a.token)
	var deadline:=Time.get_ticks_msec()+15000
	while not WorldGateway.is_ready() or not other.is_ready():
		if Time.get_ticks_msec()>deadline:check(false,"two authenticated transports ready");get_tree().quit(1);return
		await get_tree().process_frame
	var options:=await HomePortService.prepare()
	check(options.get("ok",false),"remote home options through production gateway")
	var setup=load("res://scenes/ui/new_home_setup.tscn").instantiate();add_child(setup)
	deadline=Time.get_ticks_msec()+90000
	while setup.chart==null or setup.chart.selected_plot.is_empty():
		if Time.get_ticks_msec()>deadline:
			print("SERVER_WORLD ",HomePortService.options.get("world")," CLIENT_WORLD ",setup.snapshot.world_context())
			print("AVAILABLE ",setup.available.size()," STATUS ",setup.status.text)
			check(false,"native plot map becomes ready");get_tree().quit(1);return
		await get_tree().process_frame
	check(setup.available.size()>0,"server survey matches native map world")
	var received:=[false]
	other.projection_changed.connect(func(kind:String,id:String,_p:Dictionary):
		if kind=="custom_port" and id=="home-"+str(fixture.b.id):received[0]=true)
	var claim:=await HomePortService.request("port.home.claim",{"plot_id":setup.chart.selected_plot,"company_id":fixture.b.company})
	check(claim.get("ok",false),"native client claims server-selected plot")
	if not claim.get("ok",false):print(claim);get_tree().quit(1);return
	HomePortService.adopt(claim.data.port)
	await HomePortService.prepare()
	check(HomePortService.records.size()==2,"both captains' ports fetched")
	var streamer:=CustomPortStreamer.new();streamer.live_services=true;add_child(streamer)
	streamer.configure(CustomPortWorldImport.world_identity(setup.snapshot.world_context()))
	streamer.set_process(false);streamer.loader.set_process(false)
	for record in HomePortService.records:
		var result:=streamer.upsert_record(record)
		check(result.ok,"server JSON accepted by native port model")
		if not result.ok:print(result);continue
		streamer.retained_ids[str(record.id)]=true
		var port:=streamer.load_now(str(record.id))
		check(port!=null and port.get_node_or_null("Services") is PlayerPortPlot,"same presenter constructs live port and services")
	deadline=Time.get_ticks_msec()+10000
	while not received[0] and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(received[0],"other captain receives new custom port")
	WorldGateway.stop_session();other.stop_session()
	print("REMOTE_HOME_RESULT failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
