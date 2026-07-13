class_name DebugDraw
extends Control

## F3 debug panel — system telemetry + gameplay readouts.
## Visual style follows HudStyle (warm hull-black + brass + amber).
##
## Redraws are signal-driven: gameplay sections refresh on the relevant
## state_changed signals; system stats refresh on Telemetry.sampled
## (once per second). No per-frame work.

const PANEL_W := 360.0
const PAD_X   := 12.0
const PAD_Y   := 10.0
const ROW_H   := 16.0
const LABEL_W := 130.0
const FS_ROW  := 10
const FS_SEC  := 10

# Maritime palette (HudStyle) plus a couple of debug-only accent colours.
const C_BG      := HudStyle.C_BG
const C_BORDER  := HudStyle.C_BRASS
const C_TITLE   := HudStyle.C_AMBER
const C_SECTION := HudStyle.C_AMBER
const C_LABEL   := HudStyle.C_LABEL
const C_VALUE   := HudStyle.C_TEXT
const C_STUB    := Color(HudStyle.C_LABEL.r, HudStyle.C_LABEL.g, HudStyle.C_LABEL.b, 0.55)
const C_GOLD    := HudStyle.C_AMBER
const C_SEP     := HudStyle.C_SEP
const C_GOOD    := HudStyle.C_GREEN
const C_WARN    := Color(0.92, 0.66, 0.28, 0.95)
const C_BAD     := HudStyle.C_RED


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)

	# Refresh on telemetry tick (system stats + loading log).
	var t := get_node_or_null("/root/Telemetry")
	if t != null and not t.sampled.is_connected(_on_telemetry):
		t.sampled.connect(_on_telemetry)

	# Refresh on gameplay state changes (player, ship, contracts, weather).
	# Each sub-state has its own named signals — no generic "changed".
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		_connect_if(gs.player,   "marks_changed",         _on_state_changed)
		_connect_if(gs.player,   "display_name_changed",  _on_state_changed)
		_connect_if(gs.ship,     "boarded",               _on_state_changed)
		_connect_if(gs.ship,     "exited",                _on_state_changed)
		_connect_if(gs.ship,     "hull_changed",          _on_state_changed)
		_connect_if(gs.ship,     "fuel_changed",          _on_state_changed)
		_connect_if(gs.contract, "active_changed",        _on_state_changed)
		_connect_if(gs.world,    "weather_changed",       _on_state_changed)
		_connect_if(gs.world,    "nearest_port_changed",  _on_state_changed)

	var wl := get_node_or_null("/root/WeatherLighting")
	if wl != null and wl.has_signal("state_changed"):
		wl.state_changed.connect(_on_state_changed)


static func _connect_if(obj: Object, signal_name: String, target: Callable) -> void:
	if obj != null and obj.has_signal(signal_name) and not obj.is_connected(signal_name, target):
		obj.connect(signal_name, target)


func _on_telemetry() -> void:
	if visible:
		queue_redraw()


## Accepts an optional argument so a single handler can connect to both
## 0-arg signals (ShipState.exited, WeatherLighting.state_changed) and
## 1-arg signals (marks_changed(balance), weather_changed(label), …).
func _on_state_changed(_arg: Variant = null) -> void:
	if visible:
		queue_redraw()


# Redraw once when becoming visible (so the panel doesn't show stale data).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		var viewport := get_viewport()
		if viewport == null:
			return
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), visible)
		if visible:
			queue_redraw()


