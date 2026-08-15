extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B scene, because
## BuildingFitout/DeckFitout preload BrickDoor, which names the WorldGateway
## autoload as a bare identifier.
##
## ONE QUESTION, asked of every API in this repo that writes something onto a
## grid: does it validate the placement against the grid it belongs to, and if
## not, what downstream would catch it?
##
## Measured 2026-08-15. The two grids are `BuildingGrid` and `DeckGrid` — grep
## for `func in_bounds` finds exactly those two files, which is what bounds the
## survey. Results, worst first:
##
##   • §4/§5 — a BrickLayout carrying all eight bricks `general_vessel` requires,
##     authored at 20x56 cells and written onto a 10x30 hull, certifies
##     **8/8 legal requirements, 0 errors, 0 warnings** and draws **0 of 8**
##     visuals. `BrickLayout.set_brick` takes no grid so it cannot refuse, and
##     `VesselCompliance._measure` never asks the grid; `DeckFitout._item_is_valid`
##     does, and silently drops every one. A legally-registered boat with no
##     helm, no nav lights and no mooring points anywhere on it.
##   • §8 — an off-hull `add_wall`/`add_deck`/`add_stair` is not refused, not
##     warned about, and IS drawn and collided: bake AABB 4x4 m -> **910x910 m**,
##     1 -> 17 colliders.
##   • §2 — `BuildingLayout.place_footprint` ignored the grid it was handed and
##     grew its own volume instead (8 -> 12), shifting every stored cell.
##     FIXED 2026-08-15; re-running this probe now prints `false` there.
##
## Run: xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##        --rendering-driver opengl3 --audio-driver Dummy \
##        res://tests/_placement_grid_survey.tscn


