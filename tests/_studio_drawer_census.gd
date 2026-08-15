extends Node3D

## SCRATCH PROBE (leading underscore — the gate skips it).
##
## The properties drawer and the context strip went on screen for the first time
## in 2ab3eee, and nobody has ever looked INSIDE them. This walks every Control
## under PropertiesDrawer and ContextStrip and prints, for each one: its class,
## its global rect, whether the rect is inside the viewport, whether the rect is
## inside its own panel, and what text it carries. Text that does not fit its box
## is flagged — a label whose ideal width exceeds the width it was given is a
## clipped label, and a control that is "on screen" with clipped text is still
## not delivered (REALITY §1).

const STRUCTURES_DIR := "res://resources/data/structures"

var _studio: Node


func _ready() -> void:
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	await get_tree().process_frame
	await get_tree().process_frame

	# Author something so every section has content: a deck, some fittings, and
	# a selection so the inspector builds.
	_studio.call("_set_context", "vessel")
	_studio.call("_place_deck", Vector3(1, 0, 8), Vector3(9, 0, 24))
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	_studio.call("_place_stair", Vector3(3, 0, 14), Vector3(3, 0, 17))
	_studio.call("_set_tool", 6) # Tool.FITTING
	_studio.call("_set_build_level", 0.0)
	_studio.call("_probe_click_fitting", "helm_console", Vector3i(10, 0, 40))
	for i in 4:
		_studio.call("_probe_click_fitting", "bollard_pair", Vector3i(4 + i * 4, 0, 20))
	var plan = _studio.get("_plan")
	_studio.set("_selected_id", int((plan.walls[0] as Dictionary)["id"]))
	_studio.call("_update_selection_visual")
	_studio.call("_refresh_panel")
	await get_tree().process_frame
	await get_tree().process_frame

	var vp := get_viewport().get_visible_rect()
	print("VIEWPORT %s" % vp)
	var ui: Node = _studio.get("_ui_root")
	for panel_name in ["PropertiesDrawer", "ContextStrip", "ToolPalette", "TopBar"]:
		var panel := ui.get_node_or_null(NodePath(panel_name)) as Control
		if panel == null:
			print("### %s MISSING" % panel_name)
			continue
		print("\n### %s  rect=%s  vis=%s" % [
			panel_name, panel.get_global_rect(), panel.is_visible_in_tree()
		])
		_walk(panel, 0, panel.get_global_rect(), vp)
	print("\nCENSUS DONE")
	get_tree().quit(0)


func _walk(node: Node, depth: int, panel_rect: Rect2, vp: Rect2) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			var r := c.get_global_rect()
			var text := ""
			if c is Label:
				text = (c as Label).text
			elif c is Button:
				text = (c as Button).text
			elif c is LineEdit:
				text = "<edit:%s|%s>" % [(c as LineEdit).text, (c as LineEdit).placeholder_text]
			elif c is OptionButton:
				var ob := c as OptionButton
				text = "<option %d items sel=%d: %s>" % [
					ob.item_count, ob.selected,
					ob.get_item_text(ob.selected) if ob.selected >= 0 else "-"
				]
			var flags := PackedStringArray()
			if not c.is_visible_in_tree():
				flags.append("HIDDEN")
			if not vp.grow(1.0).encloses(r) and c.is_visible_in_tree() and r.size.x > 0:
				flags.append("OFF-VIEWPORT")
			if not panel_rect.grow(1.0).encloses(r) and c.is_visible_in_tree() and r.size.x > 0:
				flags.append("OUT-OF-PANEL")
			# Text that does not fit the box it was given.
			if c is Label:
				var lab := c as Label
				if lab.is_visible_in_tree() and not lab.text.is_empty():
					var ideal := lab.get_theme_font(&"font").get_string_size(
						lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
						lab.get_theme_font_size(&"font_size")
					)
					if lab.autowrap_mode == TextServer.AUTOWRAP_OFF and ideal.x > r.size.x + 1.0:
						flags.append("CLIPPED(needs %.0f has %.0f)" % [ideal.x, r.size.x])
			if c is Button and c.is_visible_in_tree() and not (c as Button).text.is_empty():
				var b := c as Button
				var bi := b.get_theme_font(&"font").get_string_size(
					b.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, b.get_theme_font_size(&"font_size")
				)
				if bi.x > r.size.x + 1.0:
					flags.append("CLIPPED(needs %.0f has %.0f)" % [bi.x, r.size.x])
			print("%s%s [%s] %s %s %s" % [
				"  ".repeat(depth), c.name, c.get_class(), r,
				("!" + ",".join(flags)) if flags.size() > 0 else "",
				("| " + text.replace("\n", " / ")) if not text.is_empty() else ""
			])
		_walk(child, depth + 1, panel_rect, vp)
