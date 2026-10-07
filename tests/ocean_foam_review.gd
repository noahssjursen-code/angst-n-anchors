extends "res://tests/ocean_transmission_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(120).timeout.connect(func():get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/ocean-foam-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day=.5
	WeatherLighting.cloud_cover=.65
	WeatherLighting.precipitation=0
	WeatherLighting.visibility=1
	WeatherLighting.sea_state=.8
	WeatherLighting.wind_force=.7
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.far=12000
	camera.position=Vector3(0,6,0);camera.look_at(Vector3(10,-2,-20))
	renderer=WorldRenderer.new();add_child(renderer)
	await get_tree().create_timer(8).timeout
	renderer._fft_system.set_process(false)
	renderer.set_process(false)
	var materials:Array[ShaderMaterial]=[renderer._ocean_shader_material,renderer._ocean_mid_material,renderer._ocean_far_material]
	var current:Array[Shader]=[]
	for material in materials:current.append(material.shader)
	# Find actual simulated foam for a close-up, rather than aiming at bare sea.
	var fft:FFTWaterSystem=renderer._fft_system
	var pixels:=fft.rd.texture_get_data(fft.displacement_tex,0).to_float32_array()
	var peak:=0
	for pixel in 512*512:
		if pixels[pixel*4+3]>pixels[peak*4+3]:peak=pixel
	var scales:Vector4=materials[0].get_shader_parameter("length_scales")
	var crest:=Vector3(float(peak%512)/512.0*scales.x,WaveSurface.WATER_LEVEL,float(peak/512)/512.0*scales.x)
	var displacement:=Vector3.ZERO
	for layer in 4:
		var data:=fft.rd.texture_get_data(fft.displacement_tex,layer).to_float32_array()
		var x:=int(fposmod(crest.x/scales[layer],1.0)*512.0)
		var z:=int(fposmod(crest.z/scales[layer],1.0)*512.0)
		var offset:=(z*512+x)*4
		displacement+=Vector3(data[offset],data[offset+1],data[offset+2])
	crest+=displacement*float(materials[0].get_shader_parameter("wave_intensity"))*float(materials[0].get_shader_parameter("wave_energy_multiplier"))*.42
	var baseline_folder:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-dir="):baseline_folder=arg.trim_prefix("--baseline-dir=")
	for variant in ["current","baseline"]:
		if variant=="baseline":
			if baseline_folder.is_empty():continue
			var common:=FileAccess.get_file_as_string(baseline_folder.path_join("foam-before-common.gdshaderinc"))
			var lod:=FileAccess.get_file_as_string(baseline_folder.path_join("foam-before-lod.gdshaderinc"))
			assert(not common.is_empty() and not lod.is_empty())
			for index in 3:
				var source:=FileAccess.get_file_as_string(baseline_folder.path_join("foam-before-near.gdshader")) if index==0 else current[index].code
				source=source.replace('#include "res://resources/shaders/ocean_lod_surface.gdshaderinc"',lod)
				source=source.replace('#include "res://resources/shaders/ocean_surface_common.gdshaderinc"',common)
				var shader:=Shader.new();shader.code=source;materials[index].shader=shader
		for height in [2.0,6.0,40.0,180.0]:
			camera.position=Vector3(0,height,0);camera.look_at(Vector3(height,-2,-height*2.0))
			renderer._follow_camera_xz()
			await capture(variant+"-"+str(height))
			if height==6.0:await profile()
		camera.position=crest+Vector3(2,5,5);camera.look_at(crest)
		renderer._follow_camera_xz()
		await capture(variant+"-foam-close")
	for index in 3:materials[index].shader=current[index]
	print("FOAM MATCHED REVIEW COMPLETE: same frozen FFT and wave time")
	renderer.set_process(true);fft.set_process(true)
	for frame in 3:
		await get_tree().create_timer(.35).timeout
		await capture("moving-"+str(frame))
	get_tree().quit()
