extends SceneTree

## Scratch probe. Does the flat deck PLATE match the loft's top edge?
## Plate: pointed_deck_plate(loa, beam, ...) — a straight 45-degree chamfer of
## run bow_frac*loa. Shell: _assign_form_sections blends the same run with a
## SMOOTHSTEP. A straight line and an S-curve over the same interval cannot
## agree, so one overhangs the other. Measured here on both hulls, since if it
## is real it is shared code and not a property of the new hull.

func _initialize() -> void:
	_sweep("hull_15x5", 15.0, 5.0, 2.6, 1.55, 44.0, "fine_entry")
	_sweep("hull_28x10", 28.0, 10.0, 5.6, 2.8, 256.0, "fine_entry")
	quit(0)


func _sweep(id: String, loa: float, beam: float, depth: float, draft: float, disp: float, form_id: String) -> void:
	var form := HullFormProfile.resolve(form_id)
	var bow_taper_m := beam * 0.5
	var st := HullStations.from_form(loa, beam, depth, draft, disp, form, 1025.0, bow_taper_m, clampi(int(round(loa/8.0)), 8, 16))
	print("--- %s  loa=%.1f beam=%.1f  bow run=%.2f m ---" % [id, loa, beam, bow_taper_m])
	print("  z_from_bow  shell_half_beam  plate_half_beam  plate_minus_shell")
	var worst := 0.0
	for i in range(st.stations.size()):
		var z := float(st.stations[i]["z"])
		var d := z + loa * 0.5
		var shell := st.half_beam_at(i, st.deck_y)
		## pointed_deck_plate: linear 45-degree chamfer over the bow run.
		var plate := beam * 0.5
		if d < bow_taper_m:
			plate = beam * 0.5 * (d / bow_taper_m)
		if d <= loa * 0.45:
			print("  %8.3f    %10.4f      %10.4f      %+9.4f" % [d, shell, plate, plate - shell])
		worst = maxf(worst, absf(plate - shell))
	print("  worst |plate - shell| over the whole length = %.4f m per side" % worst)
