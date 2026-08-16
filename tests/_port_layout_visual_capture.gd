extends SceneTree

## SCRATCH CAPTURE RIG — leading underscore, so the gate does not score it.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_layout_visual_capture.gd
##
## ── WHY THIS FILE IS NOW A `_` INSTRUMENT AND NOT A GATE UNIT ───────────────
##
## It was `tests/port_layout_visual_capture.gd` and scored **NOTRUN** in every
## gate run, because it declares no verdict — REALITY.md §4's "scratch probe left
## in tests/", still live in the instrument. The diagnosis on record was that it
## is *"a scene-lane unit sitting in the script lane, dying on `Identifier not
## found: WorldGateway`"*. **That is wrong, and it was disproved rather than
## argued.** `tests/_port_lane_probe.tscn` runs this file's expansion loop as a
## SCENE, where every autoload registers, and prints numbers identical to lane A
## in all nine sizes — `modules=1 open=3`, primary quay 67/107/163/216/212/237/
## 236/240/239 m. The compile cascade in the log is noise (CONVENTIONS §1): the
## script loads on the retry and runs to completion. **Changing the lane would
## have changed nothing.**
##
## What was actually wrong is one level further in, and is REALITY.md §3d:
##
##   **THIS RIG PHOTOGRAPHED A DATA MODEL THE GAME ABANDONED.** The port pipeline
##   moved its quays, yards and aprons out of `PortLayoutGraph.modules` and into
##   `initial_attributes["berth_plan"]` / `["land_plan"]`. `graph.modules` now
##   holds exactly ONE module, the coast root — which is correct, and which
##   `port_layout_brick_test` asserts on purpose. `_draw_topdown` still iterated
##   `graph.modules`. So a size-4 port photographed as **one 8×10-pixel grey
##   square on an empty field**, and the frame committed at `530e396` for the
##   same port shows three fingers, a basin, cargo yards and a road spine.
##
## Three things kept that invisible for nine port generations, and each is its
## own lesson:
##
##   * **No verdict.** NOTRUN in the results table looks like an infrastructure
##     problem, so nobody opened the log.
##   * **The output was outside git.** It wrote to `user://port_layout_capture`
##     and `res://.godot/port_layout_capture`, both gitignored. A capture nobody
##     can diff is not evidence (CONVENTIONS §3). The five PNGs actually
##     committed under `screenshots/port_layouts/` were written at
##     **generation 5** against today's **generation 46**, and this rig could
##     never overwrite them: their names embed a `morphology` token
##     (`size_4_fingers_map.png`) and `morphology` was deleted from the codebase
##     — `port_sizing.gd` keeps the word only as a dead parameter name. The rig
##     wrote `size_4_?_map.png` and the two files sat side by side.
##   * **The critique could not go red and was wrong anyway.** `_critique()`
##     printed 3–7 ISSUE lines per port and failed nothing. Every one of its six
##     classes is measured against the dead model or the wrong constant, so
##     "giving it a verdict it can fail" would have shipped ~46 phantom reds and
##     invited someone to "fix" the port pipeline to satisfy an audit of a data
##     model that no longer exists (REALITY.md §4c — the naive fix scores better
##     than the correct one). Named, so nobody restores them:
##
##     | printed issue | why it is phantom |
##     |---|---|
##     | `fewer cargo yards (0) than trade slots (N)` | counts `definition.kind == "cargo"` modules; yards are `land_plan.apron_pads.pads` now |
##     | `no crane pads on developed port` | counts `kind == "equipment"` modules; cranes ride `quay_stations[].equipment_kind` |
##     | `L/U/finger ports should have multiple quay modules` | counts `kind == "quay"` modules; quays are `berth_plan.quay_stations` |
##     | `layout barely reaches past coastline` | measured off the one coast module's corners, not the piers |
##     | `<id> extends into water` | loops over cargo/road/service modules — an empty universe, so it can never fire (REALITY.md §4) |
##     | `parallel pier gap 138m < required 175m fairway` | restates `parallel_pier_center_spacing_m` as a floor; `port_berth_plan.gd` documents it as the IDEAL and compresses it deliberately — *"compress only enough to fit every family without overlap"* |
##
##     The one live question inside that list — do the piers collide — is now a
##     property check in `tests/port_berth_plan_test.gd`, stated as the thing it
##     cares about (no two decks share area) rather than as the constant
##     (REALITY.md §4a). That test is the replacement: 85 checks, mutation-red
##     five ways.
##
## ── WHAT THE RIG DOES NOW ───────────────────────────────────────────────────
##
## Draws the berth plan, the apron pads and the traced coast, which is where the
## port lives; writes to `screenshots/port_layouts/` under stable, morphology-free
## names so `git diff` on the image means something; and takes the 3D shot
## unconditionally. That last one is its own small finding: the 3D branch was
## gated on `RenderingServer.get_rendering_device() != null`, which is **null
## under `--rendering-driver opengl3`** — the only renderer that runs in this
## container — so the branch never executed here, and
## `PortLayoutGraphVisualizer`, which *had* been migrated to the berth plan
## (`_stamp_berth_terminals`, `_stamp_apron_pads`, `_stamp_land_structures`),
## was the up-to-date port renderer this rig skipped.
##
## Reproducibility: the map is CPU raster off a fixed seed, and the 3D shot
## awaits `RenderingServer.frame_post_draw` rather than grabbing after N
## `process_frame`s (CONVENTIONS §3, the grab/draw race). No vessel is spawned,
## so there is no `ShipLight` and no `WorldClock` dependency to pin. Verify with
## `tools/repro.sh --script _port_layout_visual_capture`.

