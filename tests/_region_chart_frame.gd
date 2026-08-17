extends Node

## SCRATCH CAPTURE RIG — leading underscore, so the gate does not score it.
## LANE B, and it has to be: `ChartHarbourPlan` names `HarbourRegistry` bare, which
## reaches `harbour_authority_bridge.gd`'s bare `WorldGateway`, so under `--script`
## the file fails to COMPILE (CONVENTIONS §2).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_region_chart_frame.tscn
##
## ── WHAT THIS PHOTOGRAPHS ───────────────────────────────────────────────────
##
## The harbour a player sees when they press **M**. `game_menu.gd:133` binds
## `open_map`; `:164` builds the chart's snapshot with
## `ChartDataSnapshot.from_live_tree`, which copies `PortCatalog` records verbatim,
## and `chart_layer_renderer._draw_visible_harbours` draws every visible port's
## silhouette through `ChartHarbourPlan.for_port`.
##
## Two registrations of the SAME expanded `PortData`, drawn with the SAME camera:
##
##   BEFORE — `world.gd:_setup_ports` as of `f96ca38`: fourteen arguments, so
##            `register_port`'s `region` defaults to `"coastal"`, which
##            `resolve_port_data` maps to `LEGACY_ISLAND`.
##   AFTER  — the same call plus the fifteenth argument, the placed region word.
##
## Both panels are produced in one process from one expansion, so the only thing
## that differs between them is that argument. The rig also asserts, on stdout,
## that AFTER is byte-equal to the STAMPED harbour (the `PortData` the world's own
## `PortPlot` would hand the chart) on every drawn path — otherwise the frame is
## showing something that is not the fix.
##
## The caption band carries the port card rows `chart_layer_renderer.gd:674-684`
## draws beside the silhouette, before and after, because `region` is read there
## too and a frame that hid that would be hiding half of what the fix changes.
##
## ── REPRODUCIBILITY ─────────────────────────────────────────────────────────
##
## Pins the clock through `tests/support/capture_clock.gd` and settles on
## `RenderingServer.frame_post_draw`, per CONVENTIONS §3 — even though nothing
## drawn here is lit or wall-clock driven (it is a seeded 2D canvas: no
## `ShipLight`, no ocean `wave_time`, no `WeatherLighting` read). Do not quote a
## `REPRO_GAP=0` pair as reproducibility.
##
## MEASURED 2026-08-17, `REPRO_DIR=screenshots/chart tools/repro.sh _region_chart_frame`
## at the default 780 s gap (13 game hours), twice — once before and once after the
## caption was corrected: **REPRODUCIBLE — 10 frames byte-identical across two runs**,
## exit 0, both times.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const CaptureClock := preload("res://tests/support/capture_clock.gd")

## Same seed and population as `chart_live_harbour_test`, so the frame and the
## unit are talking about the same twenty harbours.
const SEED := 90210
const PORT_COUNT := 20
const SHOOT_PORTS := 2

const OUT_DIR := "res://screenshots/chart"
const VIEW_W := 1100
const VIEW_H := 820
const CAPTION_H := 176.0
## The zoom at which `chart_layer_renderer` starts drawing station labels
## (`HARBOUR_LABEL_SPAN_M`) — a player reading a harbour is at or below this.
const APPROACH_SPAN_M := 4500.0

const PLAYER_FACING_KEYS: Array[String] = [
	"land_poly", "foundation_poly", "shore_poly", "dock_face_poly",
	"quay_polys", "quay_meta", "asphalt_polys", "asphalt_meta",
	"quay_poly_count", "asphalt_poly_count",
	"bounds", "centre_world", "suggested_span_m", "world_origin", "rotation_y",
	"data_size", "data_berth_count", "data_max_ship_class",
]


