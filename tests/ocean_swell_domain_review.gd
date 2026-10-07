extends "res://tests/ocean_transmission_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(180).timeout.connect(func():get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/ocean-domain-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.5);WeatherLighting.time_of_day=.5
	WeatherLighting.cloud_cover=.65;WeatherLighting.precipitation=0;WeatherLighting.visibility=1
	WeatherLighting.sea_state=.8;WeatherLighting.wind_force=.7
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.far=12000;camera.position=Vector3(0,40,0);camera.look_at(Vector3(0,-2,-80))
	renderer=WorldRenderer.new();add_child(renderer)
	for frame in 120:await get_tree().process_frame
	assert(renderer._fft_maps_bound)
	renderer.set_process(false)
	var fft:FFTWaterSystem=renderer._fft_system;fft.set_process(false)
	if OS.get_cmdline_user_args().has("--spectrum-sweep"):
		for span in [256.0,512.0,1024.0]:
			fft.length_scales.x=span
			for wind in [0.0,.25,.5,.75,1.0]:
				for angle in [0.0,PI*.25]:
					fft._last_wind=-1
					fft.sync_weather(wind,.7,.7,angle)
					var values:=fft.rd.texture_get_data(fft.target_spectrum_tex,0).to_float32_array()
					var sum:=0.0;var largest:=0.0
					for pixel in 512*512:
						var energy:=values[pixel*4]*values[pixel*4]+values[pixel*4+1]*values[pixel*4+1]
						sum+=energy;largest=maxf(largest,energy)
					print("SWEEP span=",span," wind=",wind," angle=",angle," peak=",largest/maxf(sum,.000001))
					if span==1024.0:assert(largest/maxf(sum,.000001)<.3,"Single mode dominates supported weather sweep")
		get_tree().quit()
		return
	for span in [256.0,512.0,1024.0]:
		fft.length_scales.x=span
		fft._spectrum_initialized=false
		fft._run_init_pack()
		for material in [renderer._ocean_shader_material,renderer._ocean_mid_material,renderer._ocean_far_material]:
			material.set_shader_parameter("length_scales",fft.length_scales)
			material.set_shader_parameter("wave_time",4.0)
		renderer._ocean_horizon_material.set_shader_parameter("length_scale_0",span)
		for frame in 240:
			fft.time=float(frame+1)/60.0
			fft._run_update_fft_assemble(1.0/60.0)
			await get_tree().process_frame
		var spectrum:=fft.rd.texture_get_data(fft.target_spectrum_tex,0).to_float32_array()
		var total:=0.0;var peak:=0.0
		for pixel in 512*512:
			var energy:=spectrum[pixel*4]*spectrum[pixel*4]+spectrum[pixel*4+1]*spectrum[pixel*4+1]
			total+=energy;peak=maxf(peak,energy)
			var k:Vector2=Vector2(float(pixel%512)-256.0,float(pixel/512)-256.0)*TAU/span
			if k.length()>=TAU/fft.length_scales.y:assert(energy<.000001,"Short waves leaked into the macro patch")
		print("SWELL DOMAIN ",span," strongest-mode-share=",peak/maxf(total,.000001)," total=",total)
		var full:=fft.rd.texture_get_data(fft.displacement_tex,0).to_float32_array()
		var query:=fft.rd.texture_get_data(fft.physics_query_tex,0).to_float32_array()
		var error:=0.0;var shifted_error:=0.0;var height_energy:=0.0
		for sample_index in 2048:
			var u:=float((sample_index*719)%4096)/4096.0
			var v:=float((sample_index*239+13)%4096)/4096.0
			var actual:=WaveSurface._bilinear_query_layer(full,512,u,v).y
			var old:=WaveSurface._bilinear_query_layer(query,128,u+.5/128,v+.5/128).x
			var corrected:=WaveSurface._bilinear_query_layer(query,128,u,v).x
			error+=pow(actual-old,2);shifted_error+=pow(actual-corrected,2);height_energy+=actual*actual
		print("DOMAIN HEIGHT raw_rms=",sqrt(height_energy/2048)," query_error=",sqrt(error/2048)," centred_error=",sqrt(shifted_error/2048))
		if span==1024.0:
			assert(sqrt(shifted_error/height_energy)<.02,"Macro buoyancy filtering error exceeds 2% RMS")
		for height in [6.0,40.0,180.0,600.0]:
			camera.position=Vector3(0,height,0);camera.look_at(Vector3(height,-2,-height*2))
			renderer._follow_camera_xz()
			renderer._update_underwater_effect()
			await capture(str(int(span))+"-"+str(int(height)))
	print("SWELL DOMAIN DIAGNOSTIC COMPLETE")
	get_tree().quit()
