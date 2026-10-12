extends Node3D

var boat:ImportedDraftVessel
var camera:Camera3D
var label:Label
var variant:=0
var angle:=.8
const PATHS=["res://resources/data/vessels/prebuilt/fishing_hook_line.json","res://resources/data/vessels/prebuilt/fishing_crab.json"]
const TITLES=["1 / LINE FISHER — starter\nOpen working deck · manual rod · one catch tank","2 / COASTAL CRABBER — equipment draft\nSheltered deck · side hauler · twelve creels · two tanks\nFuture trawler will use a larger vessel"]

func _ready()->void:
	assert(ShipyardPlaytestMode.active())
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("324955")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-40,0);sun.light_energy=1.5;add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;add_child(camera);camera.current=true
	var canvas:=CanvasLayer.new();add_child(canvas);label=Label.new();label.position=Vector2(24,24);label.add_theme_font_size_override("font_size",22);canvas.add_child(label)
	show_variant(0)
	if OS.get_cmdline_user_args().has("--capture"):review.call_deferred()

func show_variant(index:int)->void:
	variant=index
	if boat!=null:boat.free()
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PATHS[index]))
	boat=ImportedDraftVessel.new();boat.configure(data.get("brick_layout",data));boat.freeze=true;boat.process_mode=Node.PROCESS_MODE_DISABLED;add_child(boat)
	label.text=TITLES[index]+"\n1 / 2: outfits    Arrow keys: orbit    4: deck detail    5: whole boat"

func _process(dt:float)->void:
	angle+=Input.get_axis("ui_left","ui_right")*dt
	camera.position=Vector3(cos(angle)*18,17,sin(angle)*18);camera.look_at(Vector3(0,2.8,1))

func _unhandled_key_input(event:InputEvent)->void:
	if not event.is_pressed():return
	if event is InputEventKey:
		if event.keycode>=KEY_1 and event.keycode<=KEY_2:show_variant(event.keycode-KEY_1)
		if event.keycode==KEY_4:camera.size=10
		if event.keycode==KEY_5:camera.size=20

func review()->void:
	for i in PATHS.size():
		show_variant(i)
		for detail in [false,true]:
			camera.size=11 if detail else 20
			for frame in 15:await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var directory:="C:/Users/noahs/Pictures/machinescreenshots";DirAccess.make_dir_recursive_absolute(directory)
			var path:=directory.path_join("fishing-family-%d-%s-%d.png"%[i+1,"detail" if detail else "whole",Time.get_unix_time_from_system()])
			get_viewport().get_texture().get_image().save_png(path);print("CAPTURE ",path)
	print("FISHING FAMILY REVIEW COMPLETE")
	get_tree().quit()
