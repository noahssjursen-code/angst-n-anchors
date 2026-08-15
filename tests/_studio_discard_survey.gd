extends Node3D

## SCRATCH PROBE (leading underscore — the gate skips it).
##
## HOW MANY OF THE STUDIO'S CONTROLS DESTROY THE PLAN, AND WHICH OF THOSE ALSO
## DESTROY THE UNDO STACK?
##
## Not read off the source: every Button in the UI tree is PRESSED and every
## OptionButton entry is CHOSEN through `PopupMenu.index_pressed`, which is the
## engine's own wiring from a player's click on a popup row
## (`OptionButton::_selected`) — so a dropdown that only emits on a CHANGE, and
## one that emits on every pick, are told apart by measurement rather than by
## reading the engine's source.
##
## Before each control the studio is put in a KNOWN state: 3 entities and a
## 4-deep undo stack. After, entity_count and undo depth are read back.

var _studio: Node
var _ui: Control


func _ready() -> void:
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	for _i in 4:
		await get_tree().process_frame
	_ui = _studio.get("_ui_root") as Control

	print("=== EVERY CONTROL IN THE STUDIO, PRESSED")
	print("%-8s %-26s %-34s %s" % ["kind", "panel", "control", "plan -> undo"])
	## COLLECTED WITH EVERY TOOL ARMED IN TURN. The piece palette, the fitting
	## catalogue and the opening row are only in the tree while their own tool is
	## up, so a sweep taken at the boot tool misses ~60 controls and would have
	## reported a smaller, flattering total.
	var rows: Array = []
	var seen: Dictionary = {}
	for tool in range(7):
		_studio.call("_set_tool", tool)
		_studio.call("_refresh_panel")
		await get_tree().process_frame
		var found: Array = []
		_collect(_ui, "", found)
		for row in found:
			var key := "%d/%s" % [(row["node"] as Node).get_instance_id(), row.get("index", -1)]
			if seen.has(key):
				continue
			seen[key] = true
			rows.append(row)
	_studio.call("_set_tool", 0)
	var buttons := 0
	for row in rows:
		if str(row["kind"]) == "button":
			buttons += 1
	print("collected %d click targets: %d buttons + %d dropdown rows\n"
		% [rows.size(), buttons, rows.size() - buttons])

	var wipes: Array = []
	var clears: Array = []
	for row in rows:
		var panel := str(row["panel"])
		var label := str(row["label"])
		var kind := str(row["kind"])
		_arm()
		var before_n: int = (_studio.get("_plan") as StructurePlan).entity_count()
		var before_u: int = (_studio.get("_undo_stack") as Array).size()
		if kind == "button":
			(row["node"] as Button).pressed.emit()
		else:
			var option := row["node"] as OptionButton
			(option.get_popup() as PopupMenu).index_pressed.emit(int(row["index"]))
		await get_tree().process_frame
		var after_n: int = (_studio.get("_plan") as StructurePlan).entity_count()
		var after_u: int = (_studio.get("_undo_stack") as Array).size()
		var flag := ""
		if after_n == 0 and before_n > 0:
			flag += "  <<< WIPES THE PLAN"
			wipes.append("%s / %s" % [panel, label])
		if after_u == 0 and before_u > 0:
			flag += "  <<< CLEARS UNDO"
			clears.append("%s / %s" % [panel, label])
		if flag != "" or after_n != before_n or after_u != before_u:
			print("%-8s %-26s %-34s %d -> %d  undo %d -> %d%s" % [
				kind, panel, label, before_n, after_n, before_u, after_u, flag
			])

	print("\n=== TALLY")
	print("  controls that empty the plan: %d" % wipes.size())
	for w in wipes:
		print("    %s" % w)
	print("  controls that clear the undo stack: %d" % clears.size())
	for c in clears:
		print("    %s" % c)

	await _re_click_case()
	await _undo_after_hull_change()
	print("\nSURVEY DONE")
	get_tree().quit(0)


