extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const FIXED_SEED := 90210
const PORT_COUNT := 35

var _failures := PackedStringArray()


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var same_layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var other_layout: WorldLayout = GENERATOR.generate(FIXED_SEED + 1)
	var ports: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT)
	var repeated: Array[PortDefinition] = PLACER.place_ports(same_layout, PORT_COUNT)
	var varied: Array[PortDefinition] = PLACER.place_ports(other_layout, PORT_COUNT)
	_test_count_and_metadata(ports)
	_test_determinism(ports, repeated)
	_test_seed_variation(ports, varied)
	_test_geography(layout, ports)
	_test_routes(layout, ports)
	_finish(layout, ports)


func _test_count_and_metadata(ports: Array[PortDefinition]) -> void:
	_check(ports.size() == PORT_COUNT, "placer returns requested count")
	if ports.is_empty():
		return
	_check(ports[0].port_id == "port-home", "home port id is first")
	_check(ports[0].display_name == "Haugsvik", "home port name is first")
	var represented_sizes := {}
	for port in ports:
		represented_sizes[port.size] = int(represented_sizes.get(port.size, 0)) + 1
		_check(
			port.size >= PortSizing.MIN_SIZE and port.size <= PortSizing.MAX_SIZE,
			"%s size %d is inside the documented 0..8 range" % [port.port_id, port.size]
		)
		_check(
			port.size <= port.site_max_size,
			"%s size %d respects its geography ceiling %d"
			% [port.port_id, port.size, port.site_max_size]
		)
		_check(not port.site_id.is_empty(), "%s has stable site identity" % port.port_id)
		_check(port.site_seed != 0, "%s has deterministic site seed" % port.port_id)
		_check(port.has_explicit_rotation, "%s owns explicit yaw" % port.port_id)
		_check(
			port.ground_mode == PortDefinition.GroundMode.WORLD_TERRAIN,
			"%s uses world terrain" % port.port_id
		)
		_check(
			port.region_kind != PortDefinition.RegionKind.LEGACY_ISLAND,
			"%s has coastal region kind" % port.port_id
		)
	# Seed 90210 spreads 35 ports over six classes, the largest holding 12. A coast
	# that collapses to one or two archetypes is the regression this guards.
	_check(
		represented_sizes.size() >= 3,
		"coast supports multiple terminal archetypes (%d classes)" % represented_sizes.size()
	)
	var largest_bucket := 0
	for count in represented_sizes.values():
		largest_bucket = maxi(largest_bucket, int(count))
	_check(
		largest_bucket * 2 <= ports.size(),
		"no single size class dominates the coast (%d of %d)" % [largest_bucket, ports.size()]
	)


func _test_determinism(first: Array[PortDefinition], second: Array[PortDefinition]) -> void:
	_check(first.size() == second.size(), "same seed count is deterministic")
	if first.size() != second.size():
		return
	for i in range(first.size()):
		_check(
			first[i].to_dict() == second[i].to_dict(),
			"same seed port %d is byte-stable data" % i
		)


func _test_seed_variation(first: Array[PortDefinition], varied: Array[PortDefinition]) -> void:
	_check(varied.size() == PORT_COUNT, "different seed still returns requested count")
	if first.is_empty() or varied.is_empty():
		return
	var changed := first.size() != varied.size()
	for i in range(mini(first.size(), varied.size())):
		if first[i].world_position != varied[i].world_position \
				or first[i].size != varied[i].size \
				or not is_equal_approx(first[i].rotation_y, varied[i].rotation_y):
			changed = true
			break
	_check(changed, "different layout seed changes placement")


