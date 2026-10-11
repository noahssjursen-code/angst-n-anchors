extends Node

class TestPort extends PortPlot:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	var home := TestPort.new()
	var destination := TestPort.new()
	add_child(home)
	add_child(destination)
	var body := RigidBody3D.new()
	body.freeze = true
	add_child(body)
	for z in [-4.0, 4.0]:
		var cleat := MooringPoint.new()
		cleat.build_visual = false
		cleat.position = Vector3(0, 0, z)
		cleat.station = "bow" if z < 0 else "stern"
		body.add_child(cleat)
	var mc := MooringComponent.new()
	body.add_child(mc)
	var old_posts: Array[Node] = []
	var new_posts: Array[Node] = []
	for port in [home, destination]:
		for z in [-4.0, 4.0]:
			var post := Node3D.new()
			port.add_child(post)
			post.position = Vector3(-2, .5, z)
			post.add_to_group(MooringComponent.DOCK_MOORING_GROUP)
			if port == home: old_posts.append(post)
			else: new_posts.append(post)
	await get_tree().process_frame
	# Exercise the same individual toggle used by F at a bollard, in both orders.
	for order in [[0, 1], [1, 0]]:
		mc.moor_to_posts(old_posts[0], old_posts[1])
		assert(not mc.toggle_line_from_post(old_posts[order[0]]))
		assert(mc.is_moored)
		assert(not mc.toggle_line_from_post(new_posts[0]), "A remaining home line must prevent a split berth")
		assert(not mc.last_mooring_reject.is_empty())
		assert(not mc.toggle_line_from_post(old_posts[order[1]]))
		assert(not mc.is_moored)
		assert(mc.toggle_line_from_post(new_posts[0]), "After cast-off, destination tie must succeed")
		assert(mc.toggle_line_from_post(new_posts[1]))
		assert(mc.bow_line_tied and mc.stern_line_tied)
		mc.release_mooring()
	# Stream out the old port after individual cast-off. No freed endpoints survive.
	mc.moor_to_posts(old_posts[0], old_posts[1])
	mc.toggle_line_from_post(old_posts[0])
	mc.toggle_line_from_post(old_posts[1])
	home.free()
	assert(mc.toggle_line_from_post(new_posts[0]))
	assert(mc.toggle_line_from_post(new_posts[1]))
	mc.release_mooring()
	body.queue_free()
	destination.queue_free()
	await get_tree().process_frame
	print("MOORING ARRIVAL PASS: both individual cast-off orders, split-berth rejection, destination re-tie, streamed-out origin")
	get_tree().quit()
