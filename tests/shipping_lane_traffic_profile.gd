extends SceneTree

const DEFAULT_SEED := 42
const DEFAULT_PORT_COUNT := 35
const DEFAULT_VESSEL_COUNT := 250
const CHUNK_SECONDS := 1000.0
const CHUNK_COUNT := 12
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SIMULATOR := preload("res://scripts/traffic/shipping_lane_traffic_simulator.gd")
const WORLD_PORT_NAMES := preload("res://scripts/world/world_port_names.gd")


func _initialize() -> void:
	_checkpoint("start", true)
	var scenario_seed := DEFAULT_SEED
	var port_count := DEFAULT_PORT_COUNT
	var vessel_count := DEFAULT_VESSEL_COUNT
	var world_size_m := 40000.0
	var chunk_count := CHUNK_COUNT
	var chunk_seconds := CHUNK_SECONDS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			scenario_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--ports="):
			port_count = maxi(2, int(argument.trim_prefix("--ports=")))
		elif argument.begins_with("--vessels="):
			vessel_count = maxi(1, int(argument.trim_prefix("--vessels=")))
		elif argument.begins_with("--world-size="):
			world_size_m = maxf(10000.0, float(argument.trim_prefix("--world-size=")))
		elif argument.begins_with("--chunks="):
			chunk_count = maxi(0, int(argument.trim_prefix("--chunks=")))
		elif argument.begins_with("--chunk-seconds="):
			chunk_seconds = maxf(0.5, float(argument.trim_prefix("--chunk-seconds=")))
	var build_started := Time.get_ticks_usec()
	var layout := GENERATOR.generate(scenario_seed, WorldConfig.ARCHETYPE_PATH,
		world_size_m) as WorldLayout
	_checkpoint("world layout generated")
	var names := PackedStringArray()
	for name in WORLD_PORT_NAMES.NAMES:
		names.append(name)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, port_count, names)
	_checkpoint("ports placed")
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, scenario_seed, layout))
	var network_builder := ShippingLaneNetworkBuilder.new()
	var network := network_builder.build(layout, ports)
	var validation: Array[Dictionary] = network_builder.validate(network, layout)
	var validation_counts: Dictionary = {}
	var validation_samples: Array[Dictionary] = []
	for issue in validation:
		var key := "%s:%s" % [str(issue.get("severity", "unknown")),
			str(issue.get("code", "unknown"))]
		validation_counts[key] = int(validation_counts.get(key, 0)) + 1
		if validation_samples.size() < 12:
			var sample := issue.duplicate(true)
			var source := str(issue.get("source_id", issue.get("source", "")))
			var pieces := source.split(":")
			if pieces.size() >= 2 and pieces[0] in ["port", "ramp"]:
				var source_port_id := str(pieces[1])
				var issue_position := issue.get("position", Vector2.INF) as Vector2
				var nearest_gate_m := INF
				for gate_id_value in network.port_gate_nodes.get(source_port_id, []) as Array:
					var gate := network.node(str(gate_id_value))
					if not gate.is_empty():
						nearest_gate_m = minf(nearest_gate_m, issue_position.distance_to(
							gate.get("position", issue_position) as Vector2))
				if nearest_gate_m < INF:
					sample["nearest_gate_m"] = snappedf(nearest_gate_m, 0.1)
			validation_samples.append(sample)
	print("Traffic network builder profile: %s" % [network_builder.build_profile])
	print("Traffic network validation: %d issues | %s | samples %s" % [
		validation.size(), JSON.stringify(validation_counts),
		JSON.stringify(validation_samples)])
	var warned_ports: Dictionary = {}
	for issue in validation:
		if str(issue.get("code", "")) != "shore_clearance":
			continue
		var source_parts := str(issue.get("source_id", "")).split(":")
		if source_parts.size() >= 2:
			warned_ports[str(source_parts[1])] = true
	for warned_port_id_value in warned_ports.keys():
		var warned_port_id := str(warned_port_id_value)
		var gate_diagnostics: Array[Dictionary] = []
		for gate_id_value in network.port_gate_nodes.get(warned_port_id, []) as Array:
			var gate := network.node(str(gate_id_value))
			gate_diagnostics.append({"id": gate_id_value,
				"position": gate.get("position", Vector2.ZERO),
				"outbound": gate.get("outbound_vector", Vector2.ZERO),
				"sdf": layout.sample_signed_distance(gate.get("position", Vector2.ZERO) as Vector2)})
		var ramp_diagnostics: Array[Dictionary] = []
		for ramp in network.ramps_for_port(warned_port_id):
			var ramp_id := str(ramp.get("id", ""))
			ramp_diagnostics.append({"id": ramp_id, "position": ramp.get("position", Vector2.ZERO),
				"sdf": layout.sample_signed_distance(ramp.get("position", Vector2.ZERO) as Vector2)})
		print("Traffic warning port %s gates=%s ramps=%s" % [warned_port_id,
			JSON.stringify(gate_diagnostics), JSON.stringify(ramp_diagnostics)])
	_checkpoint("lane network built")
	print("Traffic profile world/network: %.2f ms" % [
		float(Time.get_ticks_usec() - build_started) / 1000.0])
	_checkpoint("network timing printed")
	var simulator := SIMULATOR.new()
	_checkpoint("simulator configure started")
	simulator.configure(network, vessel_count, scenario_seed, layout)
	_checkpoint("simulator configured")
	print("Traffic profile build/configure: %.2f ms" % [
		float(Time.get_ticks_usec() - build_started) / 1000.0])
	var total_started := Time.get_ticks_usec()
	for chunk_index in range(chunk_count):
		var chunk_started := Time.get_ticks_usec()
		simulator.advance(chunk_seconds)
		var chunk_ms := float(Time.get_ticks_usec() - chunk_started) / 1000.0
		var summary := simulator.summary()
		print("Traffic profile %5.0fs: %8.2f ms | trips %d | states %s | modes %s | overtakes %d | collisions %d" % [
			float(chunk_index + 1) * chunk_seconds, chunk_ms,
			int(summary.get("trips_completed", 0)), JSON.stringify(summary.get("states", {})),
			JSON.stringify(summary.get("passage_modes", {})), int(summary.get("overtakes", 0)),
			int(summary.get("collisions", 0))])
	print("Traffic profile total simulation: %.2f ms" % [
		float(Time.get_ticks_usec() - total_started) / 1000.0])
	var report_path := "user://traffic_live_world_report.txt"
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(simulator.generate_report())
	var summary_path := "user://traffic_live_world_summary.json"
	var summary_file := FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file != null:
		summary_file.store_string(JSON.stringify(simulator.summary(), "  "))
	print("Traffic profile artifacts: %s | %s" % [
		ProjectSettings.globalize_path(report_path), ProjectSettings.globalize_path(summary_path)])
	quit(0)


static func _checkpoint(label: String, truncate := false) -> void:
	var mode := FileAccess.WRITE if truncate else FileAccess.READ_WRITE
	var file := FileAccess.open("user://traffic_profile_progress.txt", mode)
	if file == null:
		return
	if not truncate:
		file.seek_end()
	file.store_line("%d %s" % [Time.get_ticks_msec(), label])