func _test_geography(layout: WorldLayout, ports: Array[PortDefinition]) -> void:
	_check(PLACER.max_size_for_quay_half(79.0) < 0, "too-short quay admits no size")
	_check(PLACER.max_size_for_quay_half(80.0) == 0, "80 m half fits size 0")
	_check(PLACER.max_size_for_quay_half(110.0) == 1, "110 m half fits size 1")
	_check(PLACER.max_size_for_quay_half(150.0) == 2, "150 m half fits size 2")
	_check(PLACER.max_size_for_quay_half(260.0) == 4, "260 m half fits size 4")
	var errors := PLACER.validate_ports(layout, ports, PLACER.MIN_SPACING_M)
	for error in errors:
		_check(false, error)
	for i in range(ports.size()):
		var port := ports[i]
		var point := Vector2(port.world_position.x, port.world_position.z)
		var seaward := PLACER.seaward_from_yaw(port.rotation_y)
		_check(layout.is_land(point), "%s origin is on land" % port.port_id)
		## ⚠ THE LAYOUT ARGUMENT IS LOAD-BEARING AND WAS MISSING. `world.gd:355`
		## expands every port as `PortExpander.expand(def, world_seed,
		## _world_layout)`; this line dropped the third argument, so the whole
		## geography block below was measuring a port generated against no coast
		## — the basin probe never runs, arms are never shortened, and the piers
		## are laid out for a shoreline the expander could not see. Measured over
		## all 35 ports / 66 quay stations (`tests/_port_placer_quay_branch_probe.gd`,
		## 2026-08-16), effective signed distance at the station origin:
		## WITH the layout 66/66 water, worst +14.82 m; WITHOUT it 0/66 water,
		## worst **−130.52 m** — a third of the pier roots buried more than
		## 100 m inland of the effective waterline. REALITY.md §3: assert against
		## the code path that can actually break, not the convenient one.
		var expanded := PortExpander.expand(port, layout.seed, layout)
		var root := expanded.layout_graph.modules.get("root") as PortPlacedModule
		var root_world := port.world_position \
				+ Basis(Vector3.UP, port.rotation_y) * root.position_m
		var root_xz := Vector2(root_world.x, root_world.z)
		_check(
			absf(layout.sample_signed_distance(root_xz)) < 160.0,
			"%s graph root hugs the shoreline band" % port.port_id,
		)
		_check(
			layout.sample_signed_distance(root_xz) > layout.sample_signed_distance(point) - 40.0,
			"%s graph root is not far inland of the site datum" % port.port_id,
		)
		var terrain_zones := expanded.flatten_zone_records()
		## ⚠ THIS BLOCK USED TO SELECT THE QUAY OUT OF `layout_graph.modules` —
		## `modules.get("arm_general")`, then a scan for a `kind == "quay"`
		## module — and guard the check with `if quay != null:`. Trade quays
		## moved into `initial_attributes["berth_plan"]` and `modules` now holds
		## one coast root, so BOTH lookups returned null on all 35 ports and the
		## check below ran ZERO times (REALITY.md §4, a negative against an empty
		## universe; §3d, a consumer reading a dead model). Measured 2026-08-16
		## in `tests/_port_placer_quay_branch_probe.gd`: 0 quay modules found,
		## 66 berth-plan stations available, and the property holds on every one
		## of them (worst effective signed distance: origin 14.82 m, tip 71.66 m
		## — both water) — so restoring it moves no red.
		var port_basis := Basis(Vector3.UP, port.rotation_y)
		var stations: Array = (
			expanded.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
		).get("quay_stations", []) as Array
		_check(
			not stations.is_empty(),
			"%s berth plan has a quay station to carve-test" % port.port_id,
		)
		for raw_station in stations:
			var station := raw_station as Dictionary
			## Root AND tip: the pier runs from the dock face out into the
			## basin, and it is the tip that a terrain pad can silently bury.
			for end_key in ["origin", "tip"]:
				var local := station.get(end_key, []) as Array
				if local.size() < 2:
					continue
				var end_world := port.world_position \
						+ port_basis * Vector3(float(local[0]), 0.0, float(local[1]))
				_check(
					WorldTerrainStreamer.sample_effective_signed_distance(
						layout,
						Vector2(end_world.x, end_world.z),
						terrain_zones,
					) >= 0.0,
					"%s quay carve keeps berth water open at %s of %s"
						% [port.port_id, end_key, str(station.get("id", "?"))],
				)
		_check(
			PLACER.is_land_footprint_valid(layout, point, seaward),
			"%s facilities footprint is land" % port.port_id
		)
		_check(
			PLACER.is_size_footprint_valid(layout, point, seaward, port.size),
			"%s size footprint is land" % port.port_id
		)
		_check(
			PLACER.has_seaward_clearance(layout, point, seaward),
			"%s local -Z has offshore water clearance" % port.port_id
		)
		var dock_face := point + seaward * PLACER.PLOT_HALF_DEPTH_M
		var dock_sd := layout.sample_signed_distance(dock_face)
		_check(
			dock_sd > -8.0 and dock_sd < 80.0,
			"%s quay face sits on/near the waterline" % port.port_id
		)
		var needed_half := float(PLACER.QUAY_HALF_LENGTH_BY_SIZE[PortSizing.normalized_size(port.size)])
		_check(
			PLACER.has_quay_clearance(layout, point, seaward, needed_half),
			"%s straight quay clears coastline corners" % port.port_id
		)
		var expected_yaw := PLACER.yaw_for_seaward(seaward)
		_check(
			absf(wrapf(port.rotation_y - expected_yaw, -PI, PI)) < 0.0001,
			"%s yaw maps local -Z seaward" % port.port_id
		)
		var dock_water := point + seaward * PLACER.APPROACH_START_M
		_check(
			layout.sample_signed_distance(dock_water) > 0.0,
			"%s dock face is water" % port.port_id
		)
		for j in range(i):
			var other := Vector2(ports[j].world_position.x, ports[j].world_position.z)
			_check(
				point.distance_to(other) >= PLACER.MIN_SPACING_M,
				"%s respects minimum port spacing" % port.port_id
			)


func _test_routes(layout: WorldLayout, ports: Array[PortDefinition]) -> void:
	for port in ports:
		var point := Vector2(port.world_position.x, port.world_position.z)
		var connection := PLACER.nearest_waterway_connection(layout, point)
		_check(
			not String(connection["waterway_id"]).is_empty(),
			"%s has nearest waterway graph edge" % port.port_id
		)
		_check(
			float(connection["distance_m"]) <= PLACER.MAX_WATERWAY_REACH_M,
			"%s lies within relaxed waterway reach" % port.port_id
		)
	if ports.size() >= 2:
		var a := Vector2(ports[0].world_position.x, ports[0].world_position.z)
		var b := Vector2(ports[-1].world_position.x, ports[-1].world_position.z)
		var route_ab := PLACER.navigable_route_distance(layout, a, b)
		var route_ba := PLACER.navigable_route_distance(layout, b, a)
		_check(is_finite(route_ab) and route_ab > 0.0, "waterway route is finite")
		_check(absf(route_ab - route_ba) < 0.5, "waterway route is symmetric")


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish(layout: WorldLayout, ports: Array[PortDefinition]) -> void:
	if _failures.is_empty():
		print(
			"CoastalPortPlacer tests: all checks passed; ports=%d seed=%d checksum=%s"
			% [ports.size(), layout.seed, layout.layout_checksum]
		)
		quit()
		return
	for failure in _failures:
		push_error("CoastalPortPlacer test: " + failure)
	quit(1)