func _draw() -> void:
	var vp   := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var entries: Array = _build()

	var ph := PAD_Y + ROW_H + 6.0 + _content_h(entries) + PAD_Y
	var ox := vp.x - PANEL_W - 14.0
	var oy := 14.0

	# Panel background.
	draw_rect(Rect2(ox, oy, PANEL_W, ph), C_BG)
	draw_rect(Rect2(ox, oy, PANEL_W, ph), C_BORDER, false, 1.2)

	# Title + hint.
	var ty := oy + PAD_Y + 12.0
	draw_string(font, Vector2(ox + PAD_X, ty),
		"DEBUG", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TITLE)
	var hint   := "F3 · F3+P cam · F8 ocean LOD · B lanes · F4 wx · O I fleet"
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(ox + PANEL_W - hint_w - PAD_X, ty),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_LABEL)
	draw_line(Vector2(ox + 6, oy + PAD_Y + ROW_H + 2),
			  Vector2(ox + PANEL_W - 6, oy + PAD_Y + ROW_H + 2), C_SEP, 1.0)

	# Entries.
	var cy := oy + PAD_Y + ROW_H + 6.0
	for e in entries:
		cy = _draw_entry(font, e, ox, cy)


# ── Entry list builder ────────────────────────────────────────────────────────

func _build() -> Array:
	var e:        Array = []
	_build_system(e)
	_build_water_gpu(e)
	_build_weather(e)
	_build_world_generation(e)
	_build_vessel_physics(e)
	_build_loading(e)
	_build_debug_tools(e)
	_build_gameplay(e)
	return e


func _build_world_generation(e: Array) -> void:
	_sec(e, "WORLD GENERATION")
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("get_world_generation_debug_stats"):
		_stub(e, "Layout", "world not initialized")
		_sep(e)
		return
	var stats := world.call("get_world_generation_debug_stats") as Dictionary
	_row(e, "Seed / version", "%d · v%d" % [
		int(stats.get("seed", 0)),
		int(stats.get("version", 0)),
	], C_VALUE)
	_row(e, "Layout bake", "%.1f ms · %d² · %d coast segments" % [
		float(stats.get("generation_usec", 0)) / 1000.0,
		int(stats.get("raster_resolution", 0)),
		int(stats.get("contour_segments", 0)),
	], C_VALUE)
	var checksum := str(stats.get("checksum", ""))
	_row(e, "Checksum", checksum.left(12) if not checksum.is_empty() else "—", C_LABEL)
	var terrain := get_tree().get_first_node_in_group("world_terrain_streamer")
	if terrain != null and terrain.has_method("get_debug_stats"):
		var terrain_stats := terrain.call("get_debug_stats") as Dictionary
		_row(e, "Terrain chunks", "%d loaded · %d queued · %d collision" % [
			int(terrain_stats.get("loaded", 0)),
			int(terrain_stats.get("pending", 0)),
			int(terrain_stats.get("collision_count", 0)),
		], C_VALUE)
		_row(e, "Terrain geometry", "%d verts · %d tris · %.1f MB" % [
			int(terrain_stats.get("vertices", 0)),
			int(terrain_stats.get("triangles", 0)),
			float(terrain_stats.get("memory_estimate_bytes", 0)) / (1024.0 * 1024.0),
		], C_LABEL)
		_row(e, "Terrain build", "%.2f ms last · %.2f ms avg" % [
			float(terrain_stats.get("last_build_ms", 0.0)),
			float(terrain_stats.get("average_build_ms", 0.0)),
		], C_LABEL)
	_sep(e)


