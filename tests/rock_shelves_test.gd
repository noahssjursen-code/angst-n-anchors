extends Node
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	for seed_value in [42,1212599375,77127]:
		var layout := WorldLayoutGenerator.generate(seed_value)
		var largest_shallow_radius := 0.0
		var crest_count := 0
		var bank_count := 0
		var offshore := 0
		var coastal := 0
		var gaps := 0
		for feature in layout.rock_features():
			var at: Vector2 = feature.position
			var depth := layout.sample_water_depth(at)
			if feature.kind == "bank": bank_count += 1
			if feature.kind == "crest":
				crest_count += 1
				for angle in 16:
					var direction := Vector2.from_angle(angle*TAU/16.0)
					var radius := 0.0
					while radius < 200 and layout.sample_water_depth(at+direction*radius) < 5.0:
						radius += 2
					largest_shallow_radius = maxf(largest_shallow_radius,radius)
					assert(radius < 65,"Compact crest must not become a broad shallow dome")
			assert(depth > 0 and depth <= 40.01)
			assert(is_equal_approx(layout.sample_seabed_elevation(at),WorldTerrainStreamer.sample_render_terrain_height(layout,at)))
			if layout.sample_signed_distance(at) > 1000: offshore += 1
			if layout.sample_signed_distance(at) < 500: coastal += 1
			for angle in 8:
				var across := Vector2.from_angle(float(angle)*PI/8)*500
				if layout.is_land(at+across) and layout.is_land(at-across):
					gaps += 1
					break
		for feature in layout.rock_features():
			if layout.sample_signed_distance(feature.position) > 300 or feature.kind != "crest": continue
			var coord := Vector2i(floori(feature.position.x/1000),floori(feature.position.y/1000))
			var mesh := WorldTerrainStreamer.build_chunk_mesh_data(layout,coord,25.0,[],0.0)
			var summit_present := false
			for vertex in mesh.vertices:
				if Vector2(vertex.x,vertex.z).distance_to(feature.position) < .01:
					summit_present = true
					assert(absf(vertex.y-layout.sample_seabed_elevation(feature.position)) < .01)
			assert(summit_present,"Render mesh must preserve the actual shallow summit")
			var area := 0.0
			for i in range(0,mesh.indices.size(),3):
				var a: Vector3 = mesh.vertices[mesh.indices[i]]
				var b: Vector3 = mesh.vertices[mesh.indices[i+1]]
				var c: Vector3 = mesh.vertices[mesh.indices[i+2]]
				area += absf(Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z)))*.5
			assert(absf(area-1000000.0) < 2.0,"Coastal floor must tile the complete chunk without gaps")
			break
		assert(crest_count > 20 and bank_count > 5)
		print("SHOAL FOOTPRINT seed=",seed_value," max 5m radius=",largest_shallow_radius," crests=",crest_count," banks=",bank_count)
		assert(offshore > 10)
		assert(coastal > 5)
		assert(gaps > 0,"Submerged hazards also exist between nearby shores")
		var steep := 0
		var checked := 0
		for contour in layout.coastline_contours:
			if checked >= 200: break
			var at := (contour[0]+contour[1])*.5
			var direction := (contour[1]-contour[0]).orthogonal().normalized()
			if layout.is_land(at+direction*50): direction = -direction
			var sample_at := at+direction*50
			if layout.is_land(sample_at): continue
			checked += 1
			if layout.sample_water_depth(sample_at) > 15: steep += 1
		assert(steep > checked*.5)
		var marks := CoastalSeamarks.plan(layout,[])
		for mark in marks:
			assert(layout.sample_signed_distance(mark.position) >= 80)
			assert(mark.kind == "submerged_rock")
		print("ROCK PASS seed=",seed_value," offshore=",offshore," near-island=",coastal," between-shores=",gaps," steep-shores=",steep,"/",checked," marks=",marks.size())
	get_tree().quit()
