extends Node
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var start := Time.get_ticks_usec()
	var layout := WorldLayoutGenerator.generate(1212599375)
	print("PERF generation_ms=",(Time.get_ticks_usec()-start)/1000.0)
	var features := layout.skerry_features()
	var densest := Vector2i.ZERO
	var counts := {}
	for feature in features:
		var coord := WorldTerrainStreamer.world_to_chunk(feature.position)
		counts[coord] = int(counts.get(coord,0))+1
		if counts[coord] > int(counts.get(densest,0)): densest = coord
	print("PERF densest=",densest," count=",counts[densest])
	for step in [25.0,50.0,100.0,200.0]:
		start = Time.get_ticks_usec()
		var mesh := WorldTerrainStreamer.build_chunk_mesh_data(layout,densest,step,[],0)
		print("PERF step=",step," ms=",(Time.get_ticks_usec()-start)/1000.0," vertices=",mesh.vertices.size()," triangles=",mesh.indices.size()/3)
	var raster := ChartBaseRaster.new()
	start = Time.get_ticks_usec()
	raster.prepare(layout)
	print("PERF chart_overview_ms=",(Time.get_ticks_usec()-start)/1000.0)
	var region := Rect2(WorldTerrainStreamer.chunk_origin(densest),Vector2(2000,1100))
	start = Time.get_ticks_usec()
	raster.prepare_visible(region)
	print("PERF chart_detail_request_main_ms=",(Time.get_ticks_usec()-start)/1000.0)
	var deadline := Time.get_ticks_msec()+10000
	while raster.world_rect.size.x > 3000 and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		raster.prepare_visible(region)
	assert(raster.world_rect.size.x <= 3000,"Background tile must replace overview")
	print("PERF chart_detail_ready_ms=",(Time.get_ticks_usec()-start)/1000.0)
	start = Time.get_ticks_usec()
	raster.prepare_visible(region)
	print("PERF chart_cached_detail_ms=",(Time.get_ticks_usec()-start)/1000.0)
	# Request a different region, then close while the worker is in flight.
	# Teardown must join it before the layout/script can be released.
	raster.prepare_visible(Rect2(region.position+Vector2(3000,0),region.size))
	assert(not ChartBaseRaster._pending_detail.is_empty())
	ChartBaseRaster.finish_pending_detail()
	assert(ChartBaseRaster._pending_detail.is_empty())
	print("Chart background completion and early teardown: PASS")
	get_tree().quit()