## 3 entities, 4 undo steps, vessel context, hull as booted.
func _arm() -> void:
	_studio.call("_set_context", "vessel")
	_studio.call("_set_tool", 0)
	_studio.call("_set_build_level", 0.0)
	_studio.call("_place_deck", Vector3(1, 0, 8), Vector3(9, 0, 24))
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	_studio.call("_place_wall", Vector3(2, 0, 14), Vector3(8, 0, 14))
	_studio.call("_snapshot")


func _collect(node: Node, panel: String, out: Array) -> void:
	for child in node.get_children():
		var next := panel
		if child is Control and panel.is_empty() and not str(child.name).begins_with("@"):
			next = str(child.name)
		if child is OptionButton:
			var option := child as OptionButton
			for index in option.item_count:
				out.append({
					"kind": "option", "panel": next, "node": option, "index": index,
					"label": "%s[%d] %s" % [option.name, index, option.get_item_text(index)],
				})
		elif child is Button:
			var button := child as Button
			var text := button.text
			if text.is_empty():
				text = "<swatch %s>" % button.name
			out.append({"kind": "button", "panel": next, "node": button, "label": text})
		_collect(child, next, out)


## THE RE-CLICK: does pressing the context you are ALREADY in destroy anything?
func _re_click_case() -> void:
	print("\n=== RE-CLICKING THE CONTEXT YOU ARE ALREADY IN")
	_arm()
	var ctx := str(_studio.get("_context"))
	var btns: Dictionary = _studio.get("_context_buttons")
	print("  context is %s, plan has %d entities, undo %d deep" % [
		ctx, (_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_undo_stack") as Array).size()
	])
	(btns[ctx] as Button).pressed.emit()
	await get_tree().process_frame
	print("  pressed %s (the one already active) -> plan %d entities, undo %d deep" % [
		ctx.to_upper(), (_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_undo_stack") as Array).size()
	])

	print("\n=== RE-PICKING THE HULL YOU ARE ALREADY ON")
	_arm()
	var hull_option := _studio.get("_hull_option") as OptionButton
	var current := hull_option.selected
	print("  hull is %s (index %d), plan has %d entities, undo %d deep" % [
		_studio.get("_hull_id"), current,
		(_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_undo_stack") as Array).size()
	])
	(hull_option.get_popup() as PopupMenu).index_pressed.emit(current)
	await get_tree().process_frame
	print("  chose the same row -> plan %d entities, undo %d deep" % [
		(_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_undo_stack") as Array).size()
	])


## Does UNDO after a hull change put the plan back on the hull it was drawn for?
func _undo_after_hull_change() -> void:
	print("\n=== UNDO AFTER A LOAD THAT CHANGES THE HULL")
	_studio.call("_set_context", "vessel")
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	var hull_before := str(_studio.get("_hull_id"))
	var grid_before: DeckGrid = _studio.get("_deck_grid")
	print("  before: hull=%s grid=%dx%d plan=%d entities undo=%d" % [
		hull_before, grid_before.width, grid_before.length,
		(_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_undo_stack") as Array).size()
	])
	_studio.call("_load_plan", "res://resources/data/structures/probe_container_feeder.json")
	var grid_mid: DeckGrid = _studio.get("_deck_grid")
	print("  after LOAD: hull=%s grid=%dx%d plan=%d entities undo=%d" % [
		_studio.get("_hull_id"), grid_mid.width, grid_mid.length,
		(_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_undo_stack") as Array).size()
	])
	_studio.call("_undo")
	var grid_after: DeckGrid = _studio.get("_deck_grid")
	print("  after UNDO: hull=%s grid=%dx%d plan=%d entities plan.hull_id=%s" % [
		_studio.get("_hull_id"), grid_after.width, grid_after.length,
		(_studio.get("_plan") as StructurePlan).entity_count(),
		(_studio.get("_plan") as StructurePlan).hull_id
	])
	print("  off-hull entities reported: %d" % (_studio.get("_off_hull") as Array).size())
