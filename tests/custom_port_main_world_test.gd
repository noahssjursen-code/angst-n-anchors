extends Node3D

## Actual main World acceptance, with explicitly authored isolated documents.
## No workshop scene stands in for the main world; no live captain save is used.
const SOURCE = preload("res://scripts/port/building/custom_port_world_import.gd")
const FIXTURE = preload("res://tests/custom_port_world_import_test.gd")
const SITE := Vector3(2724,.5,-692)
var world: World
var review_camera: Camera3D
var checks := 0
var failures: Array[String] = []
var original_hashes: Dictionary = {}

func _ready() -> void:_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	GameSettings.map_generation_seed=73119
	GameSettings.map_generation_version=WorldLayoutGenerator.GENERATION_VERSION
	GameSettings.map_layout_checksum=""
	GameSettings.map_world_size_m=15000
	PlayerSession.data.home_port_id="port-home"
	var layout:=WorldLayoutGenerator.generate(73119,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	var identity:={"seed":layout.seed,"generation_version":WorldLayoutGenerator.GENERATION_VERSION,"checksum":layout.layout_checksum}
	var plots: Array=[{"id":"main-world-fishing-plot","rect_m":[-100,-20,200,200],"owner_company_id":"company-fishing-pier"}]
	var fishing:=CustomPortFishingExample.build(SITE,plots,identity,func(at:Vector2)->float:return WorldTerrainStreamer.sample_render_terrain_height(layout,at))
	# Authored scenario data includes a boat record to prove it never spawns in
	# the production presentation importer. It never enters the actual fleet.
	var first:=FIXTURE.write_fixture("main-world-fishing",fishing)
	var second_position:=Vector3.ZERO
	for contour in layout.coastline_contours:
		for point in contour:
			if point.distance_to(Vector2(SITE.x,SITE.z))>3000 and point.length()<5000:
				second_position=Vector3(point.x,.5,point.y)
				break
		if second_position!=Vector3.ZERO:break
	var second:=FIXTURE.write_fixture("main-world-pier",FIXTURE.fixture("outlying-pier",second_position,identity))
	for path in [first,second]:original_hashes[path]=FileAccess.get_sha256(path)
	var fleet_before:=PlayerSession.data.owned_vessels.duplicate(true)
	world=preload("res://scenes/world.tscn").instantiate() as World
	world.port_count=3
	world.custom_port_document_paths=PackedStringArray([first,second])
	add_child(world)
	await world.boot_finished
	_check(world.get_world_layout()==layout,"Normal World reuses the finalized layout used by documents")
	var home:=world.get_node("HomePort") as PortPlot
	var player:=get_tree().get_first_node_in_group("player") as Node3D
	_check(player!=null and player.global_position.distance_to(home.get_spawn_position())<30,"Normal generated home spawn remains unchanged")
	var until:=Time.get_ticks_msec()+180000
	while world.custom_port_import_report.code=="waiting_for_generated_geometry" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	_check(world.custom_port_import_report.code=="imported","Main World explicitly imports the whole batch after generated bridge planning")
	if world.custom_port_import_report.code!="imported":
		print("MAIN_WORLD_IMPORT_REPORT ",JSON.stringify(world.custom_port_import_report))
		await _finish()
		return
	var source:=world.get_node("LocalCustomPortImport")
	var streamer:CustomPortStreamer=source.streamer
	_check(PortCatalog.get_custom_port_summaries().size()==2,"Both imported ports appear in passive live directory")
	_check(not PortCatalog.get_port_ids().has("fishing-pier") and not PortCatalog.get_port_ids().has("outlying-pier"),"Generated service/proximity list excludes passive imports")
	_check(PlayerSession.data.owned_vessels==fleet_before,"Imported fixture vessel does not enter captain fleet")
	var chart:=ChartDataSnapshot.from_live_tree(get_tree())
	_check(not chart.preview and chart.port_ids().has("fishing-pier") and chart.port_ids().has("outlying-pier"),"Actual live chart contains both custom ports")
	_check(chart.port_position("fishing-pier")==SITE,"Chart uses exact saved harbour coordinates")
	player.set_process(false)
	player.set_physics_process(false)
	review_camera=Camera3D.new()
	world.add_child(review_camera)
	review_camera.far=30000
	review_camera.global_position=SITE+Vector3(66,48,-62)
	review_camera.look_at(SITE+Vector3(0,0,22),Vector3.UP)
	review_camera.make_current()
	WorldClock.snap_time_of_day(.43)
	WorldClock.set_process(false)
	WeatherLighting.set_process(false)
	WeatherLighting.time_of_day=.43
	WeatherLighting.cloud_cover=.2
	WeatherLighting.precipitation=0
	WeatherLighting.wind_force=.15
	WeatherLighting.sea_state=.08
	until=Time.get_ticks_msec()+90000
	while (streamer.get_presenter("fishing-pier")==null or not world._terrain_streamer.is_custom_port_earthworks_ready()) and Time.get_ticks_msec()<until:await get_tree().process_frame
	var presenter:=streamer.get_presenter("fishing-pier")
	_check(presenter!=null and presenter.placement_nodes.size()==fishing.placements.size(),"Actual World camera streams every saved construction placement")
	_check(presenter!=null and not presenter.simulate_vessels and presenter.vessel_nodes.is_empty(),"Passive main-world port never creates a fixture ship")
	_check(not world._terrain_streamer._custom_earthworks.is_empty(),"Normal world terrain receives construction footprints")
	await _capture("01-imported-fishing-pier")
	var before:=JSON.stringify(streamer.record("fishing-pier"),"",true,true)
	review_camera.global_position=SITE+Vector3(7000,100,7000)
	until=Time.get_ticks_msec()+12000
	while streamer.get_presenter("fishing-pier")!=null and Time.get_ticks_msec()<until:await get_tree().process_frame
	_check(streamer.get_presenter("fishing-pier")==null,"Travel beyond range unloads only physical models")
	_check(JSON.stringify(streamer.record("fishing-pier"),"",true,true)==before,"Distance unloading preserves complete data")
	_check(PortCatalog.get_custom_port_summaries().size()==2,"Distant unloaded harbours remain on chart")
	review_camera.global_position=SITE+Vector3(66,48,-62)
	until=Time.get_ticks_msec()+30000
	while streamer.get_presenter("fishing-pier")==null and Time.get_ticks_msec()<until:await get_tree().process_frame
	_check(streamer.get_presenter("fishing-pier")!=null,"Returning reconstructs saved port in main World")
	var map:=MapOverlay.new()
	add_child(map)
	map.open_navigation()
	var plan:=ChartHarbourPlan.for_port("fishing-pier",get_tree(),map.data)
	map.camera.focus_harbour(plan.centre_world(),240)
	map.camera_initialized=true
	map.first_visible_frame=false
	map.selected_port="fishing-pier"
	map._redraw_geography();map._redraw_contacts()
	_check(plan.custom_construction and plan.foundation_poly.is_empty(),"Live chart uses exact custom outline instead of generated replacement")
	await _capture("02-live-chart-imported-outline")
	map.queue_free()
	for path in original_hashes:_check(FileAccess.get_sha256(path)==original_hashes[path],"Source file remains byte-for-byte unchanged: "+path.get_file())
	await _finish()

func _capture(label:String)->void:
	if RenderingServer.get_rendering_device()==null:return
	var until:=Time.get_ticks_msec()+3500
	while Time.get_ticks_msec()<until:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("custom-port-main-world-%d-%d-%s.png"%[Time.get_unix_time_from_system(),OS.get_process_id(),label])
	_check(get_viewport().get_texture().get_image().save_png(path)==OK,"Native World screenshot archived")
	print("CUSTOM_PORT_MAIN_WORLD_CAPTURE ",path)

func _finish()->void:
	world.queue_free()
	for frame in 8:await get_tree().process_frame
	_check(PortCatalog.get_custom_port_summaries().is_empty(),"Main World teardown leaves no passive directory entries")
	for failure in failures:push_error(failure)
	print("CUSTOM PORT MAIN WORLD ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
