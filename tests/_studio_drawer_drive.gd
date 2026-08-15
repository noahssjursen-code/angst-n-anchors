extends Node3D

## SCRATCH PROBE (leading underscore — the gate skips it).
##
## Drives every control in the properties drawer and the context strip the way a
## player would — by finding the actual Button/LineEdit/OptionButton node in the
## tree and emitting its signal — and reports what each one DID. Nothing here
## calls the underlying method.

const STRUCTURES_DIR := "res://resources/data/structures"

var _studio: Node
var _ui: Node


func _ready() -> void:
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	await get_tree().process_frame
	await get_tree().process_frame
	_ui = _studio.get("_ui_root")

	_report_scroll()
	_report_drawer_info()
	_report_library()
	await _report_strip_overflow()
	await _report_round_trip()
	_report_overwrite()
	print("\nDRIVE DONE")
	get_tree().quit(0)


func _find(root: Node, cls: String, text: String) -> Control:
	if root is Control and root.get_class() == cls:
		var t := ""
		if root is Button:
			t = (root as Button).text
		elif root is Label:
			t = (root as Label).text
		if t == text:
			return root as Control
	for c in root.get_children():
		var hit := _find(c, cls, text)
		if hit != null:
			return hit
	return null


func _drawer() -> Control:
	return _ui.get_node("PropertiesDrawer") as Control


