extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## `chart_rewrite_integration_test` carries the claim that the `world_layout`
## argument's only measured consequence is that every field `chart_summary`
## publishes comes out IDENTICAL with and without it. That was measured against the
## PRE-COLLAPSE published set. The collapse changed the set — `rotation_y`,
## `layout_seed`, `site_max_size` and `export_slots` are now taken off the world's
## PortData rather than re-derived — so the claim is re-measured here over the
## established base rather than carried forward on trust (REALITY §3f: a
## verification does not cover what it did not run over).

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817, 90210, 777, 20260816, 31337]


func _initialize() -> void:
	var total := 0
	var diverge: Dictionary = {}
	var example: Dictionary = {}
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		WeatherField.world_seed = int(world_seed)
		for port in ports:
			total += 1
			PortDataCache.clear()
			var with_layout := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			PortDataCache.clear()
			var without := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), null)
			for key in with_layout:
				if str(with_layout[key]) == str(without.get(key, "<missing>")):
					continue
				diverge[key] = int(diverge.get(key, 0)) + 1
				if not example.has(key):
					example[key] = "%d/%s  with=%s  without=%s" % [
						int(world_seed), port.port_id,
						str(with_layout[key]).substr(0, 70),
						str(without.get(key, "<missing>")).substr(0, 70)]
	print("")
	print("=== %d ports over %d seeds — published keys that MOVE when the layout is"
		% [total, SEEDS.size()] + " dropped:")
	var keys := diverge.keys()
	keys.sort_custom(func(a, b) -> bool: return int(diverge[a]) > int(diverge[b]))
	for key in keys:
		print("      %3d/%d  %-20s %s" % [int(diverge[key]), total, str(key), str(example[key])])
	if diverge.is_empty():
		print("      (none — every published field is identical with and without it)")
	quit(0)
