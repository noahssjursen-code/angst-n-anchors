class_name DebugDraw
extends Control

## Debug read-out panel — reads live from GameState and supporting singletons.
## Toggled by DebugHud autoload (F3). All rendering via _draw().

const PANEL_W := 320.0
const PAD_X   := 12.0
const PAD_Y   := 10.0
const ROW_H   := 17.0
const LABEL_W := 112.0
const FS_ROW  := 10
const FS_SEC  := 10

const C_BG      := Color(0.03, 0.05, 0.12, 0.95)
const C_BORDER  := Color(0.28, 0.40, 0.64, 0.55)
const C_TITLE   := Color(0.96, 0.86, 0.12, 0.90)
const C_SECTION := Color(0.50, 0.65, 0.90, 0.85)
const C_LABEL   := Color(0.45, 0.58, 0.76, 0.70)
const C_VALUE   := Color(0.88, 0.94, 1.00, 0.95)
const C_STUB    := Color(0.72, 0.52, 0.22, 0.60)
const C_GOLD    := Color(0.96, 0.82, 0.28, 0.95)
const C_SEP     := Color(0.20, 0.30, 0.50, 0.25)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var vp   := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	var entries: Array = _build(gs)
	var ph     := PAD_Y + ROW_H + 6.0 + _content_h(entries) + PAD_Y
	var ox     := vp.x - PANEL_W - 14.0
	var oy     := 14.0

	draw_rect(Rect2(ox, oy, PANEL_W, ph), C_BG)
	draw_rect(Rect2(ox, oy, PANEL_W, ph), C_BORDER, false, 1.0)

	var ty := oy + PAD_Y + 12.0
	draw_string(font, Vector2(ox + PAD_X, ty),
		"DEBUG", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TITLE)
	var hint   := "F3  │  F4 weather"
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(ox + PANEL_W - hint_w - PAD_X, ty),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_LABEL)
	draw_line(Vector2(ox + 6, oy + PAD_Y + ROW_H + 2),
			  Vector2(ox + PANEL_W - 6, oy + PAD_Y + ROW_H + 2), C_SEP, 1.0)

	var cy := oy + PAD_Y + ROW_H + 6.0
	for e in entries:
		cy = _draw_entry(font, e, ox, cy)


# ── Entry list builder ────────────────────────────────────────────────────────

func _build(gs: Node) -> Array:
	var e:        Array = []
	var registry: Node  = get_node_or_null("/root/ContractRegistry")

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

	return e


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


func _count_apron_cargo(contract_id: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("cargo_pickup"):
		var cp := node as CargoPickup
		if cp != null and cp.cargo_item != null and cp.cargo_item.contract_id == contract_id:
			count += 1
	return count
