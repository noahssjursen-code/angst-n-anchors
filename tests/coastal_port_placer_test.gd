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
		represented_sizes[port.size] = true
		_check(port.size >= 0, "%s has a size class" % port.port_id)
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
	_check(represented_sizes.size() >= 2, "coast supports multiple terminal archetypes")


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
	_check(PLACER.max_size_for_quay_half(23.0) < 0, "too-short quay admits no size")
	_check(PLACER.max_size_for_quay_half(24.0) == 0, "24 m half fits size 0")
	_check(PLACER.max_size_for_quay_half(100.0) == 2, "100 m half fits size 2")
	_check(PLACER.max_size_for_quay_half(240.0) == 4, "240 m half fits size 4")
	var errors := PLACER.validate_ports(layout, ports, PLACER.MIN_SPACING_M)
	for error in errors:
		_check(false, error)
	for i in range(ports.size()):
		var port := ports[i]
		var point := Vector2(port.world_position.x, port.world_position.z)
		var seaward := PLACER.seaward_from_yaw(port.rotation_y)
		_check(layout.is_land(point), "%s origin is on land" % port.port_id)
		var expanded := PortExpander.expand(port, layout.seed)
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
		var quay := expanded.layout_graph.modules.get("arm_general") as PortPlacedModule
		if quay == null:
			for instance_id in expanded.layout_graph.module_ids():
				var placed := expanded.layout_graph.modules[instance_id] as PortPlacedModule
				var module := expanded.layout_graph.module_definition(placed.module_id)
				if module != null and module.kind == "quay":
					quay = placed
					break
		if quay != null:
			var quay_world := port.world_position \
					+ Basis(Vector3.UP, port.rotation_y) * quay.position_m
			var quay_xz := Vector2(quay_world.x, quay_world.z)
			_check(
				WorldTerrainStreamer.sample_effective_signed_distance(
					layout,
					quay_xz,
					terrain_zones,
				) >= 0.0,
				"%s quay carve keeps berth water open" % port.port_id,
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
