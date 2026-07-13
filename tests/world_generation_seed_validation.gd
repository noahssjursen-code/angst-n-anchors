extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const TERRAIN := preload("res://scripts/world/world_terrain_streamer.gd")
const NAVIGATION := preload("res://scripts/navigation/waterway_navigation.gd")
const SEEDS := [42, 90210]

var _failures := PackedStringArray()


func _initialize() -> void:
	print("World seed validation: starting")
	var checksums := PackedStringArray()
	var total_started := Time.get_ticks_msec()
	var slowest_ms := 0
	for seed in SEEDS:
		var started := Time.get_ticks_msec()
		var layout: WorldLayout = GENERATOR.generate(seed)
		var generation_ms := Time.get_ticks_msec() - started
		slowest_ms = maxi(slowest_ms, generation_ms)
		checksums.append(layout.layout_checksum)
		var ports: Array[PortDefinition] = PORT_PLACER.place_ports(layout, 35)
		_validate_seed(seed, layout, ports)
	_check(_unique_count(checksums) == SEEDS.size(), "representative seeds produce distinct layouts")
	if _failures.is_empty():
		print(
			"World seed validation: %d seeds passed in %d ms (slowest layout %d ms)"
			% [SEEDS.size(), Time.get_ticks_msec() - total_started, slowest_ms]
		)
		quit()
		return
	for failure in _failures:
		push_error("World seed validation: " + failure)
	quit(1)


func _validate_seed(seed: int, layout: WorldLayout, ports: Array[PortDefinition]) -> void:
	_check(ports.size() == 35, "seed %d returns all ports" % seed)
	var placement_errors := PORT_PLACER.validate_ports(layout, ports)
	for error in placement_errors:
		_check(false, "seed %d: %s" % [seed, error])
	var navigation := NAVIGATION.new(layout)
	var regions := PackedInt32Array()
	regions.resize(4)
	var flatten_zones := TERRAIN.make_flatten_zones(ports)
	for i in range(ports.size()):
		var port := ports[i]
		var point := Vector2(port.world_position.x, port.world_position.z)
		regions[int(port.region_kind)] += 1
		_check(
			navigation.is_open_ocean_reachable(point, PORT_PLACER.MAX_WATERWAY_REACH_M),
			"seed %d %s reaches open ocean" % [seed, port.port_id],
		)
		_check(
			is_zero_approx(TERRAIN.sample_terrain_height(layout, point, flatten_zones)),
			"seed %d %s pad is sea-level flat" % [seed, port.port_id],
		)
	_check(regions[PortDefinition.RegionKind.MAINLAND] > 0, "seed %d has mainland ports" % seed)
	_check(regions[PortDefinition.RegionKind.FJORD] > 0, "seed %d has fjord ports" % seed)
	_check(regions[PortDefinition.RegionKind.ARCHIPELAGO] > 0, "seed %d has archipelago ports" % seed)


func _unique_count(values: PackedStringArray) -> int:
	var unique := {}
	for value in values:
		unique[value] = true
	return unique.size()


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)
