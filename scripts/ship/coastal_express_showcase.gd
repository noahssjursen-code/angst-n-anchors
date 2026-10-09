extends Node3D
## Isolated construction review of the same editable arrangement used in Shipyard.
## This is not stock sale/service acceptance; passenger authority comes later.
var boat: ImportedDraftVessel
var camera: Camera3D
var output: String
var title: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest to isolate captain saves")
	WorldClock.set_process(false)
	WorldClock.snap_time_of_day(.5)
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.time_of_day=.5
	WeatherLighting.wind_speed_ms=3
	WeatherLighting.precipitation=0
	WeatherLighting.sea_state=.10
	add_child(preload("res://scripts/world/world_renderer.gd").new())
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_express_recipe.json"))
	if not ImportedShipPartsEditor.valid_draft(recipe):
		var seen:={}
		for part:Dictionary in recipe.parts:
			var single:=recipe.duplicate(true);single.parts=[part]
			if not ImportedShipPartsEditor.valid_draft(single):print("INVALID FERRY PART ",part)
			var key:=ImportedShipPartsEditor.slot_key(part)
			if seen.has(key):print("DUPLICATE FERRY SLOT ",part," ",seen[key])
			seen[key]=part
		get_tree().quit(1)
		return
	boat = ImportedDraftVessel.new()
	boat.configure(recipe)
	boat.freeze=true
	add_child(boat)
	boat.position.y=WaveSurface.WATER_LEVEL-1.55
	var terminal:=preload("res://scenes/port/passenger_terminal.tscn").instantiate()
	terminal.position.y=WaveSurface.WATER_LEVEL+1.65
	add_child(terminal)
	for component in ["StripBuoyancyComponent","StripBuoyancyStarboard","HydrodynamicsComponent","PropulsionComponent","RudderComponent","BowThrusterComponent"]:
		boat.get_node(component).set_physics_process(false)
	camera=Camera3D.new();camera.far=8000;camera.fov=52;camera.near=.06;add_child(camera)
	var ui:=CanvasLayer.new();add_child(ui)
	title=Label.new();title.position=Vector2(20,18);ui.add_child(title)
	title.add_theme_font_size_override("font_size",18)
	view(0)
	output="C:/Users/noahs/Pictures/machinescreenshots/coastal-express-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	if OS.get_cmdline_user_args().has("--capture"):
		for frame in 80:await get_tree().process_frame
		var times: Array[float]=[]
		var previous:=Time.get_ticks_usec()
		for frame in 100:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now
		times.sort()
		var draw_calls:=get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		for i in 8:
			view(i)
			await capture(["bow","side","stern","saloon","bridge","tunnel","terminal","terminal-entrance"][i])
		var seats:=boat.find_children("PassengerSeat*","Node3D",true,false).size()
		var report:={"phase":"construction review", "seat_sockets":seats,"parts":recipe.parts.size(),"frame_median_ms":times[50],"frame_p95_ms":times[95],"resolution":str(get_viewport().get_visible_rect().size),"performance_view":"bow with terminal", "draw_calls":draw_calls}
		var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
		print("FERRY REVIEW ",output," ",JSON.stringify(report))
		if not OS.get_cmdline_user_args().has("--keep-open"):get_tree().quit()

func view(index: int) -> void:
	var eyes := [Vector3(29,17,-38),Vector3(46,10,2),Vector3(-29,15,37),Vector3(0,4.9,10.8),Vector3(0,7.4,-9.8),Vector3(0,1.65,-19.0),Vector3(24,14,-13),Vector3(2,5,-22)]
	var targets := [Vector3(0,4,0),Vector3(0,4,0),Vector3(0,4,1),Vector3(0,4.5,-12),Vector3(0,7.1,-16),Vector3(0,2.4,5),Vector3(0,4,-31),Vector3(0,5,-30.5)]
	camera.position=boat.to_global(eyes[index]);camera.look_at(boat.to_global(targets[index]));camera.make_current()
	title.text="COASTAL EXPRESS  |  36.5 × 11 m  |  construction review"

func capture(label: String) -> void:
	for frame in 20:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label+".png"))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode>=KEY_1 and event.keycode<=KEY_8:view(event.keycode-KEY_1)
