extends Node3D

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for seed_value in [42,1212599375,77127]:
		var layout := WorldLayoutGenerator.generate(seed_value)
		var ports := CoastalPortPlacer.place_ports(layout,35,PackedStringArray(WorldPortNames.NAMES))
		var marks := CoastalSeamarks.plan(layout,ports)
		assert(marks.size() > 0)
		assert(marks == CoastalSeamarks.plan(layout,ports))
		for i in marks.size():
			for j in range(i):
				assert(marks[i].position.distance_to(marks[j].position) >= CoastalSeamarks.SPACING_M)
		for record in marks:
			assert(record.depth_m >= 1.5 and record.depth_m <= 4)
			assert(CoastalSeamarks.deeper_side(layout,record.position,record.direction))
			# Independent swept passage check: approaches from either end, covering
			# the whole hull-width corridor rather than one outgoing radial ray.
			var tangent := Vector2(-record.direction.y,record.direction.x)
			for along in range(-180,181,5):
				for across in [30.0,45.0,60.0,75.0,90.0]:
					var point: Vector2 = record.position + tangent*along + record.direction*across
					assert(layout.sample_water_depth(point) >= 5.8)
			for port in ports:
				assert(record.position.distance_to(Vector2(port.world_position.x,port.world_position.z)) >= 450)
		var pole := CoastalSeamarks.instantiate_mark(marks[0])
		add_child(pole)
		var tip := pole.find_child("PointerTip",true,false) as Node3D
		assert(tip != null)
		var delta := tip.global_position - pole.global_position
		assert(Vector2(delta.x,delta.z).normalized().dot(marks[0].direction) > .999)
		pole.queue_free()
		print("SEAMARK PASS seed=",seed_value," poles=",marks.size())
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var streamed := CoastalSeamarks.new()
	streamed.records = [{"id":"test", "position":Vector2.ZERO,"direction":Vector2.RIGHT,"depth_m":3.0}]
	add_child(streamed)
	streamed._process(1.0)
	assert(streamed.get_child_count() == 1)
	camera.position.x = CoastalSeamarks.VIEW_RADIUS_M + 100
	streamed._process(1.0)
	await get_tree().process_frame
	assert(streamed.get_child_count() == 0)
	print("SEAMARK streaming PASS")
	get_tree().quit()
