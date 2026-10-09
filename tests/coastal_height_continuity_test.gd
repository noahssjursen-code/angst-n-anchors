extends SceneTree

class HistoricalCoast extends WorldLayout:
	func sample_height(p: Vector2) -> float:
		return sample_port_site_height(p)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var total_ports := 0
	var largest_old_step := 0.0
	var largest_new_step := 0.0
	var checked_joins := 0
	for world_seed in [424242, 42, 8675309]:
		for size in [30000.0, 40000.0]:
			var layout := WorldLayoutGenerator.generate(world_seed, WorldConfig.ARCHETYPE_PATH, size)
			var old := HistoricalCoast.new()
			old._initialize(layout.seed, layout.world_size_m, layout.raster_resolution,
				layout.get_signed_distance_raster(), layout.get_region_raster(),
				layout.coastline_contours, layout.waterway_centerlines, layout.layout_checksum)
			var old_ports := CoastalPortPlacer.place_ports(old, 35)
			var new_ports := CoastalPortPlacer.place_ports(layout, 35)
			assert(old_ports.size() == 35 and new_ports.size() == 35)
			for i in 35:
				assert(old_ports[i].to_dict() == new_ports[i].to_dict(), "Shore repair changed a saved port identity")
				var before := PortExpander.expand_uncached(old_ports[i], world_seed, old)
				var after := PortExpander.expand_uncached(new_ports[i], world_seed, layout)
				assert(before.to_chart_dict() == after.to_chart_dict(), "Shore repair changed trade/port record")
				assert(before.layout_graph.initial_attributes.berth_plan == after.layout_graph.initial_attributes.berth_plan,
					"Shore repair changed berth geometry or cargo facilities")
				total_ports += 1
			# Find the shelf boundary along coast normals and inspect a 2cm join.
			for contour in layout.coastline_contours:
				for i in range(0, contour.size(), 8):
					var coast: Vector2 = contour[i]
					var gradient := Vector2(layout.sample_signed_distance(coast + Vector2(1,0)) - layout.sample_signed_distance(coast - Vector2(1,0)),
						layout.sample_signed_distance(coast + Vector2(0,1)) - layout.sample_signed_distance(coast - Vector2(0,1))).normalized()
					var lo := coast
					var hi := coast - gradient * 500.0
					if shelf_coordinate(layout, hi) <= 0.0: continue
					for iteration in 24:
						var mid := (lo + hi) * 0.5
						if shelf_coordinate(layout, mid) < 0.0: lo = mid
						else: hi = mid
					var join := (lo + hi) * 0.5
					var a := join + gradient * 0.01
					var b := join - gradient * 0.01
					var step_old := absf(old.sample_height(a) - old.sample_height(b))
					var step_new := absf(layout.sample_height(a) - layout.sample_height(b))
					largest_old_step = maxf(largest_old_step, step_old)
					largest_new_step = maxf(largest_new_step, step_new)
					assert(step_new < 0.03, "Coastal height still jumps at shelf join")
					checked_joins += 1
			print("COAST ports preserved ", world_seed, " size ", size)
	assert(checked_joins > 100 and largest_old_step > 8.0)
	print("COAST PASS ports=", total_ports, " joins=", checked_joins, " old_jump_m=", largest_old_step, " new_jump_m=", largest_new_step)
	quit()

func shelf_coordinate(layout: WorldLayout, p: Vector2) -> float:
	var coast_var := pow(WorldLayout._noise_01(layout._coast_noise, p), 0.68)
	return -layout.sample_signed_distance(p) - lerpf(36.0, 220.0, coast_var)
