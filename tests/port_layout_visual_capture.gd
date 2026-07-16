extends SceneTree

## CPU top-down port layout maps (no GPU). Also attempts viewport capture when available.
##   godot --headless --path . --script res://tests/port_layout_visual_capture.gd

const OUTPUT_DIR := "user://port_layout_capture"
const PROJECT_OUTPUT := "res://.godot/port_layout_capture"
const SEED := 424242
const MAP_PX := 1024


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var abs_out := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_out)
	var project_out := ProjectSettings.globalize_path(PROJECT_OUTPUT)
	DirAccess.make_dir_recursive_absolute(project_out)

	var report: Array[String] = []
	report.append("seed=%d generation=%d" % [SEED, PortDefinition.CURRENT_PORT_GENERATION_VERSION])
	report.append("")

	var can_gpu := RenderingServer.get_rendering_device() != null
	var viewport: SubViewport = null
	var world: Node3D = null
	var camera: Camera3D = null
	if can_gpu:
		viewport = SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		root.add_child(viewport)
		world = Node3D.new()
		viewport.add_child(world)
		var environment := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.08, 0.11, 0.14)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.7, 0.76, 0.84)
		env.ambient_light_energy = 0.9
		environment.environment = env
		world.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
		sun.light_energy = 1.35
		world.add_child(sun)
		camera = Camera3D.new()
		camera.current = true
		camera.fov = 48.0
		world.add_child(camera)
		_add_reference_planes(world)

	for size in range(PortSizing.MAX_SIZE + 1):
		var definition := PortDefinition.new()
		definition.port_id = "capture-%d" % size
		definition.display_name = "SIZE %d" % size
		definition.size = size
		definition.region_kind = PortDefinition.RegionKind.MAINLAND
		definition.site_seed = SEED ^ (size * 9973)
		definition.has_lighthouse = size >= 2
		definition.has_fog_horn = size >= 1
		definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND

		var data := PortExpander.expand(definition, SEED)
		var graph := data.layout_graph
		var morphology := str(graph.initial_attributes.get("morphology", "?"))
		var primary := float(graph.primary_quay_pose().get("length_m", 0.0))
		var total_quay := graph.total_quay_length_m()
		var bounds := graph.bounds()
		var contract_half := PortSizing.quay_half_length_m(size)
		var ok_length := primary + 0.5 >= contract_half
		var issues := _critique(graph, size, data)
		report.append(
			"size=%d morphology=%s modules=%d open=%d primary=%.0fm total_quay=%.0fm bounds=%.0fx%.0f contract_half=%.0f %s"
			% [
				size,
				morphology,
				graph.modules.size(),
				graph.open_slots().size(),
				primary,
				total_quay,
				bounds.size.x,
				bounds.size.z,
				contract_half,
				"OK" if ok_length else "SHORT",
			]
		)
		report.append(
			"  exports=%s imports=%s"
			% [",".join(data.trade_profile.export_slots), ",".join(data.trade_profile.import_slots)]
		)
		for issue in issues:
			report.append("  ISSUE: %s" % issue)

		var map_image := _draw_topdown(graph, size, morphology)
		var map_name := "size_%d_%s_map.png" % [size, morphology]
		_save(map_image, abs_out.path_join(map_name))
		_save(map_image, project_out.path_join(map_name))
		print("Port layout map: %s (%d issues)" % [map_name, issues.size()])

		if can_gpu and viewport != null:
			var visualizer := PortLayoutGraphVisualizer.new()
			visualizer.configure(graph)
			world.add_child(visualizer)
			var center := bounds.get_center()
			var span := maxf(maxf(bounds.size.x, bounds.size.z) * 1.35, 120.0)
			camera.position = center + Vector3(span * 0.55, span * 0.85, span * 0.7)
			camera.look_at(center + Vector3(0.0, 1.0, 0.0), Vector3.UP)
			for _frame in range(4):
				await process_frame
			var image := viewport.get_texture().get_image()
			if image != null:
				var file_name := "size_%d_%s.png" % [size, morphology]
				_save(image, abs_out.path_join(file_name))
				_save(image, project_out.path_join(file_name))
				camera.position = center + Vector3(0.0, span * 1.4, span * 0.05)
				camera.look_at(center, Vector3.UP)
				for _frame2 in range(3):
					await process_frame
				image = viewport.get_texture().get_image()
				if image != null:
					file_name = "size_%d_%s_top.png" % [size, morphology]
					_save(image, abs_out.path_join(file_name))
					_save(image, project_out.path_join(file_name))
			visualizer.queue_free()
			await process_frame

	var report_text := "\n".join(report)
	for path in [abs_out.path_join("report.txt"), project_out.path_join("report.txt")]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(report_text)
			file.close()
	print(report_text)
	print("Port layout captures written to %s" % abs_out)
	quit(0)