func _build_weather(e: Array) -> void:
	_sec(e, "WEATHER")
	var weather := get_node_or_null("/root/WeatherLighting")
	if weather != null:
		_row(e, "Local zone", "%s · %.0f%% exposed" % [
			str(weather.get("zone_label")),
			float(weather.get("exposure")) * 100.0,
		], C_VALUE)
		_row(e, "Wind / sea", "%.1f m/s · %.1f m Hs" % [
			float(weather.get("wind_speed_ms")),
			float(weather.get("significant_wave_height_m")),
		], C_VALUE)
		_row(e, "Front / visibility", "%.0f%% · %.0f%%" % [
			float(weather.get("front_intensity")) * 100.0,
			float(weather.get("visibility")) * 100.0,
		], C_VALUE)
	var world_weather := get_node_or_null("/root/WorldWeather")
	if world_weather != null and world_weather.has_method("get_debug_metrics"):
		var metrics := world_weather.call("get_debug_metrics") as Dictionary
		_row(e, "Weather sampling", "%d µs · %d cached · %d fronts" % [
			int(metrics.get("sample_usec", 0)),
			int(metrics.get("cache_entries", 0)),
			int(metrics.get("front_count", 0)),
		], C_LABEL)
	var fft := get_tree().get_first_node_in_group("fft_water_system")
	if fft != null:
		_row(e, "FFT weather repacks", "%d" % int(fft.get("weather_repack_count")), C_LABEL)
	var chart := get_tree().get_first_node_in_group("marine_chart")
	if chart != null and chart.has_method("get_debug_stats"):
		var chart_stats := chart.call("get_debug_stats") as Dictionary
		_row(e, "Chart draw/cache", "%d µs · %d cells / %d rebuilds" % [
			int(chart_stats.get("draw_usec", 0)),
			int(chart_stats.get("weather_cache_cells", 0)),
			int(chart_stats.get("weather_cache_rebuilds", 0)),
		], C_LABEL)
	_sep(e)


