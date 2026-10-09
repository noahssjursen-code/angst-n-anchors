extends Node3D
## Isolated inspect scene for the exact editable stock vessel. C toggles real
## cargo, 1/2/3 select bow / stern / bridge views; F6 never writes captain saves.
var boat: ImportedDraftVessel
var camera: Camera3D
var title: Label
var laden := false
var output := ""

func _ready() -> void:
	WorldClock.set_process(false)
	WorldClock.snap_time_of_day(.5)
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.time_of_day=.5
	WeatherLighting.wind_speed_ms=3
	WeatherLighting.precipitation=0
	WeatherLighting.sea_state=.12
	var renderer := preload("res://scripts/world/world_renderer.gd").new()
	add_child(renderer)
	var p: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/container_feeder_40.json"))
	boat=VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({"uid":"feeder-review","name":p.name,"hull_id":p.hull_id,"brick_layout":p.brick_layout}))
	boat.freeze=true
	add_child(boat)
	boat.position.y=WaveSurface.WATER_LEVEL-3.3
	for component in ["StripBuoyancyComponent","HydrodynamicsComponent","PropulsionComponent","RudderComponent","BowThrusterComponent"]:
		boat.get_node(component).set_physics_process(false)
	camera=Camera3D.new();camera.far=8000;camera.fov=48;add_child(camera)
	var ui:=CanvasLayer.new();add_child(ui)
	title=Label.new();title.position=Vector2(24,24);ui.add_child(title)
	title.add_theme_font_size_override("font_size",20)
	view(0)
	output="C:/Users/noahs/Pictures/machinescreenshots/feeder-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	if OS.get_cmdline_user_args().has("--capture"):
		for i in 80: await get_tree().process_frame
		await capture("empty-bow")
		toggle_cargo()
		var samples: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame in 120:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous=now
		samples.sort()
		print("FEEDER RENDER loaded forty: median_frame_ms=",samples[60]," p95_ms=",samples[114]," resolution=",get_viewport().get_visible_rect().size," draw_calls=",get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		await capture("loaded-bow")
		view(1);await capture("loaded-stern")
		view(2);await capture("bridge")
		view(3);await capture("deck-walkway")
		view(4);await capture("helm")
		print("FEEDER CAPTURES ",output)
		if not OS.get_cmdline_user_args().has("--keep-open"):get_tree().quit()

func toggle_cargo() -> void:
	laden=not laden
	# Frozen inspection pose uses the measured free-floating equilibrium draft.
	boat.position.y=WaveSurface.WATER_LEVEL-(3.97 if laden else 3.3)
	for i in boat.get_cargo_pads().size():
		var pad:=boat.get_cargo_pads()[i]
		if laden:pad.add_container(ContainerUnit.create("review-%d"%i,"provisions",20000))
		else:pad.clear_all()
	title.text="NORTHLINE 40  |  88 × 14 m  |  %s\n1–5 Views · C Load/unload"%("40 × 20 ft / 800 t review load" if laden else "Empty deck")

func view(index: int) -> void:
	var eyes := [Vector3(55,32,-65),Vector3(-45,28,69),Vector3(21,20,57),Vector3(6,7,31),Vector3(-2,11.6,38)]
	var targets := [Vector3(0,5,0),Vector3(0,7,14),Vector3(0,10,38),Vector3(5.5,6,-20),Vector3(0,11,34)]
	camera.position=boat.to_global(eyes[index])
	camera.look_at(boat.to_global(targets[index]))
	camera.make_current()
	title.text="NORTHLINE 40  |  88 × 14 m\n1–5 Views · C Load/unload"

func capture(label: String) -> void:
	for i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label+".png"))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode>=KEY_1 and event.keycode<=KEY_5:view(event.keycode-KEY_1)
		if event.keycode==KEY_C:toggle_cargo()
