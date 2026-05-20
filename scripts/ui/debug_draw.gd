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

	# Refresh on telemetry tick (system stats + loading log).
	var t := get_node_or_null("/root/Telemetry")
	if t != null and not t.sampled.is_connected(_on_telemetry):
		t.sampled.connect(_on_telemetry)

	# Refresh on gameplay state changes (player, ship, contracts, weather).
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		for sub in [gs.player, gs.ship, gs.contract, gs.world]:
			if sub != null and sub.has_signal("changed"):
				sub.changed.connect(_on_state_changed)

	var wl := get_node_or_null("/root/WeatherLighting")
	if wl != null and wl.has_signal("state_changed"):
		wl.state_changed.connect(_on_state_changed)


func _on_telemetry() -> void:
	if visible:
		queue_redraw()


func _on_state_changed() -> void:
	if visible:
		queue_redraw()


# Redraw once when becoming visible (so the panel doesn't show stale data).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
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
	var hint   := "F3 toggle · F4 weather · E day/calm"
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
	_build_loading(e)
	_build_gameplay(e)
	return e


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
	_row(e, "Marks", "ℳ %d" % gs.player.marks, C_GOLD)
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
			_row(e, "  Reward", "ℳ %d" % contract.reward_gold, C_GOLD)
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