# ── 1. Where does the drawer's scroll sit, and can a player tell there is more?
func _report_scroll() -> void:
	print("\n=== 1. THE DRAWER'S SCROLL")
	var scroll: ScrollContainer = null
	var stack: Array = [_drawer()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			scroll = n as ScrollContainer
			break
		for c in n.get_children():
			stack.append(c)
	if scroll == null:
		print("  no ScrollContainer found")
		return
	var content := scroll.get_child(0) as Control
	print("  viewport height %.0f, content height %.0f, scroll_v=%d max=%d" % [
		scroll.size.y, content.size.y,
		scroll.scroll_vertical, scroll.get_v_scroll_bar().max_value
	])
	print("  v scrollbar visible_in_tree=%s rect=%s" % [
		scroll.get_v_scroll_bar().is_visible_in_tree(),
		scroll.get_v_scroll_bar().get_global_rect(),
	])
	# What is below the fold at scroll 0?
	var fold := scroll.get_global_rect().end.y
	for label_text in ["SURFACE LIBRARY", "PROPERTIES", "STRUCTURE FILE"]:
		var lab := _find(_drawer(), "Label", label_text)
		if lab != null:
			print("  header %-16s top y=%.0f  fold y=%.0f  %s" % [
				label_text, lab.get_global_rect().position.y, fold,
				"BELOW THE FOLD" if lab.get_global_rect().position.y >= fold else "visible"
			])
	for btn_text in ["SAVE JSON", "LOAD SELECTED", "OUTSIDE", "INSIDE"]:
		var b := _find(_drawer(), "Button", btn_text)
		if b != null:
			print("  button %-16s top y=%.0f  %s" % [
				btn_text, b.get_global_rect().position.y,
				"BELOW THE FOLD" if b.get_global_rect().position.y >= fold else "visible"
			])


# ── 2. The PROPERTIES blurb
func _report_drawer_info() -> void:
	print("\n=== 2. THE 'PROPERTIES' BLURB (_drawer_info)")
	_studio.call("_set_context", "vessel")
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	_studio.set("_selected_id", -1)
	_studio.call("_refresh_panel")
	var info: Label = _studio.get("_drawer_info")
	print("  nothing selected -> %s" % JSON.stringify(info.text))
	var plan = _studio.get("_plan")
	var wall_id := int((plan.walls[0] as Dictionary)["id"])
	_studio.set("_selected_id", wall_id)
	_studio.call("_update_selection_visual")
	_studio.call("_refresh_panel")
	print("  wall #%d selected -> %s" % [wall_id, JSON.stringify(info.text)])
	var header := ""
	var box: Node = _studio.get("_inspector_box")
	if box.get_child_count() > 0 and box.get_child(0) is Label:
		header = (box.get_child(0) as Label).text
	print("  inspector's own first row -> %s" % JSON.stringify(header))


# ── 3. The surface library
#
# WHAT THIS MEASURED BEFORE THE AUDIT, and why the OUTSIDE / INSIDE buttons this
# section used to press are no longer in the tree:
#
#   armed slot at boot: out
#   after OUTSIDE + swatch#2: wall.color=[0.90, 0.86, 0.76]
#   after INSIDE  + swatch#6: wall.color=[0.55, 0.20, 0.16]   <- the SAME key
#   a wall drawn with INSIDE armed: color=[0.90, 0.86, 0.76]  <- the OUTSIDE value
#   piece selected, swatch#4 pressed: color #e3e0d4 -> #e3e0d4  status=inside colour set
#
# i.e. "inside" painted the outside, the value it stored was read by nothing, and
# the library reported success over a placement it had not touched. The slot row
# is gone; this section now measures what the one remaining library does.
func _report_library() -> void:
	print("\n=== 3. SURFACE LIBRARY")
	_studio.call("_set_context", "vessel")
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	var plan = _studio.get("_plan")
	var wall := plan.walls[0] as Dictionary
	_studio.set("_selected_id", int(wall["id"]))
	_studio.call("_refresh_panel")
	print("  the library holds one surface: %s" % JSON.stringify(_studio.get("_lib")))
	print("  OUTSIDE button still in the tree: %s" % (_find(_drawer(), "Button", "OUTSIDE") != null))
	print("  INSIDE  button still in the tree: %s" % (_find(_drawer(), "Button", "INSIDE") != null))
	print("  wall as drawn: color=%s material=%s" % [wall.get("color"), wall.get("material")])
	var swatches := _swatch_buttons()
	print("  %d colour swatches on the drawer" % swatches.size())
	swatches[6].pressed.emit()
	print("  after swatch#6: wall.color=%s  status=%s" % [wall.get("color"), _studio.get("_status")])
	(_find(_drawer(), "Button", "WOOD") as Button).pressed.emit()
	print("  after WOOD:     wall.material=%s  status=%s" % [
		wall.get("material"), _studio.get("_status")
	])
	_studio.call("_place_wall", Vector3(2, 0, 14), Vector3(8, 0, 14))
	var fresh := plan.walls[1] as Dictionary
	print("  the NEXT wall drawn is born: color=%s material=%s" % [
		fresh.get("color"), fresh.get("material")
	])
	# On a piece placement, and on a fitting.
	_studio.call("_set_tool", 5)
	var ids: Array = _studio.call("_kit_ids")
	_studio.call("_select_piece_type", str(ids[0]))
	var placed: Dictionary = _studio.call("_place_piece_at", Vector3i(8, 0, 20))
	_studio.set("_selected_id", int(placed["id"]))
	_studio.call("_refresh_panel")
	var tint_before := str(placed.get("color", "<none>"))
	swatches[4].pressed.emit()
	print("  piece selected, swatch pressed: color %s -> %s\n    status=%s" % [
		tint_before, placed.get("color", "<none>"), _studio.get("_status")
	])
	_studio.call("_set_tool", 6)
	_studio.call("_set_build_level", 0.0)
	_studio.call("_probe_click_fitting", "bollard_pair", Vector3i(10, 0, 40))
	var item := plan.items[0] as Dictionary
	_studio.set("_selected_id", int(item["id"]))
	_studio.call("_refresh_panel")
	swatches[4].pressed.emit()
	print("  fitting selected, swatch pressed: item keys %s\n    status=%s" % [
		item.keys(), _studio.get("_status")
	])


func _swatch_buttons() -> Array:
	# The swatches are the Buttons in the drawer with empty text and a 32x32 min.
	var out: Array = []
	var stack: Array = [_drawer()]
	var found: Array = []
	_collect_buttons(_drawer(), found)
	for b in found:
		var btn := b as Button
		if btn.text.is_empty() and btn.custom_minimum_size == Vector2(32, 32):
			out.append(btn)
	return out


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(c)
		_collect_buttons(c, out)


# ── 4. The context strip: does the text fit?
func _report_strip_overflow() -> void:
	print("\n=== 4. CONTEXT STRIP FIT")
	var strip := _ui.get_node("ContextStrip") as Control
	var hint: Label = _studio.get("_hint_label")
	var status: Label = _studio.get("_status_label")
	var metrics: Label = _studio.get("_metrics_label")
	var hints: Dictionary = _studio.get("TOOL_HINTS") if false else {}
	for tool in range(7):
		_studio.call("_set_tool", tool)
		_studio.call("_refresh_panel")
		await get_tree().process_frame
		var font := hint.get_theme_font(&"font")
		var size := hint.get_theme_font_size(&"font_size")
		var need := font.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		print("  tool %d hint: needs %.0f px, has %.0f px  %s" % [
			tool, need, hint.size.x, "TRUNCATED" if need > hint.size.x + 1 else "fits"
		])
	# The longest status this studio can emit: the off-hull refusal.
	_studio.call("_set_context", "vessel")
	_studio.call("_place_wall", Vector3(900, 0, 900), Vector3(906, 0, 900))
	_studio.call("_refresh_panel")
	await get_tree().process_frame
	var sfont := status.get_theme_font(&"font")
	var ssize := status.get_theme_font_size(&"font_size")
	var sneed := sfont.get_string_size(status.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ssize).x
	print("  off-hull status (%d chars): needs %.0f px, has %.0f px" % [
		status.text.length(), sneed, status.size.x
	])
	print("    text: %s" % status.text)
	print("  strip row: metrics %.0f + hint %.0f + status %.0f = %.0f, strip inner width %.0f" % [
		metrics.size.x, hint.size.x, status.size.x,
		metrics.size.x + hint.size.x + status.size.x, strip.size.x
	])
	print("  metrics rect=%s hint rect=%s status rect=%s" % [
		metrics.get_global_rect(), hint.get_global_rect(), status.get_global_rect()
	])
	print("  hint overrun behaviour=%d  status overrun behaviour=%d" % [
		hint.text_overrun_behavior, status.text_overrun_behavior
	])


# ── 5. THE ROUND TRIP, through SAVE JSON and LOAD SELECTED
func _report_round_trip() -> void:
	print("\n=== 5. SAVE JSON -> LOAD SELECTED ROUND TRIP")
	_studio.call("_set_context", "vessel")
	# Author a plan the way a builder would: every collection the studio can make.
	_studio.call("_place_deck", Vector3(1, 0, 8), Vector3(9, 0, 24))
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	_studio.call("_place_stair", Vector3(3, 0, 14), Vector3(3, 0, 17))
	# Paint through the library so colour/material are non-default.
	var plan = _studio.get("_plan")
	_studio.set("_selected_id", int((plan.walls[0] as Dictionary)["id"]))
	_studio.call("_refresh_panel")
	_swatch_buttons()[6].pressed.emit()
	(_find(_drawer(), "Button", "STEEL") as Button).pressed.emit()
	# A kit piece.
	_studio.call("_set_tool", 5)
	var ids: Array = _studio.call("_kit_ids")
	_studio.call("_select_piece_type", str(ids[0]))
	_studio.call("_place_piece_at", Vector3i(8, 0, 20))
	# Fittings.
	_studio.call("_set_tool", 6)
	_studio.call("_set_build_level", 0.0)
	_studio.call("_probe_click_fitting", "helm_console", Vector3i(10, 0, 40))
	for i in 4:
		_studio.call("_probe_click_fitting", "bollard_pair", Vector3i(4 + i * 4, 0, 20))
	_studio.call("_probe_click_fitting", "lantern_sidelight_port", Vector3i(3, 0, 30))
	# A licence, chosen from the drawer's own dropdown.
	var reg: OptionButton = _studio.get("_registration_option")
	reg.selected = 1
	reg.item_selected.emit(1)
	_studio.call("_refresh_panel")

	var before: Dictionary = plan.to_dict()
	var before_reg := str(_studio.get("_registration_id"))
	var before_hull := str(_studio.get("_hull_id"))
	var before_level := float(_studio.get("_active_base"))
	print("  authored: %d walls %d decks %d stairs %d pieces %d items, hull=%s reg=%s" % [
		before["walls"].size(), before["decks"].size(), before["stairs"].size(),
		before["pieces"].size(), before["items"].size(), before_hull, before_reg
	])

	# Type a name and press SAVE JSON, exactly as a player would.
	var name_edit: LineEdit = _studio.get("_name_edit")
	name_edit.text = "audit round trip"
	var save_btn := _find(_drawer(), "Button", "SAVE JSON") as Button
	save_btn.pressed.emit()
	print("  SAVE JSON -> status: %s" % _studio.get("_status"))
	var wrote := str(_studio.call("_plan_save_path", "audit round trip"))
	print("  file exists: %s" % FileAccess.file_exists(wrote))

	# Wipe, then load it back through the drawer's own dropdown + button.
	_studio.call("_set_context", "vessel")
	print("  after wipe: entity_count=%d" % (_studio.get("_plan") as StructurePlan).entity_count())
	_studio.call("_refresh_panel")
	var load_opt: OptionButton = _studio.get("_load_option")
	var pick := -1
	for i in load_opt.item_count:
		if str(load_opt.get_item_metadata(i)) == wrote:
			pick = i
	print("  LOAD dropdown has %d entries; our file at index %d" % [load_opt.item_count, pick])
	load_opt.select(pick)
	var load_btn := _find(_drawer(), "Button", "LOAD SELECTED") as Button
	load_btn.pressed.emit()
	print("  LOAD SELECTED -> status: %s" % _studio.get("_status"))

	var after: Dictionary = (_studio.get("_plan") as StructurePlan).to_dict()
	var diffs := PackedStringArray()
	_diff("plan", before, after, diffs)
	if diffs.is_empty():
		print("  PLAN DOCUMENT: identical across the round trip")
	else:
		print("  PLAN DOCUMENT DIFFERS in %d places:" % diffs.size())
		for d in diffs:
			print("    %s" % d)
	print("  hull_id      %s -> %s" % [before_hull, _studio.get("_hull_id")])
	print("  registration %s -> %s" % [
		JSON.stringify(before_reg), JSON.stringify(str(_studio.get("_registration_id")))
	])
	print("  reg dropdown selected index %d (%s)" % [
		reg.selected, reg.get_item_text(reg.selected) if reg.selected >= 0 else "-"
	])
	print("  name field   %s -> %s" % [
		JSON.stringify("audit round trip"), JSON.stringify(name_edit.text)
	])
	print("  build level  %.2f -> %.2f" % [before_level, float(_studio.get("_active_base"))])
	print("  undo stack after load: %d" % (_studio.get("_undo_stack") as Array).size())
	# The checklist verdict, before vs after — the panel's own words.
	var verdict: Label = _studio.get("_registration_verdict")
	print("  verdict label after load: %s" % JSON.stringify(verdict.text))

	# What does pressing SAVE again do now — where would it write?
	print("\n  --- pressing SAVE JSON straight after a LOAD ---")
	print("  name field is now %s" % JSON.stringify(name_edit.text))
	save_btn.pressed.emit()
	print("  SAVE JSON -> status: %s" % _studio.get("_status"))

	# to_snake_case collision check, no writing.
	for candidate in ["Demo Workboat", "demo workboat", "DemoWorkboat", "demo-workboat"]:
		print("  name %-16s -> file %s.json" % [
			JSON.stringify(candidate), candidate.strip_edges().to_snake_case()
		])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wrote))


