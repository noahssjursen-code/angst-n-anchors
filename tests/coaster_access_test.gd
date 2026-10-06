extends Node3D
var boat: ImportedDraftVessel
var player: CharacterBody3D
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed=true
		push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	boat=ImportedDraftVessel.new()
	boat.configure(JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_32m_draft.json")))
	boat.freeze=true
	add_child(boat)
	for name in ["StripBuoyancyComponent","HydrodynamicsComponent","PropulsionComponent","RudderComponent","BowThrusterComponent"]:
		boat.get_node(name).set_physics_process(false)
	player=preload("res://scenes/shared/player.tscn").instantiate()
	add_child(player)
	player.walk_speed=2.0
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for i in 4:await get_tree().physics_frame
	check(boat.get_node("RailPosts").get_child_count()==boat.assembler.rail_joints().size(),"Runtime must include editor rail posts")
	check(boat.get_node("RailPosts").get_child_count()>10,"Balcony needs actual guard posts")
	for tilt in [Vector3.ZERO,Vector3(3,0,4),Vector3(-3,0,-4)]:
		boat.rotation_degrees=tilt
		boat._sync_walk_deck_transform()
		player.global_position=boat.to_global(Vector3(3.5,4.56,8.4))
		player.velocity=Vector3.ZERO
		player.rotation=Vector3.ZERO
		for i in 20:await get_tree().physics_frame
		check(player.is_on_floor(),"Player must stand at stair foot")
		await walk_to(Vector3(3.5,6.7,12.55),210)
		var local:=boat.to_local(player.global_position)
		print("ACCESS ASCENT ",tilt," ",local)
		check(local.z>12.2 and absf(local.y-6.7)<.15,"Player must climb actual treads to upper landing")
		await walk_to(Vector3(3.5,4.5,8.4),210)
		local=boat.to_local(player.global_position)
		print("ACCESS DESCENT ",tilt," ",local)
		check(local.z<8.8 and absf(local.y-4.5)<.15,"Player must descend to original deck")
	# Enter upper door from landing and reach the helm without crossing walls.
	boat.rotation=Vector3.ZERO;boat._sync_walk_deck_transform()
	player.global_position=Vector3(3.5,6.76,12.5);player.velocity=Vector3.ZERO
	for part in boat.part_roots:
		if part.get_meta("asset_id")=="cabin_door_straight" and part.position.y>6:
			var state:=part.get_node("PartState") as ShipPartState
			state.request_door_from(player.global_position)
	for i in 60:await get_tree().physics_frame
	await walk_to(Vector3(1,6.7,12.5),150)
	check(player.position.x<1.5 and absf(player.position.y-6.7)<.15,"Open bridge door must be accessible from landing")
	await walk_to(Vector3(0,6.7,12.2),100)
	check(player.position.distance_to(Vector3(0,6.7,12.2))<.35,"Player must reach approach behind helm chair")
	# Default walking speed must work too; the earlier passes intentionally walk slowly.
	player.walk_speed=4.5
	player.position=Vector3(3.5,4.56,8.4);player.velocity=Vector3.ZERO
	for i in 20:await get_tree().physics_frame
	await walk_to(Vector3(3.5,6.7,12.55),180)
	check(absf(player.position.y-6.7)<.15 and player.position.z>12.2,"Normal walking speed must climb stairs")
	# Nosing-normal tolerance must never allow walking through a low ceiling.
	var ceiling:=obstacle(Vector3(3.5,6.41,9.7),Vector3(1.5,.1,2.0))
	player.position=Vector3(3.5,4.56,8.4);player.velocity=Vector3.ZERO
	for i in 20:await get_tree().physics_frame
	await walk_to(Vector3(3.5,6.7,12.55),100)
	check(player.position.z<9.1 and player.position.y<4.6,"Step climbing must respect head clearance")
	ceiling.queue_free()
	# New portside ventilation must preserve the outside route around the house.
	player.position=Vector3(-4.4,4.56,9.5);player.velocity=Vector3.ZERO
	for i in 20:await get_tree().physics_frame
	await walk_to(Vector3(-4.4,4.5,14.6),200)
	check(player.position.z>14.2 and absf(player.position.y-4.5)<.15,"Ventilators must leave the port walkway usable")
	# A separate tall obstacle on a plain pad remains unclimbable without jumping.
	var pad:=obstacle(Vector3(40,4.4,0),Vector3(8,.2,8))
	var wall:=obstacle(Vector3(40,5.2,0),Vector3(2,1.4,.3))
	player.position=Vector3(40,4.56,-1.5);player.velocity=Vector3.ZERO
	for i in 20:await get_tree().physics_frame
	await walk_to(Vector3(40,4.5,1),100)
	check(player.position.z<-.4 and player.position.y<4.6,"Step climbing must not scale a tall wall")
	pad.queue_free();wall.queue_free()
	player.queue_free();boat.queue_free()
	for i in 4:await get_tree().process_frame
	if not failed:print("COASTER ACCESS PASS: real slow/normal walking, tilted stair ascent/descent, guard posts, bridge door/helm approach, ceiling and tall-wall limits")
	get_tree().quit(1 if failed else 0)

func walk_to(local_target: Vector3, frames: int) -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for i in frames:
		var target:=boat.to_global(local_target)
		var delta:=target-player.global_position
		delta.y=0
		if delta.length()<.09:break
		player.rotation.y=atan2(-delta.x,-delta.z)
		Input.action_press("move_forward",clampf(delta.length()*2,.65,1))
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 15:await get_tree().physics_frame

func obstacle(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.position=at;add_child(body)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape)
	return body
