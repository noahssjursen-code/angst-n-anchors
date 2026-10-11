extends Node

var failures: Array[String] = []
var checks := 0

class AudioBody extends RigidBody3D:
	var draft: Dictionary = {}

class AudioControls extends Node:
	var _throttle := 0.0

class AudioEngine extends Node:
	var throttle := 0.0
	var engine_running := false

class FogFixture extends FogHorn:
	var fog_level := 1.0
	func _sample_fog_density() -> float:
		return fog_level

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("AUDIO FAIL " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := AudioLibrary.entries()
	check(catalog.size() >= 98, "Manifest loaded")
	for path: String in catalog:
		var spec: Dictionary = catalog[path]
		var clip := AudioLibrary.stream(path, bool(spec.loop)) as AudioStreamWAV
		check(clip != null, "Load " + path)
		if clip == null:
			continue
		check(clip.get_length() > 0.1, "Duration " + path)
		check(clip.stereo == (int(spec.channels) == 2), "Channels " + path)
		check(clip.loop_mode == (AudioStreamWAV.LOOP_FORWARD if spec.loop else AudioStreamWAV.LOOP_DISABLED), "Loop policy " + path)
		if spec.loop:
			check(clip.loop_end > clip.loop_begin, "Loop range " + path)
		check(AudioServer.get_bus_index(AudioLibrary.bus(path)) >= 0, "Bus " + path)
	# Previewing a loop as a one-shot must not modify the live loop resource.
	var loop_path := "res://resources/audio/looped/ocean/calm_seas_1.wav"
	var loop := AudioLibrary.stream(loop_path, true) as AudioStreamWAV
	var shot := AudioLibrary.stream(loop_path, false) as AudioStreamWAV
	check(loop != shot and loop.loop_mode == 1 and shot.loop_mode == 0, "Independent playback modes")
	# Audible idle survives reentering the chair without retriggering ignition.
	var body := AudioBody.new()
	body.freeze = true
	add_child(body)
	var controls := AudioControls.new()
	controls.name = "BoatController"
	body.add_child(controls)
	var engine := AudioEngine.new()
	engine.name = "PropulsionComponent"
	body.add_child(engine)
	var boat := BoatAudioSystem.new()
	body.add_child(boat)
	boat.set_process(false)
	boat._on_helm_activated()
	engine.engine_running = true
	boat._process(0.1)
	check(boat._heard_running, "Engine starts on running transition")
	check(not boat._start_pool.is_empty() and boat._start_pool[0].playing, "Start clip triggered")
	for player in boat._start_pool: player.stop()
	boat._on_helm_activated()
	boat._process(0.1)
	check(not boat._start_pool[0].playing, "Reentry does not retrigger start")
	boat._on_helm_deactivated()
	boat._process(0.1)
	check(boat._heard_running and not boat._stop_pool[0].playing, "Leaving helm retains idle")
	engine.engine_running = false
	boat._process(0.1)
	check(not boat._heard_running and boat._stop_pool[0].playing, "Shutdown transition")
	body.queue_free()
	var horn := FogFixture.new()
	add_child(horn)
	horn.set_process(false)
	horn._process(0.1)
	check(horn.playing and horn._signal_wait == horn.SIGNAL_INTERVAL, "Fog starts timed blast")
	horn.stop()
	horn._process(5.0)
	check(not horn.playing, "Fog horn has quiet interval")
	horn._process(30.0)
	check(horn.playing, "Fog horn repeats on timer")
	horn.fog_level = 0.0
	horn._process(0.1)
	check(not horn.playing and not horn._is_active, "Clear weather stops horn")
	horn.queue_free()
	# Verify native looping survives more than one short loop and one-shots finish.
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.volume_db = -80
	player.stream = AudioLibrary.stream("res://resources/audio/world/horns/ship_horn_1.wav", true)
	player.play()
	await get_tree().create_timer(4.5).timeout
	check(player.playing, "Native loop continues across wrap")
	player.stop()
	player.stream = AudioLibrary.stream("res://resources/audio/ship/controls/throttle_click_1.wav", false)
	player.play()
	await get_tree().create_timer(1.0).timeout
	check(not player.playing, "One-shot finishes")
	player.queue_free()
	await get_tree().process_frame
	print("AUDIO LIBRARY ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
