extends Node

## Scratch probe (leading underscore — not a gate unit). LANE B — boot as a scene:
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_home_port_confirm_probe.tscn
##
## ONE QUESTION, AND IT OUTRANKS THE FIX: CAN A PLAYER STILL FOUND A FISHING
## COMPANY? `CompanyContracts.DEFAULT_STARTER` is "fishing", `MainMenu` maps that
## to the required berth family, and `MapOverlay._home_port_supports_required_family`
## disables the home-port CONFIRM button at every port without a fish landing. If
## making the panel honest leaves a fishing captain with nowhere to start, that is a
## finding for the owner and not a fix to ship.
##
## Driven through the production surfaces end to end — `ChartDataSnapshot.for_preview`
## → `MapOverlay.set_home_port_required_family` → `enter_home_port_pick_mode` → the
## real `pick_confirm.disabled` — so this measures the BUTTON, not a flag.
##
## Then it answers the question the previous wave recorded as not verified: what a
## captain who confirms one of these harbours actually finds there. Two ports the
## button ALLOWS and two it REFUSES are stamped through `PortPlot` and their subtrees
## walked for a node named like a fish landing that draws geometry.

const PORT_COUNT := 35
const SEEDS := [424242, 20260817]
const SETTLE_FRAMES := 8

var _world: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	for world_seed in SEEDS:
		await _one_seed(int(world_seed))
	get_tree().quit(0)


func _one_seed(world_seed: int) -> void:
	print("")
	print("════ seed %d ════" % world_seed)
	var snap := ChartDataSnapshot.for_preview(world_seed, PORT_COUNT)
	var overlay := MapOverlay.new()
	add_child(overlay)
	await get_tree().process_frame
	## Without this the overlay falls back to the LIVE TREE — and once this probe
	## has stamped a PortPlot the live `PortCatalog` answers with
	## `expand_uncached`'s feature list, which carries `Terrain-traced Port Layout`.
	## Measured: the first draft omitted it and read a panel fed by the wrong
	## producer entirely (REALITY §8 — check the camera before the subject).
	overlay.set_data_snapshot(snap)
	overlay.set_home_port_required_family("fishing")

	var allowed: Array[String] = []
	var refused: Array[String] = []
	for id_raw in snap.port_ids():
		var pid := str(id_raw)
		overlay.enter_home_port_pick_mode(pid)
		if overlay.pick_confirm != null and not overlay.pick_confirm.disabled:
			allowed.append(pid)
		else:
			refused.append(pid)
	print("CONFIRM enabled for a FISHING captain at %d of %d ports" % [
		allowed.size(), snap.ports.size()])
	print("   allowed: %s" % str(allowed))
	print("   refused: %d ports" % refused.size())
	var facilities_of := func(pid: String) -> String:
		overlay.enter_home_port_pick_mode(pid)
		for line in overlay.pick_body.text.split("\n"):
			if str(line).begins_with("FACILITIES  "):
				return str(line)
		return "(no FACILITIES line)"
	for pid in [allowed[0] if not allowed.is_empty() else "", refused[0] if not refused.is_empty() else ""]:
		if not str(pid).is_empty():
			print("   %-10s panel prints: %s" % [pid, facilities_of.call(str(pid))])
	overlay.queue_free()
	await get_tree().process_frame

	## And what is actually there. Two allowed, two refused.
	var probes: Array[String] = []
	for pid in allowed.slice(0, mini(2, allowed.size())):
		probes.append(str(pid))
	for pid in refused.slice(0, mini(2, refused.size())):
		probes.append(str(pid))
	for pid in probes:
		var info := snap.port_info(pid)
		var definition := PortDefinition.from_dict(info.get("port_definition", {}) as Dictionary)
		PortDataCache.clear()
		var data := PortExpander.expand(definition, world_seed, snap.layout)
		var plot := PortPlot.new()
		_world.add_child(plot)
		plot.configure(data)
		for _f in range(SETTLE_FRAMES):
			await get_tree().process_frame
		var names: Array[String] = []
		_collect_drawing_names(plot, names)
		var found: Array[String] = []
		for n in names:
			if _norm(n).contains(_norm("Fish Landing")) or _norm(n).contains("fishlanding"):
				found.append(n)
		print("   STAMP %-10s size %d · confirm %s · %d drawing nodes · fish-landing geometry: %s" % [
			pid, int(data.size),
			"ALLOWED" if allowed.has(pid) else "refused",
			names.size(),
			str(found) if not found.is_empty() else "NONE",
		])
		## THE NPC PATH. `harbour_master_npc.gd:110` gates "Land and sell my catch"
		## on `_port_data().has_fish_landing`, and `_port_data()` is
		## `PortPlot.port_data()` — the CORRECTED producer. Read off the live NPC in
		## the stamped tree rather than off the source, because the whole defect was
		## a producer nobody checked which path it came from.
		var master := _find_harbour_master(plot)
		if master == null:
			print("      NPC: no harbour master in this stamp")
		else:
			var npc_data := master.call("_port_data") as PortData
			print("      NPC %s reads has_fish_landing=%s (same PortData object as the plot: %s)" % [
				master.get_class(),
				str(npc_data != null and npc_data.has_fish_landing),
				"yes" if npc_data == data else "NO",
			])
		var quotes := _fish_dialogue_lines(plot)
		if not quotes.is_empty():
			print("      NPC dialogue mentioning fish, present in the tree: %s" % str(quotes))
		plot.queue_free()
		await get_tree().process_frame


func _find_harbour_master(node: Node) -> Node:
	if node is HarbourMasterNpc:
		return node
	for child in node.get_children():
		var found := _find_harbour_master(child)
		if found != null:
			return found
	return null


## Any Label/RichTextLabel text already realized in the stamped tree that names
## fish. A promise a player can READ, as opposed to one in a source string.
func _fish_dialogue_lines(node: Node) -> Array[String]:
	var out: Array[String] = []
	_walk_text(node, out)
	return out


func _walk_text(node: Node, out: Array[String]) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is RichTextLabel:
		text = (node as RichTextLabel).text
	elif node is Label3D:
		text = (node as Label3D).text
	elif node is Button:
		text = (node as Button).text
	var low := text.to_lower()
	if low.contains("fish") or low.contains("catch"):
		out.append("%s: %s" % [node.name, text.substr(0, 70)])
	for child in node.get_children():
		_walk_text(child, out)


func _collect_drawing_names(node: Node, out: Array[String]) -> bool:
	var draws := node is MeshInstance3D
	for child in node.get_children():
		if _collect_drawing_names(child, out):
			draws = true
	if draws and node is Node3D:
		out.append(str(node.name))
	return draws


static func _norm(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out
