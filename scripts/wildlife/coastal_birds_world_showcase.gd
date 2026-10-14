extends Node3D
var wildlife: CoastalBirdWorld
var camera: Camera3D
var anchor: Vector3
var time:=0.0
func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("build")
func build() -> void:
	var layout:=WorldLayoutGenerator.generate(42)
	LandField.initialize(layout)
	var record:Dictionary={}
	for x in range(-20,21):
		for z in range(-20,21):
			var candidate:=CoastalBirdHabitat.record(Vector2i(x,z),layout,[])
			if not candidate.is_empty() and candidate.species=="herring_gull":record=candidate;break
		if not record.is_empty():break
	assert(not record.is_empty())
	anchor=record.anchor
	time=300.0
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.position=anchor+Vector3(28,11,35);camera.look_at(anchor);camera.fov=45
	WorldClock.snap_time_of_day(.48);WaveSurface.set_wave_intensity(.3)
	var ocean:=WorldRenderer.new();ocean.enable_weather_post_fx=false;ocean.enable_volumetric_fog=false;add_child(ocean)
	var terrain:=WorldTerrainStreamer.new();add_child(terrain);terrain.configure(layout,[])
	wildlife=CoastalBirdWorld.new();wildlife.configure(layout,[]);wildlife.clock_provider=func():return time
	add_child(wildlife)
	var canvas:=CanvasLayer.new();add_child(canvas)
	var text:=Label.new();text.position=Vector2(25,20);text.text="LIVE COASTAL BIRD COMPONENT | seeded geography + production ocean\nSpace: vessel proximity / gull interest";canvas.add_child(text)
	if OS.get_cmdline_user_args().has("--capture-coastal-world"):call_deferred("capture")
func _process(delta: float) -> void:time+=delta
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE:scare()
func scare() -> void:
	var vessel:=VesselSpawn.instantiate("trawler_hull_14m",JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/fishing_hook_line.json")).brick_layout);vessel.freeze=true;add_child(vessel);vessel.global_position=anchor+Vector3.UP*3.0
func capture() -> void:
	var prefix:="C:/Users/noahs/Pictures/machinescreenshots/coastal-world-"+str(int(Time.get_unix_time_from_system()))
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	await get_tree().create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(prefix+"-rest.png")
	print("BIRD_CAPTURE ",prefix+"-rest.png")
	camera.position=anchor+Vector3(0,65,0.01)
	camera.look_at(anchor)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(prefix+"-overhead.png")
	print("BIRD_CAPTURE ",prefix+"-overhead.png")
	scare()
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(prefix+"-takeoff.png")
	print("BIRD_CAPTURE ",prefix+"-takeoff.png")
	await get_tree().create_timer(13.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(prefix+"-boat-interest.png")
	print("BIRD_CAPTURE ",prefix+"-boat-interest.png")
	for boat in get_tree().get_nodes_in_group("wildlife_vessels"): print("VESSEL_REVIEW ",boat.global_position," expected ",anchor," visible ",boat.visible," meshes ",boat.find_children("*","MeshInstance3D",true,false).size())
	for group in wildlife.groups.values(): print("INTEREST_REVIEW ",group.record.id," ",group.interest_weight)
	wildlife.queue_free()
	await get_tree().create_timer(.15).timeout
	get_tree().quit()
