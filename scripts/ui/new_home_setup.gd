extends Control

var chart:MapOverlay
var snapshot:ChartDataSnapshot
var sites:Dictionary={}
var available:Array[String]=[]
var busy:=false
var status:Label

func _ready()->void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var header:=Label.new()
	header.text="Preparing your coastal chart…"
	header.position=Vector2(32,32)
	add_child(header)
	await get_tree().process_frame
	snapshot=ChartDataSnapshot.for_preview(GameSettings.map_generation_seed,35,GameSettings.map_world_size_m,GameSettings.map_world_preset)
	HomePortService.chart=snapshot
	chart=MapOverlay.new()
	chart.preview_mode=true
	add_child(chart)
	chart.set_data_snapshot(snapshot)
	chart.layers.set_visible("plots",true)
	chart.layers.set_visible("weather",false)
	chart.layers.set_visible("traffic",false)
	chart._apply_mode_ui()
	chart.set_plot_inspector(_inspect)
	chart.plot_action_requested.connect(_claim)
	chart.close_requested.connect(_back)
	var banner:=Ui.sheet()
	banner.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	banner.position=Vector2(28,90)
	banner.custom_minimum_size=Vector2(350,0)
	add_child(banner)
	var column:=Ui.vbox(8)
	banner.add_child(column)
	column.add_child(Ui.eyebrow("YOUR FIRST HOME"))
	column.add_child(Ui.heading("Choose your stretch of coast"))
	status=Ui.paragraph("A finished fishing quay, a shed and your first boat.\nChoose a coastal plot to make it yours.")
	column.add_child(status)
	header.queue_free()
	if WorldGateway.is_remote():
		available.assign(HomePortService.options.get("available",[]))
		var world:Dictionary=HomePortService.options.get("world",{})
		if int(world.get("seed",0))!=snapshot.world_seed or int(world.get("generation_version",0))!=snapshot.generation_version or str(world.get("checksum",""))!=snapshot.layout_checksum:
			available.clear()
			status.text="This server has no starter-site survey for its current world. Your captain is saved; return once the server is updated."
	else:
		# Find one useful initial focus; remaining plots are surveyed on selection.
		var candidates:=chart.renderer.plots.index.plot_ids()
		candidates.sort_custom(func(a,b):return _plot_distance(a)<_plot_distance(b))
		for id in candidates:
			var plot:=chart.renderer.plots.index.get_plot(id)
			var candidate:=StarterPortSites.fit(plot,snapshot)
			sites[id]=candidate
			if not candidate.is_empty():available.append(id);break
	available.sort_custom(func(a,b):return _plot_distance(a)<_plot_distance(b))
	if WorldGateway.is_remote():chart.renderer.plots.set_ownership_status([],available)
	await get_tree().process_frame
	chart.first_visible_frame=false
	chart.camera_initialized=true
	if not available.is_empty():
		var plot:=chart.renderer.plots.index.get_plot(available[0])
		chart.camera.focus_harbour(ChartPlotLayer.plot_rect(plot).get_center(),1800)
		chart.selected_plot=str(plot.id)
		chart._refresh_plot_panel()
	chart._redraw_geography()

func _plot_distance(id:String)->float:
	var plot:=chart.renderer.plots.index.get_plot(id)
	return ChartPlotLayer.plot_rect(plot).get_center().length_squared()

func _inspect(plot:Dictionary)->Dictionary:
	if plot.is_empty():return {"heading":"Pick a coastal plot","body":"Click a square on the coastline. Your finished starter port is included."}
	var id:=str(plot.id)
	var fits:=available.has(id)
	if not WorldGateway.is_remote():
		if not sites.has(id):sites[id]=StarterPortSites.fit(plot,snapshot)
		fits=not sites[id].is_empty()
	return {"heading":"Your new home" if fits else "Choose another stretch",
		"meta":"200 × 200 m · Included with your captain",
		"body":"Littlehaven starter quay\nRed fishing shed · safe berth\nFishing boat + personal rod\n\nExpand and rebuild later, at your pace." if fits else "This plot is occupied or does not have enough clear water and shore access for the starter quay.",
		"action_text":"Preparing your home…" if busy else "Make this my home",
		"action_visible":true,"action_enabled":fits and not busy}

func _claim(plot:Dictionary)->void:
	if busy:return
	busy=true
	chart._refresh_plot_panel()
	var result:=await HomePortService.request("port.home.claim",{"plot_id":str(plot.id),"company_id":str(PlayerSession.data.company.get("id",""))})
	if not is_inside_tree():return
	if not result.get("ok",false):
		busy=false
		status.text=str(result.get("message","This plot could not be claimed. Please choose another."))
		chart._refresh_plot_panel()
		return
	HomePortService.adopt(result.data.port)
	HomePortService.welcome=true
	WorldBootstrap.enter_world(get_tree(),WorldGateway.is_remote(),true)

func _back()->void:
	if busy:return
	WorldGateway.stop_session()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