class StubWorld:
	extends Node
	var layout: WorldLayout
	var seed_value := 0

	func get_world_layout() -> WorldLayout:
		return layout

	func get_shipping_lane_network():
		return null

	func get_world_traffic_service():
		return null

	func get_world_context() -> Dictionary:
		return {
			"seed": seed_value,
			"generation_version": 0,
			"layout_checksum": str(layout.layout_checksum) if layout != null else "",
			"world_size_m": layout.world_size_m if layout != null else 40000.0,
			"world_preset": "standard",
		}


## Draws one panel. `mode` is "before", "after" or "overlay".
class Painter:
	extends Node2D

	var before: ChartHarbourPlan
	var after: ChartHarbourPlan
	var ctx: Dictionary = {}
	var mode := "after"
	var caption: Array[String] = []
	var span_m := 0.0
	## Passed in rather than read off the outer script: an inner class does not see
	## the enclosing script's constants.
	var panel := Vector2(1100.0, 820.0)

	func _draw() -> void:
		var chart: Rect2 = ctx["chart_rect"]
		draw_rect(Rect2(Vector2.ZERO, panel), BrandTokens.CHART_SEA)
		if mode != "before":
			after.draw(self, ctx, true)
		if mode != "after":
			if mode == "overlay":
				## Outline only, in the alert colour, so the old silhouette reads as
				## a ghost over the corrected one rather than covering it.
				_ghost(before)
			else:
				before.draw(self, ctx, true)
		## The caption band is painted OVER the plans: `ChartHarbourPlan.draw` does
		## not clip to `chart_rect`, so a harbour taller than the view would
		## otherwise run up through the text.
		draw_rect(Rect2(Vector2.ZERO, Vector2(panel.x, chart.position.y)), BrandTokens.INK_BODY)
		_scale_bar(chart)
		var font := BrandTheme.font_data()
		for i in range(caption.size()):
			draw_string(
				font, Vector2(18.0, 26.0 + i * 19.0), caption[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BrandTokens.INK_INVERSE,
			)

	func _ghost(plan: ChartHarbourPlan) -> void:
		var hot := BrandTokens.ALERT
		hot.a = 0.95
		for poly in plan.quay_polys:
			_outline(poly, hot, 2.4)
		for poly2 in plan.asphalt_polys:
			_outline(poly2, hot, 1.4)
		_outline(plan.foundation_poly, Color(hot.r, hot.g, hot.b, 0.55), 1.6)

	func _outline(world_poly: PackedVector2Array, color: Color, width: float) -> void:
		if world_poly.size() < 2:
			return
		var screen := PackedVector2Array()
		for p in world_poly:
			screen.append(ChartLayerRenderer._world_to_screen(Vector3(p.x, 0.0, p.y), ctx))
		screen.append(screen[0])
		draw_polyline(screen, color, width, true)

	## An absolute scale reference. A silhouette comparison without one cannot say
	## whether a change is 5 m or 200 m (CONVENTIONS §3a's rule, in 2D).
	func _scale_bar(chart: Rect2) -> void:
		var bounds: Rect2 = ctx["world_bounds"]
		var step := 100.0
		for candidate in [50.0, 100.0, 200.0, 500.0, 1000.0]:
			step = candidate
			if candidate / bounds.size.x * chart.size.x >= 110.0:
				break
		var px := step / bounds.size.x * chart.size.x
		var y := chart.position.y + chart.size.y - 26.0
		var x := chart.position.x + 22.0
		draw_line(Vector2(x, y), Vector2(x + px, y), BrandTokens.INK_INVERSE, 2.0)
		draw_line(Vector2(x, y - 5.0), Vector2(x, y + 5.0), BrandTokens.INK_INVERSE, 2.0)
		draw_line(Vector2(x + px, y - 5.0), Vector2(x + px, y + 5.0), BrandTokens.INK_INVERSE, 2.0)
		draw_string(
			BrandTheme.font_data(), Vector2(x, y - 10.0),
			"%d m   ·   view span %d m" % [int(step), int(span_m)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BrandTokens.INK_INVERSE,
		)


var _viewport: SubViewport
var _painter: Painter


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var pinned := CaptureClock.pin(get_tree())
	print("_region_chart_frame: clock pinned at time_of_day %.3f" % pinned)

	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		print("NO PortCatalog AUTOLOAD — rig cannot run")
		get_tree().quit(1)
		return

	var layout: WorldLayout = GENERATOR.generate(SEED)
	var defs: Array = PLACER.place_ports(
		layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
	if defs.size() != PORT_COUNT:
		print("PLACER RETURNED %d, EXPECTED %d — refusing to shoot" % [defs.size(), PORT_COUNT])
		get_tree().quit(1)
		return

	catalog.call("clear")
	PortDataCache.clear()
	LandField.initialize(layout)
	FishingField.initialize(SEED)
	WeatherField.world_seed = SEED
	WeatherFrontField.initialize(SEED)

	var records: Array = []
	for raw in defs:
		var placed := raw as PortDefinition
		var source := placed.to_dict()
		var world_def := PortDefinition.from_dict(source)
		var world_data := PortExpander.expand(world_def, SEED, layout)
		## `world.gd:_setup_ports` as of f96ca38 — fourteen arguments.
		catalog.call(
			"register_port",
			world_data.port_id, world_data.display_name, world_data.world_position,
			Vector3(INF, INF, INF),
			world_data.commodity_export, world_data.commodity_imports,
			world_data.island_width, world_data.plot_depth, world_data.layout_seed,
			world_data.population, world_data.features, world_data.rotation_y,
			world_data.berth_count, world_data.size,
		)
		records.append({"source": source, "data": world_data})

	var stub := StubWorld.new()
	stub.name = "ProbeWorld"
	stub.layout = layout
	stub.seed_value = SEED
	stub.add_to_group("world")
	get_tree().root.add_child(stub)
	var snapshot := ChartDataSnapshot.from_live_tree(get_tree())

	## ── measure first, choose the subject second ─────────────────────────────
	var scored: Array[Dictionary] = []
	for rec_raw in records:
		var rec: Dictionary = rec_raw
		var data := rec["data"] as PortData
		var pid := data.port_id
		var region_word := _region_word(int((rec["source"] as Dictionary).get("region_kind", 0)))
		var b := _draw_live(pid, snapshot, "coastal", catalog)
		var a := _draw_live(pid, snapshot, region_word, catalog)
		var c := _digest(ChartHarbourPlan.from_port_data(data), data)
		var moved := _diff(b, c, PLAYER_FACING_KEYS)
		var fixed := _diff(a, c, PLAYER_FACING_KEYS)
		scored.append({
			"pid": pid,
			"region": region_word,
			"moved": moved.keys(),
			"fixed_paths": fixed.keys(),
			"quay_delta": int(b["quay_poly_count"]) - int(c["quay_poly_count"]),
			"span_before": float(b["suggested_span_m"]),
			"span_after": float(c["suggested_span_m"]),
			"berth_before": int(b["data_berth_count"]),
			"berth_after": int(c["data_berth_count"]),
			"quay_meta_before": str(b["quay_meta"]),
			"quay_meta_after": str(c["quay_meta"]),
			"before_plan": b["plan"],
			"after_plan": a["plan"],
			"stamp_plan": c["plan"],
			"data": data,
		})

	var unfixed := 0
	for entry in scored:
		if not (entry["fixed_paths"] as Array).is_empty():
			unfixed += 1
			print("AFTER STILL DIVERGES at %s: %s" % [entry["pid"], str(entry["fixed_paths"])])
	print("_region_chart_frame: %d of %d ports drew a different harbour BEFORE; %d still differ AFTER"
		% [_moved_count(scored), PORT_COUNT, unfixed])

	scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var nx := (x["moved"] as Array).size()
		var ny := (y["moved"] as Array).size()
		if nx != ny:
			return nx > ny
		if absi(int(x["quay_delta"])) != absi(int(y["quay_delta"])):
			return absi(int(x["quay_delta"])) > absi(int(y["quay_delta"]))
		return str(x["pid"]) < str(y["pid"]))

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEW_W, VIEW_H)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_painter = Painter.new()
	_painter.panel = Vector2(float(VIEW_W), float(VIEW_H))
	_viewport.add_child(_painter)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var shot := 0
	for entry_raw in scored:
		if shot >= SHOOT_PORTS:
			break
		var entry: Dictionary = entry_raw
		if (entry["moved"] as Array).is_empty():
			continue
		shot += 1
		await _shoot_port(entry)

	get_tree().root.remove_child(stub)
	stub.free()
	print("_region_chart_frame: wrote frames for %d ports under %s" % [shot, OUT_DIR])
	get_tree().quit(0)


func _moved_count(scored: Array) -> int:
	var n := 0
	for entry in scored:
		if not (entry["moved"] as Array).is_empty():
			n += 1
	return n


func _shoot_port(entry: Dictionary) -> void:
	var pid := str(entry["pid"])
	var before := entry["before_plan"] as ChartHarbourPlan
	var after := entry["after_plan"] as ChartHarbourPlan
	var data := entry["data"] as PortData

	print("")
	print("=== %s (%s) — paths that moved: %s" % [pid, str(entry["region"]), str(entry["moved"])])
	print("    quay pads  before %d  after %d" % [
		before.quay_polys.size(), after.quay_polys.size()])
	print("    berths     before %d  after %d" % [
		int(entry["berth_before"]), int(entry["berth_after"])])
	print("    chart zoom-to-harbour span  before %.1f m  after %.1f m" % [
		float(entry["span_before"]), float(entry["span_after"])])
	print("    quay families before %s" % str(entry["quay_meta_before"]).substr(0, 300))
	print("    quay families after  %s" % str(entry["quay_meta_after"]).substr(0, 300))

	## One camera for every panel of this port, so nothing moves but the subject.
	##
	## Framed on the union of what the two plans actually DRAW, not on
	## `plan.bounds` — and that distinction is a finding in its own right.
	## `_compute_bounds` folds in `land_poly`, the buildable land zone, which
	## `ChartHarbourPlan.draw` never draws; framing on it put the whole visible
	## harbour in one corner of the first version of this frame. (It also means
	## `centre_world()` and `suggested_span_m()`, the chart's own zoom-to-port
	## helpers, are computed off an extent partly made of invisible geometry —
	## noted, not touched, and neither has a production caller today.)
	var extent := _drawn_extent([before, after])
	var centre := extent.get_center()
	## `_ctx` takes the X span and derives Y from the panel aspect, so a harbour
	## that is taller than it is wide has to be fitted through the aspect, not by
	## its own larger dimension. Getting this backwards cropped the quays off the
	## bottom of the first tight frame.
	var aspect := (float(VIEW_H) - CAPTION_H) / float(VIEW_W)
	var tight_span := maxf(
		maxf(extent.size.x, extent.size.y / aspect) * 1.35, 220.0)
	var chart_span := maxf(
		maxf(before.suggested_span_m(), after.suggested_span_m()), 400.0)

	for pair in [["tight", tight_span], ["chart", chart_span],
			["approach", APPROACH_SPAN_M]]:
		var tag := str(pair[0])
		var span := float(pair[1])
		var modes := ["before", "after", "overlay"] if tag == "tight" else ["overlay"]
		for mode in modes:
			_painter.before = before
			_painter.after = after
			_painter.mode = mode
			_painter.span_m = span
			_painter.ctx = _ctx(centre, span)
			_painter.caption = _caption(pid, data, mode, tag, entry)
			_painter.queue_redraw()
			await CaptureClock.settle(get_tree(), 4)
			var image := _viewport.get_texture().get_image()
			var path := ProjectSettings.globalize_path(
				"%s/harbour_region__%s__%s__%s.png" % [OUT_DIR, pid, tag, mode])
			var err := image.save_png(path)
			if err != OK:
				print("SAVE FAILED %s (%d)" % [path, err])
			else:
				print("    wrote %s" % path)


## Every polygon `ChartHarbourPlan.draw` puts on the canvas, and nothing it does
## not. `land_poly` is excluded on purpose — `draw()` has no call for it.
func _drawn_extent(plans: Array) -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var seen := false
	for plan_raw in plans:
		var plan := plan_raw as ChartHarbourPlan
		var groups: Array = [plan.foundation_poly, plan.shore_poly, plan.dock_face_poly]
		for poly in plan.quay_polys:
			groups.append(poly)
		for poly2 in plan.asphalt_polys:
			groups.append(poly2)
		for group in groups:
			for p in group as PackedVector2Array:
				if not p.is_finite():
					continue
				min_v = min_v.min(p)
				max_v = max_v.max(p)
				seen = true
	if not seen:
		var o := Vector2((plans[0] as ChartHarbourPlan).world_origin.x,
			(plans[0] as ChartHarbourPlan).world_origin.z)
		return Rect2(o - Vector2(150.0, 150.0), Vector2(300.0, 300.0))
	return Rect2(min_v, max_v - min_v)


func _ctx(centre: Vector2, span_m: float) -> Dictionary:
	var chart := Rect2(0.0, CAPTION_H, float(VIEW_W), float(VIEW_H) - CAPTION_H)
	var half_x := span_m * 0.5
	var half_y := half_x * (chart.size.y / chart.size.x)
	return {
		"chart_rect": chart,
		"world_bounds": Rect2(
			centre - Vector2(half_x, half_y), Vector2(half_x, half_y) * 2.0),
	}


## The rows `chart_layer_renderer._draw_port_card` draws, off the catalog record,
## for each registration. `region` is read there as well as by the silhouette, so
## both belong in the frame.
func _caption(
		pid: String, data: PortData, mode: String, tag: String, entry: Dictionary
) -> Array[String]:
	var chart := data.to_chart_dict()
	var placed := str(chart.get("region", "coastal"))
	## The card's SIZE / BERTHS / POPULATION / EXPORTS / IMPORTS rows all read the
	## RECORD, and `world.gd` has always passed those from the world's own expansion —
	## so they are the same in both panels. **Only the REGION row moves.** An earlier
	## version of this caption printed the REBUILD's berth count in that row, which
	## the card never shows: 2 / 2 against a card that really reads 2 / 1. The berth
	## and pad counts below are the SILHOUETTE's, and are labelled as such.
	var card := "REGION %-12s MAX CLASS %-8s SIZE / BERTHS %d / %d   POP %d" % [
		("COASTAL" if mode == "before" else placed.to_upper()),
		"VESSEL", int(chart.get("size", 0)), int(data.berth_count), data.population,
	]
	var lines: Array[String] = []
	lines.append("PRESS M · LIVE MARINE CHART · %s · seed %d · %s view · %s"
		% [pid.to_upper(), SEED, tag.to_upper(), mode.to_upper()])
	if mode == "before":
		lines.append("PORT CARD AS SHIPPED:  %s" % card)
		lines.append("SILHOUETTE rebuilt with region \"coastal\" -> LEGACY_ISLAND: %d quay pads,"
			% (entry["before_plan"] as ChartHarbourPlan).quay_polys.size()
			+ " %d berths in the rebuild." % int(entry["berth_before"]))
	elif mode == "after":
		lines.append("PORT CARD AFTER FIX:   %s" % card)
		lines.append("SILHOUETTE from the placed region word: %d quay pads, %d berths."
			% [(entry["after_plan"] as ChartHarbourPlan).quay_polys.size(),
				int(entry["berth_after"])]
			+ " Equals the STAMPED harbour.")
	else:
		lines.append("OVERLAY: filled = AFTER (region \"%s\").  RED OUTLINE = BEFORE (\"coastal\")."
			% placed)
		lines.append("silhouette quay pads %d -> %d  ·  rebuild berths %d -> %d  ·  chart"
			% [(entry["before_plan"] as ChartHarbourPlan).quay_polys.size(),
				(entry["after_plan"] as ChartHarbourPlan).quay_polys.size(),
				int(entry["berth_before"]), int(entry["berth_after"])]
			+ " zoom-to-harbour %d m -> %d m"
				% [int(entry["span_before"]), int(entry["span_after"])])
	lines.append("The ONLY port card row the fix moves is REGION. MAX CLASS stays VESSEL:")
	lines.append("`max_ship_class_name` is a SECOND silent default, wrong at 210 of 210,")
	lines.append("REGISTERED AND NOT FIXED by this wave. So is `commodity_exports` (74 of 210).")
	lines.append("paths that moved: %s" % str(entry["moved"]))
	return lines


## Drive the real `ChartHarbourPlan.resolve_port_data` against the live catalog,
## with `region` set to exactly one word and nothing else touched.
func _draw_live(
		port_id: String, snapshot: ChartDataSnapshot, region: String, catalog: Node
) -> Dictionary:
	var ports: Dictionary = catalog.get("_ports")
	var entry := ports[port_id] as Dictionary
	for key in ["site_max_size", "port_definition"]:
		entry.erase(key)
	entry["region"] = region
	## Cleared so this draw MUST enter `expand_uncached` — a warm cache would hand
	## one registration the other's PortData and the panels would be one object
	## photographed twice.
	PortDataCache.clear()
	ChartHarbourPlan.clear_cache()
	var data := ChartHarbourPlan.resolve_port_data(port_id, get_tree(), snapshot)
	if data == null:
		return {"resolved": false}
	return _digest(ChartHarbourPlan.from_port_data(data), data)


func _digest(plan: ChartHarbourPlan, data: PortData) -> Dictionary:
	return {
		"resolved": true,
		"plan": plan,
		"data_size": int(data.size),
		"data_berth_count": int(data.berth_count),
		"data_max_ship_class": int(data.max_ship_class),
		"quay_poly_count": plan.quay_polys.size(),
		"asphalt_poly_count": plan.asphalt_polys.size(),
		"land_poly": _pts(plan.land_poly),
		"foundation_poly": _pts(plan.foundation_poly),
		"shore_poly": _pts(plan.shore_poly),
		"dock_face_poly": _pts(plan.dock_face_poly),
		"quay_polys": _poly_list(plan.quay_polys),
		"quay_meta": str(plan.quay_meta),
		"asphalt_polys": _poly_list(plan.asphalt_polys),
		"asphalt_meta": str(plan.asphalt_meta),
		"bounds": [plan.bounds.position.x, plan.bounds.position.y,
			plan.bounds.size.x, plan.bounds.size.y],
		"centre_world": [plan.centre_world().x, plan.centre_world().y],
		"suggested_span_m": plan.suggested_span_m(),
		"world_origin": [plan.world_origin.x, plan.world_origin.y, plan.world_origin.z],
		"rotation_y": plan.rotation_y,
	}


func _pts(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p in poly:
		out.append([p.x, p.y])
	return out


func _poly_list(polys: Array) -> Array:
	var out: Array = []
	for poly in polys:
		out.append(_pts(poly as PackedVector2Array))
	return out


func _diff(a: Dictionary, b: Dictionary, keys: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for key in keys:
		if not a.has(key) or not b.has(key):
			out["MISSING:" + key] = true
			continue
		var av: Variant = a[key]
		var bv: Variant = b[key]
		if typeof(av) == TYPE_ARRAY or typeof(bv) == TYPE_ARRAY:
			if JSON.stringify(av) != JSON.stringify(bv):
				out[str(key)] = true
		elif str(av) != str(bv):
			out[str(key)] = true
	return out


func _region_word(region_kind: int) -> String:
	match region_kind:
		int(PortDefinition.RegionKind.MAINLAND):
			return "mainland"
		int(PortDefinition.RegionKind.FJORD):
			return "fjord"
		int(PortDefinition.RegionKind.ARCHIPELAGO):
			return "archipelago"
	return "coastal"
