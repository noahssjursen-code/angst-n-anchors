extends Node3D
var failures: Array[String] = []

class TestBody extends BoatBody:
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var body := TestBody.new()
	body.freeze = true
	add_child(body)
	var prop := PropulsionComponent.new()
	prop.name = "PropulsionComponent"
	body.add_child(prop)
	prop.set_physics_process(false)
	var controller := BoatController.new()
	controller.name = "BoatController"
	body.add_child(controller)
	controller.set_physics_process(false)
	var audio := BoatAudioSystem.new()
	body.add_child(audio)
	audio.set_process(false)
	controller.activate()
	audio._process(0.1)
	check(not prop.engine_running and not audio._heard_running, "Taking helm does not start machinery")
	controller.toggle_engine()
	audio._process(1.0)
	check(prop.engine_running and audio._heard_running, "Explicit start enables machinery and sound")
	var fuel := body.fuel_l
	prop._physics_process(1.0)
	check(body.fuel_l < fuel and prop.delivered_thrust_n == 0, "Idle consumes fuel without thrust")
	controller.deactivate()
	audio._process(1.0)
	check(prop.engine_running and audio._heard_running, "Leaving helm preserves engine idle")
	controller.activate()
	controller.toggle_engine()
	audio._process(1.0)
	check(not prop.engine_running and not audio._heard_running, "Explicit stop shuts down audio and machinery")
	fuel = body.fuel_l
	prop.throttle = -1.0
	prop._physics_process(1.0)
	check(body.fuel_l == fuel and prop.delivered_thrust_n == 0, "Stopped engine cannot burn fuel or deliver thrust")
	body.fuel_l = 0.0
	check(not prop.set_engine_running(true), "Empty tank blocks ignition")
	body.fuel_l = 0.001
	check(prop.set_engine_running(true), "Refuelling permits explicit restart")
	prop._physics_process(1.0)
	check(not prop.engine_running and prop.throttle == 0.0, "Fuel depletion stalls engine and clears drive")
	controller.deactivate()
	body.queue_free()
	for frame in 4: await get_tree().process_frame
	print("ENGINE CONTROL failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
