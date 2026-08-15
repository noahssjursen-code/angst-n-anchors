extends SceneTree

## Properties the live traffic world must hold at scale.
##
## This unit replaces the assertion-free `shipping_lane_traffic_profile.gd`,
## which the gate discovered, ran for 114 s and scored PASS while checking
## nothing (REALITY.md §4). The profiler still exists — underscored, as
## `tests/_shipping_lane_traffic_profile.gd` — because printing 12 x 1000 s of
## timings at 250 vessels is a useful thing to do by hand. What it could never
## do is fail, so what it was implicitly standing guard over is asserted here
## instead, at a cost the gate can carry every run.
##
## One property here is genuinely new: NO VESSEL IS EVER ON LAND. Nothing in
## the repository had ever compared a vessel position against
## `WorldLayout.sample_signed_distance` — REALITY.md §4b, a whole property with
## no check pointed at it. The rest of the scenario is the same ground
## `shipping_lane_network_test` (6 ports) and
## `shipping_lane_traffic_simulator_test` (8 ports) cover, run at 35, which is
## the half of the profiler's exercise worth keeping.
##
## The scenario is the profiler's own: seed 42, 35 ports, the real port-name
## table, `CoastalPortPlacer` -> `PortExpander` -> `ShippingLaneNetworkBuilder`.
## Measured on this container, that whole build half costs ~12 s of which ~8 s
## is the world raster; going from 8 ports to 35 costs about 1.5 s. The vessel
## count and the simulated window are where the profiler's 114 s actually went
## (250 vessels x 12 000 s = 99 s of it), and they are the two knobs turned
## down here.
##
## WHAT IS NOT ASSERTED, DELIBERATELY
##
## - `summary().collisions == 0`. True at 24 vessels, and measured FALSE at the
##   profiler's 250: seed 42 / 35 ports / 250 vessels reports 3 collisions and
##   leaves 226 of 250 vessels in `scheduled_strategic` forever. That is a live
##   defect this unit is not authorised to turn red; it is recorded, not hidden.
## - `validate()` warnings. The builder emits `shore_clearance` as a WARNING by
##   design. There happen to be zero of them today, and freezing that would
##   make any future legitimate warning a gate failure. Errors only.
## - Determinism, and `trips_completed > 0` as a headline claim. Both are
##   already asserted by `shipping_lane_traffic_simulator_test`. The trip count
##   appears below only as an anti-vacuity guard: a frozen simulator would make
##   the land property below trivially true.

