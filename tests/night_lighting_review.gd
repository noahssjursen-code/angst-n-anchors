extends "res://scripts/port/port_showcase.gd"

var review_boat: ImportedDraftVessel
var output: String

func _ready() -> void:
	super._ready()
	call_deferred("review")

func capture_review(tag: String) -> Image:
	for frame in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var path := output.path_join(tag+".png")
	assert(picture.save_png(path)==OK)
	print("CAPTURE ",path)
	return picture

func weather(fog: bool) -> void:
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(0.0)
	WeatherLighting.time_of_day=0.0
	WeatherLighting.cloud_coverage=.2
	WeatherLighting.rain_amount=0
	WeatherLighting.storm_intensity=0
	WeatherLighting.visibility=.3 if fog else 1.0
	WeatherLighting.sea_state=.15
	var renderer := get_node("ShowcaseWorldRenderer")
	renderer.enable_volumetric_fog=true
	renderer._apply_weather_lighting()
	for node in find_children("*","SpotLight3D",true,false):
		if node.get_script()==preload("res://scripts/port/harbour_area_light.gd"): node._update()

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/night-lighting-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 120: await get_tree().process_frame
	get_node("HudLayer").hide()
	weather(false)
	var visual := get_node("GeneratedPort/PortPlot/PortLayoutGraph")
	var terminals := []
	for node in visual.find_children("*","Node3D",true,false):
		if node.has_meta("review_walk_spawn"): terminals.append(node)
	assert(not terminals.is_empty())
	var terminal: Node3D=terminals[0]
	var pole: Node3D
	for node in visual.find_children("*","SpotLight3D",true,false):
		pole=node
		break
	assert(pole!=null)
	_camera.global_position=pole.global_position+Vector3(13,3,16)
	_camera.look_at(pole.global_position+Vector3(0,-5,0))
	await capture_review("quay-clear")
	weather(true)
	await capture_review("quay-fog")
	review_boat=ImportedDraftVessel.new()
	var vessel_id := "fishing_trawler"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vessel="): vessel_id=arg.get_slice("=",1)
	var stock: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/"+vessel_id+".json"))
	review_boat.configure(stock.brick_layout)
	review_boat.freeze=true
	review_boat.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(review_boat)
	var lighting := review_boat.get_node("ShipLighting") as ShipLighting
	lighting.process_mode=Node.PROCESS_MODE_ALWAYS
	var shore := terminal.to_global(Vector3(float(terminal.get_meta("deck_half_w",22))+14,0,0))
	shore.y=WaveSurface.WATER_LEVEL-review_boat.draft_m
	for location in ["shore","offshore"]:
		review_boat.global_position=shore if location=="shore" else shore+terminal.global_basis*Vector3(0,0,-600)
		_camera.global_position=review_boat.global_position+Vector3(18,13,22)*maxf(1,review_boat.length_m/18.0)
		_camera.look_at(review_boat.global_position+Vector3(0,3,0))
		for fog in [false,true]:
			weather(fog)
			lighting._preset=ShipLighting.Preset.ALL
			lighting._apply_preset()
			lighting._apply_day_scales()
			var lit := await capture_review(location+("-fog" if fog else "-clear")+"-all")
			lighting._preset=ShipLighting.Preset.OFF
			lighting._apply_preset()
			var unlit := await capture_review(location+("-fog" if fog else "-clear")+"-off")
			var difference := surface_difference(lit,unlit)
			print("DECK LIGHT RESPONSE ",location," fog=",fog," delta=",difference)
			assert(difference>.008,"Deck must receive real light with and without fog")
	weather(false)
	review_boat.global_position=shore
	lighting._preset=ShipLighting.Preset.ALL
	lighting._apply_preset()
	_camera.global_position=shore+Vector3(11,8,13)*maxf(1,review_boat.length_m/18.0)
	_camera.look_at(shore+Vector3(0,3,0))
	await capture_review("shore-clear-close")
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day=.5
	get_node("ShowcaseWorldRenderer")._apply_weather_lighting()
	lighting._apply_day_scales()
	await capture_review("shore-daylight-close")
	# Keep fixture coverage observable on the actual starter, not an incomplete draft.
	print("REVIEW VESSEL ",vessel_id," fixtures=",lighting._nav_lights.size()+lighting._work_lights.size())
	print("NIGHT REVIEW COMPLETE ",output)
	get_tree().quit()

func surface_difference(a: Image,b: Image) -> float:
	# Central deck ROI excludes the masthead/navigation lenses; compare actual
	# lit surfaces, not just a bright bulb against a dark background.
	var center := _camera.unproject_position(review_boat.global_position+Vector3(0,review_boat.depth_m,review_boat.length_m*.22))
	var total := 0.0
	var count := 0
	for x in range(int(center.x)-50,int(center.x)+50):
		for y in range(int(center.y)-12,int(center.y)+35):
			total+=maxf(0,a.get_pixel(x,y).get_luminance()-b.get_pixel(x,y).get_luminance())
			count+=1
	return total/count
