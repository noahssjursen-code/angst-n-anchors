extends Node3D

class RecordingWake extends OceanWakeField:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(1))
	call_deferred("run")

func run() -> void:
	var drawing := preload("res://scripts/network/replication_drawing_service.gd").new()
	add_child(drawing)
	var ship := VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record("fishing")) as ImportedDraftVessel
	ship.set_meta("remote_replica", true)
	ship.freeze = true
	drawing.add_child(ship)
	drawing._disable_physics_in_subtree(ship)
	await get_tree().process_frame
	var gear := ship.get_node("HullVisual/DriveGear") as ShipDriveVisual
	var lighting := ship.get_node("ShipLighting") as ShipLighting
	assert(not lighting._nav_lights.is_empty() and not lighting._work_lights.is_empty(), "Real imported ship fixtures are bound")
	for preset in range(4):
		drawing._apply_state_to_node(ship, "ship_test", [0,0,0,0,0,0], "eng=1;thr=-0.6;rud=0.75;lights=%d;adv=5;force=12000" % preset)
		gear._process(0.016)
		assert(is_equal_approx(gear.signed_rpm, gear.max_rpm * 0.6))
		assert(is_equal_approx(gear.steering_degrees, gear.max_rudder_degrees * 0.75))
		assert(lighting.network_state() == preset)
		assert(lighting._work_lights.back()._active == (preset in [2,3]))
		assert(lighting._nav_lights.back()._active == (preset in [1,3]))
	var before := gear.propeller.rotation.z
	gear._process(0.016)
	assert(not is_equal_approx(before, gear.propeller.rotation.z), "Remote propeller rotates despite inactive local propulsion")
	drawing._apply_state_to_node(ship, "ship_test", [0,0,0,0,0,0], "eng=1;thr=0.4;rud=-1;lights=6")
	gear._process(0.016)
	assert(gear.signed_rpm < 0 and gear.steering_degrees < 0)
	lighting._process(1.0)
	assert(lighting.network_state() == 6 and lighting._nav_lights.back()._active, "Remote automatic nav is preserved")
	# A fixture created after the snapshot receives the retained state.
	var late := ShipLight.new()
	late.light_type = ShipLight.LightType.WORK
	ship.add_child(late)
	lighting._gather_lights()
	assert(late._active)
	drawing._apply_state_to_node(ship, "ship_test", [0,0,0,0,0,0], "eng=0;thr=-1;rud=0;lights=0")
	gear._process(0.016)
	assert(gear.signed_rpm == 0 and not late._active)
	assert(not ship.get_node("PropulsionComponent").is_physics_processing())
	var sender := preload("res://scripts/network/network_manager.gd").new()
	add_child(sender)
	var prop := ship.get_node("PropulsionComponent") as PropulsionComponent
	prop.engine_running = true
	prop.throttle = -0.7
	prop.advance_speed_ms = 4.5
	prop.delivered_thrust_n = 10000
	(ship.get_node("RudderComponent") as RudderComponent).rudder_input = -0.3
	lighting.apply_network_state(7)
	sender._register_ship_sender("test", "test", ship, false)
	var wire: String = sender._local_senders.test.meta_callable.call()
	var fields: Dictionary = drawing._parse_meta_map(wire)
	assert(fields.lights == "7" and is_equal_approx(float(fields.rud), -0.3))
	assert(is_equal_approx(float(fields.adv), 4.5) and float(fields.force) == 10000)
	lighting.apply_network_state(0)
	assert(sender._local_senders.test.meta_callable.call() != wire, "Stationary light switches change snapshot metadata")
	sender.queue_free()
	var wake := RecordingWake.new()
	add_child(wake)
	drawing._wake_field = wake
	drawing._apply_state_to_node(ship, "ship_test", [0,0,0,0,0,0], "eng=1;thr=-0.6;rud=0;lights=3;adv=5;force=12000")
	drawing._submit_remote_ship_wake("test", ship, {}, 0.016)
	var first: Dictionary = wake._emitters["remote:test"].duplicate()
	ship.position += Vector3(-2, 0, 3) # A correction in the opposite travel direction.
	drawing._submit_remote_ship_wake("test", ship, {}, 0.016)
	assert(wake._emitters["remote:test"].axis == first.axis, "Position corrections cannot reverse the plume")
	assert(wake._emitters["remote:test"].speed == 5.0, "Wake uses transmitted water-relative speed")
	drawing._apply_state_to_node(ship, "ship_test", [0,0,0,0,0,0], "eng=1;thr=0.4;adv=2;force=1000")
	drawing._submit_remote_ship_wake("test", ship, {}, 0.016)
	assert(wake._emitters["remote:test"].axis == -first.axis, "Astern wash reverses just like the owner's")
	drawing._apply_state_to_node(ship, "ship_test", [0,0,0,0,0,0], "eng=0;thr=0")
	drawing._submit_remote_ship_wake("test", ship, {}, 0.016)
	assert(not wake._emitters.has("remote:test"), "Stopped machinery stops injecting prop wash")
	wake.queue_free()
	ship.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("REMOTE VESSEL PRESENTATION PASS")
	get_tree().quit()
