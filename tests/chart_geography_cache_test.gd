extends Node

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)


func wait_ready(base: ChartBaseRaster, bounds: Rect2 = Rect2()) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		ChartBaseRaster.poll_detail()
		if bounds.size.x > 0.0:
			base.prepare_visible(bounds)
			var band := ChartBaseRaster.detail_band(maxf(bounds.size.x, bounds.size.y))
			if base._detail_texture != null and base._detail_rect.encloses(bounds.intersection(base._overview_rect)) \
					and base._detail_band <= band and base.world_rect == base._detail_rect:
				return
		elif bool(base.debug_stats().overview_ready):
			base.prepare(base._layout)
			return
		await get_tree().process_frame
	check(false, "background geography finished before deadline")


func run() -> void:
	# Isolated disposable test directory; never remove the user's real cache.
	ChartRasterCache.directory = "res://.codex/chart-cache-test-%d" % OS.get_process_id()
	ChartRasterCache.enabled = true
	ChartBaseRaster.clear_memory_cache()
	var layout := WorldLayoutGenerator.generate(1212599375)
	var overview_rect := Rect2(-layout.half_extent_m, -layout.half_extent_m,
		layout.world_size_m, layout.world_size_m)
	var started := Time.get_ticks_usec()
	var reference := ChartBaseRaster._bake_region_image(layout, overview_rect, 512)
	var synchronous_usec := Time.get_ticks_usec() - started
	check(reference.has_mipmaps(), "full bake contains mipmaps")
	var base := ChartBaseRaster.new()
	started = Time.get_ticks_usec()
	base.prepare(layout)
	var cold_main_usec := Time.get_ticks_usec() - started
	check(base.texture != null, "cold chart immediately has a coarse fallback")
	check(cold_main_usec < synchronous_usec / 3, "cold preparation avoids full bake on main")
	await wait_ready(base)
	check(base.texture.get_image().get_data() == reference.get_data(), "async full overview equals production reference")
	check(int(base.debug_stats().bakes) == 1, "one shared full overview bake")
	check(base.texture.get_image().has_mipmaps(), "overview GPU source retains mipmaps")
	var warm := ChartBaseRaster.new()
	started = Time.get_ticks_usec()
	warm.prepare(layout)
	var memory_usec := Time.get_ticks_usec() - started
	check(warm.texture == base.texture, "another chart shares the same immutable texture")
	warm._drawn_revision = ChartBaseRaster._ready_revision
	var detail_bounds := Rect2(-2500, -2500, 5000, 5000)
	started = Time.get_ticks_usec()
	base.prepare_visible(detail_bounds)
	var request_usec := Time.get_ticks_usec() - started
	await wait_ready(base, detail_bounds)
	check(warm.needs_redraw(), "another retained chart observes shared completion after its poll was consumed")
	var texture := base.texture
	var builds_before := int(base.debug_stats().bakes)
	var max_zoom_usec := 0
	for index in range(100):
		var span := 4200.0 + index * 7.0
		var center := Vector2(index * 1.5, index * 0.75)
		started = Time.get_ticks_usec()
		base.prepare_visible(Rect2(center - Vector2.ONE * span * 0.5, Vector2.ONE * span))
		max_zoom_usec = maxi(max_zoom_usec, Time.get_ticks_usec() - started)
	check(base.texture == texture, "100 nearby zoom/pan updates reuse cached detail")
	check(int(base.debug_stats().bakes) == builds_before, "camera updates trigger no additional samples")
	check(ChartBaseRaster._pending_detail.is_empty(), "camera updates enqueue no obsolete detail jobs")
	check(base.texture.get_image().has_mipmaps(), "detail has mipmaps")
	ChartBaseRaster.clear_memory_cache()
	var disk := ChartBaseRaster.new()
	started = Time.get_ticks_usec()
	disk.prepare(layout)
	var disk_request_usec := Time.get_ticks_usec() - started
	await wait_ready(disk)
	check(int(disk.debug_stats().disk_hits) == 1 and int(disk.debug_stats().bakes) == 0,
		"fresh memory reconstructs overview from persistent cache without sampling")
	check(disk.texture.get_image().get_data() == reference.get_data(), "disk overview preserves pixels and mipmaps")
	disk.prepare_visible(detail_bounds)
	await wait_ready(disk, detail_bounds)
	check(int(disk.debug_stats().disk_hits) == 2 and int(disk.debug_stats().bakes) == 0,
		"persistent detail reused after in-memory cache reset")
	var world_key := ChartRasterCache.world_key(layout)
	var dummy := WorldLayout.new()
	dummy._seed = layout.seed
	dummy._checksum = layout.layout_checksum
	dummy._world_size_m = layout.world_size_m + 1.0
	check(ChartRasterCache.world_key(dummy) != world_key, "extent invalidates geography cache identity")
	dummy._world_size_m = layout.world_size_m
	dummy._seed += 1
	check(ChartRasterCache.world_key(dummy) != world_key, "seed invalidates geography cache identity")
	dummy._seed = layout.seed
	dummy._checksum += "changed"
	check(ChartRasterCache.world_key(dummy) != world_key, "checksum invalidates geography cache identity")
	# Rapidly jump away from a cold requested tile. The old worker must stop
	# at a row boundary; its canceled image must never enter RAM/disk caches.
	var obsolete := Rect2(-15500, -15500, 2000, 2000)
	var latest := Rect2(14000, 14000, 900, 900)
	disk.prepare_visible(obsolete)
	check(not ChartBaseRaster._pending_detail.is_empty(), "rapid-pan fixture starts a cold worker")
	var obsolete_key: String = ChartBaseRaster._pending_detail.key
	var canceled_start := Time.get_ticks_usec()
	disk.prepare_visible(latest)
	var canceled_deadline := Time.get_ticks_msec() + 2000
	while not ChartBaseRaster._pending_detail.is_empty() \
			and str(ChartBaseRaster._pending_detail.key) == obsolete_key \
			and Time.get_ticks_msec() < canceled_deadline:
		await get_tree().process_frame
		disk.prepare_visible(latest)
	var canceled_usec := Time.get_ticks_usec() - canceled_start
	check(int(disk.debug_stats().cancelled_jobs) == 1, "obsolete worker retires without a backlog")
	check(not ChartBaseRaster._detail_textures.has(obsolete_key), "canceled image was not published to RAM")
	check(not FileAccess.file_exists(ChartRasterCache._path(obsolete_key)), "canceled incomplete image was not published to disk")
	await wait_ready(disk, latest)
	check(disk._detail_rect.encloses(latest), "latest rapid-pan view becomes the active detailed image")
	var coastline := ChartCoastlineIndex.new()
	coastline.prepare(layout)
	var second := ChartCoastlineIndex.new()
	second.prepare(layout)
	check(second.build_usec == 0, "separate charts share immutable coastline index")
	var segments := coastline.segments_in(detail_bounds)
	check(coastline.segments_in(detail_bounds) == segments and coastline.query_hits == 1,
		"unchanged coastline query returns retained geometry")
	var snapshot := ChartDataSnapshot.new()
	snapshot.layout = layout
	snapshot.world_seed = layout.seed
	snapshot.ports = [{"id": "cache-test"}]
	var weather := ChartRasterLayer.new()
	check(weather.prepare(snapshot, detail_bounds, 100.0), "weather cold cache builds")
	check(not weather.prepare(snapshot, Rect2(-2600, -2600, 5200, 5200), 100.0),
		"nearby zoom-out uses already finer overscanned weather")
	check(weather.prepare(snapshot, detail_bounds, 100.2), "weather time change invalidates cache")
	# Final teardown may be called by both the minimap and the large chart.
	disk.prepare_visible(Rect2(-7000, -7000, 1500, 1500))
	check(not ChartBaseRaster._pending_detail.is_empty(), "teardown fixture has an in-flight worker")
	ChartBaseRaster.finish_pending_detail()
	ChartBaseRaster.finish_pending_detail()
	check(ChartBaseRaster._pending_detail.is_empty() and ChartBaseRaster._pending_overviews.is_empty(),
		"two chart teardowns join each worker exactly once")
	print("CHART_CACHE timing_us=" + JSON.stringify({
		"old_full_overview_main": synchronous_usec, "cold_prepare_main": cold_main_usec,
		"warm_memory_prepare": memory_usec, "disk_request_main": disk_request_usec,
		"detail_request_main": request_usec, "max_zoom_update": max_zoom_usec,
		"cancel_obsolete_worker": canceled_usec,
		"full_resolution": 512, "detail_resolution": ChartBaseRaster.DETAIL_RESOLUTION}))
	print("CHART_CACHE failures=" + JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
