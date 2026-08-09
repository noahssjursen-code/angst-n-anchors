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
	PortDataCache.clear()
	t.finish(self)
