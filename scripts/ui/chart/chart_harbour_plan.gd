class_name ChartHarbourPlan
extends RefCounted

## World-XZ harbour silhouette for the marine chart.
## Built from PortLayoutGraph (foundation / berth_plan / land_plan), not berth AABBs.
## Lazy-cached per port_id — expand cost is paid once when a harbour enters view.

static var C_FOUNDATION := BrandTokens.alpha(BrandTokens.QUAY, 0.92)
static var C_FOUNDATION_EDGE := BrandTokens.alpha(BrandTokens.CONCRETE, 0.95)
static var C_ASPHALT := BrandTokens.alpha(BrandTokens.QUAY_EDGE, 0.88)
static var C_QUAY := BrandTokens.alpha(BrandTokens.CONCRETE_STAINED, 0.94)
static var C_SHORE := BrandTokens.alpha(BrandTokens.SAND, 0.90)
static var C_DOCK_FACE := BrandTokens.alpha(BrandTokens.CONCRETE_LIGHT, 0.95)

var port_id := ""
var world_origin := Vector3.ZERO
var rotation_y := 0.0
var land_poly := PackedVector2Array()
var foundation_poly := PackedVector2Array()
var shore_poly := PackedVector2Array()
var dock_face_poly := PackedVector2Array()
var quay_polys: Array[PackedVector2Array] = []
var quay_meta: Array[Dictionary] = []
var asphalt_polys: Array[PackedVector2Array] = []
var asphalt_meta: Array[Dictionary] = []
var bounds := Rect2()

static var _cache: Dictionary = {} ## port_id -> ChartHarbourPlan


static func clear_cache() -> void:
	_cache.clear()


## Drop one port so the next draw re-expands with fresh catalog/summary pose.
static func invalidate_port(port_id: String) -> void:
	_cache.erase(port_id.strip_edges())


static func is_cached(port_id: String) -> bool:
	return _cache.has(port_id.strip_edges())


static func for_port(port_id: String, tree: SceneTree, chart_snapshot) -> ChartHarbourPlan:
	var pid := port_id.strip_edges()
	if pid.is_empty():
		return null
	if _cache.has(pid):
		return _cache[pid] as ChartHarbourPlan
	var data := resolve_port_data(pid, tree, chart_snapshot)
	if data == null or data.layout_graph == null:
		## Cache misses so we do not re-expand every frame.
		_cache[pid] = null
		return null
	var plan := from_port_data(data)
	_cache[pid] = plan
	return plan


