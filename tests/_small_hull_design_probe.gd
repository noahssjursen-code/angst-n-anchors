extends SceneTree

## Scratch probe (leading underscore — not a gate unit).
## Sweeps candidate small-hull numbers through the REAL constraint chain:
##   HullPhysicsProfile.validate() -> stations_geometry() -> HullStations.from_form
##   -> volume_below(draft), plus DeckGrid.from_hull cell counts.
## Prints, for each candidate, whether validate() is clean (NOT clamp-rescued),
## the achieved volume against the declared displacement, and the deck grid.


func _initialize() -> void:
	print("cand | L     B    D    T    disp_t | Cb    | validate | clamped | vol_m3  target_m3 err%%   | grid WxL taper")
	for cand in _candidates():
		_report(cand)
	quit(0)


func _candidates() -> Array:
	return [
		{"name": "A", "L": 15.0, "B": 5.0, "D": 2.6, "T": 1.55, "disp": 44.0, "form": "fine_entry"},
		{"name": "B", "L": 15.0, "B": 5.0, "D": 2.6, "T": 1.60, "disp": 48.0, "form": "fine_entry"},
		{"name": "C", "L": 15.0, "B": 4.8, "D": 2.6, "T": 1.55, "disp": 42.0, "form": "fine_entry"},
		{"name": "D", "L": 15.0, "B": 5.0, "D": 2.6, "T": 1.55, "disp": 44.0, "form": "rounded_full"},
		{"name": "E", "L": 15.0, "B": 5.0, "D": 2.6, "T": 1.55, "disp": 60.0, "form": "fine_entry"},
		{"name": "F", "L": 15.0, "B": 5.0, "D": 2.6, "T": 1.55, "disp": 30.0, "form": "fine_entry"},
		## Deliberately invalid — must be REJECTED by validate(), to prove the
		## probe can tell a clean hull from a clamp-rescued one.
		{"name": "X", "L": 15.0, "B": 5.0, "D": 2.6, "T": 3.20, "disp": 44.0, "form": "fine_entry"},
		{"name": "Y", "L": 15.0, "B": 5.0, "D": 2.6, "T": 1.55, "disp": 200.0, "form": "fine_entry"},
	]


func _report(cand: Dictionary) -> void:
	var loa := float(cand["L"])
	var beam := float(cand["B"])
	var depth := float(cand["D"])
	var draft := float(cand["T"])
	var disp := float(cand["disp"])
	var bow_taper_m := beam * 0.5

	var profile := HullPhysicsProfile.new()
	profile.length_m = loa
	profile.beam_m = beam
	profile.depth_m = depth
	profile.design_draft_m = draft
	profile.design_displacement_t = disp
	profile.bow_taper_fraction = clampf(bow_taper_m / loa, 0.0, 0.5)
	profile.station_count = clampi(int(round(loa / 8.0)), 8, 16)
	profile.hull_form = HullFormProfile.resolve(str(cand["form"]))

	var errors := profile.validate()
	var geom := profile.stations_geometry()
	var envelope_t := loa * beam * draft * profile.water_density / 1000.0
	var cb := disp / envelope_t

	var stations := HullStations.from_form(
		geom["length_m"], geom["beam_m"], geom["depth_m"], geom["draft_m"],
		geom["displacement_t"], profile.hull_form, profile.water_density,
		bow_taper_m, profile.station_count
	)
	var target_vol := disp * 1000.0 / profile.water_density
	var vol := stations.volume_below(draft)
	var err := absf(vol - target_vol) / target_vol * 100.0

	var grid := DeckGrid.from_hull(loa, beam, depth + 0.12, bow_taper_m)

	print("%4s | %-5.1f %-4.1f %-4.1f %-4.2f %-6.1f | %.3f | %-8s | %-7s | %-7.2f %-9.2f %-6.3f | %dx%d t=%d (need %d)" % [
		cand["name"], loa, beam, depth, draft, disp, cb,
		"CLEAN" if errors.is_empty() else "REJECT",
		str(geom["clamped"]),
		vol, target_vol, err,
		grid.width, grid.length, grid.bow_taper_cells, int(grid.width / 2),
	])
	if not errors.is_empty():
		print("       errors: %s" % "; ".join(errors))
	print("       sheer fwd=%.3f aft=%.3f  fullness=%.4f  deck_y=%.2f  full-depth vol=%.2f" % [
		stations.sheer_forward_m, stations.sheer_aft_m,
		stations.section_fullness_exponent, stations.deck_y,
		stations.displacement_volume_m3,
	])
