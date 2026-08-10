extends SceneTree

## scratch probe — dumps hull_150x32 geometry for authoring. Deleted after use.

const StructurePlanScript := preload("res://scripts/construction/structure_plan.gd")
const StructureEdgeScript := preload("res://scripts/construction/structure_edge.gd")


func _init() -> void:
	var st: HullStations = StructurePlanScript.make_hull_stations("hull_150x32", {})
	if st == null:
		print("NO STATIONS")
		quit(1)
		return
	print("loa=%.4f beam=%.4f deck_y=%.4f keel_y=%.4f depth=%.4f" % [
		st.length_m, st.beam_m, st.deck_y, st.keel_y, st.height_m])
	print("sheer_fwd=%.4f sheer_aft=%.4f form=%s fullness=%.4f disp=%.2f" % [
		st.sheer_forward_m, st.sheer_aft_m, st.form_id,
		st.section_fullness_exponent, st.displacement_volume_m3])
	print("stations n=%d" % st.stations.size())
	for i in st.stations.size():
		var s := st.stations[i] as Dictionary
		print("  st%02d z=%8.3f hb_deck=%7.3f" % [i, float(s["z"]), st.half_beam_at(i, st.deck_y)])
	var grid: DeckGrid = DeckGrid.from_hull(st.length_m, st.beam_m, st.deck_y + 0.12, st.beam_m * 0.5)
	print("grid half_beam=%.4f half_loa=%.4f deck_y=%.4f width=%d length=%d" % [
		grid.half_beam, grid.half_loa, grid.deck_y, grid.width, grid.length])
	print("--- deck half beam at plan z (plan z = ship z + half_loa) ---")
	var z := 0.0
	while z <= st.length_m + 0.01:
		var ship_z := z - st.length_m * 0.5
		var hb_deck: float = StructureEdgeScript.deck_half_beam_at(st, ship_z, st.deck_y)
		var cap := st.sheer_cap_y_at(ship_z) - st.deck_y
		print("  planz=%7.2f hb=%8.4f  sheer_rise=%.4f" % [z, hb_deck, cap])
		z += 2.5
	print("--- samples_for(0.08) = %d" % StructureEdgeScript.sheer_samples_for(st, 0.08))
	quit(0)