static func resolve_port_data(port_id: String, tree: SceneTree, chart_snapshot) -> PortData:
	if tree != null:
		var harbour := HarbourRegistry.controller(port_id)
		if harbour != null:
			var plot := harbour.get_parent() as PortPlot
			if plot != null and plot.port_data() != null:
				return plot.port_data()
		var home := tree.root.find_child("HomePort", true, false) as PortPlot
		if home != null and home.port_id == port_id and home.port_data() != null:
			return home.port_data()
	if chart_snapshot == null or chart_snapshot.layout == null:
		return null
	var info: Dictionary = {}
	if tree != null:
		var catalog := tree.root.get_node_or_null("/root/PortCatalog")
		if catalog != null:
			info = catalog.call("get_port_info", port_id) as Dictionary
	if info.is_empty():
		info = chart_snapshot.port_info(port_id)
	if info.is_empty():
		return null
	var definition_record := info.get("port_definition", {}) as Dictionary
	var def := PortDefinition.from_dict(definition_record) \
			if not definition_record.is_empty() else PortDefinition.new()
	def.port_id = port_id
	def.display_name = str(info.get("display_name", port_id))
	def.world_position = info.get("position", Vector3.ZERO) as Vector3
	## Missing yaw must not pretend to be an explicit north-facing pose.
	if definition_record.is_empty() and info.has("rotation_y"):
		def.rotation_y = float(info.get("rotation_y", 0.0))
		def.has_explicit_rotation = true
	elif definition_record.is_empty():
		def.has_explicit_rotation = false
	if definition_record.is_empty():
		def.size = int(info.get("size", 1))
		def.site_seed = int(info.get("layout_seed", 0))
		## A `site_max_size` READ USED TO SIT HERE AND IS DELETED — 2026-08-17,
		## REALITY §3d. Neither producer of `info` can feed it: `PortCatalog`
		## entries have no such key (`register_port` has no such parameter) and a
		## `chart_summary` record always carries `port_definition`, so this branch
		## is not taken on one. With the key absent the line assigned
		## `clampi(PortSizing.MAX_SIZE, …)`, which is the value `PortDefinition.new()`
		## already holds — a no-op in the only case any producer produces.
		##
		## MEASURED BEFORE DELETING, six seeds x 35 ports, `tests/_chart_live_ceiling_probe.gd`:
		## injecting the world's own resolved ceiling into the live `PortCatalog`
		## entry and re-running THIS function moved **no drawn path at 210 of 210
		## ports** — not a polygon point, not the bounds, not the quay count, not
		## the resolved size, not `suggested_span_m`. What it moved, at 50 of 210,
		## is `layout_graph.initial_attributes["site_max_size"]` / `basin_max_size`
		## and one `berth_plan.notes` string, whose only reader in the project is
		## `port_showcase.gd` — an F6 gallery with no route from the shipped game.
		##
		## ⚠ THE LIVE CHART DOES DRAW THE WRONG HARBOUR HERE, AND THE CEILING IS
		## NOT WHY. `register_port` also drops the `region` word, so every unstamped
		## port below resolves to `LEGACY_ISLAND` and gets a different trade theme:
		## injecting the region word ALONE reproduced the stamped harbour's every
		## drawn path at 210 of 210, and without it the silhouette differs from the
		## stamped one at 133 of 210 ports — 70 on the quay polygons, 57 on the
		## bounds, 34 on the berth count. Injecting the whole `port_definition`
		## reproduces the stamp exactly (0 of 210), which names the fix: the catalog
		## should carry the placed definition. Registered in `chart_live_harbour_test`.
		var region := str(info.get("region", "coastal"))
		match region:
			"mainland":
				def.region_kind = PortDefinition.RegionKind.MAINLAND
			"fjord":
				def.region_kind = PortDefinition.RegionKind.FJORD
			"archipelago":
				def.region_kind = PortDefinition.RegionKind.ARCHIPELAGO
			_:
				def.region_kind = PortDefinition.RegionKind.LEGACY_ISLAND
		def.ground_mode = PortDefinition.GroundMode.WORLD_TERRAIN
	return PortExpander.expand(def, int(chart_snapshot.world_seed), chart_snapshot.layout)


static func from_port_data(data: PortData) -> ChartHarbourPlan:
	var plan := ChartHarbourPlan.new()
	if data == null:
		return plan
	plan.port_id = data.port_id
	plan.world_origin = data.world_position
	plan.rotation_y = data.rotation_y
	var graph := data.layout_graph
	if graph == null:
		return plan
	var attrs: Dictionary = graph.initial_attributes
	var foundation: Dictionary = attrs.get("foundation", {}) as Dictionary
	var berth_plan: Dictionary = attrs.get("berth_plan", {}) as Dictionary
	var land_plan: Dictionary = attrs.get("land_plan", {}) as Dictionary

	var zone: Dictionary = land_plan.get("buildable_zone", {}) as Dictionary
	plan.land_poly = PortLandPlan.world_buildable_polygon(
		zone, plan.world_origin, plan.rotation_y, 0.0
	)
	plan.foundation_poly = _foundation_world_poly(foundation, plan.world_origin, plan.rotation_y)
	plan.shore_poly = _polyline_world(
		foundation.get("spine", foundation.get("natural_shore_polyline", [])),
		plan.world_origin,
		plan.rotation_y,
	)
	plan.dock_face_poly = _polyline_world(
		foundation.get("dock_face_polyline", foundation.get("coast_polyline", [])),
		plan.world_origin,
		plan.rotation_y,
	)

	for raw in berth_plan.get("asphalt_stations", []) as Array:
		var station := raw as Dictionary
		var poly := _asphalt_world_poly(station, plan.world_origin, plan.rotation_y)
		if poly.size() >= 3:
			plan.asphalt_polys.append(poly)
			plan.asphalt_meta.append({
				"id": str(station.get("id", "asphalt")),
				"family": str(station.get("family", "general")),
				"commodity_id": str(station.get("commodity_id", "")),
				"role": str(station.get("role", "")),
			})

	for raw in berth_plan.get("quay_stations", []) as Array:
		var station2 := raw as Dictionary
		var poly2 := _quay_world_poly(station2, plan.world_origin, plan.rotation_y)
		if poly2.size() >= 3:
			plan.quay_polys.append(poly2)
			plan.quay_meta.append({
				"id": str(station2.get("id", "quay")),
				"family": str(station2.get("family", "general")),
				"commodities": station2.get("commodities", []),
				"layout": str(station2.get("layout", "single")),
			})

	plan.bounds = _compute_bounds(plan)
	return plan


