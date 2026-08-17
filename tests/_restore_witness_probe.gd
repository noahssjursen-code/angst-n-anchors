extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## Blind mutation M4 — dropping the `definition.size` restore in
## `PortExpander.summary_expansion` — passed both `port_fishing_service_test` and
## `chart_rewrite_integration_test` first time. That is a finding, and this asks
## why: how many placed definitions does an UNRESTORED expansion actually change?
##
## A check that "chart_summary leaves the caller's definition untouched" is worth
## nothing at a port whose definition the expansion would not have touched anyway
## (REALITY §4). So: per seed, count the ports where `expand` resolves `size`,
## `site_max_size` or both, and print which.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SEEDS := [90210, 424242, 20260817]


func _initialize() -> void:
	for world_seed in SEEDS:
		for port_count in [20, 35]:
			var layout: WorldLayout = GENERATOR.generate(int(world_seed))
			var ports: Array[PortDefinition] = PLACER.place_ports(
				layout, port_count, PackedStringArray(WorldPortNames.NAMES))
			LandField.initialize(layout)
			FishingField.initialize(int(world_seed))
			WeatherField.world_seed = int(world_seed)
			var size_moved: Array[String] = []
			var max_moved: Array[String] = []
			for port in ports:
				var victim := PortDefinition.from_dict(port.to_dict())
				PortDataCache.clear()
				PortExpander.expand_uncached(victim, int(world_seed), layout)
				if victim.size != port.size:
					size_moved.append("%s(%d→%d)" % [port.port_id, port.size, victim.size])
				if victim.site_max_size != port.site_max_size:
					max_moved.append("%s(%d→%d)" % [
						port.port_id, port.site_max_size, victim.site_max_size])
			print("seed %d, %d ports: size resolved at %d, site_max_size at %d" % [
				int(world_seed), ports.size(), size_moved.size(), max_moved.size()])
			print("      size: %s" % str(size_moved.slice(0, 6)))
			print("      max : %s" % str(max_moved.slice(0, 6)))
	quit(0)
