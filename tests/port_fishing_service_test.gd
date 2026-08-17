extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const FishLandingLayout := preload("res://scripts/port/fish_landing_layout.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("port_fishing_service_test")
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
	t.check(
		"archipelago ports must receive fish landing",
		PortFishingService.is_eligible(island, 77127),
	)
	var summary := PortExpander.chart_summary(island, 77127)
	t.check("chart data must advertise fish landing", bool(summary.get("has_fish_landing", false)))
	t.check(
		"chart feature must be present",
		(summary.get("features", []) as Array).has("Fish Landing"),
	)
	var advertised_definition := summary.get("port_definition", {}) as Dictionary
	t.check("chart must preserve the exact placed port", advertised_definition == island.to_dict())
	t.check("chart quay clearance must survive the preview round trip", is_equal_approx(
		PortDefinition.from_dict(advertised_definition).site_quay_half_m,
		island.site_quay_half_m,
	))
	var profile := PortTradeProfile.derive(island, 77127)
	PortFishingService.apply_to_profile(profile)
	t.check(
		"fish landing must be represented in port trade data",
		profile.import_slots.has(PortFishingService.COMMODITY_ID),
	)
	var foundation := {
		"dock_face_polyline": [[-100.0, 0.0], [100.0, 0.0]],
		"spine": [[-100.0, 0.0], [100.0, 0.0]],
	}
	var plan := PortBerthPlan.build(profile, island.size, foundation, island.site_seed)
	var found := false
	for raw in plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		if PortExpander._quay_station_has_fish_landing(station):
			t.equal(
				"fish landing must never be packed into a shared twin quay",
				str(station.get("layout", "")),
				"single",
			)
			t.check(
				"fish landing must preserve the approved showcase quay width",
				float(station.get("width_m", 0.0)) >= FishLandingLayout.REFERENCE_QUAY_WIDTH_M,
			)
			found = true
			break
	t.check("fish landing must receive a proper generated quay", found)
	var expanded := PortExpander.expand(island, 77127)
	t.check("expanded port must report its realized fish landing", expanded.has_fish_landing)
	var expanded_plan := expanded.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var realized := false
	for raw in expanded_plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		if PortExpander._quay_station_has_fish_landing(station):
			realized = true
			break
	t.check("layout generation must not trim the advertised fish berth", realized)
	_check_single_assignment(t)
	PortDataCache.clear()
	t.finish(self)


## ═══ ONE ASSIGNMENT PER PUBLIC FIELD (REALITY §3b) ═══════════════════════════
##
## `PortExpander.expand_uncached` used to write `PortFishingService.is_eligible`
## into the PUBLIC `data.has_fish_landing` and overwrite it with the realized
## answer 28 lines later. That is the shape that shipped a player-facing lie: two
## derivations of one fact inside one function, with a window in which the wrong
## one is readable. Fixed 2026-08-17 by putting eligibility in a local.
##
## This is a SOURCE-SHAPE check, and that is deliberate rather than lazy. The
## window is not observable from outside the function — `data` is a local that is
## not published until `return`, and `PortLayoutGenerator` is handed the trade
## profile and an attribute dictionary, never the PortData — so there is no
## behaviour to assert against. The property is structural, and the honest way to
## hold a structural property is to read the structure. If the window ever DOES
## become externally observable, that is a different and worse finding than this
## check can express, and it should be reported rather than patched.
##
## Two defences against §4f, because a regex over production source is exactly
## the population that shed a check silently in `ship_hud_readout_test`:
##   1. the assigned-field set is compared against a DECLARED LITERAL, so a scan
##      that stops matching reds by NAME instead of quietly running fewer checks,
##      and a new public field cannot be added here without being classified;
##   2. every entry in `REPEATED_OK` must STILL be repeated at the declared count,
##      so an entry that gets fixed must be struck off rather than left to rot.
const EXPANDER_PATH := "res://scripts/port/port_expander.gd"

## Every `data.<field> =` in `expand_uncached`, enumerated 2026-08-17. The
## population is the stable thing, not the count (§4f shape 1).
const ASSIGNED_FIELDS: Array[String] = [
	"port_id", "display_name", "world_position", "site_id",
	"port_generation_version", "size", "trade_profile", "has_fuel_point",
	"has_lighthouse", "has_fog_horn", "layout_graph", "has_fish_landing",
	"dock_length", "island_width", "plot_depth", "max_ship_class", "berth_count",
	"commodity_export", "commodity_imports", "layout_seed", "rotation_y",
	"region_kind", "ground_mode", "population", "features",
]

## The one field still written more than once, with the count and the reason.
## `size` is a WORKING VALUE here — clamped by the site ceiling, clamped again by
## the trade ceiling, then re-normalised from the definition after the basin has
## had its say — and each of the three writes is read by the next. It is the same
## shape as the fish flag and it has not produced a wrong answer, because no
## intermediate value escapes the function either. Recorded so that it is a KNOWN
## instance and not an unnoticed one, and so that a SECOND field joining it fails
## this unit. Striking this entry off is how the last one gets fixed.
const REPEATED_OK: Dictionary = {"size": 3}


func _check_single_assignment(t) -> void:
	var file := FileAccess.open(EXPANDER_PATH, FileAccess.READ)
	if not t.check("the expander source opens for the one-assignment scan", file != null):
		return
	var current_func := ""
	## func -> field -> count
	var writes: Dictionary = {}
	var assign := RegEx.new()
	assign.compile("^\\s*data\\.([a-z_]+)\\s*=[^=]")
	var func_re := RegEx.new()
	func_re.compile("^static func ([a-z_]+)")
	while not file.eof_reached():
		var line := file.get_line()
		var fm := func_re.search(line)
		if fm != null:
			current_func = fm.get_string(1)
			continue
		var am := assign.search(line)
		if am == null:
			continue
		var field := am.get_string(1)
		if not writes.has(current_func):
			writes[current_func] = {}
		var per_func: Dictionary = writes[current_func]
		per_func[field] = int(per_func.get(field, 0)) + 1
	file.close()

	## The property is file-scoped: no OTHER function may build a PortData either.
	var other_funcs: Array[String] = []
	for fn in writes:
		if str(fn) != "expand_uncached":
			other_funcs.append(str(fn))
	t.check(
		"only `expand_uncached` assigns PortData fields in the expander (also: %s)"
		% str(other_funcs),
		other_funcs.is_empty(),
	)
	var found: Dictionary = writes.get("expand_uncached", {}) as Dictionary

	## 1 — the population, named both ways, so a broken scan cannot go quiet.
	var missing: Array[String] = []
	for field in ASSIGNED_FIELDS:
		if not found.has(field):
			missing.append(field)
	var unexpected: Array[String] = []
	for field in found:
		if not ASSIGNED_FIELDS.has(str(field)):
			unexpected.append(str(field))
	t.check(
		"the scan still finds every declared assignment in `expand_uncached`"
		+ " (%d of %d; missing %s) — a field that stops matching means the SCAN"
			% [ASSIGNED_FIELDS.size() - missing.size(), ASSIGNED_FIELDS.size(), str(missing)]
		+ " broke, not that the assignment is gone",
		missing.is_empty(),
	)
	t.check(
		"no undeclared public field is assigned in `expand_uncached` (%s) — a new"
			% str(unexpected)
		+ " one must be classified here, single- or multiply-assigned",
		unexpected.is_empty(),
	)

	## 2 — the actual property.
	var doubled: Array[String] = []
	for field in found:
		var n := int(found[field])
		if n <= 1:
			continue
		if int(REPEATED_OK.get(str(field), 0)) == n:
			continue
		doubled.append("%s×%d" % [str(field), n])
	t.check(
		"no public PortData field is assigned a value `expand_uncached` later"
		+ " overwrites (%s) — writing eligibility into `has_fish_landing` and"
			% str(doubled)
		+ " correcting it 28 lines down is what promised 52 fish landings the"
		+ " world never built",
		doubled.is_empty(),
	)
	t.equal(
		"`has_fish_landing` is assigned exactly once — it is the realized answer"
		+ " or nothing",
		int(found.get("has_fish_landing", 0)),
		1,
	)

	## 3 — the register cannot rot: a fixed entry must be struck off.
	for field in REPEATED_OK:
		t.equal(
			"the REPEATED_OK entry for `%s` still describes the source — strike it"
				% str(field)
			+ " off when it is fixed, do not leave it standing",
			int(found.get(str(field), 0)),
			int(REPEATED_OK[field]),
		)