const TestReport := preload("res://tests/support/test_report.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const WORLD_PORT_NAMES := preload("res://scripts/world/world_port_names.gd")

const SCENARIO_SEED := 42
const PORT_COUNT := 35
const VESSEL_COUNT := 24
const SIMULATED_SECONDS := 3000.0


func _initialize() -> void:
	var t := TestReport.new("shipping_lane_traffic_integrity_test")
	var started := Time.get_ticks_msec()

	var layout := GENERATOR.generate(SCENARIO_SEED, WorldConfig.ARCHETYPE_PATH) as WorldLayout

	# ---------------------------------------------------------------- instrument
	# REALITY.md §8: check the camera before the subject. An empty or refused
	# WorldLayout answers `sample_signed_distance` with `_world_size_m` for every
	# position on the planet, so the land property below would go green on a
	# world that had never been built. So would an all-water world. Both holes
	# are shut here, before anything is measured through the field.
	if not t.check("world layout has a raster to sample", layout.raster_resolution >= 2):
		t.finish(self)
		return
	t.check("raster cell size is a real distance", layout.cell_size_m > 0.0)
	var raster := layout.get_signed_distance_raster()
	var land_cells := 0
	var water_cells := 0
	for value in raster:
		if value < 0.0:
			land_cells += 1
		elif value > 0.0:
			water_cells += 1
	t.check("the sampled world actually contains land", land_cells > 0)
	t.check("the sampled world actually contains water", water_cells > 0)
	print("  world: %d^2 raster, cell %.2f m, %d land cells, %d water cells" % [
		layout.raster_resolution, layout.cell_size_m, land_cells, water_cells])

	# ------------------------------------------------------------------- scenario
	var names := PackedStringArray()
	for port_name in WORLD_PORT_NAMES.NAMES:
		names.append(port_name)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT, names)
	# The whole point of running 35 ports is that 35 ports get built. If the
	# placer quietly returns 6, every count below is measuring a different,
	# smaller exercise while still reading as "35 ports".
	t.equal("coastal placer delivers the requested port count",
		definitions.size(), PORT_COUNT)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, SCENARIO_SEED, layout))
	# NOT CHECKED: `ports.size() == definitions.size()`. The loop above appends
	# once per definition, so that equality holds by construction and no defect
	# can break it — a check that cannot fail (REALITY.md §4). Likewise
	# `network != null` below: `build()` is typed to return a network and
	# constructs one on its first line, including on the missing-layout path.

	var builder := ShippingLaneNetworkBuilder.new()
	var network := builder.build(layout, ports)
	# Every port that was placed must reach the network as publishable traffic
	# gates. A port that expands but never publishes gates is unreachable
	# by any vessel, and the fleet below would simply never route to it.
	t.equal("every placed port publishes traffic gates",
		network.port_gate_nodes.size(), ports.size())

	# ------------------------------------------------------- network validation
	# `build()` already runs `validate()` internally and stores the result on
	# the network, and `shipping_lane_network_test` asserts zero errors on that
	# stored copy — at SIX ports. This is the same property over the 35-port
	# world the profiler used to be the only thing exercising, which is the half
	# of the profiler's coverage worth keeping. Its `error` severities are
	# structural: an edge with no block, a quay that cannot reach a shipping
	# lane, a signal protecting nothing, a ramp attached to a through lane.
	# There is no reading of the network under which those are acceptable.
	var issues := builder.validate(network, layout)
	var by_severity_code: Dictionary = {}
	var error_issues: Array[Dictionary] = []
	for issue in issues:
		var key := "%s:%s" % [str(issue.get("severity", "unknown")),
			str(issue.get("code", "unknown"))]
		by_severity_code[key] = int(by_severity_code.get(key, 0)) + 1
		if str(issue.get("severity", "")) == "error":
			error_issues.append(issue)
	print("  validation: %d issues %s" % [issues.size(), JSON.stringify(by_severity_code)])
	for issue in error_issues:
		print("  validation ERROR %s %s @ %s" % [str(issue.get("code", "")),
			str(issue.get("message", "")), str(issue.get("source_id", issue.get("source", "")))])
	t.equal("network validation reports no error-severity issues", error_issues.size(), 0)
	# NOT CHECKED HERE, and the reason is worth writing down: `validate()`'s own
	# header promises a repeat call does not accumulate a second copy of every
	# deterministic finding. There is no check for that guarantee anywhere
	# (REALITY.md §3c) and it is tempting to add one — but on a network that
	# validates clean it compares 0 against 0 and cannot fail, whether or not
	# the de-duplication pass exists. Deleting that pass leaves such a check
	# GREEN, verified. A vacuous check is what this unit was written to remove,
	# so the guarantee stays unheld rather than falsely held.

	# -------------------------------------------------------------- simulation
	var simulator := ShippingLaneTrafficSimulator.new()
	simulator.configure(network, VESSEL_COUNT, SCENARIO_SEED, layout)
	t.equal("authority holds every requested vessel",
		int(simulator.summary().get("vessel_count", 0)), VESSEL_COUNT)

	# One sample per internal fixed step, taken from the simulator's own
	# constant rather than a number typed here: whatever the authority's step
	# becomes, every step it takes is still observed. `advance()` accumulates,
	# so stepping it in FIXED_STEP_S slices is the same trajectory as one bulk
	# call — the sampling does not change what is being sampled.
	var step_s: float = ShippingLaneTrafficSimulator.FIXED_STEP_S
	var step_count := int(SIMULATED_SECONDS / step_s)

	# The bound is the PRODUCER's own resolution, read off the layout at runtime
	# rather than typed in (REALITY.md §4a — assert the property, not a number
	# you observed once). `WaterwayNavigation._ensure_sea_grid` builds the
	# open-water A* grid directly on this raster: one grid point per raster
	# cell, `cell_size_m` apart, marked solid where the cell centre reads under
	# `ROUTE_SHORE_CLEARANCE_M`. Land is therefore only ever inspected at cell
	# centres, and one cell is the finest the router can be held to at all. A
	# vessel further inland than that is somewhere the routing grid never
	# looked. If the raster resolution changes, this bound changes with it.
	#
	# Measured on this scenario, the deepest excursion any vessel makes is
	# 8.08 m against a 156.25 m cell — 5 % of the bound — so it is not a
	# threshold fitted to today's output. It is also LOOSE, and the honest
	# limit was measured rather than assumed: dropping the router's shore
	# clearance to -100 m puts 3 028 samples on land, 122.96 m deep, and this
	# check stays GREEN. At -400 m it goes red with 12 098 breaches. A defect
	# that beaches vessels by less than one raster cell is invisible here.
	#
	# Every negative sample in this scenario is on an open-water leg. Under
	# lane control the worst clearance measured is +33.26 m here, and +4.86 m
	# on a port feeder at seed 77127 — which is why a strict `> 0` for
	# lane-controlled vessels is NOT asserted: the port basin is deliberately
	# dredged into the immutable macro coastline (see the exemption in
	# `ShippingLaneNetworkBuilder.validate`), so a berthing vessel reading
	# negative there is the design, not a defect.
	var land_bound := -layout.cell_size_m

	var worst_distance := INF
	var worst_note := ""
	var breaches := 0
	var samples := 0
	var negative_samples := 0
	var moved_vessels: Dictionary = {}
	var previous_positions: Dictionary = {}
	for step_index in range(step_count):
		simulator.advance(step_s)
		for record in simulator.presentation_records():
			var vessel_id := str(record.get("id", ""))
			var position := record.get("position", Vector2.ZERO) as Vector2
			var distance := layout.sample_signed_distance(position)
			samples += 1
			if distance < 0.0:
				negative_samples += 1
			if distance <= land_bound:
				breaches += 1
			if distance < worst_distance:
				worst_distance = distance
				worst_note = "%s at t=%.0fs state=%s pos=%s sdf=%.2f m" % [
					vessel_id, float(step_index + 1) * step_s,
					str(record.get("state", "?")), position, distance]
			if previous_positions.has(vessel_id) \
					and (previous_positions[vessel_id] as Vector2) != position:
				moved_vessels[vessel_id] = true
			previous_positions[vessel_id] = position

	# Anti-vacuity. A loop that examined nothing, or a fleet frozen at its
	# staging positions, would satisfy the land property without ever testing
	# it. `TestReport` already fails a run with zero checks; these three make
	# the land check itself non-empty.
	t.equal("every vessel was sampled at every authority step",
		samples, VESSEL_COUNT * step_count)
	t.equal("no vessel spends the whole window motionless",
		moved_vessels.size(), VESSEL_COUNT)
	t.check("traffic actually moves — the fleet completes port-to-port trips",
		int(simulator.summary().get("trips_completed", 0)) > 0)

	# The property itself.
	print("  land: %d samples, %d with negative clearance, worst %s (bound %.2f m)" % [
		samples, negative_samples, worst_note, land_bound])
	print("  fleet: %d of %d vessels moved" % [moved_vessels.size(), VESSEL_COUNT])
	t.equal("no vessel is ever driven further inland than the coastline's own resolution",
		breaches, 0)

	print("  elapsed %.1f s" % [float(Time.get_ticks_msec() - started) / 1000.0])
	t.finish(self)
