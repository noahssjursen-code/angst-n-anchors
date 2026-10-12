extends Node3D

var _bridge: Node3D
var _camera: Camera3D
var _index := 0
var _angle := 1.35
var _label: Label
var _length := 160.0
const EXAMPLES := [160.0,350.0,700.0,1100.0]

func _ready() -> void:
	_camera=Camera3D.new(); _camera.far=10000; add_child(_camera); _camera.current=true
	var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-38,-35,0); light.shadow_enabled=true; add_child(light)
	var env := WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(.36,.5,.64)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.7,.76,.83); env.environment.ambient_light_energy=.6; add_child(env)
	var water := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(10000,10000)
	water.mesh=plane; water.position.y=WaveSurface.WATER_LEVEL
	var mat := StandardMaterial3D.new(); mat.albedo_color=Color(.045,.16,.21); mat.roughness=.35; water.material_override=mat; add_child(water)
	var ui := CanvasLayer.new(); add_child(ui); _label=Label.new(); _label.position=Vector2(20,20); ui.add_child(_label)
	_select(0)
	if OS.get_cmdline_user_args().has("--capture"): call_deferred("_capture")

func _select(index: int) -> void:
	_index=wrapi(index,0,EXAMPLES.size()); _length=EXAMPLES[_index]
	if _bridge!=null: _bridge.queue_free()
	var plan := BridgeStructurePlan.design({"a_xz":Vector2.ZERO,"b_xz":Vector2(_length,0),"a_ground":10.0,"b_ground":10.0})
	_bridge=BridgeAssembler.build(plan); add_child(_bridge)
	_label.text="NORWEGIAN MODULAR BRIDGES | %s | %.0f m\nSpace: next family | arrows: orbit | Blender modules, shared textured finishes" % [plan.family,_length]
	var distance := maxf(450,_length*1.0)
	_camera.position=Vector3(_length*.5+cos(_angle)*distance,60+_length*.15,sin(_angle)*distance)
	_camera.look_at(Vector3(_length*.5,plan.deck_y,0))

func _process(delta: float) -> void:
	var change := Input.get_axis("ui_left","ui_right")*delta
	if change!=0:
		_angle+=change
		_camera.position=Vector3(_length*.5+cos(_angle)*_length*.7,_length*.32+50,sin(_angle)*_length*.8)
		_camera.look_at(Vector3(_length*.5,25,0))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_SPACE: _select(_index+1)

func _capture() -> void:
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	for i in EXAMPLES.size():
		_select(i)
		for frame in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := folder+"/bridge-kit-%d-%d.png" % [i,Time.get_ticks_usec()]
		get_viewport().get_texture().get_image().save_png(path); print("CAPTURE ",path)
	_camera.position=Vector3(_length*.5,36,22); _camera.look_at(Vector3(_length*.5,29,0))
	for frame in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var close_path := folder+"/bridge-kit-close-%d.png" % Time.get_ticks_usec()
	get_viewport().get_texture().get_image().save_png(close_path); print("CAPTURE ",close_path)
	get_tree().quit()
