extends "res://tests/ocean_transmission_review.gd"

var maps: Array[Image] = []
var readback_done := false

func read_maps() -> void:
	var rd := RenderingServer.get_rendering_device()
	for i in 4:
		maps.append(Image.create_from_data(512,512,false,Image.FORMAT_RGBAF,rd.texture_get_data(renderer._fft_system.displacement_tex,i)))
	readback_done = true

func sample_map(p: Vector2, layer: int) -> Vector3:
	var scales: Array[float] = [1024.0,64.0,16.0,4.0]
	var uv := p / scales[layer] * 512.0 - Vector2(.5,.5)
	var x := floori(uv.x); var y := floori(uv.y)
	var a := maps[layer].get_pixel(posmod(x,512),posmod(y,512)).lerp(maps[layer].get_pixel(posmod(x+1,512),posmod(y,512)),uv.x-x)
	var b := maps[layer].get_pixel(posmod(x,512),posmod(y+1,512)).lerp(maps[layer].get_pixel(posmod(x+1,512),posmod(y+1,512)),uv.x-x)
	var c := a.lerp(b,uv.y-y)
	return Vector3(c.r,c.g,c.b)

func measure(amplitude: float, old_chop: bool) -> int:
	var folds := 0
	var ends := [5500.0,1536.0,384.0,96.0]
	for mesh: MeshInstance3D in renderer._ocean_clipmap.get_children():
		var arrays := mesh.mesh.surface_get_arrays(0)
		var targets: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var displaced := PackedVector3Array()
		for p in targets:
			var world := p + Vector2(renderer._ocean_clipmap.position.x,renderer._ocean_clipmap.position.z)
			var distance := world.distance_to(Vector2(camera.position.x,camera.position.z))
			var d := Vector3.ZERO
			for layer in 4: d += sample_map(world,layer) * (1.0-smoothstep(ends[layer]*.75,ends[layer],distance))
			displaced.append(Vector3(world.x,0,world.y)+(d if old_chop else Vector3(0,d.y,0))*amplitude)
		for i in range(0,indices.size(),3):
			var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
			var base := (targets[b]-targets[a]).cross(targets[c]-targets[a])
			if absf(base)<.0001:continue
			if (displaced[b]-displaced[a]).cross(displaced[c]-displaced[a]).y>0:
				folds+=1
				if not old_chop: print("BASE FOLD ",mesh.name," ",targets[a]," ",targets[b]," ",targets[c])
	print("FOLD COUNT old_chop=",old_chop," amplitude=",amplitude," inverted=",folds)
	return folds

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(180).timeout.connect(func():get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/ocean-fold-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.time_of_day=.5;WeatherLighting.cloud_cover=.4;WeatherLighting.sea_state=.8;WeatherLighting.wind_force=.8
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.far=12000
	camera.position=Vector3(10,3,8);camera.look_at(Vector3(0,0,-70))
	renderer=WorldRenderer.new();add_child(renderer)
	await get_tree().create_timer(8).timeout
	renderer._fft_system.set_process(false);renderer.set_process(false)
	RenderingServer.call_on_render_thread(read_maps)
	while not readback_done:await get_tree().process_frame
	for amplitude in [.42,1.05,3.045]:
		measure(amplitude,true)
		assert(measure(amplitude,false)==0,"Height field must never invert")
	var materials:Array[ShaderMaterial]=[renderer._ocean_shader_material,renderer._ocean_mid_material,renderer._ocean_far_material,renderer._ocean_horizon_material]
	for intensity in [1.0,5.0]:
		for material in materials:
			material.set_shader_parameter("wave_intensity",intensity)
			material.set_shader_parameter("wave_energy_multiplier",1.45)
		for height in [3.0,-1.0,-3.0]:
			camera.position.y=height
			camera.look_at(camera.position+Vector3(-10,-.2,-70))
			renderer._update_underwater_effect()
			await capture("intensity-%s-height-%s"%[intensity,height])
	print("FOLD REVIEW COMPLETE ",output)
	get_tree().quit()
