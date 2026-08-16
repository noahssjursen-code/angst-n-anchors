extends SceneTree

## Does a port BUILD on the pads it lays?
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/port_apron_draw_test.gd
##
## ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
##
## `tests/_port_layout_visual_capture.gd`'s report printed `pads=5 structures=0`
## on all nine port sizes, and that line was read as *"every port places apron
## pads and builds nothing on them"*. It was not a measurement.
## `land_plan.structure_count` was a literal `0` at its only producer, read by
## one debug-gizmo layer looping an array that is always empty and by that one
## `print`. Nothing about it could ever have been non-zero. The field is gone.
##
## What the port really draws had never been asserted anywhere: every check on
## the apron reads `land_plan`, which is the same dictionary the pads come out
## of. A check that reads the outline from its own producer is one derivation
## testing itself (REALITY.md §3, §4a), and it cannot tell a pad that is built
## on from a pad that is not — which is exactly the question that went unanswered
## for nine port generations.
##
## So this test asserts on the NODE TREE `PortLayoutGraphVisualizer` builds —
## the thing `PortPlot._rebuild()` puts in front of a player — and pairs it
## against the plan only to name what is missing. Two properties:
##
##   1. **Every apron pad carries drawn geometry, standing on the pad.** Not
##      "some mesh exists under ApronPads": each planned pad has its own site
##      node, that site draws at least one `MeshInstance3D`, and every mesh it
##      draws has its centre inside that pad's own footprint. A slab drawn at the
##      origin, or one pad's building drawn over another's plot, fails.
##   2. **The strip test.** Empty `apron_pads.pads`, rebuild, and the drawn pad
##      geometry must go to zero — otherwise property 1 could be passing on
##      scenery that has nothing to do with pads (REALITY.md §3d).
##
## ── THE REGISTER ────────────────────────────────────────────────────────────
##
## `land_plan` publishes three collections for the visualiser. Two are drawn.
## `apron_decor` is not: `PortLayoutGraphVisualizer._stamp_apron_decor()` is a
## real builder — eight prop kinds, lamps to hatch covers — with **no callers**,
## and `_rebuild()` carries the comment *"Apron props deferred"*. The props reach
## no frame on any port.
##
## Whether aprons should be dressed with props at all is an owner decision on
## record in STATE.md, so this file does not wire it and does not delete it. It
## REGISTERS it, in the shape `tests/signal_reach_test.gd` uses: the register is
## policed in both directions and can only shrink. It fails if a second
## collection goes dark, and it fails — telling you to delete the entry — the day
## the props are wired. It is not an approval, and it is not a claim that the
## empty apron is correct.
##
## `port_trade_profile_test`'s standing red, *"apron should sprinkle service
## props"*, is a check on `apron_decor.point_count`, a DIFFERENT collection from
## the pads, failing for a different reason (prop density near quay stations). It
## is not this defect, and nothing here makes it green.
##
## Gate lane: A (`--script`). No bare autoload identifiers.

const TestReport := preload("res://tests/support/test_report.gd")

const SEED := 424242
## Pads with a blueprint host it through a `PortStructureLod`, so the drawn
## geometry appears a frame or two after `configure()`.
const SETTLE_FRAMES := 4
## A pad footprint in metres, padded for the placeholder slab's own inset and
## for float error on the rotated rect.
const FOOTPRINT_SLOP_M := 1.0