func _critique(graph: PortLayoutGraph, size: int, data: PortData) -> Array[String]:
	var issues: Array[String] = []
	var primary := float(graph.primary_quay_pose().get("length_m", 0.0))
	if primary + 0.5 < PortSizing.quay_half_length_m(size):
		issues.append("primary quay shorter than coast clearance contract")
	var seaward_min := INF
	var landward_max := -INF
	var yard_count := 0
	var crane_count := 0
	var quay_count := 0
	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition == null:
			continue
		for corner_raw in [
			Vector2(-definition.footprint_m.x, -definition.footprint_m.z) * 0.5,
			Vector2(definition.footprint_m.x, -definition.footprint_m.z) * 0.5,
			Vector2(-definition.footprint_m.x, definition.footprint_m.z) * 0.5,
			Vector2(definition.footprint_m.x, definition.footprint_m.z) * 0.5,
		]:
			var corner := corner_raw as Vector2
			var world_xz := Vector2(placed.position_m.x, placed.position_m.z) \
					+ corner.rotated(deg_to_rad(placed.yaw_degrees))
			seaward_min = minf(seaward_min, world_xz.y)
			landward_max = maxf(landward_max, world_xz.y)
		match definition.kind:
			"quay":
				quay_count += 1
			"cargo":
				yard_count += 1
			"equipment":
				crane_count += 1
	## Coastline marker sits at COASTAL_GRAPH_ROOT_Z_M; berths should poke past it seaward.
	if seaward_min > PortSizing.COASTAL_GRAPH_ROOT_Z_M - 10.0:
		issues.append(
			"layout barely reaches past coastline (seaward tip z=%.0f, coast=%.0f)"
			% [seaward_min, PortSizing.COASTAL_GRAPH_ROOT_Z_M]
		)
	var trade_n := data.trade_profile.export_slots.size() + data.trade_profile.import_slots.size()
	if yard_count < trade_n:
		issues.append("fewer cargo yards (%d) than trade slots (%d)" % [yard_count, trade_n])
	if size >= 1 and crane_count < 1:
		issues.append("no crane pads on developed port")
	if size >= 2 and quay_count < 2:
		issues.append("L/U/finger ports should have multiple quay modules")
	var pier_centers := graph.parallel_seaward_pier_centers()
	if pier_centers.size() >= 2:
		var min_spacing := PortSizing.parallel_pier_center_spacing_m(size)
		for i in range(1, pier_centers.size()):
			var gap := pier_centers[i].x - pier_centers[i - 1].x
			if gap + 0.5 < min_spacing:
				issues.append(
					"parallel pier gap %.0fm < required %.0fm fairway"
					% [gap, min_spacing]
				)
	## Cargo / service / road must not live seaward of the coastline datum.
	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition == null:
			continue
		if not (
			definition.kind in ["cargo", "road", "service"]
			or definition.tags.has("land")
		):
			continue
		var seaward_edge := placed.position_m.z - definition.footprint_m.z * 0.5
		if seaward_edge < PortSizing.COASTAL_GRAPH_ROOT_Z_M - 2.0:
			issues.append(
				"%s (%s) extends into water (seaward edge z=%.0f)"
				% [instance_id, definition.kind, seaward_edge]
			)
	return issues


func _draw_topdown(graph: PortLayoutGraph, size: int, morphology: String) -> Image:
	var image := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.06, 0.09, 0.12, 1.0))
	var bounds := graph.bounds()
	var pad := 40.0
	var span := maxf(maxf(bounds.size.x, bounds.size.z) + pad * 2.0, 160.0)
	var center := bounds.get_center()
	var metres_to_px := float(MAP_PX - 40) / span

	## Water = seaward (−Z), land = inland (+Z) relative to coastline.
	var coast_z := PortSizing.COASTAL_GRAPH_ROOT_Z_M
	_fill_band(image, center, metres_to_px, -5000.0, coast_z, Color(0.05, 0.16, 0.24))
	_fill_band(image, center, metres_to_px, coast_z, 5000.0, Color(0.25, 0.27, 0.24))
	_draw_hline(image, center, metres_to_px, coast_z, Color(0.95, 0.82, 0.25))

	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition == null:
			continue
		var color := definition.color
		var commodity := str(placed.assignment.get("commodity_id", ""))
		if not commodity.is_empty():
			color = CommodityCatalog.commodity_color(commodity)
			if str(placed.assignment.get("role", "")) == "import":
				color = color.darkened(0.18)
		_draw_oriented_rect(
			image,
			center,
			metres_to_px,
			Vector2(placed.position_m.x, placed.position_m.z),
			Vector2(definition.footprint_m.x, definition.footprint_m.z),
			deg_to_rad(placed.yaw_degrees),
			color,
		)

	## Title strip.
	for x in range(MAP_PX):
		for y in range(28):
			image.set_pixel(x, y, Color(0.12, 0.14, 0.18))
	return image