const OUT_DIR := "res://screenshots/port_layouts"
const SEED := 424242
const MAP_PX := 1024
const SHOT_SIZE := Vector2i(1280, 720)
## Frames to settle before `frame_post_draw`. Same depth the byte-stable vessel
## rigs use.
const SETTLE_FRAMES := 6

## Metres per scale-bar. A top-down port map has no 1.8 m figure to read scale
## off (CONVENTIONS §3a) — at 1000 m across, a person is two pixels. A bar with
## its length stated in the log is the honest substitute.
const SCALE_BAR_M := 100.0

const WATER := Color(0.05, 0.16, 0.24)
const LAND := Color(0.25, 0.27, 0.24)
const BUILDABLE := Color(0.31, 0.33, 0.29)
const COAST_LINE := Color(0.95, 0.82, 0.25)
const DOCK_FACE := Color(0.35, 0.62, 0.78)
const PAD_TRADE := Color(0.62, 0.45, 0.24)
const PAD_UNIVERSAL := Color(0.45, 0.47, 0.50)
const ROOT_MODULE := Color(0.55, 0.20, 0.55)
const BAR := Color(0.92, 0.92, 0.92)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var out_abs := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	var viewport := SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	## A PALE ground behind the port so the silhouette has a boundary (REALITY §8).
	env.background_color = Color(0.62, 0.68, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.76, 0.84)
	env.ambient_light_energy = 0.9
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.35
	## Not the default. `DirectionalLight3D` ships shadows OFF and a full day of
	## captures here had none (REALITY.md §8).
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	world.add_child(camera)
	_add_reference_planes(world)

	var report: Array[String] = []
	report.append("seed=%d generation=%d" % [SEED, PortDefinition.CURRENT_PORT_GENERATION_VERSION])
	report.append("")

	for size in range(PortSizing.MAX_SIZE + 1):
		var definition := PortDefinition.new()
		definition.port_id = "capture-%d" % size
		definition.display_name = "SIZE %d" % size
		definition.size = size
		definition.region_kind = PortDefinition.RegionKind.MAINLAND
		definition.site_seed = SEED ^ (size * 9973)
		definition.has_lighthouse = size >= 2
		definition.has_fog_horn = size >= 1
		definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND

		var data := PortExpander.expand(definition, SEED)
		var graph := data.layout_graph
		var berth := graph.initial_attributes.get("berth_plan", {}) as Dictionary
		var land := graph.initial_attributes.get("land_plan", {}) as Dictionary
		var stations: Array = berth.get("quay_stations", []) as Array
		var pads: Array = ((land.get("apron_pads", {}) as Dictionary).get("pads", []) as Array)

		## `structures=%d` used to stand here, reading `land_plan.structure_count`
		## — a LITERAL 0 written at the only producer and read by nothing else in
		## the project. It printed `structures=0` beside `pads=5` on every size and
		## was taken as evidence that the port lays pads and builds nothing on
		## them. The field is deleted; what stands here now is counted off the
		## node tree the visualiser builds, below, after it is in the scene.
		var decor_planned := int((land.get("apron_decor", {}) as Dictionary).get("point_count", 0))
		report.append(
			"size=%d quays=%d pads=%d apron_props_planned=%d primary=%.0fm total_quay=%.0fm modules=%d"
			% [
				size,
				stations.size(),
				pads.size(),
				decor_planned,
				float(graph.primary_quay_pose().get("length_m", 0.0)),
				graph.total_quay_length_m(),
				graph.modules.size(),
			]
		)
		report.append(
			"  exports=%s imports=%s"
			% [",".join(data.trade_profile.export_slots), ",".join(data.trade_profile.import_slots)]
		)
		for raw in stations:
			var station := raw as Dictionary
			report.append(
				"  quay %-34s %7.1fm x %5.1fm  %s"
				% [
					str(station.get("id", "?")),
					float(station.get("length_m", 0.0)),
					float(station.get("width_m", 0.0)),
					",".join(PackedStringArray(station.get("commodities", []) as Array)),
				]
			)
		for raw_pad in pads:
			var pad := raw_pad as Dictionary
			var pad_size: Array = pad.get("size_m", []) as Array
			report.append(
				"  pad  %-34s %5.0fm x %5.0fm  %s"
				% [
					str(pad.get("role", "?")),
					float(pad_size[0]) if pad_size.size() > 0 else 0.0,
					float(pad_size[1]) if pad_size.size() > 1 else 0.0,
					str(pad.get("zone", "")),
				]
			)

		var frame := _frame_for(graph, stations, pads)
		var map_image := _draw_topdown(graph, stations, pads, frame)
		var map_name := "port_layout__size_%d__map.png" % size
		_save(map_image, out_abs.path_join(map_name))
		print("[port] %s  span=%.0f m  %.3f m/px  quays=%d pads=%d"
			% [map_name, frame["span"], float(frame["span"]) / float(MAP_PX),
				stations.size(), pads.size()])

		var visualizer := PortLayoutGraphVisualizer.new()
		visualizer.configure(graph)
		world.add_child(visualizer)
		var center := Vector3(float(frame["cx"]), 0.0, float(frame["cz"]))
		var span := maxf(float(frame["span"]), 120.0)
		camera.position = center + Vector3(span * 0.55, span * 0.85, span * 0.7)
		camera.look_at(center + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		await _settle()
		var shot := viewport.get_texture().get_image()
		if shot != null:
			_save(shot, out_abs.path_join("port_layout__size_%d__quarter.png" % size))
		## Counted off the tree the visualiser BUILT, which is the only thing in
		## this report that can say whether a pad carries anything. `-1` means the
		## root node is absent — the shape `ApronDecor` has on every size, because
		## `_stamp_apron_decor` has no callers.
		report.append(
			"  drawn: pad_sites=%d pad_meshes=%d village=%d apron_props=%d"
			% [
				_child_count(visualizer.get_node_or_null("ApronPads")),
				_mesh_count(visualizer.get_node_or_null("ApronPads")),
				_child_count(visualizer.get_node_or_null("LandDecor")),
				_child_count(visualizer.get_node_or_null("ApronDecor")),
			]
		)
		visualizer.queue_free()
		await _settle()

	var report_text := "\n".join(report)
	var file := FileAccess.open("%s/report.txt" % OUT_DIR, FileAccess.WRITE)
	if file != null:
		file.store_string(report_text)
		file.close()
	print(report_text)
	print("[port] frames written to %s" % OUT_DIR)
	quit(0)


## N frames, THEN `frame_post_draw`. Awaiting `process_frame` and grabbing the
## texture returns a frame a draw out and puts a one-pixel outline round every
## silhouette edge — the grab/draw race in CONVENTIONS §3.
func _settle() -> void:
	for _frame in range(SETTLE_FRAMES):
		await process_frame
	await RenderingServer.frame_post_draw


## ── FRAMING ────────────────────────────────────────────────────────────────
##
## Fitted to WHAT IS DRAWN, not to `graph.bounds()`. `bounds()` is the module
## corners plus the foundation spine, and with one module it framed the map on
## the spine while the piers ran off the edge — which is half of why the old
## frames looked empty even where a rectangle was drawn.
func _frame_for(graph: PortLayoutGraph, stations: Array, pads: Array) -> Dictionary:
	## Collected into one list first: a GDScript lambda captures locals BY VALUE,
	## so the obvious `var note := func(p): lo.x = minf(...)` updates a copy and
	## every frame comes back INF. Learned the hard way; do not reintroduce it.
	var seen: Array = []
	for raw in stations:
		seen.append_array(_station_corners(raw as Dictionary))
	for raw_pad in pads:
		seen.append_array(_pad_corners(raw_pad as Dictionary))
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	for key in ["coast_polyline", "dock_face_polyline"]:
		for raw_point in foundation.get(key, []) as Array:
			seen.append(_point(raw_point))

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for entry in seen:
		var point := entry as Vector2
		lo.x = minf(lo.x, point.x)
		lo.y = minf(lo.y, point.y)
		hi.x = maxf(hi.x, point.x)
		hi.y = maxf(hi.y, point.y)
	if not is_finite(lo.x):
		return {"cx": 0.0, "cz": 0.0, "span": 400.0}
	var centre := (lo + hi) * 0.5
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y) * 1.25, 160.0)
	return {"cx": centre.x, "cz": centre.y, "span": span}


