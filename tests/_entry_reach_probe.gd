extends Node

## Scratch probe (leading underscore — NOT a gate unit). Scene lane.
##
## QUESTION: starting from what the GAME actually runs, can a player reach any
## authoring surface? Traced FORWARDS, never backwards from an editor.
##
## Two independent halves, because either alone is a layer trap:
##
##   A. STATIC FORWARD CLOSURE. Seed = `application/run/main_scene` from
##      project.godot plus every autoload script (those are the only things the
##      engine starts on its own). Then follow every `res://…gd|tscn` reference
##      out of each reachable file — ext_resource paths in scenes, and EVERY
##      res:// literal in scripts INCLUDING ONES INSIDE COMMENTS. The comment
##      inclusion is deliberate over-approximation: if a scene is absent even
##      from a closure that counts prose, it is absent.
##
##   B. LIVE DRIVE. Instantiate the real entry scene, walk its Control tree,
##      and print every button a player can press, per page. Then instantiate
##      the three port NPCs the world spawns and print every dialogue option.
##      A grep cannot tell you a button exists; pressing one can.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_entry_reach_probe.tscn

const APP_SCENES := [
	"res://scenes/apps/structure_studio.tscn",
	"res://scenes/apps/shipyard_brick_editor.tscn",
	"res://scenes/apps/vessel_registration_audit.tscn",
]
const APP_SCRIPTS := [
	"res://scripts/apps/structure_studio.gd",
	"res://scripts/apps/shipyard_brick_editor.gd",
	"res://scripts/apps/building_brick_editor.gd",
	"res://scripts/apps/vessel_registration_audit.gd",
]

var _seen: Dictionary = {}
var _order: Array[String] = []
var _edges: Dictionary = {} ## path -> Array[String] of referrers
var _class_paths: Dictionary = {} ## global class_name -> res:// path
var _strip_comments := true


func _ready() -> void:
	print("=== A. STATIC FORWARD CLOSURE FROM WHAT THE ENGINE STARTS ===")
	print("--- A1: comments STRIPPED (a mention in prose is not a call) ---")
	_strip_comments = true
	_closure()
	var strict := _seen.duplicate()
	print("--- A2: comments INCLUDED (deliberate over-approximation) ---")
	_seen = {}
	_order = []
	_edges = {}
	_strip_comments = false
	_closure()
	print("--- A3: files the loose closure adds that the strict one does not ---")
	var added: Array[String] = []
	for p in _order:
		if p.ends_with("\t__expanded"):
			continue
		if not strict.has(p):
			added.append(p)
	print("[closure] loose-only files: %d" % added.size())
	for p in APP_SCENES + APP_SCRIPTS:
		if added.has(p):
			print("[closure] %s is reached ONLY through prose: %s" % [p, str(_edges.get(p, []))])
	print("=== B. LIVE DRIVE OF THE ENTRY SCENE ===")
	await _drive()
	get_tree().quit(0)


# ── A ─────────────────────────────────────────────────────────────────────────

