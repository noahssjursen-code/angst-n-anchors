extends Node3D

## SCRATCH PROBE (leading underscore — the gate skips it).
##
## THE QUESTION: does a real mouse wheel over the properties drawer scroll it, or
## is it swallowed by the studio's camera zoom? The drawer audit set
## `scroll_vertical` in code for its capture, which proves the ScrollContainer can
## be moved by an ASSIGNMENT and says nothing about whether a player can move it.
## If the wheel zooms instead, SAVE JSON is unreachable by any means.
##
## Delivery is `Viewport.push_input` with a real `InputEventMouseButton`
## (WHEEL_DOWN/UP, pressed then released) positioned in viewport coordinates —
## the same space the Control rects below are printed in. That path runs the whole
## input stack: `Viewport._gui_input` first, `_unhandled_input` after.

var _studio: Node
var _ui: Control
var _scroll: ScrollContainer


func _ready() -> void:
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	for _i in 4:
		await get_tree().process_frame
	_ui = _studio.get("_ui_root") as Control
	_scroll = _studio.get("_drawer_scroll") as ScrollContainer

	print("VIEWPORT %s" % get_viewport().get_visible_rect())
	_report_geometry()
	await _wheel_over_drawer()
	await _wheel_over_3d_control()
	await _wheel_over_palette()
	print("\nWHEEL PROBE DONE")
	get_tree().quit(0)


func _filter_name(c: Control) -> String:
	match c.mouse_filter:
		Control.MOUSE_FILTER_STOP: return "STOP"
		Control.MOUSE_FILTER_PASS: return "PASS"
		Control.MOUSE_FILTER_IGNORE: return "IGNORE"
	return "?"


func _report_geometry() -> void:
	print("\n=== GEOMETRY")
	var drawer := _ui.get_node("PropertiesDrawer") as Control
	var content := _scroll.get_child(0) as Control
	var bar := _scroll.get_v_scroll_bar()
	print("  drawer      rect=%s filter=%s" % [drawer.get_global_rect(), _filter_name(drawer)])
	print("  scroll      rect=%s filter=%s" % [_scroll.get_global_rect(), _filter_name(_scroll)])
	print("  content     rect=%s filter=%s" % [content.get_global_rect(), _filter_name(content)])
	print("  v scrollbar rect=%s visible=%s max=%.0f page=%.0f min_size=%s" % [
		bar.get_global_rect(), bar.is_visible_in_tree(),
		bar.max_value, bar.page, bar.get_combined_minimum_size()
	])
	print("  scroll viewport %.0f px over %.0f px of content" % [_scroll.size.y, content.size.y])
	var palette := _ui.get_node("ToolPalette") as Control
	var pscroll: ScrollContainer = _first_scroll(palette)
	print("  palette     rect=%s scroll=%s content=%.0f px filter=%s" % [
		palette.get_global_rect(), pscroll.get_global_rect(),
		(pscroll.get_child(0) as Control).size.y, _filter_name(pscroll)
	])


func _first_scroll(root: Node) -> ScrollContainer:
	if root is ScrollContainer:
		return root as ScrollContainer
	for c in root.get_children():
		var hit := _first_scroll(c)
		if hit != null:
			return hit
	return null


## One real wheel notch, delivered at `at`. Returns nothing; the caller reads the
## state it cares about. Both halves of the click are sent, as a real mouse does.
func _wheel(at: Vector2, up: bool) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		ev.factor = 1.0
		get_viewport().push_input(ev, true)
	await get_tree().process_frame


func _state() -> String:
	return "scroll_vertical=%d cam_distance=%.3f" % [
		_scroll.scroll_vertical, float(_studio.get("_cam_distance"))
	]