func _diff(path: String, a: Variant, b: Variant, out: PackedStringArray) -> void:
	if a is Dictionary and b is Dictionary:
		var keys := {}
		for k in (a as Dictionary).keys():
			keys[k] = true
		for k in (b as Dictionary).keys():
			keys[k] = true
		for k in keys.keys():
			if not (a as Dictionary).has(k):
				out.append("%s.%s: MISSING BEFORE, after=%s" % [path, k, (b as Dictionary)[k]])
			elif not (b as Dictionary).has(k):
				out.append("%s.%s: LOST, before=%s" % [path, k, (a as Dictionary)[k]])
			else:
				_diff("%s.%s" % [path, k], (a as Dictionary)[k], (b as Dictionary)[k], out)
	elif a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			out.append("%s: size %d -> %d" % [path, (a as Array).size(), (b as Array).size()])
			return
		for i in (a as Array).size():
			_diff("%s[%d]" % [path, i], (a as Array)[i], (b as Array)[i], out)
	else:
		if typeof(a) != typeof(b) or str(a) != str(b):
			out.append("%s: %s (%s) -> %s (%s)" % [
				path, a, type_string(typeof(a)), b, type_string(typeof(b))
			])


# ── 6. What a name collision costs
func _report_overwrite() -> void:
	print("\n=== 6. SAVE JSON NAME COLLISION")
	# Stand in a decoy fixture in the shipped structures directory, then save a
	# DIFFERENT plan under a name that snake-cases onto it.
	# Deliberately planted in the SHIPPED directory: the question is whether a
	# builder's save can reach it.
	var decoy := "%s/audit_decoy_fixture.json" % STRUCTURES_DIR
	var f := FileAccess.open(decoy, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"format": "structure_plan_v1", "context": "vessel", "hull_id": "hull_28x10",
		"walls": [], "decks": [], "stairs": [], "edges": [], "pieces": [], "items": [],
		"palette": {}, "hull": {}, "MARKER": "THE PLAN THAT WAS ALREADY THERE",
	}, "\t"))
	f.close()
	var before_bytes := FileAccess.get_file_as_string(decoy).length()
	print("  decoy on disk: %d bytes, marker present=%s" % [
		before_bytes, FileAccess.get_file_as_string(decoy).contains("MARKER")
	])
	_studio.call("_set_context", "vessel")
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	var name_edit: LineEdit = _studio.get("_name_edit")
	name_edit.text = "Audit Decoy Fixture"
	print("  a player types %s and presses SAVE JSON" % JSON.stringify(name_edit.text))
	(_find(_drawer(), "Button", "SAVE JSON") as Button).pressed.emit()
	print("  status: %s" % _studio.get("_status"))
	var after := FileAccess.get_file_as_string(decoy)
	print("  decoy on disk now: %d bytes, marker present=%s" % [
		after.length(), after.contains("MARKER")
	])
	print("  the SHIPPED fixtures the LOAD dropdown offers are in the same directory:")
	var load_opt: OptionButton = _studio.get("_load_option")
	_studio.call("_refresh_panel")
	var names := PackedStringArray()
	for i in mini(6, load_opt.item_count):
		names.append(load_opt.get_item_text(i))
	print("    %s ... (%d files)" % [", ".join(names), load_opt.item_count])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(decoy))

	print("\n=== 7. A FRESH STUDIO OPENS THE SAVED FILE")
	var second: Node = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(second)
	print("  a second studio's registration at boot: %s" % second.get("_registration_id"))
	print("  (a builder who picked another licence and saved gets this one back)")
