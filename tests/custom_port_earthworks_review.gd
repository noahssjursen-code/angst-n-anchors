extends Node3D

## Native collision and appearance review on real seeded steep coast terrain.
## Isolated from captain saves; run with --shipyard-playtest.
const ProjectionData = preload("res://scripts/port/state/custom_port_earthworks.gd")
const PLAYER = preload("res://scenes/shared/player.tscn")
var terrain: WorldTerrainStreamer
var presenter: CustomPortPresenter
var camera := Camera3D.new()
var player: CharacterBody3D
var site := Vector3(2712,.5,-264)
var checks := 0
var failures: Array[String] = []
var capture_prefix := ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	WorldClock.snap_time_of_day(.43)
	WorldClock.set_process(false)
	WorldWeather.set_process(false)
	WeatherLighting.time_of_day=.43
	capture_prefix="C:/Users/noahs/Pictures/machinescreenshots/custom-port-earthworks-%d-%d"%[Time.get_unix_time_from_system(),OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(capture_prefix.get_base_dir())
	var layout:=WorldLayoutGenerator.generate(73119,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	var world:={"seed":layout.seed,"generation_version":WorldLayoutGenerator.GENERATION_VERSION,"checksum":layout.layout_checksum}
	var renderer:=WorldRenderer.new()
	renderer.enable_ocean_system=false
	renderer.enable_ssil=false
	renderer.enable_weather_post_fx=false
	renderer.enable_volumetric_fog=false
	add_child(renderer)
	var record:={"schema_version":1,"id":"steep-coast-review","name":"Steep coast construction","owner_company_id":CustomPortExample.OWNER,"revision":0,"world":world,
		"origin_m":[site.x,site.y,site.z],"deck_height_above_sea_m":2,"placements":[],"stores":[],"vessels":[],"reservations":[],"receipts":{},"water_regions":[],
		"plots":[{"id":"coast:13:-2","rect_m":[-112,-136,200,200],"owner_company_id":CustomPortExample.OWNER}]}
	for x in range(-12,13,4):
		for z in range(-12,13,4):
			# A central untouched patch and a real angled corner exercise topology.
			if x==8 and z==8:continue
			var asset:="foundation_triangle_4m" if x==12 and z==-12 else "foundation"
			record.placements.append({"id":"tile-%d-%d"%[x,z],"asset_id":asset,"position_m":[x,0,z],"yaw_degrees":0,"attributes":{"support_depth_m":4}})
	var state:=CustomPortState.from_dict(record,world,CustomPortCatalog.definitions())
	_check(state.validation_errors.is_empty(),"Native steep-coast fixture is a valid full port document: "+str(state.validation_errors))
	record=state.to_dict()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port-export="):
			var target:=argument.trim_prefix("--port-export=")
			var file:=FileAccess.open(target,FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify(record,"\t",true,true));file.close()
			print("STEEP_PORT_EXPORT ",target)
	if OS.get_cmdline_user_args().has("--port-export-only"):
		camera.free()
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	presenter=CustomPortPresenter.new()
	add_child(presenter)
	presenter.load_record(record)
	add_child(camera)
	camera.far=12000
	camera.position=site+Vector3(-38,38,-42)
	camera.look_at(site+Vector3(0,6,0))
	camera.current=true
	terrain=WorldTerrainStreamer.new()
	terrain.visual_radius_m=1000
	terrain.collision_radius_m=800
	add_child(terrain)
	terrain.begin_boot_priority(site)
	terrain.set_custom_port_earthworks([ProjectionData.project(record,CustomPortCatalog.definitions())])
	terrain.configure(layout)
	var timeout:=Time.get_ticks_msec()+30000
	while not terrain.is_ready_around(site,220) and Time.get_ticks_msec()<timeout: await get_tree().process_frame
	_check(terrain.is_ready_around(site,220),"Initial terrain and collision with cuts become ready")
	terrain.set_process(false)
	player=PLAYER.instantiate()
	player.position=site+Vector3(-10,.1,-10)
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	camera.current=true
	for frame in 3:await get_tree().physics_frame
	var deck_hit:=_ray(site+Vector3(0,30,0),site-Vector3.UP*5)
	_check(not deck_hit.is_empty() and absf(deck_hit.position.y-site.y)<.02,"Real physics ray lands on foundation, not former 12m hillside")
	var hole_hit:=_ray(site+Vector3(8,40,8),site+Vector3(8,-5,8))
	_check(not hole_hit.is_empty() and hole_hit.position.y>10,"Unbuilt central hole retains original hill collision")
	var outside_hit:=_ray(site+Vector3(14.05,40,0),site+Vector3(14.05,-5,0))
	_check(not outside_hit.is_empty() and outside_hit.position.y>10,"Terrain five centimetres outside built footprint remains untouched")
	await _walk(Vector3(-10,.05,-10),Vector3(10,0,-10),"twenty metres across cleared foundations",true)
	await _walk(Vector3(10,.05,0),Vector3(16,0,0),"retaining wall boundary",false)
	_check(player.position.x < site.x+13.8,"Actual player collides with retaining wall instead of walking through hillside")
	player.position=site+Vector3(-3,.05,-2)
	player.velocity=Vector3.ZERO
	camera.position=site+Vector3(-34,34,-36)
	camera.look_at(site+Vector3(0,5,0))
	await _capture("overview")
	camera.position=site+Vector3(-10,2,-10)
	camera.look_at(site+Vector3(4,3,8))
	await _capture("deck-and-retaining-walls")
	camera.position=site+Vector3(18,24,20)
	camera.look_at(site+Vector3(8,8,8))
	await _capture("untouched-hole")
	# Remove all foundations/cuts and rebuild the same loaded terrain. The former
	# deck point must again hit the original hill collider.
	presenter.load_record({"origin_m":record.origin_m,"placements":[],"stores":[],"vessels":[]})
	terrain.set_custom_port_earthworks([])
	_check(not terrain.is_custom_port_earthworks_ready(),"Undo waits for replacement collision")
	timeout=Time.get_ticks_msec()+30000
	while not terrain.is_custom_port_earthworks_ready() and Time.get_ticks_msec()<timeout:
		terrain._process_jobs(site)
		await get_tree().process_frame
	for frame in 3:await get_tree().physics_frame
	var restored:=_ray(site+Vector3(0,40,0),site-Vector3.UP*5)
	_check(not restored.is_empty() and restored.position.y>10,"Removing foundations restores original real hill collision")
	camera.position=site+Vector3(-34,34,-36)
	camera.look_at(site+Vector3(0,5,0))
	player.hide()
	await _capture("undo-restored-coast")
	print("CUSTOM_PORT_EARTHWORKS_NATIVE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _walk(start:Vector3,finish:Vector3,label:String,arrive:bool)->void:
	player.position=site+start
	player.velocity=Vector3.ZERO
	player._air_deck=null
	player.reset_physics_interpolation()
	var direction:=(finish-start)*Vector3(1,0,1)
	var yaw:=atan2(-direction.x,-direction.z)
	player.rotation.y=yaw
	var player_camera:Node=player.get_node("PlayerCamera")
	player_camera.shift_look_yaw(yaw-player_camera.get_look_yaw())
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for frame in 24:
		await get_tree().physics_frame
		player._physics_process(1.0/60.0)
	Input.action_press("move_forward")
	for frame in 500:
		await get_tree().physics_frame
		player._physics_process(1.0/60.0)
		if ((site+finish-player.position)*Vector3(1,0,1)).length()<.3:break
	Input.action_release("move_forward")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var error:=((site+finish-player.position)*Vector3(1,0,1)).length()
	print("EARTHWORK_WALK ",label," error=",error," position=",player.position-site)
	if arrive:_check(error<.4 and player.is_on_floor(),"Actual player walks "+label)

func _ray(from:Vector3,to:Vector3)->Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,[player.get_rid()]))

func _capture(label:String)->void:
	for frame in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path:=capture_prefix+"-"+label+".png"
	var error:=get_viewport().get_texture().get_image().save_png(path)
	print("EARTHWORK_CAPTURE ",path," status=",error)

func _check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures.append(text);push_error(text)
