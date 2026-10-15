extends Node3D
## Native review: generated coastal geography, production forest and finite cut.
## Run with --shipyard-playtest. Captures use one unchanged camera and lighting.

var forest: WorldForestStreamer
var camera: Camera3D
var label: Label
var output := ""
var footprint: Dictionary
var focus := Vector3.ZERO

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	output = "C:/Users/noahs/Pictures/machinescreenshots/custom-port-forest-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	var layout := WorldLayoutGenerator.generate(424242, WorldLayoutGenerator.DEFAULT_CONFIG_PATH, 10000)
	ForestField.initialize(layout, layout.seed)
	var site := Vector2.ZERO
	var best := 0.0
	# Select existing woodland from the generated field rather than an empty display plot.
	for z in range(-3072, 3073, 256):
		for x in range(-3072, 3073, 256):
			var p := Vector2(x + 128, z + 128)
			var density := ForestField.sample(p)
			if density > best and layout.sample_height(p) > 8 and layout.sample_height(p) < 280:
				site = p
				best = density
	assert(best > .55, "Generated review fixture contains no suitable populated woodland")
	focus = Vector3(site.x, WorldForestStreamer.sample_root_height(layout, site, [], {}), site.y)
	var polygon := PackedVector2Array()
	for corner in [Vector2(-70, -85), Vector2(70, -85), Vector2(70, 85), Vector2(-70, 85)]:
		polygon.append(site + corner.rotated(.22))
	footprint = {"polygon": polygon, "forest_clear_only": true}
	_build_lighting()
	_build_terrain(layout, site)
	camera = Camera3D.new()
	camera.fov = 48
	camera.far = 5000
	add_child(camera)
	camera.position = focus + Vector3(190, 210, 270)
	camera.look_at(focus + Vector3(0, 7, 0))
	camera.current = true
	forest = WorldForestStreamer.new()
	forest.boot_focus = focus
	forest.build_budget_ms = 8
	forest.max_jobs_per_frame = 4
	add_child(forest)
	forest.configure(layout)
	_build_boundary(layout, polygon)
	label = Label.new()
	label.position = Vector2(22, 18)
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	await _settle()
	var original := _roots_inside()
	assert(original > 80, "Visual fixture must actually clear a tree-rich footprint")
	var base_pixels := ForestField.coverage_texture().get_image().get_data()
	await _capture("01-before", "Before clearing", original)
	forest.set_custom_port_exclusions("review-port", [footprint])
	await _settle()
	assert(_roots_inside() == 0, "Production near forest still occupies custom footprint")
	await _capture("02-cleared", "Custom port footprint cleared", _roots_inside())
	forest.set_custom_port_exclusions("review-port", [])
	await _settle()
	assert(_roots_inside() == original, "Undo did not restore original tree count")
	assert(ForestField.coverage_texture().get_image().get_data() == base_pixels, "Custom clearing changed base coverage texture")
	await _capture("03-restored", "Footprint removed — forest restored", _roots_inside())
	print("CUSTOM PORT FOREST REVIEW PASS site=", site, " density=", best, " trees_inside=", original, " output=", output)
	forest.queue_free()
	await get_tree().process_frame
	ForestField.clear()
	get_tree().quit()

func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.39, .48, .56)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.74, .83, .94)
	env.environment.ambient_light_energy = .65
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

func _build_terrain(layout: WorldLayout, site: Vector2) -> void:
	var builder := WorldTerrainStreamer.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/shaders/terrain.gdshader")
	TerrainSurfaceMaps.bind_to_material(material, layout.seed)
	material.set_shader_parameter("forest_map", ForestField.coverage_texture())
	material.set_shader_parameter("forest_world_half_extent_m", ForestField.world_half_extent_m())
	var center := WorldTerrainStreamer.world_to_chunk(site)
	for z in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var data := WorldTerrainStreamer.build_chunk_mesh_data(layout, Vector2i(x, z), 25, [], 0)
			var visual := MeshInstance3D.new()
			visual.mesh = builder._array_mesh_from_data(data)
			visual.material_override = material
			add_child(visual)
	builder.free()

func _build_boundary(layout: WorldLayout, polygon: PackedVector2Array) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(.3, .95, 1)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge in polygon.size():
		for step in 30:
			for endpoint in 2:
				var p := polygon[edge].lerp(polygon[(edge + 1) % polygon.size()], (step + endpoint) / 30.0)
				mesh.surface_add_vertex(Vector3(p.x, WorldForestStreamer.sample_root_height(layout, p, [], {}) + .35, p.y))
	mesh.surface_end()
	var outline := MeshInstance3D.new()
	outline.mesh = mesh
	add_child(outline)

func _settle() -> void:
	# Give the streamer one request refresh before checking empty queues.
	for frame in 8: await get_tree().process_frame
	for attempt in 300:
		var stats := forest.get_debug_stats()
		if stats.pending == 0 and stats.world_canopy_pending == 0 and forest._distant.exclusion_jobs.is_empty():
			for frame in 12: await get_tree().process_frame
			return
		await get_tree().create_timer(.1).timeout
	assert(false, "Custom forest review did not settle")

func _roots_inside() -> int:
	var count := 0
	for record: Dictionary in forest._chunks.values():
		for xf: Transform3D in record.get("transforms", []):
			if ForestField.inside_flatten_zones(Vector2(xf.origin.x, xf.origin.z), [footprint]): count += 1
	return count

func _capture(tag: String, state: String, count: int) -> void:
	label.text = "%s\n140 × 170 m footprint · %d near trees inside" % [state, count]
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var path := output.path_join(tag + ".png")
	var job := WorkerThreadPool.add_task(func(): assert(picture.save_png(path) == OK))
	while not WorkerThreadPool.is_task_completed(job): await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(job)
	print("CAPTURE ", path)
