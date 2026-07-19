class_name ShippingTrafficSnapshotRenderer
extends RefCounted

## Headless-friendly traffic-lab artifact renderer. It turns the same pure-data
## network and vessel records used by authority into an inspectable SVG/PNG.


static func render_svg(
		network: ShippingLaneNetwork,
		vessels: Array[Dictionary],
		summary: Dictionary,
		size := Vector2i(1600, 1000),
) -> String:
	var bounds := _content_bounds(network, vessels)
	var margin := 44.0
	var drawable := Vector2(float(size.x) - margin * 2.0, float(size.y) - margin * 2.0)
	var scale := minf(drawable.x / maxf(bounds.size.x, 1.0),
		drawable.y / maxf(bounds.size.y, 1.0))
	var offset := Vector2(margin, margin) + (drawable - bounds.size * scale) * 0.5
	var lines := PackedStringArray([
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [size.x, size.y],
		'<rect width="100%%" height="100%%" fill="#07131d"/>',
		'<g fill="none" stroke-linecap="round" stroke-linejoin="round">',
	])
	var seen := {}
	if network != null:
		for edge_id in network.sorted_edge_ids():
			var edge := network.edges[edge_id] as Dictionary
			var kind := str(edge.get("kind", ""))
			if kind not in ["main_lane", "regional_lane", "port_connector", "port_approach", "port_merge"]:
				continue
			var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
			if points.size() < 2:
				continue
			var signature := _segment_signature(kind, points[0], points[points.size() - 1])
			if seen.has(signature):
				continue
			seen[signature] = true
			lines.append('<polyline points="%s" stroke="%s" stroke-width="%s" opacity="0.72"/>' % [
				_svg_points(points, bounds, offset, scale),
				"#21b7db" if kind in ["main_lane", "regional_lane"] else "#4fc8a5",
				"2.0" if kind == "main_lane" else "1.2",
			])
	lines.append("</g>")
	for vessel in vessels:
		for raw_step in vessel.get("route_steps", []) as Array:
			var step := raw_step as Dictionary
			if str(step.get("kind", "")) != "open_water":
				continue
			var points := step.get("points", PackedVector2Array()) as PackedVector2Array
			if points.size() >= 2:
				lines.append('<polyline points="%s" fill="none" stroke="#a0efb9" stroke-width="1.1" opacity="0.34"/>' %
					_svg_points(points, bounds, offset, scale))
	for vessel in vessels:
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		var screen := _screen(point, bounds, offset, scale)
		var color := _state_color(str(vessel.get("state", "")))
		lines.append('<circle cx="%.2f" cy="%.2f" r="5.2" fill="%s" stroke="#eaf6fa" stroke-width="1"/>' %
			[screen.x, screen.y, color])
		lines.append('<text x="%.2f" y="%.2f" fill="#d7e7ec" font-family="sans-serif" font-size="10">%s</text>' %
			[screen.x + 7.0, screen.y - 7.0, str(vessel.get("id", ""))])
	lines.append('<rect x="18" y="18" width="430" height="72" rx="5" fill="#02070b" opacity="0.88"/>')
	lines.append('<text x="34" y="46" fill="#e7f5f8" font-family="sans-serif" font-size="18">TRAFFIC LAB · %.0f simulated seconds</text>' %
		float(summary.get("simulated_seconds", 0.0)))
	lines.append('<text x="34" y="72" fill="#9bc6cf" font-family="sans-serif" font-size="14">%d vessels · %d trips · %d collisions · %d starved</text>' % [
		int(summary.get("vessel_count", 0)), int(summary.get("trips_completed", 0)),
		int(summary.get("collisions", 0)), int(summary.get("starved_vessels", 0))])
	lines.append("</svg>")
	return "\n".join(lines)


static func save_artifacts(
		directory: String, network: ShippingLaneNetwork,
		vessels: Array[Dictionary], summary: Dictionary,
) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var svg_path := directory.path_join("traffic_snapshot.svg")
	var png_path := directory.path_join("traffic_snapshot.png")
	var json_path := directory.path_join("traffic_summary.json")
	var svg := render_svg(network, vessels, summary)
	var svg_file := FileAccess.open(svg_path, FileAccess.WRITE)
	if svg_file == null:
		return {"ok": false, "reason": "svg_open_failed"}
	svg_file.store_string(svg)
	var image := Image.new()
	var image_error := image.load_svg_from_string(svg)
	if image_error != OK:
		return {"ok": false, "reason": "svg_render_failed", "error": image_error}
	var png_error := image.save_png(png_path)
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(JSON.stringify(summary, "  "))
	return {
		"ok": png_error == OK,
		"svg_path": ProjectSettings.globalize_path(svg_path),
		"png_path": ProjectSettings.globalize_path(png_path),
		"json_path": ProjectSettings.globalize_path(json_path),
	}


static func _content_bounds(
		network: ShippingLaneNetwork, vessels: Array[Dictionary],
) -> Rect2:
	var points := PackedVector2Array()
	if network != null:
		for edge_id in network.sorted_edge_ids():
			var edge := network.edges[edge_id] as Dictionary
			if str(edge.get("kind", "")) in ["main_lane", "regional_lane", "port_connector", "port_approach", "port_merge"]:
				points.append_array(edge.get("points", PackedVector2Array()) as PackedVector2Array)
	for vessel in vessels:
		points.append(vessel.get("position", Vector2.ZERO) as Vector2)
	if points.is_empty():
		return Rect2(-1.0, -1.0, 2.0, 2.0)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds.grow(maxf(bounds.size.length() * 0.025, 100.0))


static func _svg_points(
		points: PackedVector2Array, bounds: Rect2, offset: Vector2, scale: float,
) -> String:
	var out := PackedStringArray()
	for point in points:
		var screen := _screen(point, bounds, offset, scale)
		out.append("%.2f,%.2f" % [screen.x, screen.y])
	return " ".join(out)


static func _screen(point: Vector2, bounds: Rect2, offset: Vector2, scale: float) -> Vector2:
	return offset + Vector2(point.x - bounds.position.x, bounds.end.y - point.y) * scale


static func _segment_signature(kind: String, a: Vector2, b: Vector2) -> String:
	var ends := PackedStringArray([
		"%d,%d" % [roundi(a.x * 10.0), roundi(a.y * 10.0)],
		"%d,%d" % [roundi(b.x * 10.0), roundi(b.y * 10.0)],
	])
	ends.sort()
	return "%s|%s|%s" % [kind, ends[0], ends[1]]


static func _state_color(state: String) -> String:
	match state:
		"traveling", "traveling_open_water", "departing": return "#2ec8f4"
		"waiting_signal", "waiting_open_water_slot": return "#f4c33e"
		"waiting_berth": return "#dc63ec"
		"docked": return "#45e77f"
		_: return "#d7e7ec"