func _build_water_gpu(e: Array) -> void:
	_sec(e, "WATER / GPU")

	var viewport_rid := get_viewport().get_viewport_rid()
	var frame_gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
	var frame_cpu_render_ms := (
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		+ RenderingServer.get_frame_setup_time_cpu()
	)
	var cap := Engine.max_fps
	var target_fps := float(cap)
	var refresh_hz := DisplayServer.screen_get_refresh_rate()
	if GameSettings.vsync_enabled and refresh_hz > 1.0:
		target_fps = minf(target_fps, refresh_hz) if target_fps > 0.0 else refresh_hz
	var budget_ms := 1000.0 / target_fps if target_fps > 0.0 else 0.0
	var frame_color := C_VALUE
	if budget_ms > 0.0:
		var headroom := budget_ms - frame_gpu_ms
		frame_color = C_GOOD if headroom >= 2.0 else (C_WARN if headroom >= 0.5 else C_BAD)
		_row(e, "GPU frame", "%.2f / %.2f ms  (%.2f free)" % [
			frame_gpu_ms, budget_ms, headroom,
		], frame_color)
	else:
		_row(e, "GPU frame", "%.2f ms (uncapped)" % frame_gpu_ms, C_WARN)
	_row(e, "Render CPU", "%.2f ms" % frame_cpu_render_ms, C_VALUE)

	var fft := get_tree().get_first_node_in_group("fft_water_system")
	if fft != null and fft.has_method("get_debug_stats"):
		var s: Dictionary = fft.call("get_debug_stats")
		var fft_gpu := float(s.get("gpu_fft_ms", -1.0))
		if fft_gpu >= 0.0:
			var fps := maxf(float(Performance.get_monitor(Performance.TIME_FPS)), 1.0)
			var amortized := fft_gpu * float(s.get("sim_hz", 0.0)) / fps
			var share := amortized / frame_gpu_ms * 100.0 if frame_gpu_ms > 0.001 else 0.0
			_row(e, "FFT GPU", "%.3f ms/tick · %.3f/frame · %.1f%%" % [
				fft_gpu, amortized, share,
			], C_VALUE)
		else:
			_stub(e, "FFT GPU", "collecting timestamps…")
		_row(e, "FFT submit CPU", "%.3f ms" % float(s.get("cpu_submit_ms", 0.0)), C_VALUE)
		_row(e, "FFT quality", "%d² × %d @ %dHz · %d groups" % [
			int(s.get("resolution", 0)),
			int(s.get("cascades", 0)),
			int(s.get("sim_hz", 0)),
			int(s.get("workgroups_per_tick", 0)),
		], C_VALUE)
		_row(e, "FFT memory/I-O", "%.1f MB · %.1f MB/s @ %.0fHz%s" % [
			float(s.get("texture_mb", 0.0)),
			float(s.get("readback_mb_s", 0.0)),
			float(s.get("readback_hz", 0.0)),
			" · copy" if bool(s.get("readback_in_flight", false)) else "",
		], C_VALUE)
		_row(e, "Physics query", "%d² · %.1f ms old" % [
			int(s.get("physics_query_resolution", 0)),
			float(s.get("snapshot_age_ms", 0.0)),
		], C_VALUE)
	else:
		_stub(e, "FFT", "system not found")

	var wake := get_tree().get_first_node_in_group("ocean_wake_field")
	if wake != null and wake.has_method("get_debug_stats"):
		var w: Dictionary = wake.call("get_debug_stats")
		_row(e, "Wake field", "%d² / %.1f km · %.1f MB @ %.0fHz" % [
			int(w.get("resolution", 0)),
			float(w.get("extent_m", 0.0)) / 1000.0,
			float(w.get("memory_mb", 0.0)),
			float(w.get("update_hz", 0.0)),
		], C_VALUE)
		_row(e, "Wake emitters", "%d active · %d segments · %.2f strength" % [
			int(w.get("active_emitters", 0)),
			int(w.get("stamped_segments", 0)),
			float(w.get("local_strength", 0.0)),
		], C_VALUE)
		_row(e, "Wake update", "%.3f ms GPU · %.3f ms CPU" % [
			float(w.get("gpu_update_ms", -1.0)),
			float(w.get("cpu_update_ms", 0.0)),
		], C_VALUE)
	else:
		_stub(e, "Wake", "field not found")

	var renderer := get_tree().get_first_node_in_group("world_renderer")
	if renderer != null and renderer.has_method("get_ocean_debug_stats"):
		var r: Dictionary = renderer.call("get_ocean_debug_stats")
		_row(e, "Ocean geometry", "%d verts · %d tris" % [
			int(r.get("vertices", 0)),
			int(r.get("triangles", 0)),
		], C_VALUE)
		if r.has("active_rings"):
			var tier_vertices: PackedInt32Array = r.get("tier_vertices", PackedInt32Array())
			var tier_triangles: PackedInt32Array = r.get("tier_triangles", PackedInt32Array())
			var samples: PackedInt32Array = r.get("cascade_samples", PackedInt32Array())
			_row(e, "Clipmap rings", "%d active · %.2fm base · %.1fkm" % [
				int(r.get("active_rings", 0)),
				float(r.get("base_cell", 0.0)),
				float(r.get("outer_extent", 0.0)) / 1000.0,
			], C_LABEL)
			if tier_vertices.size() >= 4 and tier_triangles.size() >= 4:
				_row(e, "  Near / mid", "%dk/%dk v · %dk/%dk t" % [
					tier_vertices[0] / 1000, tier_vertices[1] / 1000,
					tier_triangles[0] / 1000, tier_triangles[1] / 1000,
				], C_LABEL)
				_row(e, "  Far / horizon", "%dk/%dk v · %dk/%dk t" % [
					tier_vertices[2] / 1000, tier_vertices[3] / 1000,
					tier_triangles[2] / 1000, tier_triangles[3] / 1000,
				], C_LABEL)
			if samples.size() >= 4:
				_row(e, "Cascade samples", "%d / %d / %d / %d per vertex" % [
					samples[0], samples[1], samples[2], samples[3],
				], C_LABEL)
			_row(e, "Ring false color", "ON (F8)" if bool(r.get("false_color", false)) else "off (F8)", C_WARN if bool(r.get("false_color", false)) else C_LABEL)
		else:
			_row(e, "Clipmap fallback", "%dm:%d  %dm:%d  %dkm:%d" % [
				int(r.get("near_size", 0)),
				int(r.get("near_subdivisions", 0)),
				int(r.get("mid_size", 0)),
				int(r.get("mid_subdivisions", 0)),
				int(float(r.get("horizon_size", 0.0)) / 1000.0),
				int(r.get("horizon_subdivisions", 0)),
			], C_LABEL)

	_stub(e, "Ocean raster", "included in GPU frame; Godot cannot isolate it")
	_sep(e)