## Collections `land_plan` publishes for `PortLayoutGraphVisualizer`, and the
## node each one is drawn into. **Frozen register — see the header.** Removing an
## entry from `UNDRAWN` is the fix; adding one needs a reason in STATE.md.
const UNDRAWN := ["apron_decor"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("port_apron_draw_test")
	PortModuleCatalog.clear_cache()
	var world := Node3D.new()
	root.add_child(world)

	var pads_seen := 0
	for size in range(PortSizing.MAX_SIZE + 1):
		var graph := _expand(size)
		var land := graph.initial_attributes.get("land_plan", {}) as Dictionary
		var pads: Array = ((land.get("apron_pads", {}) as Dictionary).get("pads", []) as Array)
		var vis := await _build(world, graph)

		if not t.check("size %d lays at least one apron pad" % size, not pads.is_empty()):
			vis.queue_free()
			continue
		var apron_root := vis.get_node_or_null("ApronPads")
		if not t.check("size %d draws an ApronPads node for its %d pads" % [size, pads.size()],
				apron_root != null):
			vis.queue_free()
			continue
		t.equal("size %d draws one site per planned pad" % size,
				apron_root.get_child_count(), pads.size())

		for raw in pads:
			var pad: Dictionary = raw
			pads_seen += 1
			var role := str(pad.get("role", "?"))
			var site := apron_root.get_node_or_null(NodePath(str(pad.get("id", role)))) as Node3D
			if not t.check("size %d pad %s has a drawn site" % [size, role], site != null):
				continue
			var meshes := _meshes(site)
			## The property: a pad is a building lot, so something stands on it.
			if not t.check(
					"size %d pad %s carries drawn geometry" % [size, role],
					not meshes.is_empty()):
				continue
			## And the property that says it stands on THIS pad: every mesh the
			## site draws has its centre inside the pad's own footprint. Stated
			## against the pad rectangle rather than against a distance constant,
			## so it survives a re-tune of either (REALITY.md §4a).
			var outside := 0
			var worst := 0.0
			for mesh in meshes:
				var centre := (mesh as MeshInstance3D).global_transform \
						* (mesh as MeshInstance3D).get_aabb().get_center()
				var slack := _outside_by_m(pad, Vector2(centre.x, centre.z))
				if slack > FOOTPRINT_SLOP_M:
					outside += 1
					worst = maxf(worst, slack)
			t.equal(
				"size %d pad %s draws %d meshes outside its own footprint (worst %.2f m)"
					% [size, role, outside, worst],
				outside,
				0,
			)
		vis.queue_free()
		await process_frame

	t.check("the pad sweep had pads to check (%d over %d sizes)"
			% [pads_seen, PortSizing.MAX_SIZE + 1], pads_seen >= PortSizing.MAX_SIZE + 1)

	## ── STRIP TEST ──────────────────────────────────────────────────────────
	## Delete the input, re-measure, compare. Without this, every check above
	## could be passing on geometry that has nothing to do with a pad.
	var strip_graph := _expand(2)
	var vis_full := await _build(world, strip_graph)
	var full_meshes := _meshes(vis_full.get_node_or_null("ApronPads")).size()
	vis_full.queue_free()
	await process_frame

	var strip_land := strip_graph.initial_attributes.get("land_plan", {}) as Dictionary
	var strip_pads := strip_land.get("apron_pads", {}) as Dictionary
	strip_pads["pads"] = []
	strip_pads["pad_count"] = 0
	var vis_strip := await _build(world, strip_graph)
	var stripped_meshes := _meshes(vis_strip.get_node_or_null("ApronPads")).size()
	vis_strip.queue_free()
	await process_frame

	t.check("strip test had pad geometry to remove (%d meshes)" % full_meshes, full_meshes > 0)
	t.equal("deleting the pads removes every drawn pad mesh", stripped_meshes, 0)

	## ── THE REGISTER ────────────────────────────────────────────────────────
	var register_graph := _expand(4)
	var vis_reg := await _build(world, register_graph)
	var reg_land := register_graph.initial_attributes.get("land_plan", {}) as Dictionary
	var published := {
		"apron_pads": [
			((reg_land.get("apron_pads", {}) as Dictionary).get("pads", []) as Array).size(),
			_child_count(vis_reg.get_node_or_null("ApronPads")),
		],
		"terrain_grid": [
			((reg_land.get("terrain_grid", {}) as Dictionary).get("points", []) as Array).size(),
			_child_count(vis_reg.get_node_or_null("LandDecor")),
		],
		"apron_decor": [
			((reg_land.get("apron_decor", {}) as Dictionary).get("points", []) as Array).size(),
			_child_count(vis_reg.get_node_or_null("ApronDecor")),
		],
	}
	for key in published:
		var planned := int((published[key] as Array)[0])
		var drawn := int((published[key] as Array)[1])
		print("  land_plan.%s: %d published, %d drawn" % [key, planned, drawn])
		t.check("land_plan.%s publishes something to draw" % key, planned > 0)
		if UNDRAWN.has(key):
			## Policed the other way: the day this is wired, this check goes RED
			## and the fix is to delete the entry from UNDRAWN, not to unwire it.
			t.equal(
				"REGISTER: land_plan.%s still reaches no node — when it does, drop it from UNDRAWN"
					% key,
				drawn,
				0,
			)
		else:
			t.equal("land_plan.%s draws one node per published entry" % key, drawn, planned)
	vis_reg.queue_free()

	t.finish(self)


func _expand(size: int) -> PortLayoutGraph:
	PortDataCache.clear()
	var definition := PortDefinition.new()
	definition.port_id = "apron-draw-%d" % size
	definition.display_name = "APRON %d" % size
	definition.size = size
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.site_seed = SEED ^ (size * 9973)
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
	return PortExpander.expand(definition, SEED).layout_graph


func _build(world: Node3D, graph: PortLayoutGraph) -> PortLayoutGraphVisualizer:
	var vis := PortLayoutGraphVisualizer.new()
	world.add_child(vis)
	vis.configure(graph)
	for _frame in range(SETTLE_FRAMES):
		await process_frame
	return vis


func _child_count(node: Node) -> int:
	return node.get_child_count() if node != null else 0


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


## Metres by which `world_xz` falls outside the pad's own rotated footprint.
## Zero when inside. Derived from the pad's origin, size and yaw — the same three
## fields the map draws it from — so the check and the picture cannot disagree
## about where a pad is.
func _outside_by_m(pad: Dictionary, world_xz: Vector2) -> float:
	var origin_arr: Array = pad.get("origin", []) as Array
	if origin_arr.size() < 2:
		return 0.0
	var size_arr: Array = pad.get("size_m", []) as Array
	var half := Vector2(
		(float(size_arr[0]) if size_arr.size() > 0 else 0.0) * 0.5,
		(float(size_arr[1]) if size_arr.size() > 1 else 0.0) * 0.5,
	)
	var local := (world_xz - Vector2(float(origin_arr[0]), float(origin_arr[1]))) \
			.rotated(-deg_to_rad(float(pad.get("yaw_deg", 0.0))))
	return maxf(maxf(absf(local.x) - half.x, absf(local.y) - half.y), 0.0)
