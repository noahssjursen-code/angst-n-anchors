extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## `population` and `berth_count` are the pick panel's OWN numbers and are held as
## registered owner decisions. Nothing in the gate notices if they change: they are
## registered as DIVERGENT from the world, and a panel number that quietly becomes a
## different wrong-by-register number still diverges, so the register still passes.
##
## Reproducing the panel's population needs the RNG stream the old parallel
## derivation advanced. So the value a player reads is guarded by freezing it — and
## the number must be PREDICTED from the producer that exists BEFORE the change, not
## read off the changed one, or the guard is just writing the answer down.
##
## Run this against the pre-change `port_expander.gd` to get the numbers to freeze,
## then against the changed one to confirm they did not move. Definition is
## byte-identical to `port_fishing_service_test`'s `island`.


func _initialize() -> void:
	PortDataCache.clear()
	var island := PortDefinition.new()
	island.port_id = "fish-island"
	island.display_name = "Fish Island"
	island.size = 2
	island.site_seed = 91919
	island.site_quay_half_m = 137.5
	island.region_kind = PortDefinition.RegionKind.ARCHIPELAGO
	island.has_explicit_rotation = true
	island.rotation_y = 0.0
	var summary := PortExpander.chart_summary(island, 77127)
	var world := PortExpander.expand(
		PortDefinition.from_dict(island.to_dict()), 77127)
	print("PANEL  population=%d  berth_count=%d  size=%d" % [
		int(summary.get("population", -1)),
		int(summary.get("berth_count", -1)),
		int(summary.get("size", -1)),
	])
	print("WORLD  population=%d  berth_count=%d  size=%d" % [
		world.population, world.berth_count, world.size])
	quit(0)