func draw(canvas: CanvasItem, ctx: Dictionary, show_labels: bool = true) -> void:
	_fill_poly(canvas, ctx, foundation_poly, C_FOUNDATION)
	_stroke_poly(canvas, ctx, foundation_poly, C_FOUNDATION_EDGE, 1.8)
	for i in range(asphalt_polys.size()):
		var family := str(asphalt_meta[i].get("family", "general")) if i < asphalt_meta.size() else "general"
		var tint := CommodityCatalog.terminal_family_color(family)
		var fill := C_ASPHALT.lerp(tint, 0.35)
		fill.a = 0.88
		_fill_poly(canvas, ctx, asphalt_polys[i], fill)
		_stroke_poly(canvas, ctx, asphalt_polys[i], BrandTokens.alpha(BrandTokens.SURFACE_EDGE, 0.85), 1.2)
	for i in range(quay_polys.size()):
		var family2 := str(quay_meta[i].get("family", "general")) if i < quay_meta.size() else "general"
		var tint2 := CommodityCatalog.terminal_family_color(family2)
		var fill2 := C_QUAY.lerp(tint2, 0.4)
		fill2.a = 0.94
		_fill_poly(canvas, ctx, quay_polys[i], fill2)
		_stroke_poly(canvas, ctx, quay_polys[i], BrandTokens.alpha(BrandTokens.PAPER, 0.95), 1.6)
	_stroke_open(canvas, ctx, shore_poly, C_SHORE, 2.0)
	_stroke_open(canvas, ctx, dock_face_poly, C_DOCK_FACE, 2.2)
	if not show_labels:
		return
	## Station labels only when zoomed in enough to read them.
	for i in range(quay_polys.size()):
		_label_poly(canvas, ctx, quay_polys[i], _station_label(quay_meta[i] if i < quay_meta.size() else {}))
	for i in range(asphalt_polys.size()):
		_label_poly(
			canvas,
			ctx,
			asphalt_polys[i],
			_station_label(asphalt_meta[i] if i < asphalt_meta.size() else {}),
		)


func centre_world() -> Vector2:
	if bounds.size.x > 1.0 and bounds.size.y > 1.0:
		return bounds.get_center()
	return Vector2(world_origin.x, world_origin.z)


func suggested_span_m() -> float:
	if bounds.size.x < 1.0 and bounds.size.y < 1.0:
		return 1400.0
	return maxf(maxf(bounds.size.x, bounds.size.y) * 2.4, 700.0)