func _fill_band(
		image: Image,
		center: Vector3,
		metres_to_px: float,
		z0: float,
		z1: float,
		color: Color,
) -> void:
	var y0 := int((_world_to_px(center, metres_to_px, Vector2(0.0, z0)).y))
	var y1 := int((_world_to_px(center, metres_to_px, Vector2(0.0, z1)).y))
	var lo := clampi(mini(y0, y1), 0, MAP_PX - 1)
	var hi := clampi(maxi(y0, y1), 0, MAP_PX - 1)
	for y in range(lo, hi + 1):
		for x in range(MAP_PX):
			image.set_pixel(x, y, color)


func _draw_hline(
		image: Image,
		center: Vector3,
		metres_to_px: float,
		z: float,
		color: Color,
) -> void:
	var y := clampi(int(_world_to_px(center, metres_to_px, Vector2(0.0, z)).y), 0, MAP_PX - 1)
	for x in range(MAP_PX):
		image.set_pixel(x, y, color)
		if y + 1 < MAP_PX:
			image.set_pixel(x, y + 1, color)


func _draw_oriented_rect(
		image: Image,
		center: Vector3,
		metres_to_px: float,
		pos: Vector2,
		size_m: Vector2,
		yaw: float,
		color: Color,
) -> void:
	var half := size_m * 0.5
	var corners: Array[Vector2] = [
		pos + Vector2(-half.x, -half.y).rotated(yaw),
		pos + Vector2(half.x, -half.y).rotated(yaw),
		pos + Vector2(half.x, half.y).rotated(yaw),
		pos + Vector2(-half.x, half.y).rotated(yaw),
	]
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var px_corners: Array[Vector2] = []
	for corner in corners:
		var px := _world_to_px(center, metres_to_px, corner)
		px_corners.append(px)
		min_x = minf(min_x, px.x)
		max_x = maxf(max_x, px.x)
		min_y = minf(min_y, px.y)
		max_y = maxf(max_y, px.y)
	for y in range(int(floor(min_y)), int(ceil(max_y)) + 1):
		for x in range(int(floor(min_x)), int(ceil(max_x)) + 1):
			if x < 0 or y < 0 or x >= MAP_PX or y >= MAP_PX:
				continue
			if _point_in_quad(Vector2(x, y), px_corners):
				image.set_pixel(x, y, color)


func _point_in_quad(point: Vector2, quad: Array[Vector2]) -> bool:
	var signs := 0
	for i in range(4):
		var a: Vector2 = quad[i]
		var b: Vector2 = quad[(i + 1) % 4]
		var cross := (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
		if cross >= 0.0:
			signs += 1
		else:
			signs -= 1
	return abs(signs) == 4


func _world_to_px(center: Vector3, metres_to_px: float, world_xz: Vector2) -> Vector2:
	## X right, −Z (seaward) up on the image so water is at the top.
	var local := world_xz - Vector2(center.x, center.z)
	return Vector2(
		MAP_PX * 0.5 + local.x * metres_to_px,
		MAP_PX * 0.5 - local.y * metres_to_px,
	)


func _add_reference_planes(world: Node3D) -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000.0, 2000.0)
	water.mesh = plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.05, 0.16, 0.24)
	water.material_override = water_mat
	water.position.y = -0.3
	world.add_child(water)
	var land := MeshInstance3D.new()
	var land_mesh := BoxMesh.new()
	land_mesh.size = Vector3(900.0, 0.4, 500.0)
	land.mesh = land_mesh
	var land_mat := StandardMaterial3D.new()
	land_mat.albedo_color = Color(0.28, 0.30, 0.27)
	land.material_override = land_mat
	land.position = Vector3(0.0, -0.2, 250.0)
	world.add_child(land)


func _save(image: Image, path: String) -> void:
	if image == null:
		return
	var err := image.save_png(path)
	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])
