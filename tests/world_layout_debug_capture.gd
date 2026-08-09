extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const IMAGE_SIZE := 256
const REPRESENTATIVE_SEEDS := [42, 90210, 8675309]


func _initialize() -> void:
	var t := TestReport.new("world_layout_debug_capture")
	var output_dir := OS.get_user_data_dir().path_join("world_layout_debug")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var captures_written := 0
	var capture_seeds := _requested_seeds()
	var checksums := {}
	var renders := {}
	for seed_index in range(capture_seeds.size()):
		var seed: int = capture_seeds[seed_index]
		var layout: WorldLayout = GENERATOR.generate(seed)
		var ports: Array[PortDefinition] = PORT_PLACER.place_ports(layout, 35)
		var image := _render(layout, ports)
		var path := output_dir.path_join("norway_coast_%d.png" % seed)
		var saved: bool = t.check("seed %d capture written" % seed, image.save_png(path) == OK)
		# save_png returning OK is not evidence the bytes are on disk and legible,
		# and a capture nobody can open is worth nothing as review evidence.
		var reloaded: Image = Image.load_from_file(path) if saved else null
		var legible: bool = t.check(
			"seed %d capture reloads at %dx%d" % [seed, IMAGE_SIZE, IMAGE_SIZE],
			reloaded != null
			and not reloaded.is_empty()
			and reloaded.get_width() == IMAGE_SIZE
			and reloaded.get_height() == IMAGE_SIZE,
		)
		var colors := _distinct_colors(reloaded) if legible else 0
		var readable: bool = t.check(
			"seed %d capture is not blank paint (%d colours)" % [seed, colors],
			colors >= 8,
		)
		checksums[layout.layout_checksum] = true
		if legible:
			renders[FileAccess.get_md5(path)] = true
		print("WorldLayout debug capture: %s checksum=%s" % [path, layout.layout_checksum])
		if saved and legible and readable:
			captures_written += 1
	t.equal("captures written", captures_written, capture_seeds.size())
	if capture_seeds.size() > 1:
		# A generator that ignored its seed would satisfy every per-seed check
		# above and still emit the same coast three times.
		t.equal("each seed yields a distinct layout", checksums.size(), capture_seeds.size())
		t.equal("each seed yields a distinct render", renders.size(), capture_seeds.size())
	print("WorldLayout debug captures: wrote %d representative seeds" % captures_written)
	t.finish(self)


func _distinct_colors(image: Image) -> int:
	var seen := {}
	for py in range(0, IMAGE_SIZE, 4):
		for px in range(0, IMAGE_SIZE, 4):
			seen[image.get_pixel(px, py)] = true
	return seen.size()


func _requested_seeds() -> Array[int]:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--world-capture-seed="):
			return [int(argument.get_slice("=", 1))]
	var seeds: Array[int] = []
	seeds.assign(REPRESENTATIVE_SEEDS)
	return seeds


func _render(layout: WorldLayout, ports: Array[PortDefinition]) -> Image:
	var image := Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	var half := layout.half_extent_m
	for py in range(IMAGE_SIZE):
		var world_z := lerpf(half, -half, float(py) / float(IMAGE_SIZE - 1))
		for px in range(IMAGE_SIZE):
			var world_x := lerpf(-half, half, float(px) / float(IMAGE_SIZE - 1))
			var point := Vector2(world_x, world_z)
			var signed_distance := layout.sample_signed_distance(point)
			var region := layout.classify_region(point)
			var color := _region_water_color(region)
			if signed_distance < 0.0:
				var height_t := clampf(layout.sample_height(point) / 800.0, 0.0, 1.0)
				color = Color(0.18, 0.34, 0.16).lerp(Color(0.55, 0.58, 0.38), height_t)
			image.set_pixel(px, py, color)
	for contour in layout.coastline_contours:
		_draw_world_line(image, contour[0], contour[1], half, Color(0.98, 0.86, 0.45))
	for waterway in layout.waterway_centerlines:
		var points: PackedVector2Array = waterway["points"]
		var line_color := Color(0.1, 0.95, 1.0) if String(waterway["kind"]) == "trunk" else Color(0.45, 0.75, 1.0)
		for i in range(points.size() - 1):
			_draw_world_line(image, points[i], points[i + 1], half, line_color)
	for port in ports:
		var world := Vector2(port.world_position.x, port.world_position.z)
		var pixel := _world_to_pixel(world, half)
		var marker := Color(1.0, 0.25, 0.12) if port.port_id == "port-home" else Color(1.0, 0.96, 0.72)
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				var x := clampi(int(round(pixel.x)) + ox, 0, IMAGE_SIZE - 1)
				var y := clampi(int(round(pixel.y)) + oy, 0, IMAGE_SIZE - 1)
				image.set_pixel(x, y, marker)
	return image


func _region_water_color(region: WorldLayout.Region) -> Color:
	match region:
		WorldLayout.Region.FJORD:
			return Color(0.05, 0.32, 0.48)
		WorldLayout.Region.ARCHIPELAGO:
			return Color(0.06, 0.25, 0.38)
		WorldLayout.Region.MAINLAND:
			return Color(0.08, 0.29, 0.39)
		_:
			return Color(0.025, 0.12, 0.24)


func _draw_world_line(image: Image, a: Vector2, b: Vector2, half: float, color: Color) -> void:
	var pa := _world_to_pixel(a, half)
	var pb := _world_to_pixel(b, half)
	var delta := pb - pa
	var steps := maxi(1, int(maxf(absf(delta.x), absf(delta.y))))
	for i in range(steps + 1):
		var point := pa.lerp(pb, float(i) / float(steps))
		var x := clampi(int(round(point.x)), 0, IMAGE_SIZE - 1)
		var y := clampi(int(round(point.y)), 0, IMAGE_SIZE - 1)
		image.set_pixel(x, y, color)
		if x + 1 < IMAGE_SIZE:
			image.set_pixel(x + 1, y, color)


func _world_to_pixel(point: Vector2, half: float) -> Vector2:
	return Vector2(
		(point.x + half) / (half * 2.0) * float(IMAGE_SIZE - 1),
		(half - point.y) / (half * 2.0) * float(IMAGE_SIZE - 1)
	)
