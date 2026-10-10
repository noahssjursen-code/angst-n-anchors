extends "res://tests/terrain_material_review.gd"
## Actual sourced terrain/paving under identical lighting, plus wet/dry isolation.
var results := {"checks":[],"captures":[]}
var failures: Array[String] = []

func check(ok: bool, description: String) -> void:
	results.checks.append({"ok":ok,"check":description})
	print("WET GROUND ","PASS " if ok else "FAIL ",description)
	if not ok: failures.append(description)

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/wet-ground-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true);WorldClock.set_process(false)
	WorldClock.snap_time_of_day(.44);WeatherLighting.time_of_day=.44
	var state:=WeatherState.new();state.cloud_cover=.94;state.precipitation=.8;state.visibility=.92
	WeatherLighting.apply_weather_state(state)
	var renderer:=WorldRenderer.new();renderer.enable_ocean_system=false;add_child(renderer)
	renderer.set_process(false) # Freeze lighting/clouds; compare only surface response.
	camera=Camera3D.new();camera.fov=58;add_child(camera);camera.make_current()
	material=ShaderMaterial.new();material.shader=load("res://resources/shaders/terrain.gdshader")
	TerrainSurfaceMaps.bind_to_material(material,90210)
	label=Label.new();add_child(label);label.hide()
	_contracts()
	for variant in 3:
		kind=variant;show_surface()
		await pair(["bedrock","heath","woodland-soil"][variant],eye(false),target())
		if variant==1:
			# Far material matches at the handover, not just independently at origin.
			ground.scale=Vector3(20,1,20)
			await pair("heath-near-lod",Vector3(0,85,680),target())
			material.shader=load("res://resources/shaders/terrain_far.gdshader")
			TerrainSurfaceMaps.bind_to_material(material,90210)
			await pair("heath-far-lod",Vector3(0,85,680),target())
			material.shader=load("res://resources/shaders/terrain.gdshader")
			ground.scale=Vector3.ONE
	for profile in ["quay","asphalt","crushed_aggregate","deck_grip"]:
		ground.free();ground=MeshInstance3D.new()
		var slab:=PlaneMesh.new();slab.size=Vector2(80,80);ground.mesh=slab
		ground.material_override=HarbourEnvironmentKit.paving() if profile=="quay" else SurfaceMaterialLibrary.material(profile,Color(.34,.36,.37),"",null,profile!="deck_grip")
		add_child(ground)
		await pair(profile,Vector3(2,1.7,7),Vector3(0,0,-4))
	results.failures=failures
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("WET GROUND REPORT ",output," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func target() -> Vector3:
	return Vector3(0,2.9 if kind==0 else 30,0)

func pair(name: String, position: Vector3, aim: Vector3) -> void:
	for value in [0.0,1.0]:
		SurfaceWetness.set_amount(value)
		var tag:=name+("-dry" if value==0 else "-wet")
		await shot(tag,position,aim)
		results.captures.append(tag)

func _contracts() -> void:
	SurfaceWetness.set_amount(0)
	var indoor:=SurfaceMaterialLibrary.material("asphalt",Color.WHITE)
	var outdoor:=SurfaceMaterialLibrary.material("asphalt",Color.WHITE,"",null,true)
	check(indoor!=outdoor,"sheltered and exposed finish caches are separate")
	SurfaceWetness.advance(.8,1.0/60)
	check(SurfaceWetness.amount>0 and SurfaceWetness.amount<.002,"rain onset does not pop to wet")
	for tick in 480: SurfaceWetness.advance(.8,.125)
	var damp:=SurfaceWetness.amount
	check(damp>.95,"sustained rain saturates exposed ground")
	check(float(outdoor.get_shader_parameter("rain_wetness"))>.95,"existing exposed finish follows rain")
	check(float(indoor.get_shader_parameter("rain_wetness"))==0,"same sheltered finish stays dry")
	var late:=SurfaceMaterialLibrary.material("crushed_aggregate",Color(.6,.6,.6),"",null,true)
	check(is_equal_approx(float(late.get_shader_parameter("rain_wetness")),damp),"new streamed finish starts at current wetness")
	SurfaceWetness.advance(0,1)
	check(SurfaceWetness.amount>damp*.99,"clearing weather retains wet ground")
	for tick in 240:SurfaceWetness.advance(0,1)
	check(SurfaceWetness.amount<.4 and SurfaceWetness.amount>.3,"ground dries gradually over several minutes")
	SurfaceWetness.set_amount(0);SurfaceWetness.advance(.8,30);var coarse:=SurfaceWetness.amount
	SurfaceWetness.set_amount(0)
	for tick in 240:SurfaceWetness.advance(.8,.125)
	check(is_equal_approx(SurfaceWetness.amount,coarse),"wetting independent of frame rate")
