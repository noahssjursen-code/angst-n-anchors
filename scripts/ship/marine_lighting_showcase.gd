extends Node3D

var boat: ImportedDraftVessel
var lights: ShipLighting
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var label: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.set_game_hours_elapsed(0)
	WeatherLighting.time_of_day=0
	var world:=WorldEnvironment.new();environment=Environment.new();world.environment=environment;add_child(world)
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("101924")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("7f91aa");environment.ambient_light_energy=.14
	sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-30,0);sun.light_energy=.035;sun.shadow_enabled=true;add_child(sun)
	boat=_vessel("coastal_trawler_draft",Vector3.ZERO)
	var other:=_vessel("coastal_32m_draft",Vector3(50,0,0))
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=18;add_child(camera)
	camera.position=Vector3(15,14,18);camera.look_at(Vector3(0,3,0));camera.make_current()
	var canvas:=CanvasLayer.new();label=Label.new();label.position=Vector2(24,70);label.add_theme_font_size_override("font_size",20);canvas.add_child(label);add_child(canvas)
	for i in 12:await get_tree().process_frame
	lights=boat.get_node("ShipLighting")
	var other_lights:=other.get_node("ShipLighting") as ShipLighting
	assert(lights._nav_lights.size()==4 and lights._work_lights.size()==2)
	assert(other_lights._nav_lights.size()==4 and other_lights._work_lights.size()==2)
	for fixture: ShipLight in lights._nav_lights+lights._work_lights:
		assert(not fixture.build_housing and fixture._lens_mesh != null and fixture._lens_mat != null)
		assert(fixture._active and fixture._light.visible)
		assert(fixture._lens_mat.emission_enabled)
		if fixture.light_type==ShipLight.LightType.WORK:
			var direction:Vector3=-fixture._light.global_basis.z
			assert(direction.y<-.5,"Flood beam must follow the authored downward lamp face")
	var controller:=boat.get_node("BoatController") as BoatController
	controller.process_mode=Node.PROCESS_MODE_ALWAYS;controller._active=true
	# Real input dispatch through BoatController and existing preset state.
	await _press_l()
	assert(lights.get_preset_name()=="OFF")
	for fixture:ShipLight in lights._nav_lights+lights._work_lights:
		assert(not fixture._active and not fixture._light.visible and not fixture._lens_mat.emission_enabled)
	assert(other_lights.get_preset_name()=="ALL","One boat's switch must not change another vessel")
	var args:=OS.get_cmdline_user_args();var index:=args.find("--capture")
	if index>=0:
		label.text="MARINE LIGHTING / OFF\nSix editable Blender fixtures / normal L switch"
		await _capture(args[index+1].get_basename()+"-off.png")
	await _press_l();assert(lights.get_preset_name()=="NAV")
	assert((lights._nav_lights[0] as ShipLight)._active and not (lights._work_lights[0] as ShipLight)._active)
	await _press_l();assert(lights.get_preset_name()=="WORK")
	assert((lights._work_lights[0] as ShipLight)._active)
	await _press_l();assert(lights.get_preset_name()=="ALL")
	var lamp:=lights._work_lights[0] as ShipLight
	lamp.set_day_scale(.15,.1)
	assert(is_equal_approx(lamp._light.light_energy,lamp._base_energy*.15))
	lamp.set_day_scale(1,1)
	if index>=0:
		label.text="MARINE LIGHTING / NIGHT / ALL\nImported lenses and tilted flood heads / existing lighting control"
		await _capture(args[index+1])
		camera.size=3.7;camera.position=Vector3(-4,7,5);camera.look_at(Vector3(-2.12,5.2,.5))
		label.visible=false
		await _capture(args[index+1].get_basename()+"-fixture.png")
		camera.size=33;camera.position=other.position+Vector3(32,27,-37);camera.look_at(other.position+Vector3(0,3,0))
		await _capture(args[index+1].get_basename()+"-coaster.png")
		WorldClock.set_game_hours_elapsed(12);WeatherLighting.time_of_day=.5
		lights._apply_day_scales()
		assert(lamp._day_scale<.3,"Daytime must damp real fixture output")
		sun.light_energy=1;environment.ambient_light_energy=.6;environment.background_color=Color("263943")
		camera.size=18;camera.position=Vector3(15,14,18);camera.look_at(Vector3(0,3,0))
		await _capture(args[index+1].get_basename()+"-day.png")
	print("LIGHTING PASS: six fixtures per vessel, authored lens/aim, real L presets, off emission, independent ships and daylight energy")
	if index>=0:
		boat.queue_free();other.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _vessel(name_:String,at:Vector3) -> ImportedDraftVessel:
	var result:=ImportedDraftVessel.new()
	result.configure(JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/"+name_+".json")))
	result.freeze=true;result.process_mode=Node.PROCESS_MODE_DISABLED;result.position=at;add_child(result)
	(result.get_node("ShipLighting") as ShipLighting).process_mode=Node.PROCESS_MODE_ALWAYS
	return result

func _press_l() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_L;event.physical_keycode=KEY_L;event.pressed=true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event=InputEventKey.new();event.keycode=KEY_L;event.physical_keycode=KEY_L;event.pressed=false;Input.parse_input_event(event)
	await get_tree().process_frame

func _capture(path:String) -> void:
	for i in 12:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _unhandled_key_input(event:InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