func _build_vessel_physics(e: Array) -> void:
	_sec(e, "VESSEL PHYSICS")
	var boat := PlayerVessel.find_active_ship(get_tree())
	if boat == null:
		_stub(e, "Vessel", "no active player hull")
		_sep(e)
		return
	var profile := boat.physics_profile
	var buoyancy := boat.get_node_or_null(
		"StripBuoyancyComponent"
	) as StripBuoyancyComponent
	var breakdown := boat.get_mass_breakdown()
	_row(e, "Quality / CPU", "%s · %.3f ms buoyancy" % [
		boat.get_physics_quality_name(),
		buoyancy.cpu_time_ms if buoyancy != null else 0.0,
	], C_VALUE)
	if buoyancy != null:
		var target_draft := profile.design_draft_m if profile != null else boat.draft_m
		_row(e, "Draft", "%.2f m / %.2f m target" % [
			buoyancy.current_draft_m, target_draft,
		], C_VALUE)
		_row(e, "Displacement", "%.1f m³ · %.1f t" % [
			buoyancy.submerged_volume_m3,
			float(breakdown.get("total_kg", boat.mass)) / 1000.0,
		], C_VALUE)
		_row(e, "Waterplane / ζ", "%.1f m² · %.2f" % [
			buoyancy.waterplane_area_m2,
			buoyancy.effective_damping_ratio,
		], C_VALUE)
		_row(e, "Lift / damping", "%.0f / %.0f kN" % [
			buoyancy.total_lift_n / 1000.0,
			buoyancy.total_damping_n / 1000.0,
		], C_VALUE)
		_row(e, "Water age / stale", "%.1f ms · %d samples" % [
			buoyancy.water_snapshot_age_s * 1000.0,
			buoyancy.stale_sample_count,
		], C_WARN if buoyancy.stale_sample_count > 0 else C_VALUE)
	var com: Vector3 = breakdown.get("center_of_mass", boat.center_of_mass)
	var cob := (
		boat.to_local(buoyancy.center_of_buoyancy_world)
		if buoyancy != null else Vector3.ZERO
	)
	_row(e, "COM", "(%.2f, %.2f, %.2f)" % [com.x, com.y, com.z], C_LABEL)
	_row(e, "COB", "(%.2f, %.2f, %.2f)" % [cob.x, cob.y, cob.z], C_LABEL)
	_sep(e)


func _build_debug_tools(e: Array) -> void:
	_sec(e, "DEBUG TOOLS")
	_row(e, "Berth lanes", "%s (%d ports, %d curves)" % [
		BerthApproachLanes.debug_label(),
		BerthApproachLanes.baked_port_count(),
		BerthApproachLanes.debug_polyline_count(),
	], C_VALUE)
	_stub(e, "Toggle", "B lane overlay")
	_sep(e)


