extends Node3D
var failures: Array[String] = []
var checks := 0

class Body extends RigidBody3D:
	var draft: Dictionary = {}
	var length_m := 15.0
	var beam_m := 4.0

class Propulsion extends Node:
	var throttle := 0.5
	var engine_running := true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var body := Body.new()
	body.freeze = true
	add_child(body)
	body.position = Vector3(100, 0, 100)
	var mount := Node3D.new()
	mount.name = "InstalledEngine"
	body.add_child(mount)
	mount.position = Vector3(1, 0, 4)
	var propulsion := Propulsion.new()
	propulsion.name = "PropulsionComponent"
	body.add_child(propulsion)
	var audio := BoatAudioSystem.new()
	body.add_child(audio)
	audio.set_process(false)
	audio._on_helm_activated()
	audio._process(3.0)
	check(audio._engine_idle.global_position.is_equal_approx(mount.global_position), "Engine at installed machinery")
	check(audio._start_pool[0].global_position.is_equal_approx(mount.global_position), "Ignition at engine")
	body.position += Vector3(50, 0, -30)
	body.rotation.y = 1.2
	check(audio._engine_idle.global_position.is_equal_approx(mount.global_position), "Engine follows translation and rotation")
	check(audio._start_pool[0].global_position.is_equal_approx(mount.global_position), "Playing ignition follows boat")
	check(not audio.is_in_group("ship_owner_only"), "Other vessels retain spatial machinery")
	audio._on_helm_deactivated()
	audio._process(10.0)
	check(audio._heard_running and audio._engine_gain_s > 0.99, "Running machinery stays audible after leaving helm")
	var hull: Node3D = load("res://scripts/ship/hull_world_audio.gd").new()
	body.add_child(hull)
	hull.set_process(false)
	hull._process(0.1)
	check(hull._bow.global_position.is_equal_approx(body.to_global(Vector3(0, .15, -6.3))), "Bow emitter follows hull")
	check(hull.get_node_or_null("EngineIdleWorld") == null, "No duplicate engine layer")
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = mount.global_position + Vector3(6, 0, 0)
	camera.look_at(mount.global_position)
	camera.current = true
	check(camera.to_local(mount.global_position).z < 0, "Source in front of first camera")
	var orbit := Camera3D.new()
	add_child(orbit)
	orbit.position = mount.global_position + Vector3(0, 3, 20)
	orbit.look_at(mount.global_position)
	orbit.current = true
	check(get_viewport().get_camera_3d() == orbit, "Camera switch changes listener view")
	check(audio._engine_idle.global_position.is_equal_approx(mount.global_position), "Camera switch does not relocate source")
	var wall := StaticBody3D.new()
	add_child(wall)
	wall.position = (orbit.global_position + mount.global_position) * 0.5
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 10, 0.5)
	collision.shape = shape
	wall.add_child(collision)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(audio._engine_idle._probe(orbit) == 1.0, "Wall obstructs camera-to-source path")
	wall.collision_layer = 0
	await get_tree().physics_frame
	check(audio._engine_idle._probe(orbit) == 0.0, "Opening path clears obstruction")
	var weather := WeatherAudioSystem.new()
	add_child(weather)
	weather.set_process(false)
	var strike := Vector3(700, 40, -800)
	weather._on_lightning_strike(0.8, 1200.0, strike)
	weather._update_pending_thunder(10.0)
	var located := false
	for thunder: AudioStreamPlayer3D in weather._thunder_pool:
		if thunder.playing:
			located = thunder.global_position.is_equal_approx(strike)
	check(located, "Delayed thunder retains strike location")
	weather.queue_free()
	for node in [body, camera, orbit, wall]: node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--measure-output"):
		await _measure_output()
	for frame in 4: await get_tree().process_frame
	print("SPATIAL AUDIO ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _measure_output() -> void:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, "SpatialProbe")
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(index, capture)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var emitter := SpatialSoundEmitter.new()
	add_child(emitter)
	emitter.obstruction_enabled = false
	emitter.bus = "SpatialProbe"
	emitter.stream = AudioLibrary.stream("res://resources/audio/ship/engines/compact_i6/engine_idle_1.wav", true)
	emitter.position = Vector3(8, 0, -8)
	emitter.unit_size = 2.0
	emitter.max_distance = 100.0
	emitter.source_db = -12.0
	emitter.play()
	var right := await _energy(capture)
	camera.rotation.y = PI
	var left := await _energy(capture)
	camera.rotation.y = 0
	camera.position = Vector3(0, 0, 40)
	var far := await _energy(capture)
	check(right.y > right.x * 1.2, "Mixed output pans right")
	check(left.x > left.y * 1.2, "Turning camera pans source left")
	check(far.length() < right.length() * 0.6, "Moving listener away lowers mixed output")
	print("SPATIAL OUTPUT energies right=", right, " turned=", left, " distant=", far)
	emitter.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	AudioServer.remove_bus(index)

func _energy(capture: AudioEffectCapture) -> Vector2:
	await get_tree().create_timer(0.3).timeout
	capture.clear_buffer()
	await get_tree().create_timer(0.1).timeout
	var data := capture.get_buffer(capture.get_frames_available())
	var total := Vector2.ZERO
	for sample: Vector2 in data:
		total += sample * sample
	return total / maxf(data.size(), 1.0)
