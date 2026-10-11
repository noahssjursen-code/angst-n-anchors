extends Node

func _ready() -> void:call_deferred("run")

func run() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(90).timeout.connect(func():get_tree().quit(1))
	var fft:=FFTWaterSystem.new();add_child(fft);fft.set_process(false)
	assert(fft.rd!=null)
	# Zero spectra give a uniform Jacobian of one: forcing can be specified
	# independently of wave phase, making different timesteps comparable.
	var zero:=PackedByteArray();zero.resize(512*512*16);zero.fill(0)
	for layer in 8:assert(fft.rd.texture_update(fft.spectrum_tex,layer,zero)==OK)
	var initial:=PackedFloat32Array();initial.resize(512*512*4);initial.fill(0)
	for pixel in 512*512:initial[pixel*4+3]=.2
	var initial_bytes:=initial.to_byte_array()
	for forcing in [false,true]:
		for decay in [.08,0.0]:
			fft.foam_decay_rate=decay
			fft.foam_bias=1.1 if forcing else 1.0
			var baseline:=-1.0
			for hz in [60,30,20,10]:
				for layer in 4:assert(fft.rd.texture_update(fft.displacement_tex,layer,initial_bytes)==OK)
				fft._update_push_constants(1.0/float(hz))
				for step in hz:
					var list:=fft.rd.compute_list_begin()
					fft.rd.compute_list_bind_compute_pipeline(list,fft.pipeline_assemble)
					fft.rd.compute_list_bind_uniform_set(list,fft.uniform_set,0)
					fft.rd.compute_list_set_push_constant(list,fft.push_constant_params,fft.push_constant_params.size())
					fft.rd.compute_list_dispatch(list,64,64,1)
					fft.rd.compute_list_end()
				var data:=fft.rd.texture_get_data(fft.displacement_tex,0).to_float32_array()
				var value:=data[3]
				if baseline<0:baseline=value
				assert(absf(value-baseline)<.00002,"Foam lifetime depends on update rate")
				assert(is_finite(value) and value>=0 and value<=1)
				if not forcing:assert(absf(value-.2*exp(-decay*60.0))<.00002)
				print("FOAM GPU hz=",hz," forcing=",forcing," decay=",decay," value=",value)
	fft.queue_free()
	await get_tree().process_frame
	print("FOAM TIMING PASS: GPU decay and sustained injection, 10/20/30/60 Hz, zero-decay limit")
	get_tree().quit()
