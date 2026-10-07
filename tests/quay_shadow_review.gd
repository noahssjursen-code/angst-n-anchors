extends Node3D
## Diagnostic only: deliberately includes rejected blur and omnidirectional variants.
## Run with -- --shipyard-playtest; compare D3D12 and --rendering-driver vulkan.
var camera: Camera3D
var lamp: SpotLight3D
var output: String
func _ready() -> void:call_deferred("review")
func capture(tag:String) -> void:
	for frame in 45:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(output.path_join(tag+".png"))==OK)
	print("CAPTURE ",output.path_join(tag+".png"))
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/quay-shadow-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(0);WeatherLighting.time_of_day=0
	WeatherLighting.cloud_cover=.2;WeatherLighting.precipitation=0;WeatherLighting.convection_index=0;WeatherLighting.visibility=1
	var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env
	env.background_mode=Environment.BG_COLOR;env.background_color=Color(.012,.016,.022)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.4,.5,.7);env.ambient_light_energy=.15
	add_child(environment)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(70,70);ground.mesh=plane;ground.material_override=HarbourEnvironmentKit.paving();add_child(ground)
	var root:=HarbourEnvironmentKit.model(self,"quay_light",Vector3.ZERO)
	for child in root.find_children("*","SpotLight3D",true,false):lamp=child
	assert(lamp!=null)
	# Controlled one-metre and two-metre occluders measure contact vs remote penumbra.
	for i in 3:
		var object:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.4,1.0+i*.5,.4);object.mesh=box
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.28,.32,.34);object.material_override=mat
		add_child(object);object.position=Vector3(-3+i*3,box.size.y*.5,-3)
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.position=Vector3(7,4,12);camera.look_at(Vector3(0,1,0))
	if OS.get_cmdline_user_args().has("--gi-review"):
		await capture("gi-before")
		for mesh in find_children("*","MeshInstance3D",true,false):
			mesh.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		lamp.light_indirect_energy=1.0
		env.sdfgi_min_cell_size=.25
		env.sdfgi_cascades=4
		env.sdfgi_enabled=true
		for frame in 180:await get_tree().process_frame
		await capture("gi-after")
		print("GI DIAGNOSTIC COMPLETE")
		get_tree().quit()
		return
	for variant in ["current","point","large","blur","no-shadow"]:
		lamp.light_size=0.0 if variant=="point" else (2.0 if variant=="large" else .65)
		lamp.shadow_blur=8.0 if variant=="blur" else 2.0
		lamp.shadow_enabled=variant!="no-shadow"
		await capture(variant)
	lamp.shadow_enabled=true
	lamp.light_size=.35
	lamp.shadow_blur=32.0
	await capture("diffuser-filter32")
	lamp.shadow_blur=64.0
	await capture("diffuser-filter64")
	lamp.light_size=0.0
	lamp.shadow_blur=8.0
	await capture("pcf-filter8")
	lamp.set_process(false)
	lamp.visible=false
	var omni:=OmniLight3D.new()
	add_child(omni)
	omni.global_position=lamp.global_position
	omni.light_color=lamp.light_color
	omni.light_energy=20.0
	omni.omni_range=32.0
	omni.omni_attenuation=1.0
	omni.light_size=.35
	omni.shadow_enabled=true
	omni.shadow_bias=.03
	omni.shadow_normal_bias=.25
	await capture("omni-diffuser")
	omni.light_size=.65
	await capture("omni-large")
	print("QUAY SHADOW DIAGNOSTIC COMPLETE: captures are comparisons, not art acceptance")
	get_tree().quit()
