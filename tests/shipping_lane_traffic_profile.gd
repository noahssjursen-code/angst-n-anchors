extends SceneTree

const FIXED_SEED := 77127
const PORT_COUNT := 8
const CHUNK_SECONDS := 1000.0
const CHUNK_COUNT := 12
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SIMULATOR := preload("res://scripts/traffic/shipping_lane_traffic_simulator.gd")


func _initialize() -> void:
	_checkpoint("start", true)
	var vessel_count := 24
	var chunk_count := CHUNK_COUNT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--vessels="):
			vessel_count = maxi(1, int(argument.trim_prefix("--vessels=")))
		elif argument.begins_with("--chunks="):
			chunk_count = maxi(0, int(argument.trim_prefix("--chunks=")))
	var build_started := Time.get_ticks_usec()
	var layout := GENERATOR.generate(FIXED_SEED) as WorldLayout
	_checkpoint("world layout generated")
	var names := PackedStringArray()
	for index in range(PORT_COUNT):
		names.append("Traffic Profile %02d" % index)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT, names)
	_checkpoint("ports placed")
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, FIXED_SEED, layout))
	var network := ShippingLaneNetworkBuilder.new().build(layout, ports)
	_checkpoint("lane network built")
	print("Traffic profile world/network: %.2f ms" % [
		float(Time.get_ticks_usec() - build_started) / 1000.0])
	_checkpoint("network timing printed")
	var simulator := SIMULATOR.new()
	_checkpoint("simulator configure started")
	simulator.configure(network, vessel_count, FIXED_SEED, layout)
	_checkpoint("simulator configured")
	print("Traffic profile build/configure: %.2f ms" % [
		float(Time.get_ticks_usec() - build_started) / 1000.0])
	var total_started := Time.get_ticks_usec()
	for chunk_index in range(chunk_count):
		var chunk_started := Time.get_ticks_usec()
		simulator.advance(CHUNK_SECONDS)
		var chunk_ms := float(Time.get_ticks_usec() - chunk_started) / 1000.0
		var summary := simulator.summary()
		print("Traffic profile %5.0fs: %8.2f ms | trips %d | states %s | collisions %d" % [
			float(chunk_index + 1) * CHUNK_SECONDS, chunk_ms,
			int(summary.get("trips_completed", 0)), JSON.stringify(summary.get("states", {})),
			int(summary.get("collisions", 0))])
	print("Traffic profile total simulation: %.2f ms" % [
		float(Time.get_ticks_usec() - total_started) / 1000.0])
	quit(0)


static func _checkpoint(label: String, truncate := false) -> void:
	var mode := FileAccess.WRITE if truncate else FileAccess.READ_WRITE
	var file := FileAccess.open("user://traffic_profile_progress.txt", mode)
	if file == null:
		return
	if not truncate:
		file.seek_end()
	file.store_line("%d %s" % [Time.get_ticks_msec(), label])
