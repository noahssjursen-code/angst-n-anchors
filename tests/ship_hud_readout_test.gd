extends Node

## Lane B — the ship HUD is the surface a player reads for the whole game, and
## until today it had no test of any kind. It needs autoloads: the frames here
## are driven through `GameState.ship.publish_instruments()` →
## `LocalPlayerView.helm_instruments_changed` → `ShipHud._on_instruments_changed`,
## which is the production path, rather than by poking `_instruments` (§3).
##
## FIVE THINGS ARE ASSERTED, and they are deliberately not the same kind of
## thing, because each one is blind to the next:
##
## 1. THE SNAPSHOT SURVEY. Every key `GameState._capture_instruments()` publishes
##    must be read by something (`ShipHud` or `ChartNavSnapshot`), and every key
##    a consumer reads must be published. `GameState.status` was published and
##    drawn by nothing for the life of the fishing feature (REALITY §3d); this
##    is the check that would have said so on the day it landed. The two
##    directions are each other's guard: if the source scan breaks, one of them
##    goes red rather than both going quiet.
##
## 2. THE LAYOUT. `ShipHud.hud_layout()` states the rect every instrument
##    occupies. Regions must be inside the viewport, must not overlap, cells
##    must tile the band in order, and every cell's text must FIT the cell it
##    owns — which it did not: at the project's real 1920 px viewport an
##    autopilot destination measured 253 px of text in a 165 px cell and was
##    drawn straight through the FISH HOLD tonnage beside it. Both strings were
##    correct. Both were unreadable.
##
## 3. THE FRAME. A layout is a claim about pixels, so the claim is checked
##    against pixels: every region holds ink, no ink is painted outside the
##    regions, and inside the band no pixel of one cell's text lands in another
##    cell. This is the half a cell-list seam cannot have. The studio drawer sat
##    ENTIRELY OFF-VIEWPORT for the whole project's life while its probe
##    asserted the string in it, and a list of labels would have passed that
##    every time.
##
## 4. THE ONE STRING THE LAST WAVE ADDED. Hatch-shut and hatch-open frames are
##    rendered with everything else held equal: the FISH HOLD cell's pixels must
##    differ and no other cell's may. `catch_hold_test` asserts the string
##    arrives at `get_activity_status()`; nothing asserted it arrives on screen.
##
## 5. THE TOAST. Every one-shot notice the game sends a helmsman goes through
##    one panel, and that panel was drawn in the wrong place twice over — half
##    off the left edge of the screen, and 1357 px tall across the status band.
##    Both were geometry no cell list contains, and both are asserted here as
##    "inside the viewport" and "one notice tall".
##
## What none of it can see is listed at the bottom of this file.

const TestReport := preload("res://tests/support/test_report.gd")

const GAME_STATE_PATH := "res://scripts/state/game_state.gd"
const SHIP_HUD_PATH := "res://scripts/ui/ship_hud.gd"
const CHART_SNAPSHOT_PATH := "res://scripts/ui/chart/chart_nav_snapshot.gd"

## Keys `_capture_instruments()` publishes that no consumer reads, each with the
## reason it is not simply a defect to fix here. The list POLICES ITSELF: a key
## named here that acquires a consumer fails the run too, so it cannot quietly
## become a stale caveat (REALITY §4b — a caveat is a claim, and it rots).
const KNOWN_UNCONSUMED := {
	"bridge_watch":
	"published since the alarm landed and drawn by nobody: walking_hud.gd reads the "
	+ "alarm from LocalPlayerView.get_autopilot_snapshot(), which builds its own copy "
	+ "from the same node. This key is a second producer with no reader.",
}

## Alpha above this counts as painted. The viewport is rendered with a
## transparent background so "ink" is not a guess about a clear colour.
const INK_ALPHA := 8

var _t := TestReport.new("ship_hud_readout_test")
var _sub: SubViewport
var _hud: ShipHud
var _production_size := Vector2i(1920, 1080)


func _ready() -> void:
	_production_size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	)
	_survey_snapshot_keys()
	await _build_hud(_production_size)
	_check_layout(Vector2(_production_size), "production %dx%d" % [
		_production_size.x, _production_size.y
	])
	_check_layout(Vector2(1280, 720), "1280x720")
	await _check_frames()
	await _check_fish_hold_status_reaches_pixels()
	_check_production_wiring()
	_t.finish(get_tree())


# ── 1. the snapshot survey ────────────────────────────────────────────────────

