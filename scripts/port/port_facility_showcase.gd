extends Node3D

const KINDS := ["office","general","fishing","container","bulk_ore","bulk_grain","diesel","crude_oil","lng"]
var index := 0
var facility: Node3D
var camera: Camera3D
var caption: Label

func _ready() -> void:
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.28,.37,.44)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.75,.82,.93)
	env.environment.ambient_light_energy = .65
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(135,110)
	floor_mesh.mesh = plane
	floor_mesh.material_override = HarbourEnvironmentKit.paving()
	add_child(floor_mesh)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(32,23,-38)
	camera.look_at(Vector3(0,2,0))
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	caption = Label.new()
	caption.position = Vector2(24,80)
	caption.add_theme_font_size_override("font_size",22)
	ui.add_child(caption)
	show_facility()
	if OS.get_cmdline_user_args().has("--verify"): call_deferred("verify")

func show_facility() -> void:
	if is_instance_valid(facility): facility.free()
	var kind: String = KINDS[index]
	var extent := [64,56]
	if kind=="office": extent=[48,48]
	if kind=="container": extent=[64,56]
	if kind in ["lng","diesel","crude_oil"]: extent=[88,64]
	facility = PortFacilityVisual.build(self,{"id":"review_"+kind,"kind":kind,"origin":[0,0],"size_m":extent,"commodity_ids":[]},.025)
	camera.position=Vector3(extent[0]*.7,extent[0]*.48,-extent[0]*.85)
	camera.look_at(Vector3(0,6,0))
	caption.text = "PORT FACILITIES — "+kind.replace("_"," ").to_upper()+"\nLeft / Right: cycle · Space: close view"

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"): index = (index+1)%KINDS.size(); show_facility()
	if event.is_action_pressed("ui_left"): index = posmod(index-1,KINDS.size()); show_facility()
	if event.is_action_pressed("ui_accept"):
		camera.position = Vector3(17,10,-22) if camera.position.y>15 else Vector3(32,23,-38)
		camera.look_at(Vector3(0,3,3))

func verify() -> void:
	assert(ShipyardPlaytestMode.active())
	for i in KINDS.size():
		index=i
		show_facility()
		for frame in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if OS.get_cmdline_user_args().has("--capture"):
			var folder := "C:/Users/noahs/Pictures/machinescreenshots/2026-10-06_harbour-rebuild"
			DirAccess.make_dir_recursive_absolute(folder)
			var path := folder.path_join(str(Time.get_unix_time_from_system()).replace(".","-")+"-precinct-"+KINDS[i]+".png")
			assert(get_viewport().get_texture().get_image().save_png(path)==OK)
			print("CAPTURE ",path)
			camera.position = Vector3(17,10,-22)
			camera.look_at(Vector3(0,3,3))
			for frame in 8: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var close_path := folder.path_join(str(Time.get_unix_time_from_system()).replace(".","-")+"-detail-"+KINDS[i]+".png")
			assert(get_viewport().get_texture().get_image().save_png(close_path)==OK)
			print("CAPTURE ",close_path)
			camera.position = Vector3(32,23,-38)
			camera.look_at(Vector3(0,2,0))
	var light := preload("res://scripts/port/harbour_area_light.gd").new()
	WeatherLighting.time_of_day=.5
	add_child(light)
	assert(not light.visible)
	WeatherLighting.time_of_day=.1
	light._update()
	assert(light.visible)
	WeatherLighting.time_of_day=.5
	print("PORT FACILITY VISUAL PASS families=9 day/night light checked")
	get_tree().quit()