func _closure() -> void:
	_load_class_index()
	var seeds: Array[String] = []
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	print("[seed] main_scene = %s" % main_scene)
	seeds.append(main_scene)
	for key in ProjectSettings.get_property_list():
		var name := str(key.get("name", ""))
		if not name.begins_with("autoload/"):
			continue
		var value := str(ProjectSettings.get_setting(name, "")).lstrip("*")
		if value.begins_with("res://"):
			print("[seed] autoload %s = %s" % [name.trim_prefix("autoload/"), value])
			seeds.append(value)
	for s in seeds:
		_visit(s, "<engine>")
	while true:
		var grew := false
		var snapshot := _order.duplicate()
		for path in snapshot:
			if _expand(path):
				grew = true
		if not grew:
			break

	var scenes := 0
	var scripts := 0
	for p in _order:
		if p.ends_with(".tscn"):
			scenes += 1
		elif p.ends_with(".gd"):
			scripts += 1
	print("[closure] %d files reachable (%d scenes, %d scripts)" % [_order.size(), scenes, scripts])

	## Sanity: the closure must contain things we KNOW the game runs, or the
	## walker is broken and every "unreachable" below would be an artefact.
	for must in [
		"res://scenes/world.tscn",
		"res://scripts/world/world.gd",
		"res://scripts/npc/shipwright_npc.gd",
		"res://scripts/ship/deck_fitout.gd",
		"res://scripts/construction/structure_baker.gd",
		"res://scripts/construction/piece_kit.gd",
	]:
		print("[closure] control: %-52s %s" % [must, "REACHED" if _seen.has(must) else "*** MISSING — WALKER IS BROKEN ***"])

	print("--- the authoring surfaces ---")
	for p in APP_SCENES + APP_SCRIPTS:
		var exists := ResourceLoader.exists(p) or FileAccess.file_exists(p)
		var verdict := "REACHABLE" if _seen.has(p) else "NOT REACHABLE"
		if not exists:
			verdict += " (no such file)"
		print("[reach] %-48s %s" % [p.trim_prefix("res://"), verdict])
		if _seen.has(p):
			print("        referred from: %s" % str(_edges.get(p, [])))

	## Also: does ANY reachable file mention an apps scene at all?
	var mentions: Array[String] = []
	for path in _order:
		if not path.ends_with(".gd") and not path.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		if text.contains("scenes/apps/"):
			mentions.append(path)
	print("[reach] reachable files that even MENTION scenes/apps/ : %d %s" % [mentions.size(), str(mentions)])


func _load_class_index() -> void:
	if not _class_paths.is_empty():
		return
	for entry in ProjectSettings.get_global_class_list():
		var name := str(entry.get("class", ""))
		var path := str(entry.get("path", ""))
		if not name.is_empty() and path.begins_with("res://"):
			_class_paths[name] = path
	print("[closure] global class_name index: %d classes" % _class_paths.size())


