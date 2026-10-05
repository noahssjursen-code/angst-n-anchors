extends Node3D

func _ready() -> void:
	var boat := ImportedDraftVessel.new()
	boat.configure({"hull":"trawler_hull_14m", "parts":[
		{"asset_id":"cabin_door_straight", "position":[0,2.92,0], "yaw_degrees":0},
		{"asset_id":"cabin_door_straight", "position":[0,2.92,2], "yaw_degrees":180},
	]})
	add_child(boat)
	boat.freeze = true
	for name in ["StripBuoyancyComponent", "HydrodynamicsComponent", "PropulsionComponent", "RudderComponent", "BowThrusterComponent"]:
		boat.get_node(name).set_physics_process(false)
	var player := preload("res://scenes/shared/player.tscn").instantiate() as CharacterBody3D
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	for i in range(3): await get_tree().physics_frame
	var cases := 0
	for tilt in [Vector3.ZERO, Vector3(0,0,12), Vector3(0,0,-12), Vector3(8,0,12), Vector3(-8,0,-12)]:
		boat.rotation_degrees = tilt
		boat._sync_walk_deck_transform()
		for i in range(2): await get_tree().physics_frame
		for part in boat.part_roots:
			var driver := part.get_node("PartState") as ShipPartState
			var centre := part.position + part.basis * Vector3(0, .03, -.5)
			for side in [-1.0, 1.0]:
				var start := centre + Vector3(side * 1.1, 0, 0)
				player.global_position = boat.to_global(start)
				player._sync_deck_capsule()
				var capsule := player.get_node("CollisionShape3D") as CollisionShape3D
				assert(capsule.global_basis.y.dot(boat.global_basis.y) > .999, "Capsule must share the tilted deck frame")
				driver.apply_snapshot({"door_open":false}, driver.revision + 1, true)
				boat._physics_process(0)
				var movement := boat.global_basis * Vector3(-side * 2.2, 0, 0)
				assert(player.test_move(player.global_transform, movement), "Closed door must block passage")
				driver.request_door_from(player.global_position)
				var pivot := part.find_children("DoorLeafPivot*", "Node3D", true, false)[0] as Node3D
				var closed_tip := pivot.to_global(Vector3(0,1,-.6))
				driver._physics_process(1)
				boat._physics_process(0)
				for i in range(2): await get_tree().physics_frame
				var opened_tip := pivot.to_global(Vector3(0,1,-.6))
				assert((opened_tip - closed_tip).dot(boat.global_basis * Vector3(side,0,0)) < 0, "Door must open away from player in both drawing directions")
				var result := KinematicCollision3D.new()
				if player.test_move(player.global_transform, movement, result):
					print("BLOCK ", part.name, " ", driver.state, " normal ",result.get_normal(), " pos ",result.get_position(), " shape ",result.get_collider_shape())
					var owner := result.get_collider_shape()
					for item in boat.moving_colliders:
						if item.collision == owner: print("BLOCK MESH ",item.mesh.name, " ",item.collision.transform)
				assert(not player.test_move(player.global_transform, movement), "Open doorway must pass at roll/pitch %s and side %s" % [tilt, side])
				cases += 1
	# Explicit inertia response: identical roll impulse produces less angular acceleration.
	var old_roll_inertia := 52000.0 * pow(5.0 * .30, 2)
	assert(boat.inertia.z > old_roll_inertia * 1.7)
	assert(boat.physics_profile.heave_damping_ratio >= 1.0)
	print("DOOR MOTION PASS: %d closed/open crossings, reversed walls, both sides, roll/pitch, deck capsule and increased hull inertia" % cases)
	get_tree().quit()