func _draw_topdown(
		graph: PortLayoutGraph,
		stations: Array,
		pads: Array,
		frame: Dictionary,
) -> Image:
	var image := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	image.fill(WATER)
	var centre := Vector2(float(frame["cx"]), float(frame["cz"]))
	var px_per_m := float(MAP_PX) / float(frame["span"])

	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var land_plan := graph.initial_attributes.get("land_plan", {}) as Dictionary

	## Land first: the buildable zone is the town side of the traced coast.
	var zone := land_plan.get("buildable_zone", {}) as Dictionary
	var polygon: Array = zone.get("polygon", []) as Array
	if polygon.size() >= 3:
		_fill_polygon(image, centre, px_per_m, _points(polygon), BUILDABLE)

	## The traced coast, which is a polyline and not the straight datum line the
	## old map drew at COASTAL_GRAPH_ROOT_Z_M.
	_stroke_polyline(image, centre, px_per_m,
		_points(foundation.get("coast_polyline", []) as Array), COAST_LINE, 2)
	_stroke_polyline(image, centre, px_per_m,
		_points(foundation.get("dock_face_polyline", []) as Array), DOCK_FACE, 2)

	## Apron pads — the cargo yards the old map called missing because it was
	## counting modules.
	for raw_pad in pads:
		var pad := raw_pad as Dictionary
		var commodity := str(pad.get("commodity_id", ""))
		var colour := PAD_UNIVERSAL
		if str(pad.get("kind", "")) == "trade":
			colour = CommodityCatalog.commodity_color(commodity) if not commodity.is_empty() \
					else PAD_TRADE
		_fill_polygon(image, centre, px_per_m, _pad_corners(pad), colour)

	## Quay stations, coloured by the commodity zone they serve.
	for raw in stations:
		var station := raw as Dictionary
		var commodities: Array = station.get("commodities", []) as Array
		var colour := DOCK_FACE
		if not commodities.is_empty():
			colour = CommodityCatalog.commodity_color(str(commodities[0]))
		_fill_polygon(image, centre, px_per_m, _station_corners(station), colour)

	## The single coast root module, so the map still shows what `graph.modules`
	## holds — one rectangle, which is the whole point.
	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition == null:
			continue
		_fill_polygon(image, centre, px_per_m,
			_oriented_corners(
				Vector2(placed.position_m.x, placed.position_m.z),
				Vector2(definition.footprint_m.x, definition.footprint_m.z),
				deg_to_rad(placed.yaw_degrees)),
			ROOT_MODULE)

	_draw_scale_bar(image, px_per_m)
	return image