func _survey_snapshot_keys() -> void:
	var published := _published_keys()
	var hud_keys := _read_keys(SHIP_HUD_PATH, "_instruments\\.get\\(\\s*\"([a-z_]+)\"")
	var chart_keys := _read_keys(CHART_SNAPSHOT_PATH, "projection\\.get\\(\\s*\"([a-z_]+)\"")
	var consumed := {}
	for key in hud_keys:
		consumed[key] = "ShipHud"
	for key in chart_keys:
		consumed[key] = "%s+ChartNavSnapshot" % consumed.get(key, "").trim_suffix("")

	print("  published by GameState._capture_instruments: %d keys" % published.size())
	print("  read by ShipHud: %d · by ChartNavSnapshot: %d" % [hud_keys.size(), chart_keys.size()])

	var undrawn := PackedStringArray()
	for key in published:
		if consumed.has(key):
			continue
		undrawn.append(key)
		if KNOWN_UNCONSUMED.has(key):
			print("  KNOWN UNCONSUMED  %s — %s" % [key, KNOWN_UNCONSUMED[key]])
			continue
		_t.check(
			"published key '%s' reaches a consumer (nothing reads it — REALITY §3d)" % key,
			false
		)
	_t.check(
		"every published key either reaches a consumer or is named in KNOWN_UNCONSUMED",
		undrawn.size() == KNOWN_UNCONSUMED.size()
	)
	## The other half of the self-policing: a key excused here that has since
	## acquired a reader must be struck off, or the excuse outlives the defect.
	for key in KNOWN_UNCONSUMED:
		_t.check(
			"KNOWN_UNCONSUMED key '%s' is still unread (strike it off if it now draws)" % key,
			not consumed.has(key)
		)
		_t.check(
			"KNOWN_UNCONSUMED key '%s' is still published (strike it off if it is gone)" % key,
			published.has(key)
		)

	## The reverse direction, and the guard on the scan above: a cell reading a
	## key nothing sets renders its default forever and looks like working code.
	for key in hud_keys:
		_t.check(
			"ShipHud reads '%s' and GameState publishes it" % key,
			published.has(key)
		)
	for key in chart_keys:
		if key in ["contracts", "waypoint", "moored_port_id", "moored_berth_id"]:
			continue  # added by get_navigation_snapshot(), not by _capture_instruments
		_t.check(
			"ChartNavSnapshot reads '%s' and GameState publishes it" % key,
			published.has(key)
		)


## The keys of the dictionary `_capture_instruments()` returns, read from the
## source: the function needs a live boat and a live controller to call, and a
## test that stubs those measures the stub.
func _published_keys() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(GAME_STATE_PATH)
	var out := PackedStringArray()
	if text.is_empty():
		_t.fail("could not read %s" % GAME_STATE_PATH)
		return out
	var func_at := text.find("func _capture_instruments")
	if func_at < 0:
		_t.fail("GameState has no _capture_instruments — the publisher moved")
		return out
	var return_at := text.find("\n\treturn {", func_at)
	var close_at := text.find("\n\t}", return_at)
	if return_at < 0 or close_at < 0:
		_t.fail("could not find the snapshot literal in _capture_instruments")
		return out
	var regex := RegEx.new()
	regex.compile("\"([a-z_]+)\"\\s*:")
	for m in regex.search_all(text.substr(return_at, close_at - return_at)):
		out.append(m.get_string(1))
	return out