func _ready() -> void:
	print("=== 1. BuildingLayout.set_brick — own grid ===")
	var bl := BuildingLayout.new()
	bl.grid_size = Vector3i(8, 6, 8)
	print("  in-bounds (1,0,1)      -> ", bl.set_brick(Vector3i(1, 0, 1), "block"))
	print("  out-of-bounds (9,0,0)  -> ", bl.set_brick(Vector3i(9, 0, 0), "block"))
	print("  negative (-1,0,0)      -> ", bl.set_brick(Vector3i(-1, 0, 0), "block"))
	print("  stored cells           -> ", bl.count(), "  grid_size ", bl.grid_size)

	print("=== 2. BuildingLayout.place_footprint — caller's grid ===")
	var b2 := BuildingLayout.new()
	b2.grid_size = Vector3i(8, 6, 8)
	var g2 := b2.grid()
	b2.place_footprint(Vector3i(1, 0, 1), "foundation", 0, g2)
	b2.place_footprint(Vector3i(1, 1, 1), "block", 90, g2)
	b2.place_footprint(Vector3i(3, 0, 1), "block_door", 0, g2)
	b2.place_footprint(Vector3i(0, 0, 3), "block", 0, null, Color(0.7, 0.2, 0.15))
	b2.place_footprint(Vector3i(0, 0, 4), "floor", 0)
	b2.place_footprint(Vector3i(0, 0, 4), "block", 0)
	b2.erase_footprint_at(Vector3i(0, 0, 4))
	print("  before  grid_size ", b2.grid_size, "  primaries ", b2.iter_primary_cells().size())
	print("  yawed block at (1,1,1) -> ", b2.get_brick(Vector3i(1, 1, 1)))
	var accepted := b2.place_footprint(Vector3i(9, 0, 0), "block", 0, g2)
	print("  place at (9,0,0) with an 8-wide grid -> ", accepted)
	print("  after   grid_size ", b2.grid_size, "  primaries ", b2.iter_primary_cells().size())
	print("  cell (1,1,1) is now  -> ", b2.get_brick(Vector3i(1, 1, 1)))
	print("  cell (3,1,1) is now  -> ", b2.get_brick(Vector3i(3, 1, 1)))
	var fit := BuildingFitout.build(b2)
	print("  BuildingFitout children -> ", fit.get_child_count())
	fit.free()
	var rules := BuildingRules.validate(b2)
	print("  BuildingRules.ok -> ", rules.get("ok"), "  warnings ", rules.get("warnings"))

	print("=== 2b. does a REJECTED placement still mutate the layout? ===")
	var b2b := BuildingLayout.new()
	b2b.grid_size = Vector3i(8, 6, 8)
	b2b.place_footprint(Vector3i(1, 0, 1), "block", 0)
	var before_size := b2b.grid_size
	var r := b2b.place_footprint(Vector3i(9, 0, 0), "not_a_brick_in_any_vocabulary", 0, b2b.grid())
	print("  unknown-brick refusal -> ", r, " grid ", before_size, " -> ", b2b.grid_size)

	print("=== 3. BrickLayout.set_brick — NO grid argument at all ===")
	var grid_small := DeckGrid.from_hull(15.0, 5.0, 0.0, 2.0)
	print("  grid width/length -> ", grid_small.width, " x ", grid_small.length)
	var vl := BrickLayout.new()
	vl.hull_id = "fishing_trawler_small"
	vl.set_brick(Vector3i(3, 0, 5), "block")
	vl.set_brick(Vector3i(19, 0, 55), "block")   ## authored for a 20x56 hull
	vl.set_brick(Vector3i(-4, 0, -9), "block")
	print("  set_brick returns  -> (void — it cannot refuse)")
	print("  stored cells       -> ", vl.count())
	print("  in_bounds(19,0,55) -> ", grid_small.in_bounds(Vector3i(19, 0, 55)))
	print("  in_bounds(-4,0,-9) -> ", grid_small.in_bounds(Vector3i(-4, 0, -9)))

	print("=== 4. THE VESSEL CASE — a fully certified boat with nothing on it ===")
	## Every brick `general_vessel` requires, authored at cells from a 20x56 hull
	## and written onto a 10x30 grid. Side rules still read the right side, so the
	## ONLY thing wrong with this boat is that none of it is on the hull.
	var vc := BrickLayout.new()
	vc.hull_id = "fishing_trawler_small"
	vc.set_brick(Vector3i(5, 1, 55), "helm")
	vc.set_brick(Vector3i(1, 2, 55), "light_nav_port")
	vc.set_brick(Vector3i(8, 2, 55), "light_nav_stbd")
	vc.set_brick(Vector3i(5, 3, 55), "light_nav_white")
	for ix in [2, 3, 6, 7]:
		vc.set_brick(Vector3i(ix, 0, 55), "bollard")
	var off := 0
	for row in vc.iter_primary_cells():
		if not grid_small.in_bounds(row["cell"] as Vector3i):
			off += 1
	print("  bricks stored ", vc.count(), " of which OFF-GRID ", off)
	var rep := VesselCompliance.validate(vc, "fishing_trawler_small", "general_vessel", grid_small)
	print("  compliance ok -> ", rep.get("ok"))
	print("  errors        -> ", rep.get("errors"))
	print("  warnings      -> ", rep.get("warnings"))
	print("  checklist     -> ", VesselCompliance.checklist_summary(rep))
	var vout := VesselOutfit.validate(vc, "fishing_trawler_small", grid_small, {})
	print("  outfit ok     -> ", vout.get("ok"), "  errors ", vout.get("errors"))

	print("=== 5. does the fitout DRAW an off-grid brick? ===")
	var root := Node3D.new()
	add_child(root)
	var drawn := 0
	for row in vc.iter_primary_cells():
		var v := DeckFitout.create_item_visual(root, grid_small, row)
		if v != null:
			drawn += 1
	print("  visuals drawn out of ", vc.count(), " -> ", drawn)
	var v_in := DeckFitout.create_item_visual(
		root, grid_small, {"cell": Vector3i(3, 0, 5), "brick_id": "block", "yaw": 0}
	)
	print("  control, in-bounds -> ", v_in != null)
	root.queue_free()

	print("=== 6. BrickLayout.place_footprint / add_bulk_hold / add_container_pad ===")
	var vl2 := BrickLayout.new()
	print("  place_footprint in-bounds  -> ", vl2.place_footprint(Vector3i(3, 0, 5), "block", 0, grid_small))
	print("  place_footprint off-grid   -> ", vl2.place_footprint(Vector3i(19, 0, 55), "block", 0, grid_small))
	print("  add_bulk_hold off-grid     -> ", vl2.add_bulk_hold(Vector3i(19, 0, 55), "bulk_hold_6x12", 0, grid_small))
	print("  add_container_pad w/ grid  -> ", vl2.add_container_pad(Vector3i(16, 0, 48), Vector3i(19, 0, 51), grid_small))
	print("  add_container_pad w/ NULL  -> ", vl2.add_container_pad(Vector3i(16, 0, 48), Vector3i(19, 0, 51), null))
	print("  container pads stored      -> ", vl2.iter_container_pads().size())
	var out2 := VesselOutfit.validate(vl2, "fishing_trawler_small", grid_small, {})
	print("  outfit ok after null pad   -> ", out2.get("ok"), " errors ", out2.get("errors"))

	print("=== 7. StructurePlan.add_piece / add_item / add_wall — off-hull ===")
	var plan := StructurePlan.new()
	plan.hull_id = "fishing_trawler_small"
	var hg := HullRegistry.make_grid("fishing_trawler_small")
	print("  hull grid -> ", hg.width, " x ", hg.length)
	var p := plan.add_piece("wall_panel", Vector3i(400, 0, 400), 0, {"span": 2, "height": 2})
	print("  add_piece at (400,0,400) -> id ", p.get("id"), " (returns a dict, never refuses)")
	plan.add_item("cleat", Vector3(500.0, 0.0, 500.0))
	plan.add_item("net_drum", Vector3(500.0, 0.0, 500.0))
	plan.add_item("bulk_hold", Vector3(500.0, 0.0, 500.0))
	plan.add_wall(Vector3(900.0, 0.0, 900.0), "x", 10.0)
	plan.add_deck(Vector3(900.0, 0.0, 900.0), Vector2(10.0, 10.0))
	plan.add_stair(Vector3(900.0, 0.0, 900.0), "+x", 4.0)
	var po := PlanOutfit.validate(plan, "fishing_trawler_small", hg, {})
	print("  PlanOutfit ok -> ", po.get("ok"))
	print("  errors        -> ", po.get("errors"))
	print("  warnings      -> ", po.get("warnings"))

	print("=== 8. STRIP TEST — is the off-hull plan geometry actually DRAWN? ===")
	var strip := StructurePlan.new()
	strip.hull_id = "fishing_trawler_small"
	strip.add_deck(Vector3(0.0, 3.0, 0.0), Vector2(4.0, 4.0))
	var base_node := StructureBaker.bake(strip)
	var base_aabb := _aabb_of(base_node)
	var base_cols := StructureBaker.collect_colliders(strip).size()
	base_node.free()
	strip.add_wall(Vector3(900.0, 0.0, 900.0), "x", 10.0)
	strip.add_deck(Vector3(900.0, 0.0, 900.0), Vector2(10.0, 10.0))
	strip.add_stair(Vector3(900.0, 0.0, 900.0), "+x", 4.0)
	var off_node := StructureBaker.bake(strip)
	var off_aabb := _aabb_of(off_node)
	var off_cols := StructureBaker.collect_colliders(strip).size()
	off_node.free()
	print("  on-hull only  aabb ", base_aabb, "  colliders ", base_cols)
	print("  + off-hull    aabb ", off_aabb, "  colliders ", off_cols)

	get_tree().quit()


func _aabb_of(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var a := mi.mesh.get_aabb()
			a.position += mi.position
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		var sub := _aabb_of(child)
		if sub.size != Vector3.ZERO:
			if first:
				out = sub
				first = false
			else:
				out = out.merge(sub)
	return out