## A stated-length bar, because a top-down map has no figure to read scale from.
func _draw_scale_bar(image: Image, px_per_m: float) -> void:
	var length_px := int(round(SCALE_BAR_M * px_per_m))
	if length_px < 4 or length_px > MAP_PX - 40:
		return
	var y := MAP_PX - 24
	for x in range(20, 20 + length_px):
		for thickness in range(6):
			image.set_pixel(x, y + thickness, BAR)
	for cap in [20, 20 + length_px - 1]:
		for thickness2 in range(-6, 12):
			image.set_pixel(cap, clampi(y + thickness2, 0, MAP_PX - 1), BAR)


## ── GEOMETRY ───────────────────────────────────────────────────────────────


func _point(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr == null or arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


func _points(raw: Array) -> Array:
	var out: Array = []
	for entry in raw:
		out.append(_point(entry))
	return out


## The deck a pier actually draws: origin→tip, `width_m` across. Same three
## fields `port_berth_plan_test` measures, so the map and the check cannot
## disagree about where a pier is.
func _station_corners(station: Dictionary) -> Array:
	var origin := _point(station.get("origin", []))
	var tip := _point(station.get("tip", []))
	var axis := tip - origin
	if axis.length() < 0.0001:
		axis = Vector2(0.0, -1.0)
	axis = axis.normalized()
	var across := Vector2(-axis.y, axis.x) * (float(station.get("width_m", 8.0)) * 0.5)
	return [origin - across, origin + across, tip + across, tip - across]


func _pad_corners(pad: Dictionary) -> Array:
	var origin := _point(pad.get("origin", []))
	var size_raw: Array = pad.get("size_m", []) as Array
	var size := Vector2(
		float(size_raw[0]) if size_raw.size() > 0 else 8.0,
		float(size_raw[1]) if size_raw.size() > 1 else 8.0,
	)
	return _oriented_corners(origin, size, deg_to_rad(float(pad.get("yaw_deg", 0.0))))


func _oriented_corners(centre: Vector2, size: Vector2, yaw: float) -> Array:
	var half := size * 0.5
	return [
		centre + Vector2(-half.x, -half.y).rotated(yaw),
		centre + Vector2(half.x, -half.y).rotated(yaw),
		centre + Vector2(half.x, half.y).rotated(yaw),
		centre + Vector2(-half.x, half.y).rotated(yaw),
	]


## X right, +Z (inland) DOWN, so water is at the top of the image. The old
## header claimed this and the arithmetic did the opposite — seaward −Z mapped
## to a LARGER pixel y, which put the sea at the bottom under a comment saying
## it was at the top.
func _to_px(centre: Vector2, px_per_m: float, world_xz: Vector2) -> Vector2:
	var local := world_xz - centre
	return Vector2(
		MAP_PX * 0.5 + local.x * px_per_m,
		MAP_PX * 0.5 + local.y * px_per_m,
	)


func _fill_polygon(
		image: Image,
		centre: Vector2,
		px_per_m: float,
		corners: Array,
		colour: Color,
) -> void:
	if corners.size() < 3:
		return
	var px_corners: Array = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in corners:
		var px := _to_px(centre, px_per_m, corner as Vector2)
		px_corners.append(px)
		lo.x = minf(lo.x, px.x)
		lo.y = minf(lo.y, px.y)
		hi.x = maxf(hi.x, px.x)
		hi.y = maxf(hi.y, px.y)
	for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)) + 1, MAP_PX)):
		for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)) + 1, MAP_PX)):
			if _inside(Vector2(x, y), px_corners):
				image.set_pixel(x, y, colour)


