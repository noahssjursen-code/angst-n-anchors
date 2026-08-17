extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## ONE QUESTION, AND IT IS AN INSTRUMENT QUESTION (REALITY §8).
##
## `port_feature_promise_test` names 424242 / `port-home` as the fish-landing
## DIVERGENCE WITNESS. `_fish_landing_realization_probe` measures that same port
## as advertised AND realized, and names 20260817 / `port-home` as the divergent
## one instead. Both cannot be right, and the consequence measurement this wave
## reports depends on which.
##
## The two differ in exactly two ways, so both are tried here:
##   a) WHERE THE DEFINITION COMES FROM — the placer's object, versus the
##      `port_definition` record `chart_summary` writes into the snapshot and the
##      test round-trips through `PortDefinition.from_dict`.
##   b) ORDER — the test builds BOTH preview snapshots first and expands
##      afterwards; the probe generates one seed and expands it immediately.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35


func _initialize() -> void:
	print("── (a) definition source, one seed at a time ──")
	for world_seed in [424242, 20260817]:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		print("   seed %d · port order[0..3] = %s" % [
			int(world_seed),
			str([ports[0].port_id, ports[1].port_id, ports[2].port_id, ports[3].port_id]),
		])
		for pid in ["port-home", "port-1"]:
			var def := _find(ports, pid)
			if def == null:
				continue
			var summary := PortExpander.chart_summary(
				PortDefinition.from_dict(def.to_dict()), int(world_seed))
			var record := summary.get("port_definition", {}) as Dictionary
			print("      %-10s size=%d  to_dict round trip identical: %s" % [
				pid, int(summary.get("size", -1)),
				"yes" if record == def.to_dict() else "NO",
			])
			print("         realized from PLACER definition:   %s" % _realized(def, world_seed, layout))
			print("         realized from SNAPSHOT definition: %s" % _realized(
				PortDefinition.from_dict(record), world_seed, layout))

	print("")
	print("── (b) the test's ORDER: both snapshots built first, expanded after ──")
	var snaps: Array = []
	for world_seed in [424242, 20260817]:
		snaps.append([world_seed, ChartDataSnapshot.for_preview(int(world_seed), PORT_COUNT)])
	for raw in snaps:
		var pair: Array = raw
		var world_seed: int = int(pair[0])
		var snap: ChartDataSnapshot = pair[1]
		var ids := snap.port_ids()
		print("   seed %d · snapshot port order[0..3] = %s" % [
			world_seed, str([ids[0], ids[1], ids[2], ids[3]]),
		])
		for pid in ["port-home", "port-1"]:
			var info := snap.port_info(pid)
			if info.is_empty():
				continue
			var def := PortDefinition.from_dict(info.get("port_definition", {}) as Dictionary)
			print("      %-10s advertised=%s  realized=%s" % [
				pid,
				str(bool(info.get("has_fish_landing", false))),
				_realized(def, world_seed, snap.layout),
			])
	quit(0)


func _realized(definition: PortDefinition, world_seed: int, layout: WorldLayout) -> String:
	PortDataCache.clear()
	var data := PortExpander.expand_uncached(
		PortDefinition.from_dict(definition.to_dict()), int(world_seed), layout)
	var quays: Array = (data.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary) \
		.get("quay_stations", []) as Array
	var families: Array[String] = []
	for st in quays:
		families.append(str((st as Dictionary).get("family", "")))
	return "%s (size %d, quay families %s, imports %s)" % [
		str(data.has_fish_landing), int(data.size), str(families), str(data.commodity_imports),
	]


func _find(ports: Array[PortDefinition], port_id: String) -> PortDefinition:
	for port in ports:
		if port.port_id == port_id:
			return port
	return null
