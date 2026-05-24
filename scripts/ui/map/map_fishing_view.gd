class_name MapFishingView
extends RefCounted

## Fishing-ground overlay for the sea chart — grid-sampled `FishingField`.

const MIN_CELL_M := 2500.0
const MAX_CELLS_X := 32
const MAX_CELLS_Y := 22

var _cache_wx0: float = NAN
var _cache_wz0: float = NAN
var _cache_cell_m: float = -1.0
var _cache_cols: int = -1
var _cache_rows: int = -1
var _cache_tier_ids: PackedStringArray = PackedStringArray()


func render(canvas: CanvasItem, ctx: Dictionary) -> void:
	if not FishingField.is_initialized():
		return
	var g := _grid(ctx)
	_ensure_cache(g)
	_draw_grounds(canvas, g)
	_draw_legend(canvas, ctx)
	if bool(ctx.get("hover_inside", false)):
		_draw_hover(canvas, g, ctx)


func _grid(ctx: Dictionary) -> Dictionary:
	var wx_min: float = float(ctx["wx_min"])
	var wx_max: float = float(ctx["wx_max"])
	var wz_min: float = float(ctx["wz_min"])
	var wz_max: float = float(ctx["wz_max"])
	var cpw: float = float(ctx["cpw"])
	var cph: float = float(ctx["cph"])
	var span_x := wx_max - wx_min
	var span_z := wz_max - wz_min
	var cell_m := maxf(MIN_CELL_M, maxf(span_x / float(MAX_CELLS_X), span_z / float(MAX_CELLS_Y)))
	var wx0 := floorf(wx_min / cell_m) * cell_m
	var wz0 := floorf(wz_min / cell_m) * cell_m
	var cols := clampi(int(ceilf((wx_max - wx0) / cell_m)), 1, MAX_CELLS_X + 2)
	var rows := clampi(int(ceilf((wz_max - wz0) / cell_m)), 1, MAX_CELLS_Y + 2)
	return {
		"cell_m": cell_m,
		"cols": cols,
		"rows": rows,
		"wx0": wx0,
		"wz0": wz0,
		"wx_min": wx_min,
		"wz_min": wz_min,
		"cpx": float(ctx["cpx"]),
		"cpy": float(ctx["cpy"]),
		"cpw": cpw,
		"cph": cph,
		"ppu_x": cpw / span_x,
		"ppu_z": cph / span_z,
	}


func _ensure_cache(g: Dictionary) -> void:
	var cell_m: float = g["cell_m"]
	var cols: int = g["cols"]
	var rows: int = g["rows"]
	var wx0: float = g["wx0"]
	var wz0: float = g["wz0"]
	if (
		_cache_cell_m == cell_m
		and _cache_cols == cols
		and _cache_rows == rows
		and is_equal_approx(_cache_wx0, wx0)
		and is_equal_approx(_cache_wz0, wz0)
	):
		return
	_cache_wx0 = wx0
	_cache_wz0 = wz0
	_cache_cell_m = cell_m
	_cache_cols = cols
	_cache_rows = rows
	var n := cols * rows
	_cache_tier_ids.resize(n)
	for j in range(rows):
		for i in range(cols):
			var wx := wx0 + (float(i) + 0.5) * cell_m
			var wz := wz0 + (float(j) + 0.5) * cell_m
			var zone := FishingField.sample(Vector3(wx, 0.0, wz))
			_cache_tier_ids[j * cols + i] = str(zone["tier_id"])


func _draw_grounds(canvas: CanvasItem, g: Dictionary) -> void:
	var cell_m: float = g["cell_m"]
	var cell_w: float = cell_m * float(g["ppu_x"])
	var cell_h: float = cell_m * float(g["ppu_z"])
	var cols: int = g["cols"]
	var rows: int = g["rows"]
	for j in range(rows):
		var wz0: float = float(g["wz0"]) + float(j) * cell_m
		var sy: float = _wz_to_sy(wz0, g)
		for i in range(cols):
			var wx0: float = float(g["wx0"]) + float(i) * cell_m
			var sx: float = _wx_to_sx(wx0, g)
			var tier_id := _cache_tier_ids[j * cols + i]
			canvas.draw_rect(
				Rect2(sx, sy, cell_w + 1.0, cell_h + 1.0),
				FishingField.tier_color(tier_id),
				true
			)


