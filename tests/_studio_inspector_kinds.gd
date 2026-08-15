extends Node3D

## SCRATCH PROBE. What does the properties drawer say about each kind of thing a
## player can select? The kind ladder in `_refresh_inspector` tests `piece`,
## `axis`, `dir` and falls through to "deck" — and a FITTING has none of those.

var _studio: Node


func _ready() -> void:
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	await get_tree().process_frame
	await get_tree().process_frame

	_studio.call("_set_context", "vessel")
	_studio.call("_place_deck", Vector3(1, 0, 8), Vector3(9, 0, 24))
	_studio.call("_place_wall", Vector3(2, 0, 10), Vector3(8, 0, 10))
	_studio.call("_place_stair", Vector3(3, 0, 14), Vector3(3, 0, 17))
	_studio.call("_set_tool", 5)
	var ids: Array = _studio.call("_kit_ids")
	_studio.call("_select_piece_type", str(ids[0]))
	_studio.call("_place_piece_at", Vector3i(8, 0, 20))
	_studio.call("_set_tool", 6)
	_studio.call("_set_build_level", 0.0)
	_studio.call("_probe_click_fitting", "helm_console", Vector3i(10, 0, 40))
	_studio.call("_probe_click_fitting", "lantern_sidelight_port", Vector3i(3, 0, 30))

	var plan: StructurePlan = _studio.get("_plan")
	var cases := [
		["wall", plan.walls[0]], ["deck", plan.decks[0]], ["stair", plan.stairs[0]],
		["piece", plan.pieces[0]], ["fitting (helm)", plan.items[0]],
		["fitting (port light)", plan.items[1]],
	]
	for c in cases:
		var e := c[1] as Dictionary
		_studio.set("_selected_id", int(e["id"]))
		_studio.call("_update_selection_visual")
		_studio.call("_refresh_panel")
		var box: Node = _studio.get("_inspector_box")
		var info: Label = _studio.get("_drawer_info")
		print("\n--- selected %s  (id %d, keys %s)" % [c[0], int(e["id"]), e.keys()])
		print("    blurb: %s" % JSON.stringify(info.text))
		_dump(box, 4)

	# Drive the field the fitting was offered and see where the value lands.
	var light := plan.items[1] as Dictionary
	_studio.set("_selected_id", int(light["id"]))
	_studio.call("_refresh_panel")
	print("\n--- driving the fitting's own SpinBox")
	print("    item before: %s" % JSON.stringify(light))
	var spins: Array = []
	_collect(_studio.get("_inspector_box"), "SpinBox", spins)
	for s in spins:
		(s as SpinBox).value_changed.emit(0.25)
	print("    item after : %s" % JSON.stringify(light))
	print("    normalised : %s" % JSON.stringify(StructurePlan.normalize_item(light.duplicate(true))))
	# and what a save/load makes of it
	var round_tripped := StructurePlan.from_dict(
		JSON.parse_string(JSON.stringify(plan.to_dict())) as Dictionary
	)
	for it in round_tripped.items:
		if int((it as Dictionary)["id"]) == int(light["id"]):
			print("    after a save/load: %s" % JSON.stringify(it))

	# Does an EDGE fall through the same way? Load a fixture that has one.
	_studio.call("_load_plan", "res://resources/data/structures/probe_sheer_bulwark.json")
	var p2: StructurePlan = _studio.get("_plan")
	if not p2.edges.is_empty():
		var edge := p2.edges[0] as Dictionary
		_studio.set("_selected_id", int(edge["id"]))
		_studio.call("_refresh_panel")
		print("\n--- selected edge (keys %s)" % [edge.keys()])
		_dump(_studio.get("_inspector_box"), 4)

	print("\nKINDS DONE")
	get_tree().quit(0)


func _collect(node: Node, cls: String, out: Array) -> void:
	for c in node.get_children():
		if c.get_class() == cls:
			out.append(c)
		_collect(c, cls, out)


func _dump(node: Node, indent: int) -> void:
	for c in node.get_children():
		if c is Control:
			var t := ""
			if c is Label:
				t = (c as Label).text
			elif c is Button:
				t = (c as Button).text
			elif c is SpinBox:
				var sb := c as SpinBox
				t = "value=%.3f min=%.2f max=%.2f step=%.2f" % [
					sb.value, sb.min_value, sb.max_value, sb.step
				]
			print("%s%s: %s" % [" ".repeat(indent), c.get_class(), t])
		_dump(c, indent + 2)