func _wheel_over_drawer() -> void:
	print("\n=== 1. WHEEL OVER THE DRAWER")
	_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var at := _scroll.get_global_rect().get_center()
	print("  before  %s" % _state())
	print("  wheel DOWN x5 at %s (centre of the drawer's scroll viewport)" % at)
	for _i in 5:
		await _wheel(at, false)
	print("  after   %s" % _state())
	var scrolled := _scroll.scroll_vertical
	print("  wheel UP x5 at the same point")
	for _i in 5:
		await _wheel(at, true)
	print("  after   %s" % _state())
	print("  VERDICT: the wheel %s the drawer" % (
		"SCROLLS" if scrolled > 0 else "DOES NOT SCROLL"
	))
	## Can the wheel reach the very bottom — SAVE JSON and LOAD SELECTED?
	_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var notches := 0
	while notches < 200:
		var before := _scroll.scroll_vertical
		await _wheel(at, false)
		notches += 1
		if _scroll.scroll_vertical == before:
			break
	print("  wheeling down until it stops: %d notches -> scroll_vertical=%d (max %.0f)" % [
		notches, _scroll.scroll_vertical, _scroll.get_v_scroll_bar().max_value - _scroll.get_v_scroll_bar().page
	])
	var fold := _scroll.get_global_rect().end.y
	for text in ["SAVE JSON", "LOAD SELECTED"]:
		var b := _find_button(_ui.get_node("PropertiesDrawer"), text)
		if b != null:
			print("  %-14s rect=%s  %s" % [
				text, b.get_global_rect(),
				"REACHED" if b.get_global_rect().end.y <= fold + 1.0 else "STILL BELOW THE FOLD"
			])


func _wheel_over_3d_control() -> void:
	print("\n=== 2. CONTROL — WHEEL OVER THE 3D VIEW (must zoom)")
	var at := Vector2(760.0, 520.0)
	print("  before  %s" % _state())
	for _i in 3:
		await _wheel(at, false)
	print("  after wheel DOWN x3 at %s: %s" % [at, _state()])
	for _i in 3:
		await _wheel(at, true)
	print("  after wheel UP   x3: %s" % _state())


func _wheel_over_palette() -> void:
	print("\n=== 3. WHEEL OVER THE LEFT TOOL PALETTE")
	var palette := _ui.get_node("ToolPalette") as Control
	var pscroll := _first_scroll(palette)
	## The palette's height is decided by the ARMED TOOL — the fitting catalogue is
	## only in the tree when the fitting tool is up, which is the state the drawer
	## audit measured "7 of 17 fittings below the fold" in.
	for tool in [0, 5, 6]:
		_studio.call("_set_tool", tool)
		_studio.call("_refresh_panel")
		for _f in 2:
			await get_tree().process_frame
		pscroll.scroll_vertical = 0
		await get_tree().process_frame
		var content := pscroll.get_child(0) as Control
		var at := pscroll.get_global_rect().get_center()
		var cam_before := float(_studio.get("_cam_distance"))
		for _i in 8:
			await _wheel(at, false)
		var cam_after := float(_studio.get("_cam_distance"))
		print("  tool %d: viewport %.0f px over %.0f px content; wheel DOWN x8 -> scroll_v=%d (max %.0f), cam %.3f -> %.3f%s" % [
			tool, pscroll.size.y, content.size.y, pscroll.scroll_vertical,
			maxf(pscroll.get_v_scroll_bar().max_value - pscroll.get_v_scroll_bar().page, 0.0),
			cam_before, cam_after,
			"  <<< CAMERA MOVED" if not is_equal_approx(cam_before, cam_after) else ""
		])
		var below := 0
		var total := 0
		var fold := pscroll.get_global_rect().end.y
		for b in _all_buttons(palette):
			if (b as Button).text.is_empty():
				continue
			total += 1
			if (b as Button).get_global_rect().position.y >= fold:
				below += 1
		print("    palette buttons: %d total, %d still below the fold after 8 notches" % [total, below])


func _all_buttons(root: Node, out: Array = []) -> Array:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		_all_buttons(c, out)
	return out


func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for c in root.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null