func _read_keys(path: String, pattern: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(path)
	var out := PackedStringArray()
	if text.is_empty():
		_t.fail("could not read %s" % path)
		return out
	var regex := RegEx.new()
	regex.compile(pattern)
	for m in regex.search_all(text):
		var key := m.get_string(1)
		if not out.has(key):
			out.append(key)
	return out


# ── 2. the layout ─────────────────────────────────────────────────────────────

func _check_layout(viewport: Vector2, case_name: String) -> void:
	_publish(_snapshot("autopilot_fishing"))
	var layout := _hud.hud_layout(viewport)
	var frame := Rect2(Vector2.ZERO, viewport)
	var regions := layout["regions"] as Array[Dictionary]
	_t.check("%s: the layout names regions" % case_name, regions.size() >= 4)
	for region in regions:
		var rect := region["rect"] as Rect2
		_t.check(
			"%s: region '%s' %s is inside the viewport" % [case_name, region["id"], rect],
			frame.encloses(rect)
		)
	for a in range(regions.size()):
		for b in range(a + 1, regions.size()):
			var ra := regions[a]["rect"] as Rect2
			var rb := regions[b]["rect"] as Rect2
			_t.check(
				"%s: region '%s' does not overlap '%s'" % [
					case_name, regions[a]["id"], regions[b]["id"]
				],
				not ra.intersects(rb)
			)

	var band := layout["status_band"] as Rect2
	var cells := layout["cells"] as Array[Dictionary]
	_t.check("%s: the band carries cells" % case_name, cells.size() >= 8)
	var previous := Rect2()
	for index in range(cells.size()):
		var cell := cells[index]
		var rect := cell["rect"] as Rect2
		var label := str(cell["label"])
		_t.check("%s: cell '%s' is inside the band" % [case_name, label], band.encloses(rect))
		if index > 0:
			_t.check(
				"%s: cell '%s' starts where the one before it ends" % [case_name, label],
				absf(rect.position.x - previous.end.x) < 0.001
			)
		previous = rect
		## The property the live bug broke. Not "the string is 253 px" — the
		## width of a destination name is not a constant — but "one cell, one
		## cell's worth of ink".
		var value_w := _hud.call("_text_width", str(cell["text"]), ShipHud.STATUS_VALUE_SIZE) as float
		var label_w := _hud.call("_text_width", str(cell["label_text"]), ShipHud.STATUS_LABEL_SIZE) as float
		_t.check(
			"%s: cell '%s' value %.1f px fits its %.1f px cell" % [
				case_name, label, value_w, rect.size.x
			],
			value_w <= rect.size.x
		)
		_t.check(
			"%s: cell '%s' label %.1f px fits its %.1f px cell" % [
				case_name, label, label_w, rect.size.x
			],
			label_w <= rect.size.x
		)
		_t.check(
			"%s: cell '%s' has something to draw" % [case_name, label],
			not str(cell["text"]).is_empty() and not str(cell["label_text"]).is_empty()
		)
	_t.check(
		"%s: the cells span the band's usable width" % case_name,
		previous.end.x <= band.end.x + 0.001
	)


# ── 3. the frame ──────────────────────────────────────────────────────────────

func _check_frames() -> void:
	for case_name in ["underway", "autopilot_fishing"]:
		_publish(_snapshot(case_name))
		var layout := _hud.hud_layout(Vector2(_production_size))
		var image := await _grab()
		_check_frame_against_layout(image, layout, case_name)

	## Nothing published means nothing helmed: the instrument panel must not be
	## painted over a player who is walking the deck. The marks panel is a child
	## Control and keeps drawing, which is why it is a region and not an
	## exception.
	_clear()
	var empty_layout := _hud.hud_layout(Vector2(_production_size))
	var empty_image := await _grab()
	var empty_regions := empty_layout["regions"] as Array[Dictionary]
	var ids := PackedStringArray()
	for region in empty_regions:
		ids.append(str(region["id"]))
	_t.check(
		"no instruments: the layout claims only the marks panel (got %s)" % [ids],
		ids.size() == 1 and ids[0] == "marks"
	)
	_t.check("no instruments: no cells", (empty_layout["cells"] as Array).is_empty())
	_check_frame_against_layout(empty_image, empty_layout, "no instruments")

	## The toast is the HUD's only channel for a one-shot notice — the moored
	## warning, the autopilot toast, every trawl refusal `FishingSystem` sends —
	## and it is the element that was drawn in the wrong place twice over: the
	## HUD's own Control rect was 0 x 0 under a 1920 x 1080 window, so a
	## CENTER_TOP child centred on x = 0 and hung half off the left edge, and its
	## unset bottom offset let it lay out **680 x 1357**, a slab from y=210 to
	## past the bottom of the screen straight over HDG, COG, SOG and FUEL.
	## Neither was visible to anything that reads a cell list.
	_publish(_snapshot("underway"))
	_hud.show_toast("MOORED - untie both quay lines before departure", 60.0)
	await _settle_toast()
	var toast_layout := _hud.hud_layout(Vector2(_production_size))
	var toast_image := await _grab()
	var toast_ids := PackedStringArray()
	for region in toast_layout["regions"] as Array[Dictionary]:
		toast_ids.append(str(region["id"]))
	_t.check("a shown toast becomes a declared region", toast_ids.has("toast"))
	_check_frame_against_layout(toast_image, toast_layout, "toast")
	for region in toast_layout["regions"] as Array[Dictionary]:
		if str(region["id"]) != "toast":
			continue
		var rect := region["rect"] as Rect2
		_t.check(
			"the toast %s is inside the viewport" % rect,
			Rect2(Vector2.ZERO, Vector2(_production_size)).encloses(rect)
		)
		_t.check(
			"the toast is one notice tall, not a slab (%.0f px)" % rect.size.y,
			rect.size.y <= ShipHud.TOAST_HEIGHT * 2.0
		)


func _check_frame_against_layout(image: Image, layout: Dictionary, case_name: String) -> void:
	var regions := layout["regions"] as Array[Dictionary]
	var rects: Array[Rect2] = []
	for region in regions:
		var rect := region["rect"] as Rect2
		rects.append(rect)
		_t.check(
			"%s: region '%s' holds ink where the layout says it does" % [case_name, region["id"]],
			_ink_inside(image, rect) > 0
		)
	## Anything painted outside every declared rect is a region the layout does
	## not know about — which is the shape of the bug where a drawer is drawn
	## somewhere nobody is looking.
	_t.equal("%s: no ink outside the declared regions" % case_name, _ink_outside(image, rects), 0)

	## Inside the band, ink belongs to exactly one cell. This is the check the
	## cell-list seam cannot make: the list was right, the pixels were on top of
	## each other.
	var cells := layout["cells"] as Array[Dictionary]
	if cells.is_empty():
		return
	var band := layout["status_band"] as Rect2
	var stray := 0
	var per_cell := PackedInt32Array()
	var min_x := PackedInt32Array()
	var max_x := PackedInt32Array()
	per_cell.resize(cells.size())
	min_x.resize(cells.size())
	max_x.resize(cells.size())
	for index in range(cells.size()):
		min_x[index] = image.get_width()
		max_x[index] = -1
	var data := image.get_data()
	var width := image.get_width()
	var ink := BrandTokens.INK
	var ink_r := int(roundf(ink.r * 255.0))
	var ink_g := int(roundf(ink.g * 255.0))
	var ink_b := int(roundf(ink.b * 255.0))
	for y in range(int(band.position.y) + BrandTokens.RULE_WIDTH, int(band.end.y)):
		for x in range(image.get_width()):
			var i := (y * width + x) * 4
			if (
				absi(data[i] - ink_r) + absi(data[i + 1] - ink_g) + absi(data[i + 2] - ink_b) <= 8
			):
				continue
			var owner_index := -1
			var on_divider := false
			for index in range(1, cells.size()):
				if absf(float(x) - (cells[index]["rect"] as Rect2).position.x) <= 1.5:
					on_divider = true
					break
			for index in range(cells.size()):
				var rect := cells[index]["rect"] as Rect2
				if float(x) >= rect.position.x - 1.0 and float(x) <= rect.end.x + 1.0:
					owner_index = index
					break
			if owner_index < 0:
				stray += 1
				continue
			if on_divider:
				continue  # the rule between two cells belongs to neither
			per_cell[owner_index] += 1
			min_x[owner_index] = mini(min_x[owner_index], x)
			max_x[owner_index] = maxi(max_x[owner_index], x)
	_t.equal("%s: no band ink outside a cell" % case_name, stray, 0)
	for index in range(cells.size()):
		var cell := cells[index]
		var rect := cell["rect"] as Rect2
		var label := str(cell["label"])
		_t.check(
			"%s: cell '%s' is actually painted (%d px)" % [case_name, label, per_cell[index]],
			per_cell[index] > 0
		)
		## Not merely "inside SOME cell": ink shifted into the neighbour's column
		## is inside a cell and is still a cell drawn on top of another. The ink
		## must stand where this cell's own text, centred in this cell, puts it.
		var half := maxf(
			_hud.call("_text_width", str(cell["text"]), ShipHud.STATUS_VALUE_SIZE) as float,
			_hud.call("_text_width", str(cell["label_text"]), ShipHud.STATUS_LABEL_SIZE) as float
		) * 0.5
		var centre := rect.position.x + rect.size.x * 0.5
		_t.check(
			"%s: cell '%s' ink spans [%d,%d], its centred text allows [%.0f,%.0f]" % [
				case_name, label, min_x[index], max_x[index], centre - half, centre + half
			],
			(
				per_cell[index] > 0
				and float(min_x[index]) >= centre - half - 2.0
				and float(max_x[index]) <= centre + half + 2.0
			)
		)


# ── 4. the string the last wave added ─────────────────────────────────────────

func _check_fish_hold_status_reaches_pixels() -> void:
	_publish(_snapshot("autopilot_fishing"))
	var layout := _hud.hud_layout(Vector2(_production_size))
	var open_frame := await _grab()
	_publish(_snapshot("hatch_shut"))
	var shut_layout := _hud.hud_layout(Vector2(_production_size))
	var shut_frame := await _grab()

	var cells := layout["cells"] as Array[Dictionary]
	var shut_cells := shut_layout["cells"] as Array[Dictionary]
	_t.equal("hatch shut does not change the cell count", shut_cells.size(), cells.size())
	var fish_index := -1
	for index in range(cells.size()):
		if str(cells[index]["label"]) == "FISH HOLD":
			fish_index = index
	if not _t.check("the fishing snapshot produces a FISH HOLD cell", fish_index >= 0):
		return
	_t.check(
		"the shut-hatch cell draws the status string, not the tonnage",
		str(shut_cells[fish_index]["text"]) == FishingSystem.STATUS_HATCH_SHUT
	)
	for index in range(cells.size()):
		var rect := cells[index]["rect"] as Rect2
		var changed := _pixels_differing(open_frame, shut_frame, rect)
		if index == fish_index:
			_t.check(
				"shutting the hatch changes the FISH HOLD cell's pixels (%d differ)" % changed,
				changed > 0
			)
		else:
			_t.equal(
				"shutting the hatch leaves cell '%s' alone" % cells[index]["label"], changed, 0
			)


# ── the production path ───────────────────────────────────────────────────────

func _check_production_wiring() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	var state := get_node_or_null("/root/GameState")
	if not _t.check("LocalPlayerView and GameState are up", view != null and state != null):
		return
	## Every frame above arrived through this chain; assert it explicitly so a
	## disconnected HUD fails by name rather than by a blank picture.
	_t.check(
		"ShipState.instruments_changed reaches LocalPlayerView",
		(state.ship as ShipState).instruments_changed.is_connected(view._emit_helm_instruments)
	)
	_t.check(
		"LocalPlayerView.helm_instruments_changed reaches the HUD",
		view.helm_instruments_changed.is_connected(_hud._on_instruments_changed)
	)
	_t.check(
		"LocalPlayerView.ship_notice_requested reaches the HUD toast",
		view.ship_notice_requested.is_connected(_hud.show_toast)
	)
	_clear()
	_t.check("clearing the helm empties the HUD's instruments", _hud.status_cells().is_empty())
	_publish(_snapshot("underway"))
	_t.check(
		"publishing a snapshot refills them through the signal chain",
		_hud.status_cells().size() >= 8
	)


# ── rig ───────────────────────────────────────────────────────────────────────

func _build_hud(size: Vector2i) -> void:
	_sub = SubViewport.new()
	_sub.size = size
	_sub.transparent_bg = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub)
	_hud = ShipHud.new()
	_sub.add_child(_hud)
	await get_tree().process_frame
	## `_ready` anchors it full-rect. A Control that does not cover the viewport
	## is the shape of the studio drawer that sat off-screen for the project's
	## life, and it is invisible to every check that reads a cell list.
	_t.equal("the HUD covers the whole viewport", _hud.get_rect(), Rect2(Vector2.ZERO, Vector2(size)))
	_t.equal(
		"the HUD reports the viewport it draws into",
		_hud.get_viewport_rect().size,
		Vector2(size)
	)


