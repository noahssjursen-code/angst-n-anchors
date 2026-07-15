class_name PortDockRecipe
extends RefCounted

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")

## Seed recipe: how many boats, at what coast positions, extruded at 90° or 45°.


static func derive(
		size: int,
		site_seed: int,
		coast_path: PackedVector2Array,
		families: Array[String],
) -> Dictionary:
	var berth_count := PortSizing.berth_count(size)
	var arc_lengths: Array[float] = CoastTracer.path_arc_lengths(coast_path)
	var total_arc := float(arc_lengths[arc_lengths.size() - 1]) if not arc_lengths.is_empty() else 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x52454349 ^ (size * 7919)

	var arm_families := PortSizing.assign_families_to_arms(
		families,
		berth_count,
		"solo_jetty",
		site_seed,
	)
	var berths: Array[Dictionary] = []
	for berth_index in range(berth_count):
		var arc_s := total_arc * (float(berth_index) + 0.5) / float(berth_count)
		var use_ninety := rng.randf() < 0.62
		var side := -1 if rng.randf() < 0.5 else 1
		var boats := 1
		if size >= 4 and berth_index == 0 and rng.randf() < 0.35:
			boats = 2
		berths.append({
			"berth_index": berth_index,
			"arc_s": arc_s,
			"extrude_angle_deg": 90 if use_ninety else 45,
			"extrude_side": side,
			"boats": boats,
			"family": arm_families[berth_index] if berth_index < arm_families.size() else "general",
		})

	return {
		"berth_count": berth_count,
		"total_coast_arc_m": total_arc,
		"berths": berths,
	}
