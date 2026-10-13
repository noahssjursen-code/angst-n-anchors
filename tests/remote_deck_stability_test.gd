extends Node3D

class DeckBoat extends BoatBody:
	var support: AnimatableBody3D
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _sync_walk_deck_transform() -> void:
		if is_instance_valid(support): support.global_transform = global_transform

var ship: DeckBoat
var player: CharacterBody3D
var manager: Node
var drawing: Node3D
var tick := 0.0
var moving := false
var walking := false
var state: Dictionary

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	if DisplayServer.get_name() == "headless":
		push_error("Run this input test with a window: headless cannot capture the mouse")
		get_tree().quit(1)
		return
	process_physics_priority = -110
	get_tree().create_timer(35).timeout.connect(func(): get_tree().quit(1))
	call_deferred("run")

func _physics_process(delta: float) -> void:
	if walking:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.action_press("move_forward")
	if not moving: return
	tick += delta
	state.target_pos = Vector3(tick * 6.0, sin(tick * 1.4) * .4, 0)
	state.target_payload = [0,0,0, sin(tick)*.08, tick*.03, sin(tick*1.2)*.12]
	state.received_at_ms = Time.get_ticks_msec()
	state.last_seen_ms = Time.get_ticks_msec()

func run() -> void:
	manager = preload("res://scripts/network/network_manager.gd").new()
	add_child(manager)
	drawing = preload("res://scripts/network/replication_drawing_service.gd").new()
	add_child(drawing)
	manager.drawing_service = drawing
	manager._session_active = true
	manager.process_mode = Node.PROCESS_MODE_ALWAYS
	manager.set_process(false)
	manager.set_physics_process(true)
	ship = DeckBoat.new()
	ship.freeze = true
	drawing.add_child(ship)
	ship.support = AnimatableBody3D.new()
	ship.support.sync_to_physics = false
	ship.support.collision_layer = 4
	ship.support.set_meta("_boat_owner", ship)
	ship.support.set_meta("align_player_capsule", true)
	add_child(ship.support)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(20,.4,20)
	shape.position.y = -.2
	ship.support.add_child(shape)
	state = {"node": ship, "type": "test_deck", "target_pos": Vector3.ZERO,
		"target_payload": [0,0,0,0,0,0], "interpolated_payload": [0,0,0,0,0,0],
		"meta": "", "last_seen_ms": Time.get_ticks_msec()}
	drawing._visible_entities["test"] = state
	# Production drawing syncs the support immediately after each ship pose.
	ship.set_meta("remote_replica", true)
	state.type = "ship_test"
	player = preload("res://scenes/shared/player.tscn").instantiate()
	player.position = Vector3(1,.1,1)
	add_child(player)
	await get_tree().create_timer(.5).timeout
	assert(player.is_deck_mounted())
	moving = true
	for fps in [30,144]:
		Engine.max_fps = fps
		var worst := 0.0
		for frame in 150:
			await get_tree().physics_frame
			var local := ship.to_local(player.global_position)
			worst = maxf(worst, Vector2(local.x-1,local.z-1).length())
		assert(worst < .08, "Stationary passenger must retain deck-relative footing")
		print("REMOTE DECK fps=",fps," max horizontal drift=",worst)
	var start := ship.to_local(player.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	walking = true
	for frame in 90:
		Input.action_press("move_forward")
		await get_tree().physics_frame
	walking = false
	Input.action_release("move_forward")
	var distance := ship.to_local(player.global_position).distance_to(start)
	assert(distance > 1.0, "Deck stabilization must not suppress deliberate walking")
	print("REMOTE DECK deliberate walking=", distance)
	moving = false
	manager._session_active = false
	player.queue_free()
	ship.support.queue_free()
	ship.queue_free()
	await get_tree().process_frame
	print("REMOTE DECK STABILITY PASS")
	get_tree().quit()