func _build_system(e: Array) -> void:
	var t := get_node_or_null("/root/Telemetry")
	_sec(e, "SYSTEM")
	if t == null:
		_stub(e, "Status", "Telemetry autoload missing")
		_sep(e)
		return

	# Static identity (only updates once, but cheap to redraw).
	_row(e, "CPU", "%s × %d" % [str(t.cpu_name), int(t.cpu_cores)], C_VALUE)
	_row(e, "GPU", str(t.gpu_name), C_VALUE)
	if not str(t.gpu_driver).is_empty():
		_row(e, "  Driver", str(t.gpu_driver), C_LABEL)
	_row(e, "RAM", "%d MB total" % int(t.ram_total_mb), C_VALUE)
	_row(e, "OS",  str(t.os_name), C_LABEL)
	_sep(e)

	# Live perf — colour-code values based on health thresholds.
	var fps    := int(t.fps)
	var fps_c := _band(fps, 50, 30)
	_row(e, "FPS", "%d  (frame %.2f ms)" % [fps, t.frame_time_ms], fps_c)
	_row(e, "  Process",  "%.2f ms" % t.process_time_ms, C_VALUE)
	_row(e, "  Physics",  "%.2f ms" % t.physics_time_ms, C_VALUE)
	_row(e, "Draw calls", "%d  (%d prim)" % [int(t.draw_calls), int(t.primitives)], C_VALUE)
	_row(e, "Video mem",  "%s / %s tex / %s buf" % [
		_mb(t.video_mem_mb), _mb(t.texture_mem_mb), _mb(t.buffer_mem_mb)
	], C_VALUE)
	_row(e, "RAM used",   "%d / %d MB free" % [int(t.ram_used_mb), int(t.ram_free_mb)], C_VALUE)
	_row(e, "Heap",       _mb(t.heap_mb), C_VALUE)
	var orph := int(t.orphan_count)
	var orph_c := C_BAD if orph > 0 else C_VALUE
	_row(e, "Nodes",      "%d  (orphan %d)" % [int(t.node_count), orph], orph_c)
	_row(e, "Objects",    "%d" % int(t.object_count), C_VALUE)
	_sep(e)


func _build_loading(e: Array) -> void:
	var t := get_node_or_null("/root/Telemetry")
	_sec(e, "LOADING LOG")
	if t == null or t.load_events.is_empty():
		_stub(e, "—", "no events recorded")
		_sep(e)
		return
	# Show most recent 8, newest at the top.
	var events: Array = t.load_events
	var start := maxi(0, events.size() - 8)
	for i in range(events.size() - 1, start - 1, -1):
		var ev := events[i] as Dictionary
		var dur := float(ev["duration_ms"])
		var name := str(ev["name"])
		# Colour-code by duration: <50ms green, 50-200ms amber, >200ms red.
		var c := C_GOOD if dur < 50.0 else (C_WARN if dur < 200.0 else C_BAD)
		_row(e, name, "%.1f ms" % dur, c)
	_sep(e)


func _build_gameplay(e: Array) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		_sec(e, "GAMEPLAY")
		_stub(e, "Status", "GameState autoload missing")
		return
	var registry := get_node_or_null("/root/ContractRegistry")

	# ── Player ────────────────────────────────────────────────────────────────
	_sec(e, "PLAYER")
	_row(e, "Marks", PlayerSession.format_money(gs.player.marks), C_GOLD)
	_row(e, "Name",  gs.player.display_name,     C_VALUE)

	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var pos := (players[0] as Node3D).global_position
		_row(e, "Position",
			"%.0f  %.0f  %.0f" % [pos.x, pos.y, pos.z], C_VALUE)
	else:
		_stub(e, "Position", "player node not found")

	# ── Ship ──────────────────────────────────────────────────────────────────
	_sep(e)
	_sec(e, "SHIP")
	var sd: ShipData = gs.ship.data
	if sd != null:
		_row(e,  "Vessel", sd.display_name, C_VALUE)
		_stub(e, "Hull",   "not implemented")
		_stub(e, "Fuel",   "not implemented")
		if sd.cargo != null:
			_row(e, "Cargo",
				"%d / %d units" % [sd.cargo.total_units(), sd.cargo.capacity],
				C_VALUE)
			for entry in sd.cargo.entries:
				var ce := entry as CargoEntry
				_row(e, "  " + ce.display_name, "× %d" % ce.quantity, C_VALUE)
		else:
			_stub(e, "Cargo", "no manifest")
	else:
		_stub(e, "Status", "not helming")

	# ── Contracts ─────────────────────────────────────────────────────────────
	_sep(e)
	_sec(e, "CONTRACTS")
	var active: Array = gs.contract.active
	if active.is_empty():
		_stub(e, "—", "none active")
	else:
		for c in active:
			var contract := c as Contract
			if contract == null:
				continue
			var dest: String = registry.get_port_display_name(contract.destination_port_id) \
				if registry != null else "?"
			_row(e, contract.display_name,
				"× %d  →  %s" % [contract.quantity, dest], C_VALUE)
			_row(e, "  Delivered",
				"%d / %d" % [contract.delivered_count, contract.quantity], C_VALUE)
			_row(e, "  Reward", PlayerSession.format_money(contract.reward_gold), C_GOLD)
			var apron := _count_apron_cargo(contract.id)
			if apron > 0:
				_row(e, "  Apron cargo", "%d crates" % apron, C_VALUE)
			else:
				_stub(e, "  Apron cargo", "none staged")

	# ── World ─────────────────────────────────────────────────────────────────
	_sep(e)
	_sec(e, "WORLD")
	if gs.world.nearest_port_id.is_empty():
		_stub(e, "Nearest Port", "—")
	else:
		var pname: String = registry.get_port_display_name(gs.world.nearest_port_id) \
			if registry != null else gs.world.nearest_port_id
		_row(e, "Nearest Port", pname, C_VALUE)
	_row(e, "Weather",
		gs.world.weather_label if not gs.world.weather_label.is_empty() else "—",
		C_VALUE)


