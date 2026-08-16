extends SceneTree

## SCRATCH PROBE — leading underscore, the gate must not score it.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_stale_reader_probe.gd
##
## Sibling sweep for the `modules` → `berth_plan` migration. Every site that
## walks `module_ids()` expecting to see berths is wrong the same way
## `bounds()` was. This measures, per site, what it actually sees.

const SEED := 424242
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var layout := WORLD_LAYOUT_GENERATOR.generate(SEED)
	var quay_modules_seen := 0
	var road_modules_seen := 0
	var ports := 0
	for size in range(PortSizing.MAX_SIZE + 1):
		for pass_label in ["open", "terrain"]:
			var d := PortDefinition.new()
			d.port_id = "%s-%d" % [pass_label, size]
			d.display_name = "SIZE %d" % size
			d.size = size
			d.region_kind = PortDefinition.RegionKind.MAINLAND
			d.site_seed = SEED ^ (size * 9973)
			d.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
			d.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
			var data := PortExpander.expand(
				d, SEED, null if pass_label == "open" else layout
			)
			var graph := data.layout_graph
			ports += 1
			var kinds: Array = []
			for instance_id in graph.module_ids():
				var placed := graph.modules[instance_id] as PortPlacedModule
				var definition := graph.module_definition(placed.module_id)
				var kind := "<null-def>" if definition == null else definition.kind
				kinds.append("%s:%s" % [instance_id, kind])
				if definition != null and definition.kind == "quay":
					quay_modules_seen += 1
				if definition != null and definition.kind == "road":
					road_modules_seen += 1
			var stations: Array = (graph.initial_attributes.get("berth_plan", {}) as Dictionary) \
					.get("quay_stations", []) as Array
			var zones := graph.flatten_zone_records(Vector3.ZERO, 0.0)
			var envelope := 0
			var forest := 0
			for raw in zones:
				var rec := raw as Dictionary
				if str(rec.get("facility_id", "")).ends_with(":site_envelope"):
					envelope += 1
				if bool(rec.get("forest_clear_only", false)):
					forest += 1
			## Are the land_plan apron pads inside bounds() too?
			var box := graph.bounds()
			var blo := Vector2(box.position.x, box.position.z)
			var bhi := Vector2(box.position.x + box.size.x, box.position.z + box.size.z)
			var pads: Array = ((graph.initial_attributes.get("land_plan", {}) as Dictionary)
					.get("apron_pads", {}) as Dictionary).get("pads", []) as Array
			var pad_out := 0
			var pad_worst := 0.0
			for raw_pad in pads:
				var pad := raw_pad as Dictionary
				var centre := pad.get("center_m", pad.get("center", [])) as Array
				var extent := pad.get("size_m", pad.get("size", [])) as Array
				if centre == null or centre.size() < 2 or extent == null or extent.size() < 2:
					continue
				var hx := float(extent[0]) * 0.5
				var hz := float(extent[1]) * 0.5
				for corner in [
					Vector2(float(centre[0]) - hx, float(centre[1]) - hz),
					Vector2(float(centre[0]) + hx, float(centre[1]) - hz),
					Vector2(float(centre[0]) + hx, float(centre[1]) + hz),
					Vector2(float(centre[0]) - hx, float(centre[1]) + hz),
				]:
					var c := corner as Vector2
					var o := maxf(maxf(maxf(blo.x - c.x, c.x - bhi.x), 0.0),
							maxf(maxf(blo.y - c.y, c.y - bhi.y), 0.0))
					if o > 0.001:
						pad_out += 1
						pad_worst = maxf(pad_worst, o)
			print("           apron pads=%d corners outside bounds()=%d worst=%.2f m"
				% [pads.size(), pad_out, pad_worst])
			print("%-8s size %d | modules=%d %s | quay_stations=%d | footprints=%d | flatten records=%d (site_envelope=%d forest_clear=%d) | arm_general=%s"
				% [pass_label, size, graph.modules.size(), str(kinds), stations.size(),
					graph.local_footprints().size(), zones.size(), envelope, forest,
					str(graph.modules.has("arm_general"))])
	print("\nOVER %d PORTS: quay-kind modules seen = %d ; road-kind modules seen = %d"
		% [ports, quay_modules_seen, road_modules_seen])
	print("  -> coastal_port_placer_test.gd:123-142 selects `quay` from those modules;")
	print("     port_layout_graph.spawn_local_position() falls back to road modules;")
	print("     port_expander._count_berths() falls back to quay modules.")
	quit(0)