func _publish(snapshot: Dictionary) -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		_t.fail("GameState autoload missing — this test must run in lane B")
		return
	(state.ship as ShipState).publish_instruments(snapshot)


func _clear() -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		(state.ship as ShipState).clear_instruments()


## `BrandToast.show_message` slides the panel in on a tween, so its rect moves
## for the first few frames. Wait for it to stop rather than for a frame count —
## a fixed count is a guess that goes flaky on a slower box.
func _settle_toast() -> void:
	var previous := Rect2()
	for _i in range(240):
		await get_tree().process_frame
		var rect := _hud.hud_layout(Vector2(_production_size))["regions"] as Array[Dictionary]
		var current := Rect2()
		for region in rect:
			if str(region["id"]) == "toast":
				current = region["rect"] as Rect2
		if current == previous and current.size.y > 0.0:
			return
		previous = current
	_t.fail("the toast never settled to a stable rect")


func _grab() -> Image:
	_hud.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _sub.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _ink_inside(image: Image, rect: Rect2) -> int:
	var data := image.get_data()
	var width := image.get_width()
	var count := 0
	for y in range(maxi(int(rect.position.y), 0), mini(int(rect.end.y), image.get_height())):
		for x in range(maxi(int(rect.position.x), 0), mini(int(rect.end.x), width)):
			if data[(y * width + x) * 4 + 3] >= INK_ALPHA:
				count += 1
	return count


