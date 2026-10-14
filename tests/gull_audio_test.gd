extends Node3D
var failures: Array[String] = []
var camera: Camera3D
var bird: CoastalGull
var probe_bus: int
var capture: AudioEffectCapture

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	for category in GullCallAudio.VARIANTS:
		for variant in range(1, GullCallAudio.VARIANTS[category] + 1):
			var path := GullCallAudio.ROOT + "%s_%02d.wav" % [category, variant]
			var clip := AudioLibrary.stream(path) as AudioStreamWAV
			check(clip != null and not clip.stereo and clip.get_length() > 0.4, "Usable mono clip: " + path)
	var a := GullProfile.seeded(761, 0, 4, 1, 0.6)
	var b := GullProfile.seeded(761, 1, 4, 1, 0.6)
	check(GullCallAudio.call_for(60, a, true) != GullCallAudio.call_for(60, b, true), "Birds have separate schedules")
	var restored := GullProfile.from_record(JSON.parse_string(JSON.stringify(a.to_record())))
	check(GullCallAudio.call_for(60, a, true) == GullCallAudio.call_for(60, restored, true), "Call schedule reconstructs from identity and time")
	bird = CoastalGull.new()
	add_child(bird)
	bird.position = Vector3(4, 0, -4)
	check(bird.calls.play_call("contact", 1), "Individual source starts")
	bird.position.x += 3.0
	check(bird.calls.emitter.global_position.distance_to(bird.global_position) < 0.6, "Voice follows bird")
	bird.calls.enabled = false
	check(not bird.calls.emitter.playing, "Mute stops an active call")
	bird.calls.enabled = true
	bird.position = Vector3(500, 0, 0)
	check(not bird.calls.play_call("contact", 1), "Distant birds do not allocate playback")
	bird.position = Vector3(4, 0, -4)
	bird.visible = false
	check(not bird.calls.play_call("contact", 1), "Hidden birds stay silent")
	bird.visible = true
	var voices: Array[GullCallAudio] = []
	var started := 0
	for i in 12:
		var voice := GullCallAudio.new()
		add_child(voice)
		voice.position = Vector3(0, 0, -4)
		voices.append(voice)
		if voice.play_call("contact", 1): started += 1
	check(started == GullCallAudio.MAX_VOICES, "Large flocks have bounded simultaneous voices")
	for voice in voices:
		voice.enabled = false
		voice.queue_free()
	await get_tree().process_frame
	AudioServer.add_bus()
	probe_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(probe_bus, "GullAudioProbe")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(probe_bus, capture)
	var right := await energy(Vector3(4, 0, -4))
	var left := await energy(Vector3(-4, 0, -4))
	var far := await energy(Vector3(40, 0, -40))
	check(right.y > right.x * 1.2, "Actual mixed gull call pans right")
	check(left.x > left.y * 1.2, "Actual mixed gull call pans left")
	check(far.length() < right.length() * 0.15, "Actual mixed gull call fades with distance")
	print("GULL AUDIO OUTPUT right=", right, " left=", left, " distant=", far)
	bird.calls.enabled = false
	# Give the audio mixer time to release its playback before removing its bus.
	await get_tree().create_timer(0.15).timeout
	bird.queue_free()
	await get_tree().process_frame
	AudioServer.remove_bus(probe_bus)
	print("GULL AUDIO failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func energy(at: Vector3) -> Vector2:
	bird.calls.emitter.stop()
	await get_tree().create_timer(0.1).timeout
	bird.position = at
	bird.calls.emitter.obstruction_enabled = false
	check(bird.calls.play_call("contact", 1, 1.0, true), "Probe starts")
	bird.calls.emitter.bus = "GullAudioProbe"
	capture.clear_buffer()
	await get_tree().create_timer(1.8).timeout
	var data := capture.get_buffer(capture.get_frames_available())
	var total := Vector2.ZERO
	for sample: Vector2 in data: total += sample * sample
	return total / maxf(data.size(), 1.0)
