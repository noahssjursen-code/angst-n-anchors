extends Node

## SCRATCH PROBE — leading underscore, not a gate unit. LANE B (it boots the real
## `World`, which names autoloads bare all over).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_world_boot_region_probe.tscn
##
## ── THE ONE QUESTION ────────────────────────────────────────────────────────
##
## `chart_live_harbour_test` proves that a `PortCatalog` record carrying the placed
## region word draws the right harbour, and that a record carrying `"coastal"` does
## not. It cannot prove that **`world.gd:_setup_ports`' own line passes the word**,
## because it REPLICATES that argument list rather than calling it — REALITY §3's
## layer trap, stated in that unit's header and open.
##
## This probe closes it the only way that is not a source scan (which would be
## `ship_hud_readout_test`'s vanishing check: an ordinary refactor deletes the
## check and nothing counts the absence). It boots the actual `World` node, lets
## `_rebuild()` run the actual `_setup_ports`, and reads `PortCatalog` back:
##
##   Q  For every port the real world registered, is the record's `region` the word
##      the real placer assigned to that site — and is it never `"coastal"`?
##
## It is a probe and not a gate unit on purpose: booting a world takes tens of
## seconds, spawns a player, streams terrain and is not something to put in front of
## every future wave. Re-run it by hand whenever `world.gd`'s `register_port`
## argument list is edited.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const WORLD_CONFIG := preload("res://scripts/world/world_config.gd")

const SEED := 90210
const PORT_COUNT := 20
## Generous: a real boot generates a layout, traces every coast and spawns a player.
const BOOT_TIMEOUT_S := 240.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		print("NO PortCatalog AUTOLOAD — probe cannot run")
		get_tree().quit(1)
		return

	## What the placer assigns, computed independently of the world so the
	## comparison is against the real source of the word and not against the world's
	## own opinion of it.
	var layout: WorldLayout = GENERATOR.generate(SEED, WORLD_CONFIG.ARCHETYPE_PATH, 40000.0)
	var defs: Array = PLACER.place_ports(
		layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
	var placed: Dictionary = {}
	for raw in defs:
		var d := raw as PortDefinition
		placed[d.port_id] = _region_word(int(d.region_kind))
	print("placer assigned: %d ports, words %s" % [placed.size(), str(_tally(placed))])

	catalog.call("clear")

	## `World._ready` OVERWRITES `world_seed`, `world_size_m` and the generation
	## versions from `GameSettings` before it rebuilds, so setting them on the node is
	## not enough — the first version of this probe did exactly that, booted at
	## GameSettings' default seed 42 and reported 6 of 20 records "disagreeing with
	## the placer". They disagreed because they were a different world. The control
	## has to be set where the world reads it.
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		print("NO GameSettings AUTOLOAD — cannot pin the world's seed, probe INCONCLUSIVE")
		get_tree().quit(2)
		return
	settings.set("map_generation_seed", SEED)
	settings.set("map_generation_version", int(GENERATOR.GENERATION_VERSION))
	settings.set("map_layout_checksum", "")
	settings.set("map_world_size_m", 40000.0)

	var world := World.new()
	world.name = "World"
	world.world_seed = SEED
	world.port_count = PORT_COUNT
	world.world_size_m = 40000.0
	get_tree().root.add_child(world)

	var waited := 0.0
	while waited < BOOT_TIMEOUT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if (catalog.call("get_port_ids") as Array).size() >= PORT_COUNT:
			break
	var ids: Array = catalog.call("get_port_ids")
	print("after %.1f s of real boot, PortCatalog holds %d ports" % [waited, ids.size()])
	if ids.size() < PORT_COUNT:
		print("WORLD DID NOT REGISTER ITS PORTS — probe INCONCLUSIVE, not a pass")
		get_tree().quit(2)
		return

	var wrong: Array[String] = []
	var coastal: Array[String] = []
	var seen: Dictionary = {}
	for id_raw in ids:
		var pid := str(id_raw)
		var info: Dictionary = catalog.call("get_port_info", pid)
		var got := str(info.get("region", ""))
		seen[pid] = got
		if got == "coastal":
			coastal.append(pid)
		if not placed.has(pid):
			wrong.append("%s:UNPLACED" % pid)
		elif got != str(placed[pid]):
			wrong.append("%s:%s!=%s" % [pid, got, str(placed[pid])])

	print("")
	print("=== _world_boot_region_probe ===")
	print("region words on the records the REAL world wrote: %s" % str(_tally(seen)))
	print("records whose region is \"coastal\": %d %s" % [coastal.size(), str(coastal)])
	print("records disagreeing with the placer: %d %s" % [wrong.size(), str(wrong)])
	## `port_plot.gd` also registers, for the HomePort it stamps, and it has always
	## passed the region word — so a green here with the home port excluded would
	## prove nothing. It is included above deliberately.
	if wrong.is_empty() and coastal.is_empty():
		print("VERDICT: world.gd:_setup_ports PASSES THE PLACED REGION WORD at %d of %d ports"
			% [ids.size(), PORT_COUNT])
		get_tree().quit(0)
	else:
		print("VERDICT: world.gd:_setup_ports DOES NOT pass the placed region word")
		get_tree().quit(1)


func _tally(words: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in words:
		var w := str(words[key])
		out[w] = int(out.get(w, 0)) + 1
	return out


func _region_word(region_kind: int) -> String:
	match region_kind:
		int(PortDefinition.RegionKind.MAINLAND):
			return "mainland"
		int(PortDefinition.RegionKind.FJORD):
			return "fjord"
		int(PortDefinition.RegionKind.ARCHIPELAGO):
			return "archipelago"
	return "coastal"
