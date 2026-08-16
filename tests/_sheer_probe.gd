extends Node

## SCRATCH PROBE — leading underscore so the gate does not discover it.
##
## Question 1 of the sheer wave: for every hull the kit photographs, and every
## shipped vessel, which HullStations constructor did it actually go through, what
## is its `strake_level`, and what sheer does it carry? Measured through the
## PRODUCTION path (`HullRegistry.build_hull` -> `boat.hull_stations`), not by
## re-deriving `from_form` the way `hull_sheer_test._hull_cases` does.
##
## Question 2: what is the DRAWN amplitude of the strake band — max strake-top Y
## minus the amidships strake-top Y over the stations that actually have width —
## against the derived `sheer_forward_m`. If the clearance clamp is biting, those
## two numbers differ and only the second one is on screen.

const HULL_IDS := [
	"hull_15x5",
	"hull_28x10",
	"hull_45x16_cat",
	"hull_100x24",
	"hull_130x28",
	"hull_150x32",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== SHEER PROBE: production path per hull ===")
	for hull_id in HULL_IDS:
		var boat := HullRegistry.build_hull(hull_id)
		if boat == null:
			print("%s: build_hull returned null" % hull_id)
			continue
		var s: HullStations = boat.hull_stations
		if s == null:
			print("%s: NO hull_stations on the built body" % hull_id)
			boat.free()
			continue
		print("--- %s  (%s) ---" % [hull_id, boat.get_script().resource_path])
		print("  form_id=%s  L=%.3f B=%.3f depth=%.3f deck_y=%.3f draft=%.3f  stations=%d"
			% [s.form_id, s.length_m, s.beam_m, s.height_m, s.deck_y,
				s.design_draft_m, s.stations.size()])
		print("  strake_level=%d  sheer_forward_m=%.4f  sheer_aft_m=%.4f"
			% [s.strake_level, s.sheer_forward_m, s.sheer_aft_m])
		var freeboard := s.deck_y - s.design_draft_m
		print("  freeboard=%.4f  band=%.4f  clear=%.4f  clamp_y=%.4f"
			% [freeboard,
				maxf(freeboard * HullStations.STRAKE_BAND_FRACTION, 0.03),
				maxf(freeboard * HullStations.STRAKE_MIN_CLEAR_FRACTION, 0.04),
				s.deck_y - maxf(freeboard * HullStations.STRAKE_MIN_CLEAR_FRACTION, 0.04)])
		if s.strake_level >= 0:
			_report_band(s)
		else:
			print("  NO STRAKE BAND — the sheer curve is computed and thrown away here.")
		boat.free()
	print("=== SHEER PROBE: done ===")
	get_tree().quit()


func _report_band(s: HullStations) -> void:
	var live: Array = []
	for station in s.stations:
		var section: Array = station["section"]
		if s.strake_level >= section.size():
			continue
		if (section[s.strake_level] as Vector2).y > 0.001:
			live.append(station)
	print("  live strake stations: %d of %d" % [live.size(), s.stations.size()])
	var mid_top := 0.0
	var mid_abs := 1e18
	for station in live:
		if absf(float(station["z"])) < mid_abs:
			mid_abs = absf(float(station["z"]))
			mid_top = ((station["section"] as Array)[s.strake_level + 1] as Vector2).x
	var max_top := -1e18
	var max_z := 0.0
	for station in live:
		var top := ((station["section"] as Array)[s.strake_level + 1] as Vector2).x
		if top > max_top:
			max_top = top
			max_z = float(station["z"])
	for station in live:
		var z := float(station["z"])
		var section: Array = station["section"]
		var bot := (section[s.strake_level] as Vector2).x
		var top := (section[s.strake_level + 1] as Vector2).x
		print("    z=%+8.3f  band_bottom=%.4f  band_top=%.4f  half_beam=%.4f  want_rise=%.4f  got_rise=%.4f"
			% [z, bot, top, (section[s.strake_level] as Vector2).y,
				s.sheer_rise_at(z), top - mid_top])
	print("  DRAWN AMPLITUDE (max band_top - midships band_top) = %.4f m at z=%+.3f"
		% [max_top - mid_top, max_z])
	print("  DERIVED sheer_forward_m                            = %.4f m" % s.sheer_forward_m)
	print("  drawn/derived = %.3f   drawn/hull_height = %.4f"
		% [(max_top - mid_top) / maxf(s.sheer_forward_m, 1e-6),
			(max_top - mid_top) / maxf(s.height_m, 1e-6)])
