extends SceneTree

const FishLandingLayout := preload("res://scripts/port/fish_landing_layout.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	assert(PortFishingService.is_eligible(island, 77127), "archipelago ports must receive fish landing")
	var summary := PortExpander.chart_summary(island, 77127)
	assert(bool(summary.get("has_fish_landing", false)), "chart data must advertise fish landing")
	assert((summary.get("features", []) as Array).has("Fish Landing"), "chart feature must be present")
	var advertised_definition := summary.get("port_definition", {}) as Dictionary
	assert(advertised_definition == island.to_dict(), "chart must preserve the exact placed port")
	assert(is_equal_approx(
		PortDefinition.from_dict(advertised_definition).site_quay_half_m,
		island.site_quay_half_m,
	), "chart quay clearance must survive the preview round trip")
	var profile := PortTradeProfile.derive(island, 77127)
	PortFishingService.apply_to_profile(profile)
	assert(
		profile.import_slots.has(PortFishingService.COMMODITY_ID),
		"fish landing must be represented in port trade data",
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
			assert(
				str(station.get("layout", "")) == "single",
				"fish landing must never be packed into a shared twin quay",
			)
			assert(
				float(station.get("width_m", 0.0)) >= FishLandingLayout.REFERENCE_QUAY_WIDTH_M,
				"fish landing must preserve the approved showcase quay width",
			)
			found = true
			break
	assert(found, "fish landing must receive a proper generated quay")
	var expanded := PortExpander.expand(island, 77127)
	assert(expanded.has_fish_landing, "expanded port must report its realized fish landing")
	var expanded_plan := expanded.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var realized := false
	for raw in expanded_plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		if PortExpander._quay_station_has_fish_landing(station):
			realized = true
			break
	assert(realized, "layout generation must not trim the advertised fish berth")
	print("PortFishingService: eligibility, port data, and berth generation passed")
	PortDataCache.clear()
	quit()
