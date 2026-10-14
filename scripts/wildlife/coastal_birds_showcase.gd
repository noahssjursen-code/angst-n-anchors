extends Node3D
var birds: Array[CoastalGull]=[]
var camera: Camera3D
var elapsed:=0.0
var glide:=true
var angle:=0.6
var zoom:=6.0
var dragging:=false
func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var env:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("405567")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color("dae5f1");settings.ambient_light_energy=.65
	env.environment=settings;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.8;add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;add_child(camera)
	for i in 3:
		var bird:=CoastalGull.new();bird.profile=GullProfile.new()
		bird.profile.species=["herring_gull","white_tailed_eagle","arctic_tern"][i]
		bird.profile.flap_hz=[1.65,.65,3.0][i]
		add_child(bird);bird.position.x=(i-1)*2.0;birds.append(bird)
		var label:=Label3D.new();label.text=["Herring gull","Havørn · white-tailed eagle","Arctic tern"][i];label.position=Vector3((i-1)*2.0,-.6,0);label.font_size=44;label.pixel_size=.003;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(label)
	var canvas:=CanvasLayer.new();add_child(canvas)
	var label:=Label.new();label.text="COASTAL BIRDS · actual size comparison\nDrag to orbit · wheel to zoom · Space: flap / glide";label.position=Vector2(24,22);canvas.add_child(label)
	if OS.get_cmdline_user_args().has("--capture-coastal-birds"):call_deferred("capture")
func _process(delta: float) -> void:
	elapsed+=delta
	for bird in birds: bird.pose(elapsed,1.0 if glide else 0.0)
	camera.size=zoom;camera.position=Vector3(sin(angle)*6,3.5,cos(angle)*6);camera.look_at(Vector3.ZERO)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom=maxf(1,zoom*.9)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom=minf(10,zoom*1.1)
	if event is InputEventMouseMotion and dragging:angle-=event.relative.x*.008
	if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE:glide=not glide
func capture() -> void:
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var prefix:=folder+"/coastal-birds-"+str(int(Time.get_unix_time_from_system()))
	for view in ["comparison","planform"]:
		angle=0.0 if view=="comparison" else 1.3
		await get_tree().create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(prefix+"-"+view+".png")
		print("BIRD_CAPTURE ",prefix+"-"+view+".png")
	get_tree().quit()