static func _without_comments(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var idx := line.find("#")
		## Skip a `#` that is inside a string literal (colour hex etc.).
		while idx >= 0:
			var head := line.substr(0, idx)
			if head.count("\"") % 2 == 0 and head.count("'") % 2 == 0:
				line = head
				break
			idx = line.find("#", idx + 1)
		out.append(line)
	return "\n".join(out)


func _visit(path: String, from: String) -> void:
	if path.is_empty() or not path.begins_with("res://"):
		return
	if not _seen.has(path):
		_seen[path] = true
		_order.append(path)
		_edges[path] = []
	var refs: Array = _edges[path]
	if not refs.has(from):
		refs.append(from)


func _expand(path: String) -> bool:
	if _seen.get(path + "\t__expanded", false):
		return false
	_seen[path + "\t__expanded"] = true
	if not FileAccess.file_exists(path):
		return true
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return true
	if _strip_comments and path.ends_with(".gd"):
		text = _without_comments(text)
	var before := _order.size()
	var re := RegEx.new()
	re.compile("res://[A-Za-z0-9_./\\-]+\\.(gd|tscn|gdshader)")
	for m in re.search_all(text):
		var found := m.get_string()
		if found.ends_with(".gdshader"):
			continue
		_visit(found, path)
	## GDScript global class names resolve with NO path reference at all —
	## `PortPlot.new()` is how `world.gd` reaches the shipwright. A walker that
	## only follows res:// literals misses the entire game.
	if path.ends_with(".gd") or path.ends_with(".tscn"):
		var ident := RegEx.new()
		ident.compile("[A-Za-z_][A-Za-z0-9_]*")
		var seen_here := {}
		for m in ident.search_all(text):
			var token := m.get_string()
			if seen_here.has(token) or not _class_paths.has(token):
				continue
			seen_here[token] = true
			_visit(str(_class_paths[token]), path)
	return _order.size() != before


# ── B ─────────────────────────────────────────────────────────────────────────

func _drive() -> void:
	var menu_scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	if menu_scene == null:
		print("[drive] COULD NOT LOAD main_menu.tscn — drive aborted")
		return
	var menu := menu_scene.instantiate()
	add_child(menu)
	for i in 8:
		await get_tree().process_frame
	print("[drive] entry scene instantiated: %s" % menu.get_class())
	_print_buttons(menu, "MODE_SELECT (what the player sees first)")

	## Press "Singleplayer" the way a player would.
	var sp := _find_button(menu, "Singleplayer")
	if sp == null:
		print("[drive] no 'Singleplayer' button found — cannot go deeper")
	else:
		sp.emit_signal("pressed")
		for i in 6:
			await get_tree().process_frame
		_print_buttons(menu, "after pressing Singleplayer")

	## The only "make something of your own" flow a player can actually reach.
	var newcap := _find_button(menu, "New captain")
	if newcap != null:
		newcap.emit_signal("pressed")
		for i in 10:
			await get_tree().process_frame
		_print_buttons(menu, "after pressing New captain (character creator)")
		var confirm := _find_button(menu, "BUILD COMPANY  →")
		if confirm != null:
			confirm.emit_signal("pressed")
			for i in 10:
				await get_tree().process_frame
			_print_buttons(menu, "after Continue (company setup)")

	var mp := _find_button(menu, "Multiplayer")
	if mp != null:
		mp.emit_signal("pressed")
		for i in 6:
			await get_tree().process_frame
		_print_buttons(menu, "after pressing Multiplayer")

	menu.queue_free()
	await get_tree().process_frame

	## The pause menu the player gets in-world (autoload GameMenu builds it).
	var gm := get_node_or_null("/root/GameMenu")
	if gm != null:
		_print_buttons(gm, "in-world pause menu (GameMenu autoload)")
	else:
		print("[drive] GameMenu autoload absent")

	## The three port NPCs `PortPlot` spawns — the only interactables a player
	## meets ashore. Drive each one's top-level dialogue.
	await _drive_npc("ShipwrightNpc")
	await _drive_npc("HarbourMasterNpc")
	await _drive_npc("CargoAgentNpc")


func _drive_npc(class_id: String) -> void:
	var npc: Node = null
	match class_id:
		"ShipwrightNpc": npc = ShipwrightNpc.new()
		"HarbourMasterNpc": npc = HarbourMasterNpc.new()
		"CargoAgentNpc": npc = CargoAgentNpc.new()
	if npc == null:
		print("[drive] %s could not be constructed" % class_id)
		return
	add_child(npc)
	for i in 6:
		await get_tree().process_frame
	if npc.has_method("_on_interact"):
		npc.call("_on_interact")
		for i in 6:
			await get_tree().process_frame
	_print_buttons(npc, "%s — options after pressing F" % class_id)
	npc.queue_free()
	await get_tree().process_frame


func _print_buttons(root: Node, label: String) -> void:
	var found: Array[String] = []
	_collect_buttons(root, found)
	print("[drive] %s: %d pressable" % [label, found.size()])
	for f in found:
		print("          · %s" % f)
	var suspect: Array[String] = []
	for f in found:
		var low := f.to_lower()
		for word in ["build", "studio", "editor", "refit", "custom", "design", "yard", "construct", "author"]:
			if low.contains(word) and not suspect.has(f):
				suspect.append(f)
	print("[drive] %s: builder-ish labels = %d %s" % [label, suspect.size(), str(suspect)])


func _collect_buttons(node: Node, out: Array[String]) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		if b.is_visible_in_tree():
			var text := ""
			if b is Button:
				text = (b as Button).text
			if text.strip_edges().is_empty():
				text = "<%s %s>" % [b.get_class(), b.name]
			out.append(text.strip_edges().replace("\n", " "))
	for c in node.get_children():
		_collect_buttons(c, out)


func _find_button(node: Node, text: String) -> BaseButton:
	if node is Button and (node as Button).text.strip_edges() == text:
		return node as BaseButton
	for c in node.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null