func _ink_outside(image: Image, rects: Array) -> int:
	var data := image.get_data()
	var width := image.get_width()
	var height := image.get_height()
	var grown: Array[Rect2] = []
	for rect in rects:
		grown.append((rect as Rect2).grow(2.0))
	var count := 0
	for y in range(height):
		var row := y * width
		for x in range(width):
			if data[(row + x) * 4 + 3] < INK_ALPHA:
				continue
			var inside := false
			for rect in grown:
				if rect.has_point(Vector2(x, y)):
					inside = true
					break
			if not inside:
				count += 1
	return count


func _pixels_differing(a: Image, b: Image, rect: Rect2) -> int:
	var da := a.get_data()
	var db := b.get_data()
	var width := a.get_width()
	var count := 0
	for y in range(maxi(int(rect.position.y), 0), mini(int(rect.end.y), a.get_height())):
		for x in range(maxi(int(rect.position.x), 0), mini(int(rect.end.x), width)):
			var i := (y * width + x) * 4
			if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
				count += 1
	return count


## Snapshots shaped like `GameState._capture_instruments()` output. They are
## written out rather than captured from a live boat because a boat cannot be
## asked for an autopilot bound for a long-named port with a full hold on
## demand — see "what this test does not contain" below.
func _snapshot(case_name: String) -> Dictionary:
	var snapshot := {
		"position": Vector3(120.0, 0.0, -48.0),
		"bow": Vector2(0.0, -1.0),
		"velocity": Vector3(3.0, 0.0, -4.0),
		"heading_deg": 143.0,
		"speed_knots": 9.7,
		"fuel_fraction": 0.42,
		"throttle_values": [-0.5, 0.0, 0.25, 0.5, 1.0],
		"throttle_index": 3,
		"throttle_value": 0.5,
		"thruster_mode": 1,
		"lights": "NAV",
		"autopilot_active": false,
		"target_bearing_deg": NAN,
		"destination_name": "",
		"remaining_distance_m": 0.0,
		"bridge_watch": {},
		"fishing": {},
		"wind_direction": Vector3(1.0, 0.0, 0.4),
		"wind_speed_ms": 8.3,
		"time_hours": 14.5,
	}
	if case_name in ["autopilot_fishing", "hatch_shut"]:
		snapshot["autopilot_active"] = true
		snapshot["destination_name"] = "Bornholm Fiskerihavn"
		snapshot["remaining_distance_m"] = 18450.0
		snapshot["target_bearing_deg"] = 91.0
		snapshot["fishing"] = {"status": "ACTIVE", "mass_t": 3.4, "capacity_t": 12.0}
	if case_name == "hatch_shut":
		snapshot["fishing"]["status"] = FishingSystem.STATUS_HATCH_SHUT
	return snapshot

