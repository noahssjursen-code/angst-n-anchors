extends SceneTree

## Scratch probe (agent-owned, deleted before hand-back): prints the deck-edge
## plan curve of hull_28x10 so a hand-authored sheer path can hug the real hull.

func _init() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/structures/probe_sheer_bulwark.json"
	))
	var plan := StructurePlan.from_dict(raw as Dictionary)
	var st := plan.hull_stations("hull_28x10")
	var grid := plan.hull_grid("hull_28x10")
	print("deck_y=%.4f grid.deck_y=%.4f half_beam=%.3f half_loa=%.3f" % [
		st.deck_y, grid.deck_y, grid.half_beam, grid.half_loa])
	print("sheer fwd=%.4f aft=%.4f  len=%.2f beam=%.2f" % [
		st.sheer_forward_m, st.sheer_aft_m, st.length_m, st.beam_m])
	print("samples_for(0.04)=%d" % StructureEdge.sheer_samples_for(st, 0.04))
	# Deck half-beam at a range of heights above deck, every 0.5 m of plan z.
	var heights := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]
	var head := "planz  local_z"
	for h in heights:
		head += "   hb@+%.1f" % [float(h)]
	print(head)
	var z := 0.0
	while z <= 28.0001:
		var lz := z - 14.0
		var line := "%5.2f  %6.2f" % [z, lz]
		for h in heights:
			line += "   %7.4f" % [
				StructureEdge.deck_half_beam_at(st, lz, st.deck_y + float(h))
			]
		print(line)
		z += 0.5
	quit()
