extends Node

## SCRATCH PROBE (leading underscore — the gate must not discover it).
## Does the port layout expander produce the same graph in lane B as it does in
## lane A? `port_layout_visual_capture` is a lane-A unit whose log shows
## `modules=1 open=3 morphology=?` for every size 0..8, which is either what the
## expander really produces today or lane A's compile cascade eating half of it.
## Same loop, same seed, run as a scene so the autoloads register.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_port_lane_probe.tscn

const SEED := 424242


func _ready() -> void:
	PortModuleCatalog.clear_cache()
	print("[probe] generation=%d" % PortDefinition.CURRENT_PORT_GENERATION_VERSION)
	for size in range(PortSizing.MAX_SIZE + 1):
		var definition := PortDefinition.new()
		definition.port_id = "capture-%d" % size
		definition.display_name = "SIZE %d" % size
		definition.size = size
		definition.region_kind = PortDefinition.RegionKind.MAINLAND
		definition.site_seed = SEED ^ (size * 9973)
		definition.has_lighthouse = size >= 2
		definition.has_fog_horn = size >= 1
		definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND

		var data := PortExpander.expand(definition, SEED)
		var graph := data.layout_graph
		var kinds: Dictionary = {}
		for instance_id in graph.module_ids():
			var placed := graph.modules[instance_id] as PortPlacedModule
			var module_definition := graph.module_definition(placed.module_id)
			var kind := "MISSING-DEFINITION" if module_definition == null else module_definition.kind
			kinds[kind] = int(kinds.get(kind, 0)) + 1
		print("[probe] size=%d modules=%d open=%d primary=%.0f total=%.0f attrs=%s kinds=%s"
			% [
				size,
				graph.modules.size(),
				graph.open_slots().size(),
				float(graph.primary_quay_pose().get("length_m", 0.0)),
				graph.total_quay_length_m(),
				str(graph.initial_attributes.keys()),
				str(kinds),
			])
	print("[probe] catalog modules=%d" % PortModuleCatalog.module_ids().size())
	get_tree().quit(0)
