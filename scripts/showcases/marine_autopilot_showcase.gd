extends Node2D

## F6 route-plan viewer. The marker advances by distance-along-route exactly as
## a far NPC voyage would; nearby physical ships use VesselAutopilot instead.

const SEED := 90210

var layout: WorldLayout
var plan: MarineRoutePlan
var map_texture: ImageTexture
var progress_m := 0.0
var simulation_speed := 140.0
var paused := false


func _ready() -> void:
	layout = WorldLayoutGenerator.generate(SEED)
	var definitions := CoastalPortPlacer.place_ports(
		layout,
		18,
		PackedStringArray(["A", "B", "C", "D", "E", "F", "G", "H"]),
	)
	if definitions.size() >= 2:
		var a: PortDefinition = definitions[0]
		var b: PortDefinition = definitions[-1]
		var planner := MarineRoutePlanner.new(layout)
		plan = planner.plan(
			Vector2(a.world_position.x, a.world_position.z),
			Vector2(b.world_position.x, b.world_position.z),
			a.port_id,
			b.port_id,
		)
	_build_map_texture()
	queue_redraw()


func _process(delta: float) -> void:
	if paused or plan == null or not plan.is_valid():
		return
	progress_m = fposmod(progress_m + simulation_speed * delta, plan.total_distance_m())
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			paused = not paused
		KEY_R:
			progress_m = 0.0
		KEY_EQUAL, KEY_KP_ADD:
			simulation_speed = minf(simulation_speed * 1.5, 1200.0)
		KEY_MINUS, KEY_KP_SUBTRACT:
			simulation_speed = maxf(simulation_speed / 1.5, 10.0)
	queue_redraw()


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.015, 0.025, 0.035))
	var chart := Rect2(36.0, 72.0, viewport_size.x - 72.0, viewport_size.y - 110.0)
	if map_texture != null:
		draw_texture_rect(map_texture, chart, false)
	draw_rect(chart, Color(0.75, 0.72, 0.55), false, 2.0)
	if plan != null and plan.is_valid():
		var screen_points := PackedVector2Array()
		for point in plan.waypoints:
			screen_points.append(_world_to_screen(point, chart))
		draw_polyline(screen_points, Color(0.95, 0.28, 0.12), 3.0, true)
		var marker := _world_to_screen(plan.point_at_distance(progress_m), chart)
		draw_circle(marker, 7.0, Color(0.95, 0.86, 0.42))
		draw_circle(marker, 10.0, Color(0.95, 0.86, 0.42), false, 2.0)
	var title := "MARINE AUTOPILOT / REPLICATED VOYAGE"
	draw_string(ThemeDB.fallback_font, Vector2(36.0, 34.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.88, 0.72))
	var status := "SPACE pause   R restart   +/- speed   %.0f m/s" % simulation_speed
	if plan != null:
		status += "   route %s   progress %.0f / %.0f m" % [plan.route_id, progress_m, plan.total_distance_m()]
	draw_string(ThemeDB.fallback_font, Vector2(36.0, 58.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.72, 0.70))


func _build_map_texture() -> void:
	if layout == null:
		return
	var resolution := layout.raster_resolution
	var distances := layout.get_signed_distance_raster()
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	for z in range(resolution):
		for x in range(resolution):
			var land := distances[z * resolution + x] < 0.0
			image.set_pixel(x, z, Color(0.53, 0.55, 0.46) if land else Color(0.055, 0.16, 0.21))
	map_texture = ImageTexture.create_from_image(image)


func _world_to_screen(point: Vector2, chart: Rect2) -> Vector2:
	var uv := (point + Vector2.ONE * layout.half_extent_m) / layout.world_size_m
	return chart.position + uv * chart.size