## WHAT THIS CANNOT SEE
##
## - Whether the HUD is on screen at all. It renders into a SubViewport here;
##   in the game `BoatController._ensure_hud` puts it on a CanvasLayer and
##   `_set_hud_visible` toggles it. A HUD hidden by that path passes everything
##   above. Nothing in the repo covers it.
## - Legibility. "Ink is inside the cell" is not "a person can read it": the
##   trimmed autopilot cell now reads BORNHOLM FISKERI… and whether that is
##   useful is a taste answer, which belongs to a person looking at
##   `screenshots/hud/` (REALITY §1, §2).
## - Anything above the band that overlaps in Z rather than in XY. Regions here
##   are rects on one CanvasItem; another CanvasLayer drawn over the HUD is
##   invisible to it.
## - The producer. `_capture_instruments()` is surveyed by reading the source,
##   not by calling it, so a key that is published as the WRONG VALUE — the
##   right name carrying a stale number — reads as consumed here. That is the
##   next test, and it needs a live boat.
## - Four of the six strings `FishingSystem.get_activity_status()` can return.
##   READY, ACTIVE, TOO SLOW and TOO CLOSE TO SHORE never reach a pixel: the
##   cell draws tonnage unless the status is one of the two blockers. TOO SLOW
##   has no toast either, so a trawl streamed below one knot catches nothing and
##   says nothing, anywhere, ever.
