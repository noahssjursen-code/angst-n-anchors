extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## Dumps EVERY key `PortExpander.chart_summary` publishes, for every port of the
## established measurement base (six seeds x 35 ports), to a JSON file. Run once
## before a change and once after, then diff the two files.
##
## Whole structures, not summaries: the previous wave's under-measurement came
## from comparing a polyline by `.size()` and quays by a sum. Every value here is
## serialized in full, keys sorted, so a change anywhere in the published dossier
## shows up as a line in the diff.
##
## Output path comes from the OUT environment variable.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817, 90210, 777, 20260816, 31337]


func _initialize() -> void:
	var out_path := OS.get_environment("OUT")
	if out_path.is_empty():
		out_path = "user://summary_dump.json"
	var rows: Array = []
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		WeatherField.world_seed = int(world_seed)
		for port in ports:
			PortDataCache.clear()
			var fresh := PortDefinition.from_dict(port.to_dict())
			var summary := PortExpander.chart_summary(fresh, int(world_seed), layout)
			## The definition chart_summary promises not to touch, read back AFTER
			## the call so a broken restore shows up in the diff as well.
			var line: Array = ["%d|%s" % [int(world_seed), port.port_id]]
			var keys: Array = summary.keys()
			keys.sort()
			for key in keys:
				line.append("%s=%s" % [str(key), str(summary[key])])
			line.append("definition_after_call=%s" % str(fresh.to_dict()))
			rows.append("  ".join(PackedStringArray(line)))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot open %s" % out_path)
		quit(1)
		return
	for row in rows:
		file.store_line(str(row))
	file.close()
	print("wrote %d rows to %s" % [rows.size(), out_path])
	quit(0)