## Even-odd crossing count — works for the convex quads AND for the buildable
## zone's traced polygon, which the old `abs(signs) == 4` quad test could not do.
func _inside(point: Vector2, polygon: Array) -> bool:
	var inside := false
	var count := polygon.size()
	var j := count - 1
	for i in range(count):
		var a := polygon[i] as Vector2
		var b := polygon[j] as Vector2
		if (a.y > point.y) != (b.y > point.y):
			var t := (point.y - a.y) / (b.y - a.y)
			if point.x < a.x + t * (b.x - a.x):
				inside = not inside
		j = i
	return inside


func _stroke_polyline(
		image: Image,
		centre: Vector2,
		px_per_m: float,
		points: Array,
		colour: Color,
		thickness: int,
) -> void:
	for i in range(1, points.size()):
		var a := _to_px(centre, px_per_m, points[i - 1] as Vector2)
		var b := _to_px(centre, px_per_m, points[i] as Vector2)
		var steps := int(ceil(maxf(absf(b.x - a.x), absf(b.y - a.y))))
		for step in range(steps + 1):
			var t := 0.0 if steps == 0 else float(step) / float(steps)
			var p := a.lerp(b, t)
			for dy in range(thickness):
				for dx in range(thickness):
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if x >= 0 and y >= 0 and x < MAP_PX and y < MAP_PX:
						image.set_pixel(x, y, colour)


func _child_count(node: Node) -> int:
	return node.get_child_count() if node != null else -1


func _mesh_count(node: Node) -> int:
	if node == null:
		return -1
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += maxi(_mesh_count(child), 0)
	return n


func _add_reference_planes(world: Node3D) -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	water.mesh = plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = WATER
	water.material_override = water_mat
	water.position.y = -0.3
	world.add_child(water)


func _save(image: Image, path: String) -> void:
	if image == null:
		return
	var err := image.save_png(path)
	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])
