extends Node3D

const SURVEY := "C:/Users/noahs/Documents/Codex/2026-10-11/referenced-chatgpt-conversation-this-is-an/outputs/custom-port-site.json"
const Library := preload("res://scripts/port/building/custom_harbour_asset_library.gd")
var camera: Camera3D
var frame: Node3D
var label: Label
var layout: WorldLayout

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	WorldClock.snap_time_of_day(.45)
	WorldClock.set_process(false)
	WeatherLighting.set_process(false)
	WeatherLighting.time_of_day=.45
	WeatherLighting.cloud_cover=.2
	WeatherLighting.precipitation=0
	WeatherLighting.wind_force=.15
	WeatherLighting.sea_state=.08
	layout=WorldLayoutGenerator.generate(73119,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	LandField.initialize(layout)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SURVEY))
	var selected: Dictionary = data.selected
	frame=Node3D.new()
	frame.position=Vector3(selected.origin_xz[0],.5,selected.origin_xz[1])
	frame.rotation.y=deg_to_rad(float(selected.rotation_y_degrees))
	add_child(frame)
	camera=Camera3D.new()
	camera.far=16000
	camera.fov=52
	add_child(camera)
	_aim(Vector3(125,105,-145),Vector3(0,0,28))
	var renderer:=WorldRenderer.new()
	renderer.enable_ssil=false
	renderer.enable_weather_post_fx=false
	renderer.enable_volumetric_fog=false
	add_child(renderer)
	var terrain:=WorldTerrainStreamer.new()
	terrain.visual_radius_m=6500
	terrain.collision_radius_m=0
	terrain.build_budget_ms=10
	terrain.max_jobs_per_frame=3
	terrain.begin_boot_priority(frame.position)
	add_child(terrain)
	terrain.configure(layout)
	_deck(Vector3(0,0,32),Vector2(144,64))
	_deck(Vector3(8,0,66),Vector2(4,4))
	for i in 36:_asset("quay_edge_4m",Vector3(-70+i*4,0,0))
	for x in [-64,-40,-16,16,40,64]:
		_asset("tractor_tire_fender",Vector3(x,0,0))
		_asset("quay_bollard",Vector3(x,0,1))
	_asset("quay_ladder",Vector3(0,0,0))
	_asset("lifering_station",Vector3(-2,0,1.2),180)
	for x in [-66,66]:_asset("quay_light",Vector3(x,0,58))
	for x in [-58,-54]:
		_asset("workshop_window_4m",Vector3(x,0,46))
		_asset("workshop_wall_4m",Vector3(x,0,54),180)
		for z in [48,52]:_asset("workshop_roof_4m",Vector3(x,0,z))
	for z in [48,52]:
		_asset("workshop_wall_4m",Vector3(-60,0,z),90)
	_asset("workshop_open_bay_4m",Vector3(-52,0,48),-90)
	_asset("workshop_door_4m",Vector3(-52,0,52),-90)
	for x in [-48,-46]:_asset("timber_bundle",Vector3(x,0,52))
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	label=Label.new()
	label.position=Vector2(24,20)
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y",2)
	label.text="ACTUAL ISLAND SITE · 144 × 64 m · Sea +2 m\nUnmodified terrain · 25.5 m minimum sampled approach depth · One 200 m coastal plot"
	canvas.add_child(label)
	var deadline:=Time.get_ticks_msec()+60000
	while not terrain.is_ready_around(frame.position,1000) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(terrain.is_ready_around(frame.position,1000))
	for i in 120:await get_tree().process_frame
	await _capture("island-overview")
	_aim(Vector3(75,34,-55),Vector3(10,0,45))
	await _capture("natural-shore-connection")
	_aim(Vector3(8,5,57),Vector3(8,.5,74))
	await _capture("access-detail")
	print("CUSTOM PORT SITE NATIVE REVIEW PASS")
	get_tree().quit()

func _deck(centre: Vector3,size: Vector2) -> void:
	# Survey placeholder only. Actual construction records belong to the builder.
	var geometry:=BoxMesh.new()
	geometry.size=Vector3(size.x,32,size.y)
	var mesh:=MeshInstance3D.new()
	mesh.mesh=geometry
	mesh.position=centre+Vector3(0,-16,0)
	mesh.material_override=SurfaceMaterialLibrary.material("working_concrete",Color("71766f"))
	frame.add_child(mesh)
	SurfaceMaterialLibrary.map_frame(mesh)

func _asset(id:String,at:Vector3,yaw:float=0) -> void:
	var item:=Library.instantiate(id,false)
	item.position=at
	item.rotation_degrees.y=yaw
	frame.add_child(item)

func _aim(at:Vector3,target:Vector3) -> void:
	camera.position=frame.to_global(at)
	camera.look_at(frame.to_global(target))

func _capture(description:String) -> void:
	for i in 40:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("custom-port-site-"+str(Time.get_unix_time_from_system()).replace(".","-")+"-"+description+".png")
	assert(get_viewport().get_texture().get_image().save_png(path)==OK)
	print("CAPTURE ",path)
