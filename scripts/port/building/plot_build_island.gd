class_name PlotBuildIsland
extends RefCounted

## Finds a real closed macro-coast island in the production geography.
## No replacement island disks or gameplay ports are generated for this scene.
static func choose(layout: WorldLayout, index: CoastalPlotIndex) -> Dictionary:
	var segments := layout.macro_coastline_contours()
	var endpoints := {}
	for i in segments.size():
		for point in segments[i]:
			var key := Vector2i((point*10.0).round())
			if not endpoints.has(key):
				endpoints[key] = []
			endpoints[key].append(i)
	var seen := {}
	var best := {}
	var best_score := INF
	for start in segments.size():
		if seen.has(start):
			continue
		var stack: Array[int] = [start]
		var component: Array[int] = []
		var bounds := Rect2(segments[start][0], Vector2.ZERO)
		while not stack.is_empty():
			var current: int = stack.pop_back()
			if seen.has(current):
				continue
			seen[current] = true
			component.append(current)
			for point in segments[current]:
				bounds = bounds.expand(point)
				for other in endpoints[Vector2i((point*10.0).round())]:
					if not seen.has(other):
						stack.append(other)
		var span := maxf(bounds.size.x,bounds.size.y)
		if span < 500.0 or span > 2200.0 or not index.world_bounds.grow(-40).encloses(bounds):
			continue
		var candidates := {}
		for segment_id in component:
			for point in [segments[segment_id][0], segments[segment_id][0].lerp(segments[segment_id][1],0.5)]:
				var plot := index.plot_at(point)
				if not plot.is_empty():
					candidates[str(plot.id)] = plot
		var homes := {}
		for id in candidates:
			var dry := dry_point(layout, ChartPlotLayer.plot_rect(candidates[id]))
			if dry.is_finite():
				homes[id] = dry
		if homes.size() < 4:
			continue
		var score := absf(span-1200.0)
		if score < best_score:
			best_score = score
			best = {"bounds": bounds, "homes": homes, "span_m": span}
	return best

## A dry, gently sloped landing inside the exact square chosen on the chart.
static func dry_point(layout: WorldLayout, rect: Rect2) -> Vector3:
	var result := Vector3.INF
	var best := INF
	var deck_y := WaveSurface.WATER_LEVEL+PlotBuildLayout.DECK_HEIGHT_ABOVE_SEA_M
	for z in range(8, int(rect.size.y)-8, 8):
		for x in range(8, int(rect.size.x)-8, 8):
			var at := rect.position + Vector2(x,z)
			if layout.sample_signed_distance(at) > -7.0:
				continue
			var y := WorldTerrainStreamer.sample_render_terrain_height(layout,at)
			if y < WaveSurface.WATER_LEVEL+1.0:
				continue
			var slope := absf(WorldTerrainStreamer.sample_render_terrain_height(layout,at+Vector2(3,0))-y) \
				+ absf(WorldTerrainStreamer.sample_render_terrain_height(layout,at+Vector2(0,3))-y)
			if slope > 3.0:
				continue
			# Arrive on the shore beside the shared deck height, not up the hill.
			var score := slope*8.0 + at.distance_to(rect.get_center())*0.01 + absf(y-(deck_y-.1))*50.0
			if score < best:
				best = score
				result = Vector3(at.x,y+1.0,at.y)
	return result
