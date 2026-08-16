extends SceneTree

## SCRATCH PROBE (leading underscore — the gate does not score it).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_apron_reality_probe.gd
##
## Answers three separate questions the "empty apron" claim conflates:
##   1. what `land_plan.structure_count` actually is (it was a literal `0`;
##      DELETED 2026-08-16, so this column now prints `-1` = key absent)
##   2. whether anything is DRAWN on an apron pad, measured by walking the
##      visualiser's node tree, plus a strip test (delete the pads, re-measure)
##   3. how many `apron_decor` props each size produces, and whether the
##      visualiser draws any of them

const SEED := 424242


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var world := Node3D.new()
	root.add_child(world)

	print("size | pads | decor | structure_count | ApronPads kids | pad meshes | ApronDecor | LandDecor kids")
	for size in range(PortSizing.MAX_SIZE + 1):
		var data := _expand(size)
		var graph := data.layout_graph
		var land := graph.initial_attributes.get("land_plan", {}) as Dictionary
		var pads: Array = ((land.get("apron_pads", {}) as Dictionary).get("pads", []) as Array)
		var decor := int((land.get("apron_decor", {}) as Dictionary).get("point_count", 0))

		var vis := PortLayoutGraphVisualizer.new()
		world.add_child(vis)
		vis.configure(graph)
		await process_frame
		var apron_root := vis.get_node_or_null("ApronPads")
		var decor_root := vis.get_node_or_null("ApronDecor")
		var land_root := vis.get_node_or_null("LandDecor")
		print("%4d | %4d | %5d | %15d | %14d | %10d | %10s | %d"
			% [
				size,
				pads.size(),
				decor,
				int(land.get("structure_count", -1)),
				apron_root.get_child_count() if apron_root != null else -1,
				_mesh_count(apron_root),
				"yes" if decor_root != null else "NO",
				land_root.get_child_count() if land_root != null else -1,
			])
		if size == 2:
			for raw in pads:
				var pad: Dictionary = raw
				var role := str(pad.get("role", ""))
				var site := apron_root.get_node_or_null(NodePath(str(pad.get("id", role)))) \
						if apron_root != null else null
				var blueprint := BuildingBlueprintCatalog.find_for_pad(
					role, str(pad.get("pad_template_id", "")))
				print("   pad %-18s tpl=%-8s site=%s meshes=%d blueprint=%s"
					% [
						role,
						str(pad.get("pad_template_id", "")),
						"yes" if site != null else "MISSING",
						_mesh_count(site),
						blueprint.blueprint_id if blueprint != null else "-none-",
					])
		vis.queue_free()
		await process_frame

	## ── STRIP TEST — delete the pads from the plan, rebuild, re-measure ──
	var data2 := _expand(2)
	var graph2 := data2.layout_graph
	var vis_a := PortLayoutGraphVisualizer.new()
	world.add_child(vis_a)
	vis_a.configure(graph2)
	await process_frame
	var full := _mesh_count(vis_a)
	var full_pads := _mesh_count(vis_a.get_node_or_null("ApronPads"))
	vis_a.queue_free()
	await process_frame

	var land2 := graph2.initial_attributes.get("land_plan", {}) as Dictionary
	var pads2 := land2.get("apron_pads", {}) as Dictionary
	pads2["pads"] = []
	pads2["pad_count"] = 0
	var vis_b := PortLayoutGraphVisualizer.new()
	world.add_child(vis_b)
	vis_b.configure(graph2)
	await process_frame
	var stripped := _mesh_count(vis_b)
	vis_b.queue_free()
	await process_frame

	print("")
	print("STRIP TEST size 2: as shipped %d visualiser meshes (%d of them under ApronPads)"
		% [full, full_pads])
	print("STRIP TEST size 2: pads deleted %d meshes  -> delta %d"
		% [stripped, full - stripped])
	quit(0)


func _expand(size: int) -> PortData:
	PortDataCache.clear()
	var definition := PortDefinition.new()
	definition.port_id = "probe-%d" % size
	definition.display_name = "PROBE %d" % size
	definition.size = size
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.site_seed = SEED ^ (size * 9973)
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
	return PortExpander.expand(definition, SEED)


func _mesh_count(node: Node) -> int:
	if node == null:
		return 0
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _mesh_count(child)
	return n