# ── Renderer ──────────────────────────────────────────────────────────────────

func _draw_entry(font: Font, entry: Dictionary, ox: float, cy: float) -> float:
	match entry.kind:
		"section":
			draw_string(font, Vector2(ox + PAD_X, cy + 12.0),
				entry.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SEC, C_SECTION)
			return cy + ROW_H
		"sep":
			draw_line(Vector2(ox + 6, cy + 4),
					  Vector2(ox + PANEL_W - 6, cy + 4), C_SEP, 1.0)
			return cy + 8.0
		"row":
			draw_string(font, Vector2(ox + PAD_X, cy + 12.0),
				entry.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_ROW, C_LABEL)
			draw_string(font, Vector2(ox + PAD_X + LABEL_W, cy + 12.0),
				entry.value, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_ROW, entry.color as Color)
			return cy + ROW_H
		"stub":
			draw_string(font, Vector2(ox + PAD_X, cy + 12.0),
				entry.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_ROW, C_LABEL)
			draw_string(font, Vector2(ox + PAD_X + LABEL_W, cy + 12.0),
				"— " + entry.value, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_ROW, C_STUB)
			return cy + ROW_H
	return cy + ROW_H


func _content_h(entries: Array) -> float:
	var h := 0.0
	for e in entries:
		match e.kind:
			"section", "row", "stub": h += ROW_H
			"sep":                     h += 8.0
	return h


# ── Entry helpers ─────────────────────────────────────────────────────────────

func _sec(e: Array, label: String) -> void:
	e.append({ "kind": "section", "label": label, "value": "",     "color": C_SECTION })

func _row(e: Array, label: String, value: String, color: Color) -> void:
	e.append({ "kind": "row",     "label": label, "value": value,  "color": color     })

func _stub(e: Array, label: String, reason: String) -> void:
	e.append({ "kind": "stub",    "label": label, "value": reason, "color": C_STUB    })

func _sep(e: Array) -> void:
	e.append({ "kind": "sep",     "label": "",    "value": "",     "color": C_SEP     })


# ── Formatting helpers ────────────────────────────────────────────────────────

static func _mb(value_mb: Variant) -> String:
	var v := float(value_mb)
	if v >= 1024.0:
		return "%.2f GB" % (v / 1024.0)
	return "%.1f MB" % v


## Health colouring: good if >= good_th, warn if >= warn_th, bad otherwise.
static func _band(value: float, good_th: float, warn_th: float) -> Color:
	if value >= good_th:
		return C_GOOD
	if value >= warn_th:
		return C_WARN
	return C_BAD


func _count_apron_cargo(contract_id: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("cargo_pickup"):
		var cp := node as CargoPickup
		if cp != null and cp.cargo_item != null and cp.cargo_item.contract_id == contract_id:
			count += 1
	return count
