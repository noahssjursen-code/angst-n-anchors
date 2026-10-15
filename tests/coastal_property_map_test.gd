extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run() -> void:
	check(ShipyardPlaytestMode.active(), "isolated from captain data")
	var snapshot := ChartDataSnapshot.for_preview(73119, 3, 15000.0)
	var map := MapOverlay.new()
	map.preview_mode = true
	add_child(map)
	map.set_data_snapshot(snapshot)
	map.first_visible_frame = false
	map.camera_initialized = true
	map.layers.set_visible("weather", false)
	map.layers.set_visible("traffic", false)
	var rows := map.renderer.plots.index.plots_in_rect(Rect2(-7500, -7500, 15000, 15000))
	check(not rows.is_empty(), "production coast has plots")
	var row: Dictionary = rows[rows.size()/2]
	var rect := ChartPlotLayer.plot_rect(row)
	map.camera.focus_harbour(rect.get_center(), 2000.0)
	map._redraw_geography()
	await get_tree().process_frame
	await get_tree().process_frame
	print("MAP_PANEL rect=", map.plot_panel.get_global_rect(), " visible=", map.plot_panel.visible,
		" map=", map.size)
	check(map.plot_panel.visible and map.get_global_rect().intersects(map.plot_panel.get_global_rect()),
		"plot inspector visible inside viewport")
	# Cursor-anchored zoom works with the production chart transform.
	var pointer := map._chart_rect().position + map._chart_rect().size * Vector2(0.31, 0.63)
	var before := map._screen_to_world(pointer)
	map._zoom_at(pointer, 1)
	check(before.distance_to(map._screen_to_world(pointer)) < 0.01, "wheel keeps world point under cursor")
	map.interaction_settle = 0.0
	map.overlays_dirty = false
	ChartBaseRaster.finish_pending_detail()
	map._redraw_geography()
	await get_tree().process_frame
	await get_tree().process_frame
	map.set_process(false)
	var static_draws := map.renderer.geography_draw_count
	var mesh_builds := map.renderer.plots.build_count
	for i in 40:
		var motion := InputEventMouseMotion.new()
		motion.position = pointer + Vector2(i*2, 0)
		map._input(motion)
		await get_tree().process_frame
	check(map.renderer.geography_draw_count == static_draws, "hover never redraws static geography")
	check(map.renderer.plots.build_count == mesh_builds, "hover never rebuilds plot mesh")
	# Clicking a parcel emits the same JSON-safe record as the data index.
	map.camera.focus_harbour(rect.get_center(), 2000.0)
	map._redraw_geography()
	await get_tree().process_frame
	var center := map._chart_rect().get_center()
	map._click_chart(center)
	check(map.selected_plot == str(row.id), "click selects exact coastal plot")
	check(not map.plot_focus.visible or map.plot_heading.text.contains(str(row.grid[0])), "inspector matches selected plot")
	var camera_before := map.camera.center
	var span_before := map.camera.span
	map.open_navigation()
	map.set_process(true)
	await get_tree().process_frame
	check(map.camera.center == camera_before and map.camera.span == span_before, "reopening preserves inspection camera")
	map.enter_home_port_pick_mode()
	check(not map.layers.is_visible("plots") and not map.plot_panel.visible, "home port picker excludes property layer")
	var port: Dictionary = snapshot.ports[0]
	var pos: Vector3 = port.position
	map.camera.focus_harbour(Vector2(pos.x, pos.z), 3000.0)
	map.first_visible_frame = false
	map._redraw_geography()
	await get_tree().process_frame
	var port_screen := ChartLayerRenderer._world_to_screen(pos, map.last_ctx)
	map._click_chart(port_screen)
	check(map.selected_port == str(port.id), "home port click still selects harbour")
	map.queue_free()
	await get_tree().process_frame
	print("COASTAL_PROPERTY_MAP failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
