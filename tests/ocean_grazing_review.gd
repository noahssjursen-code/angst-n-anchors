extends "res://tests/ocean_transmission_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(120).timeout.connect(func():get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/ocean-grazing-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.5);WeatherLighting.time_of_day=.5
	WeatherLighting.cloud_cover=.85;WeatherLighting.precipitation=0
	WeatherLighting.visibility=1;WeatherLighting.sea_state=.55;WeatherLighting.wind_force=.6
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.far=12000
	camera.position=Vector3(10,4,8);camera.look_at(Vector3(0,0,-22))
	renderer=WorldRenderer.new();add_child(renderer)
	var boat:=VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record("fishing")) as ImportedDraftVessel
	boat.freeze=true;add_child(boat);boat.position=Vector3(0,WaveSurface.WATER_LEVEL-boat.draft_m,-22)
	await get_tree().create_timer(8).timeout
	renderer._fft_system.set_process(false);renderer.set_process(false)
	var surface_y:=WaveSurface.sample_at(camera.position.x,camera.position.z).height
	print("REFERENCE SURFACE ",surface_y," mean=",WaveSurface.WATER_LEVEL)
	for offset in [1.0,.3,.05,-.05,-.3]:
		camera.position.y=surface_y+offset
		camera.look_at(camera.position+Vector3(-10,-.5,-30))
		renderer._update_underwater_effect()
		await capture("surface-offset-"+str(offset))
	camera.position.y=surface_y+.3
	camera.look_at(camera.position+Vector3(-10,-.5,-30))
	renderer._update_underwater_effect()
	await capture("comparison-normal")
	renderer._ocean_shader_material.set_shader_parameter("transmission_strength",0.0)
	await capture("comparison-no-transmission")
	renderer._ocean_shader_material.set_shader_parameter("transmission_strength",1.0)
	camera.near=.005
	await capture("comparison-near-5mm")
	camera.near=.05
	var near_original:Shader=renderer._ocean_shader_material.shader
	var geometric:=Shader.new()
	geometric.code=near_original.code.replace("vec3 nm = normalize(vec3(-fine_slope.x * v_amplitude, 1.0, -fine_slope.y * v_amplitude));","vec3 nm = normalize(v_world_normal);")
	renderer._ocean_shader_material.shader=geometric
	await capture("comparison-no-pixel-normal-detail")
	renderer._ocean_shader_material.shader=near_original
	var materials:Array[ShaderMaterial]=[renderer._ocean_shader_material,renderer._ocean_mid_material,renderer._ocean_far_material,renderer._ocean_horizon_material]
	var originals:Array[Shader]=[]
	for material in materials:
		originals.append(material.shader)
		var source:=material.shader.code
		source=source.replace('#include "res://resources/shaders/ocean_lod_surface.gdshaderinc"',FileAccess.get_file_as_string("res://resources/shaders/ocean_lod_surface.gdshaderinc"))
		var fragment:=source.find("void fragment()")
		assert(fragment>=0)
		source=source.substr(0,fragment)+"void fragment() { ALBEDO=vec3(0.0); EMISSION=FRONT_FACING ? vec3(1.0,.05,.4) : vec3(.05,1.0,1.0); }"
		var diagnostic:=Shader.new();diagnostic.code=source;material.shader=diagnostic
	await capture("comparison-face-orientation")
	for offset in [.05,-.05,-.3]:
		camera.position.y=surface_y+offset
		renderer._update_underwater_effect()
		await capture("faces-surface-offset-"+str(offset))
	for i in materials.size():materials[i].shader=originals[i]
	camera.position.y=surface_y+.3
	renderer._update_underwater_effect()
	# Same fixed camera and simulation, opposite headings distinguish local
	# clipping from a particular sun/specular direction.
	for heading in [90.0,180.0]:
		camera.rotation_degrees=Vector3(-1,heading,0)
		await capture("heading-"+str(int(heading)))
	print("GRAZING REVIEW COMPLETE ",output)
	get_tree().quit()
