extends SceneTree

## SCRATCH PROBE (underscore-prefixed, not a gate unit). Lane A (`--script`),
## the same lane `port_layout_brick_test` runs in with the same generator.
##
## ONE QUESTION: what does a player actually see where a harbour keeps its fuel?
## `entry_reach_test` says `scenes/systems/fuel_station.tscn` has no referrer.
## The register's reason says refuelling is "a harbour-master menu action, not
## this object", which is true of the FUNCTION and says nothing about the
## OBJECT. `PortLayoutGraphVisualizer._stamp_fuel_tank` exists and draws a grey
## cylinder with a FUEL label for any module of kind `service` tagged `fuel` —
## so before calling the scene superseded by that, somebody has to establish
## that such a module is ever placed. Grep says `PortLayoutGraph.attach_module`
## has no caller outside its own class; this measures the same thing through the
## production expander instead of trusting the grep (REALITY §3).
##
## It also asks the same of the OTHER fuel route, `land_plan.apron_pads` —
## `PortApronPadCatalog` declares a `fuel_bunker` pad in UNIVERSAL_DECORATIVE_V1
## and `_stamp_apron_pads` looks for a blueprint by role, falling back to
## `_stamp_apron_pad_placeholder` when none exists.
##
## Nothing is mutated. Three port sizes, one seed, printed not asserted.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")



func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:

	var layout := WORLD_LAYOUT_GENERATOR.generate(424242)

	var blueprint_ids := BuildingBlueprintCatalog.ids()
	print("[blueprints] on disk: %s" % [str(blueprint_ids)])
	for role in ["fuel_bunker", "general_warehouse"]:
		var found := BuildingBlueprintCatalog.find_for_pad(role, "pad_1x1")
		var found2 := BuildingBlueprintCatalog.find_for_pad(role, "pad_2x2")
		print("[blueprints] role %-18s pad_1x1 -> %s   pad_2x2 -> %s"
			% [role,
				"<none>" if found == null else found.blueprint_id,
				"<none>" if found2 == null else found2.blueprint_id])

	for size in [0, 4, 8]:
		var definition := PortDefinition.new()
		definition.port_id = "fuel-probe-%d" % size
		definition.display_name = "Fuel Probe %d" % size
		definition.size = size
		definition.region_kind = PortDefinition.RegionKind.MAINLAND
		definition.site_seed = 424242
		definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		definition.world_position = Vector3(12000.0, 0.0, -8000.0)
		definition.rotation_y = 0.4
		definition.has_explicit_rotation = true
		definition.has_lighthouse = true
		definition.has_fog_horn = true

		var expanded := PortExpander.expand(definition, 424242, layout)
		var graph: PortLayoutGraph = expanded.layout_graph
		if graph == null:
			print("[size %d] NO GRAPH" % size)
			continue
		var kinds := {}
		for instance_id in graph.modules:
			var placed: PortPlacedModule = graph.modules[instance_id]
			var d := graph.module_definition(placed.module_id)
			var key := "%s/%s" % [placed.module_id, "?" if d == null else d.kind]
			kinds[key] = int(kinds.get(key, 0)) + 1
		print("[size %d] graph.modules = %d  %s" % [size, graph.modules.size(), str(kinds)])

		var land_plan: Dictionary = graph.initial_attributes.get("land_plan", {}) as Dictionary
		var pads: Array = (land_plan.get("apron_pads", {}) as Dictionary).get("pads", []) as Array
		var roles := {}
		for raw in pads:
			var role := str((raw as Dictionary).get("role_id", (raw as Dictionary).get("id", "?")))
			roles[role] = int(roles.get(role, 0)) + 1
		print("[size %d] apron pads = %d  roles %s" % [size, pads.size(), str(roles)])

		## The two flags the map overlay prints to the player as FACILITIES.
		print("[size %d] initial_attributes has has_lighthouse=%s has_fog_horn=%s"
			% [size,
				str(graph.initial_attributes.has("has_lighthouse")),
				str(graph.initial_attributes.has("has_fog_horn"))])
		var data: PortData = expanded
		if data != null:
			print("[size %d] PortData: has_fuel_point=%s has_lighthouse=%s has_fog_horn=%s features=%s"
				% [size, data.has_fuel_point, data.has_lighthouse, data.has_fog_horn,
					str(data.features)])

	## NO CHECK IS RECORDED HERE ON PURPOSE. An earlier draft ended with
	## `t.check("probe ran", true)`, which is REALITY §4 exactly — a check that
	## cannot fail. This file is an observation, not a property: everything it
	## establishes is in the lines above, and a reader has to look at them.
	print("_fuel_facility_probe: printed, asserted nothing (see REALITY §4)")
	quit(0)
