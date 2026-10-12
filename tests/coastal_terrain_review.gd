extends Node
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	for seed_value in [42,1212599375,77127]:
		var started := Time.get_ticks_msec()
		var layout := WorldLayoutGenerator.generate(seed_value)
		var ports := CoastalPortPlacer.place_ports(layout,35,PackedStringArray(WorldPortNames.NAMES))
		var marks := CoastalSeamarks.plan(layout,ports)
		assert(ports.size() == 35)
		for z in range(-18000,18000,500):
			for x in range(-18000,18000,500):
				var at := Vector2(x,z)
				assert(layout.is_land(at) == (layout.sample_seabed_elevation(at) > WaveSurface.WATER_LEVEL))
		assert(not marks.is_empty())
		assert(layout.layout_checksum == WorldLayoutGenerator.generate(seed_value).layout_checksum)
		for way in layout.waterway_centerlines:
			var points: PackedVector2Array = way.points
			for i in range(1,points.size()):
				for step in 8:
					assert(not layout.is_land(points[i-1].lerp(points[i],float(step)/8)))
		var picture := Image.create(1024,1024,false,Image.FORMAT_RGB8)
		for y in 1024:
			for x in 1024:
				var at := Vector2(x/1023.0-.5,y/1023.0-.5)*layout.world_size_m
				var depth := layout.sample_water_depth(at)
				var color := Color("0c2536")
				if depth < 100: color = Color("204459")
				if depth < 25: color = Color("397588")
				if depth < 8: color = Color("73b6bb")
				if layout.is_land(at): color = Color("b8b68b")
				picture.set_pixel(x,y,color)
		for mark in marks:
			var px: Vector2 = (mark.position/layout.world_size_m+Vector2(.5,.5))*1023
			picture.set_pixel(clampi(int(px.x),0,1023),clampi(int(px.y),0,1023),Color.YELLOW)
		var path := "C:/Users/noahs/Pictures/machinescreenshots/coast-v9-%d-%d.png" % [seed_value,Time.get_ticks_usec()]
		var job := WorkerThreadPool.add_task(func(): picture.save_png(path))
		while not WorkerThreadPool.is_task_completed(job): await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(job)
		print("COAST PASS seed=",seed_value," ports=",ports.size()," marks=",marks.size()," elapsed=",Time.get_ticks_msec()-started," image=",path)
	get_tree().quit()
