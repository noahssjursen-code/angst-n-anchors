extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit).
## Answers three questions before any geometry moves:
##  1. how many hulls go through `HullStations._assign_form_sections`;
##  2. what the profile silhouette of hull_15x5 / hull_28x10 actually is
##     (top line, keel line, stem line per level);
##  3. how far the lofted shell and `pointed_deck_plate` disagree, per hull.


func _initialize() -> void:
	_who_owns_the_silhouette()
	_silhouette("hull_15x5")
	_silhouette("hull_28x10")
	_plate_vs_shell()
	quit(0)


func _who_owns_the_silhouette() -> void:
	print("\n== hulls routed through HullStations.from_form / _assign_form_sections ==")
	var n := 0
	for entry in HullCatalog.catalog_entries():
		var form: Dictionary = entry.get("hull_form", {}) as Dictionary
		print("  catalog  %-12s  loa %6.1f beam %5.1f depth %5.1f draft %5.2f  form=%s" % [
			str(entry.get("id", "")), float(entry.get("loa_m", 0.0)),
			float(entry.get("beam_m", 0.0)), float(entry.get("depth_m", 0.0)),
			float(entry.get("draft_m", 0.0)), str(form.get("id", "?")),
		])
		n += 1
	for named in [
		["FishingTrawlerSmall", FishingTrawlerSmall.make_physics_profile()],
		["PassengerCatamaran", PassengerCatamaran.make_physics_profile()],
	]:
		var p: HullPhysicsProfile = named[1]
		print("  scripted %-12s  loa %6.1f beam %5.1f depth %5.1f draft %5.2f  form=%s" % [
			str(named[0]), p.length_m, p.beam_m, p.depth_m, p.design_draft_m,
			str(p.hull_form.get("id", "?")),
		])
		n += 1
	print("  TOTAL hulls whose silhouette _assign_form_sections draws: %d" % n)


func _stations_for(hull_id: String) -> HullStations:
	if hull_id == "hull_28x10":
		return FishingTrawlerSmall.make_physics_profile().make_stations()
	var e := HullCatalog.get_by_id(hull_id)
	return HullStations.from_form(
		float(e.get("loa_m", 1.0)), float(e.get("beam_m", 1.0)),
		float(e.get("depth_m", 1.0)), float(e.get("draft_m", 1.0)),
		float(e.get("displacement_t", 1.0)), e.get("hull_form", {}) as Dictionary,
		1025.0, float(e.get("bow_taper_m", 0.0)),
		clampi(int(round(float(e.get("loa_m", 1.0)) / 8.0)), 8, 16),
	)


func _silhouette(hull_id: String) -> void:
	var s := _stations_for(hull_id)
	print("\n== %s profile silhouette (L=%.1f B=%.1f D=%.2f draft=%.2f) ==" % [
		hull_id, s.length_m, s.beam_m, s.height_m, s.design_draft_m])
	print("   sheer_forward=%.4f  sheer_aft=%.4f  deck_y=%.4f  (computed, not drawn)" % [
		s.sheer_forward_m, s.sheer_aft_m, s.deck_y])
	print("   %-8s %-8s %-8s | half-beam per level" % ["z", "keel_y", "top_y"])
	for st in s.stations:
		var sec: Array = st["section"]
		var line := ""
		for lv in sec:
			line += "%6.3f@%5.3f " % [(lv as Vector2).y, (lv as Vector2).x]
		print("   %-8.3f %-8.4f %-8.4f | %s" % [
			float(st["z"]), (sec[0] as Vector2).x, (sec[sec.size() - 1] as Vector2).x, line])

	## Where does the outline's FRONT edge sit at each height? Sample the loft
	## surface: for each level index, the most-forward z with half_beam > 1% of beam.
	var lvl := (s.stations[0]["section"] as Array).size()
	print("   stem line: forward-most z with half_beam > 1%% of B/2, per level")
	for j in range(lvl):
		var best := 1e9
		var y := 0.0
		for st in s.stations:
			var sec: Array = st["section"]
			if j >= sec.size():
				continue
			var p := sec[j] as Vector2
			if p.y > s.beam_m * 0.005 and float(st["z"]) < best:
				best = float(st["z"])
				y = p.x
		print("     level %d  y=%.3f  z_front=%.3f  (bow tip is %.3f)" % [j, y, best, -s.length_m * 0.5])


func _plate_vs_shell() -> void:
	print("\n== lofted shell vs pointed_deck_plate at deck_y, per hull ==")
	var cases := [["hull_15x5", 2.5], ["hull_28x10", -1.0]]
	for c in cases:
		var hull_id: String = c[0]
		var s := _stations_for(hull_id)
		var loa := s.length_m
		var beam := s.beam_m
		var bow_frac := 0.0
		if hull_id == "hull_28x10":
			bow_frac = FishingTrawlerSmall.BOW_FRAC
		else:
			bow_frac = clampf(float(c[1]) / loa, 0.0, 0.5)
		var ring := MeshBuilder._pointed_plan_ring(loa, beam, bow_frac)
		## Sample the CONTINUOUS drawn edges, not the station planes: the loft is a
		## linear loft between stations, so the drawn deck edge between two stations is
		## the straight line between their top-level half beams. Sampling only at
		## stations reports whatever the station spacing happens to hit and moves when
		## the spacing moves — which would have made this change look like a 25x
		## improvement it is not.
		var worst := 0.0
		var worst_z := 0.0
		var samples := 2000
		for k in range(samples + 1):
			var z := lerpf(-loa * 0.5, loa * 0.5, float(k) / float(samples))
			var d := _shell_deck_half_beam(s, z) - _ring_half_beam(ring, z)
			if absf(d) > absf(worst):
				worst = d
				worst_z = z
		print("  %-10s bow_frac=%.4f  worst shell-minus-plate = %+.4f m per side at z=%.3f" % [
			hull_id, bow_frac, worst, worst_z])


func _ring_half_beam(ring: PackedVector2Array, z: float) -> float:
	var best := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if absf(b.y - a.y) < 1e-6:
			continue
		var lo := minf(a.y, b.y)
		var hi := maxf(a.y, b.y)
		if z < lo or z > hi:
			continue
		var t := (z - a.y) / (b.y - a.y)
		best = maxf(best, absf(a.x + t * (b.x - a.x)))
	return best


## Drawn deck-edge half beam at ship-local Z: linear between the two bracketing
## stations' top section levels, which is exactly what the loft draws.
func _shell_deck_half_beam(s: HullStations, z: float) -> float:
	var n := s.stations.size()
	if n == 0:
		return 0.0
	if z <= float(s.stations[0]["z"]):
		return ((s.stations[0]["section"] as Array).back() as Vector2).y
	for i in range(n - 1):
		var za := float(s.stations[i]["z"])
		var zb := float(s.stations[i + 1]["z"])
		if z >= za and z <= zb:
			var ha := ((s.stations[i]["section"] as Array).back() as Vector2).y
			var hb := ((s.stations[i + 1]["section"] as Array).back() as Vector2).y
			return lerpf(ha, hb, (z - za) / maxf(zb - za, 1e-6))
	return ((s.stations[n - 1]["section"] as Array).back() as Vector2).y