static func _foundation_world_poly(
		foundation: Dictionary,
		origin: Vector3,
		yaw: float,
) -> PackedVector2Array:
	var spine := _polyline_local(foundation.get("spine", []))
	if spine.size() < 2:
		spine = _polyline_local(foundation.get("natural_shore_polyline", []))
	if spine.size() < 2:
		return PackedVector2Array()
	var sea_m := float(foundation.get("dock_reach_m", PortCoastTracer.FOUNDATION_DOCK_REACH_M)) \
			+ float(foundation.get("bay_lip_m", PortCoastTracer.FOUNDATION_BAY_LIP_M))
	var inland_m := float(foundation.get("town_inland_m", PortCoastTracer.FOUNDATION_TOWN_INLAND_M))
	var sea := PortCoastTracer.offset_spine_perpendicular(
		spine, sea_m, PortCoastTracer.PORT_LOCAL_INLAND_DIR, false
	)
	var inland := PortCoastTracer.offset_spine_perpendicular(
		spine, inland_m, PortCoastTracer.PORT_LOCAL_INLAND_DIR, true
	)
	var local := PackedVector2Array()
	for p in sea:
		local.append(p)
	for i in range(inland.size() - 1, -1, -1):
		local.append(inland[i])
	return _local_poly_to_world(local, origin, yaw)


static func _asphalt_world_poly(
		station: Dictionary,
		origin: Vector3,
		yaw: float,
) -> PackedVector2Array:
	var o := _xz(station.get("origin", [0.0, 0.0]))
	var seaward := _xz(station.get("direction", [0.0, -1.0])).normalized()
	var tangent := _xz(station.get("tangent", [1.0, 0.0])).normalized()
	if seaward.length_squared() < 0.0001:
		seaward = Vector2(0.0, -1.0)
	if tangent.length_squared() < 0.0001:
		tangent = Vector2(-seaward.y, seaward.x)
	var length_m := maxf(float(station.get("length_m", 40.0)), 8.0)
	var depth_m := maxf(float(station.get("depth_m", 36.0)), 8.0)
	var c := o - seaward * (depth_m * 0.5)
	var half_t := tangent * (length_m * 0.5)
	var half_d := seaward * (depth_m * 0.5)
	var local := PackedVector2Array([
		c - half_t - half_d,
		c + half_t - half_d,
		c + half_t + half_d,
		c - half_t + half_d,
	])
	return _local_poly_to_world(local, origin, yaw)


static func _quay_world_poly(
		station: Dictionary,
		origin: Vector3,
		yaw: float,
) -> PackedVector2Array:
	var o := _xz(station.get("origin", [0.0, 0.0]))
	var tip := _xz(station.get("tip", [o.x, o.y]))
	var seaward := _xz(station.get("direction", [0.0, -1.0])).normalized()
	var tangent := _xz(station.get("tangent", [1.0, 0.0])).normalized()
	if seaward.length_squared() < 0.0001 and tip.distance_to(o) > 0.1:
		seaward = (tip - o).normalized()
	if tangent.length_squared() < 0.0001:
		tangent = Vector2(-seaward.y, seaward.x)
	var length_m := maxf(float(station.get("length_m", o.distance_to(tip))), 12.0)
	var width_m := maxf(float(station.get("width_m", 24.0)), 8.0)
	if tip.distance_to(o) < 1.0:
		tip = o + seaward * length_m
	var half_w := tangent * (width_m * 0.5)
	var local := PackedVector2Array([
		o - half_w,
		o + half_w,
		tip + half_w,
		tip - half_w,
	])
	return _local_poly_to_world(local, origin, yaw)


static func _polyline_world(raw: Variant, origin: Vector3, yaw: float) -> PackedVector2Array:
	return _local_poly_to_world(_polyline_local(raw), origin, yaw)