func _draw_legend(canvas: CanvasItem, ctx: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var x: float = float(ctx["cpx"]) + 8.0
	var y: float = float(ctx["cpy"]) + float(ctx["cph"]) - 58.0
	canvas.draw_string(
		font, Vector2(x, y - 4.0), "Fishing grounds", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.82, 0.90, 0.82, 0.85)
	)
	var sw := 42.0
	var sh := 10.0
	for idx in range(FishingField.TIERS.size()):
		var tier: Dictionary = FishingField.TIERS[idx]
		var lx := x + float(idx) * (sw + 4.0)
		var col: Color = tier["color"] as Color
		canvas.draw_rect(Rect2(lx, y + 4.0, sw, sh), col, true)
		canvas.draw_string(
			font, Vector2(lx, y + sh + 14.0), str(tier["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.78, 0.86, 0.80, 0.88)
		)


func _draw_hover(canvas: CanvasItem, g: Dictionary, ctx: Dictionary) -> void:
	var hover_pos: Vector2 = ctx["hover_pos"]
	var cell_m: float = g["cell_m"]
	var cols: int = g["cols"]
	var rows: int = g["rows"]
	var cpx: float = float(ctx["cpx"])
	var cpy: float = float(ctx["cpy"])
	var wx_min: float = float(ctx["wx_min"])
	var wz_min: float = float(ctx["wz_min"])
	var wx: float = wx_min + (hover_pos.x - cpx) / float(g["ppu_x"])
	var wz: float = wz_min + (hover_pos.y - cpy) / float(g["ppu_z"])
	var i := int(floorf((wx - float(g["wx0"])) / cell_m))
	var j := int(floorf((wz - float(g["wz0"])) / cell_m))
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return
	var cell_wx: float = float(g["wx0"]) + (float(i) + 0.5) * cell_m
	var cell_wz: float = float(g["wz0"]) + (float(j) + 0.5) * cell_m
	var zone := FishingField.sample(Vector3(cell_wx, 0.0, cell_wz))
	var crate_val := ContractRegistry.fish_crate_value(float(zone["price_mul"]))
	var lines: Array[String] = [
		"Position:  %d, %d  m" % [int(cell_wx), int(cell_wz)],
		"Grounds:   %s" % str(zone["tier_label"]),
		"Crate pay: ~%s" % PlayerData.format_money(crate_val),
	]
	if not bool(zone["open_water"]):
		lines.append("Too close to shore")
	var font := ThemeDB.fallback_font
	var line_h := 13
	var pad := 6.0
	var w := 0.0
	for ln in lines:
		w = maxf(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	w += pad * 2.0
	var h := float(lines.size()) * float(line_h) + pad * 2.0
	var tx := clampf(hover_pos.x + 12.0, cpx + 4.0, cpx + float(ctx["cpw"]) - w - 4.0)
	var ty := clampf(hover_pos.y + 12.0, cpy + 4.0, cpy + float(ctx["cph"]) - h - 4.0)
	canvas.draw_rect(Rect2(tx, ty, w, h), Color(0.02, 0.06, 0.08, 0.88), true)
	canvas.draw_rect(Rect2(tx, ty, w, h), Color(0.35, 0.62, 0.48, 0.55), false, 1.0)
	for li in range(lines.size()):
		canvas.draw_string(
			font, Vector2(tx + pad, ty + pad + float(li + 1) * float(line_h) - 2.0),
			lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.96, 0.90, 0.95)
		)


func _wx_to_sx(wx: float, g: Dictionary) -> float:
	return float(g["cpx"]) + (wx - float(g["wx_min"])) * float(g["ppu_x"])


func _wz_to_sy(wz: float, g: Dictionary) -> float:
	return float(g["cpy"]) + (wz - float(g["wz_min"])) * float(g["ppu_z"])
