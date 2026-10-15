extends Control

var chart: MapOverlay

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	chart = MapOverlay.new()
	chart.preview_mode = true
	add_child(chart)
	var snapshot := ChartDataSnapshot.for_preview(73119, 5)
	chart.set_data_snapshot(snapshot)
	chart.layers.set_visible("weather", false)
	chart.layers.set_visible("traffic", false)
	chart.close_requested.connect(func() -> void: get_tree().quit())
	if OS.get_cmdline_user_args().has("--capture-coastal-plots"):
		chart.set_process_input(false)
	await get_tree().process_frame
	chart.first_visible_frame = false
	chart.camera_initialized = true
	var coast := snapshot.layout.macro_coastline_contours()
	var focus := coast[coast.size()/2][0]
	chart.camera.focus_harbour(focus, 5200.0)
	chart._redraw_geography()
	if OS.get_cmdline_user_args().has("--capture-coastal-plots"):
		await _capture_review()

func _capture_review() -> void:
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := "%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]
	await _wait_for_chart()
	print("COASTAL_PANEL ", chart.plot_panel.visible, " rect=", chart.plot_panel.get_global_rect(),
		" parent=", chart.size, " stats=", JSON.stringify(chart.get_debug_stats()))
	await RenderingServer.frame_post_draw
	var path := folder.path_join("coastal-plots-" + stamp + "-coast.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("COASTAL_PLOTS_CAPTURE ", path)
	var rows := chart.renderer.plots.index.plots_in_rect(chart.camera.world_bounds(chart._chart_rect().size))
	if not rows.is_empty():
		var row: Dictionary = rows[rows.size()/2]
		chart.selected_plot = str(row.id)
		chart._refresh_plot_panel()
		chart._focus_plot()
	await _wait_for_chart()
	await RenderingServer.frame_post_draw
	path = folder.path_join("coastal-plots-" + stamp + "-selected.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("COASTAL_PLOTS_CAPTURE ", path)
	chart.camera.focus_harbour(Vector2.ZERO, 42000.0)
	chart.selected_plot = ""
	chart._refresh_plot_panel()
	chart._redraw_geography()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	path = folder.path_join("coastal-plots-" + stamp + "-world.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("COASTAL_PLOTS_CAPTURE ", path)
	print("COASTAL_CHART_STATS ", JSON.stringify(chart.get_debug_stats()))
	var max_pan_usec := 0
	var mesh_builds := chart.renderer.plots.build_count
	chart.dragging = true
	for step in 60:
		chart.camera.center = Vector2(float(step-30)*120, 800)
		chart._redraw_geography()
		await RenderingServer.frame_post_draw
		max_pan_usec = maxi(max_pan_usec, chart.renderer.last_geography_usec)
	print("COASTAL_CHART_PAN max_draw_usec=", max_pan_usec,
		" plot_mesh_rebuilds=", chart.renderer.plots.build_count-mesh_builds)
	chart.dragging = false
	get_tree().quit()

func _wait_for_chart() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	# Each new zoom can request one new cached tile after the current job.
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.15).timeout
		if int(chart.renderer.base.debug_stats().pending) == 0:
			await get_tree().process_frame
			if int(chart.renderer.base.debug_stats().pending) == 0:
				return
