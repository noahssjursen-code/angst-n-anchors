extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## ONE QUESTION: if the onboarding default career becomes `fishing`, the home
## port picker calls `MapOverlay._home_port_supports_required_family("fishing")`,
## which disables CONFIRM on every port without a fish landing. Flipping the
## default without measuring that would be REALITY.md §6 — "should work" reported
## as "works" — so this counts, over real generated worlds, how many ports a
## fishing captain may actually choose.
##
## ⚠ THE PARAGRAPH THAT USED TO BE HERE WAS FALSE, AND ITS NUMBER WENT INTO
## `CompanyContracts.DEFAULT_STARTER`'S HEADER — corrected 2026-08-17.
##
## It said: *"`PortFishingService.is_eligible` is the same predicate `PortExpander`
## uses to set `has_fish_landing`, so this measures the production answer without
## expanding 35 ports per seed."* It is the predicate `PortExpander` uses to
## **start**, and `expand_uncached` then OVERWRITES the flag with
## `_has_realized_fish_landing(layout_graph)` because the size ladder can trim the
## fish berth out of a small harbour. This file counts ports that are ALLOWED a fish
## landing. It has never counted ports that HAVE one, and the gap is 137 against 85
## over six seeds.
##
## Two further reasons its numbers are not the production answer, both measured:
## `is_eligible` samples `FishingField`, whose `open_water` term reads the GLOBAL
## `LandField` — which this file never bakes, so it asks the most permissive form of
## the question; and it is 35 ports of one snapshot per seed with no port ever
## expanded, so nothing here can see a berth plan at all.
##
## KEPT, NOT DELETED, because the shape of the question (how many home ports may a
## fishing captain choose) is still the right one and this is the record of how it
## was first answered wrongly. **Use `tests/_fish_landing_realization_probe.gd`,
## which measures both producers side by side, and `tests/_home_port_confirm_probe.gd`,
## which drives the actual CONFIRM button.**

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35


func _initialize() -> void:
	var total := 0
	var fishing := 0
	for world_seed in [90210, 424242, 7, 1337, 20260815]:
		var layout: WorldLayout = GENERATOR.generate(world_seed)
		var ports: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT)
		var n := 0
		var home_ok := false
		for port in ports:
			if PortFishingService.is_eligible(port, world_seed):
				n += 1
				if port.port_id == "port-home":
					home_ok = true
		total += ports.size()
		fishing += n
		print("seed %-10d ports=%2d  fish_landing=%2d (%5.1f%%)  home_port_eligible=%s" % [
			world_seed, ports.size(), n,
			100.0 * float(n) / maxf(float(ports.size()), 1.0),
			"yes" if home_ok else "NO",
		])
	print("TOTAL %d/%d ports offer a fish landing (%.1f%%)" % [
		fishing, total, 100.0 * float(fishing) / maxf(float(total), 1.0),
	])
	quit(0)