static func _polyline_local(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in raw as Array:
		var pt := item as Array
		if pt.size() >= 2:
			out.append(Vector2(float(pt[0]), float(pt[1])))
	return out


static func _local_poly_to_world(
		local: PackedVector2Array,
		origin: Vector3,
		yaw: float,
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in local:
		out.append(PortCoastTracer.port_local_to_world(p, origin, yaw))
	return out


static func _xz(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


static func _compute_bounds(plan: ChartHarbourPlan) -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var dirty := false
	for poly in [
		plan.land_poly, plan.foundation_poly, plan.shore_poly, plan.dock_face_poly
	]:
		for p in poly:
			min_v = min_v.min(p)
			max_v = max_v.max(p)
			dirty = true
	for poly2 in plan.quay_polys:
		for p2 in poly2:
			min_v = min_v.min(p2)
			max_v = max_v.max(p2)
			dirty = true
	for poly3 in plan.asphalt_polys:
		for p3 in poly3:
			min_v = min_v.min(p3)
			max_v = max_v.max(p3)
			dirty = true
	if not dirty or not min_v.is_finite() or not max_v.is_finite():
		var o := Vector2(plan.world_origin.x, plan.world_origin.z)
		return Rect2(o - Vector2(200, 200), Vector2(400, 400))
	return Rect2(min_v, max_v - min_v)


static func _station_label(meta: Dictionary) -> String:
	var family := CommodityCatalog.terminal_family_display(str(meta.get("family", "")))
	var commodity := CommodityCatalog.commodity_display(str(meta.get("commodity_id", "")))
	if commodity.is_empty() or commodity == "—":
		var commodities: Array = meta.get("commodities", []) as Array
		if not commodities.is_empty():
			commodity = CommodityCatalog.commodity_display(str(commodities[0]))
	if not commodity.is_empty() and commodity != "—":
		return commodity
	return family


static func _fill_poly(
		canvas: CanvasItem,
		ctx: Dictionary,
		world_poly: PackedVector2Array,
		color: Color,
) -> void:
	if world_poly.size() < 3:
		return
	var screen := _sanitized_screen_poly(world_poly, ctx)
	if screen.size() < 3:
		return
	## CanvasItem logs a renderer error when handed a degenerate polygon. Some
	## generated harbour outlines contain duplicate/collinear points, so verify
	## triangulation before crossing the rendering boundary.
	if Geometry2D.triangulate_polygon(screen).is_empty():
		return
	canvas.draw_colored_polygon(screen, color)


static func _sanitized_screen_poly(world_poly: PackedVector2Array, ctx: Dictionary) -> PackedVector2Array:
	var screen := PackedVector2Array()
	for p in world_poly:
		if not p.is_finite():
			continue
		var point := ChartLayerRenderer._world_to_screen(Vector3(p.x, 0.0, p.y), ctx)
		if not point.is_finite():
			continue
		if screen.is_empty() or screen[screen.size() - 1].distance_squared_to(point) > 0.0001:
			screen.append(point)
	if screen.size() > 2 and screen[0].distance_squared_to(screen[screen.size() - 1]) <= 0.0001:
		screen.resize(screen.size() - 1)
	return screen


static func _stroke_poly(
		canvas: CanvasItem,
		ctx: Dictionary,
		world_poly: PackedVector2Array,
		color: Color,
		width: float,
) -> void:
	if world_poly.size() < 2:
		return
	var screen := PackedVector2Array()
	for p in world_poly:
		screen.append(ChartLayerRenderer._world_to_screen(Vector3(p.x, 0.0, p.y), ctx))
	screen.append(screen[0])
	canvas.draw_polyline(screen, color, width, true)


static func _stroke_open(
		canvas: CanvasItem,
		ctx: Dictionary,
		world_poly: PackedVector2Array,
		color: Color,
		width: float,
) -> void:
	if world_poly.size() < 2:
		return
	var screen := PackedVector2Array()
	for p in world_poly:
		screen.append(ChartLayerRenderer._world_to_screen(Vector3(p.x, 0.0, p.y), ctx))
	canvas.draw_polyline(screen, color, width, true)


static func _label_poly(
		canvas: CanvasItem,
		ctx: Dictionary,
		world_poly: PackedVector2Array,
		text: String,
) -> void:
	if text.is_empty() or world_poly.size() < 1:
		return
	var acc := Vector2.ZERO
	for p in world_poly:
		acc += p
	acc /= float(world_poly.size())
	var screen := ChartLayerRenderer._world_to_screen(Vector3(acc.x, 0.0, acc.y), ctx)
	## Sit above pad centre so FREE/TAKEN (drawn below) does not collide.
	canvas.draw_string(
		BrandTheme.font_data(),
		screen + Vector2(-18.0, -8.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		BrandTokens.alpha(BrandTokens.INK_INVERSE, 0.95),
	)
