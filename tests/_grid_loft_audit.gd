extends Node

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_grid_loft_audit.tscn
##
## DOES THE GRID OFFER CELLS THE HULL DOES NOT HAVE — INDEPENDENTLY MEASURED?
##
## `_figure_offship_survey` recorded hull_45x16_cat at +6.639 m of cell-centre
## overhang. This probe re-takes that number from scratch rather than re-running
## that rig: its half-breadth reader is written HERE, from the station table's
## documented shape (`section` = Array[Vector2(y, half_beam)], sorted by y), and
## is then cross-checked against the shipped `_hull_half_breadth_at` on the same
## z values so a disagreement between the two is visible rather than assumed.
##
## Three readings of "where is the hull", because for a catamaran they differ:
##
##   LOFT       `boat.hull_stations` — what the shipped off-ship check reads.
##   DRAWN      the AABB of every MeshInstance3D under HullVisual, in boat-local
##              space. This is the geometry a player SEES.
##   COLLIDED   the AABB of every CollisionShape3D on the body, plus the WalkDeck
##              slab if one exists. This is what a player can STAND on.
##
## No rendering and no bake. Hulls are built through `HullRegistry.build_hull`
## and never enter the tree, so there is no physics transient to hold still.

const HULLS := [
	"hull_15x5", "hull_28x10", "hull_45x16_cat",
	"hull_70x18", "hull_90x24", "hull_100x24",
	"hull_120x28", "hull_130x28", "hull_150x32",
]
## The six `hull_visual_capture.HULL_IDS` photographs — "the kit hulls".
const KIT_HULLS := [
	"hull_15x5", "hull_28x10", "hull_45x16_cat",
	"hull_100x24", "hull_130x28", "hull_150x32",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== A. GRID AGAINST LOFT, EVERY OFFERED CELL, EVERY HULL ===")
	print("positive overhang = the grid offers a cell whose CENTRE is outside the loft")
	print(
		"%-15s %-4s %6s %6s %5s %5s %10s %10s %9s %s"
		% ["hull", "kit", "loa", "beam", "taper", "cells", "worst_cent", "at_z",
			"long_over", "rows_offending/total"]
	)
	for hull_id in HULLS:
		_audit(hull_id)

	print("\n=== B. MY READER AGAINST THE SHIPPED ONE ===")
	_cross_check()

	print("\n=== C. WHAT GEOMETRY ACTUALLY EXISTS AT THE WORST CELL ===")
	for hull_id in ["hull_45x16_cat", "hull_28x10", "hull_150x32"]:
		_geometry_at_worst(hull_id)

	print("\n=== D. THE CATAMARAN'S FOUR OUTLINES, STATION BY STATION ===")
	_catamaran_outlines()

	get_tree().quit()


## The catamaran has four statements of "how wide is the ship here", and this is
## where they are put side by side rather than argued about:
##
##   grid       `make_grid` — rectangular, 32 x 90 cells
##   plate      the DRAWN bridge deck, `rect_plan_ring(16, 45)`
##   demihulls  `make_demihull_stations`, offset +/- (BEAM - DEMIHULL_BEAM)/2 —
##              the loft that is actually drawn and actually collided
##   aggregate  `physics_profile.make_stations()`, which is what the BoatBody
##              publishes as `hull_stations` and what the off-ship check reads
func _catamaran_outlines() -> void:
	var boat := HullRegistry.build_hull("hull_45x16_cat")
	var grid := HullRegistry.make_grid("hull_45x16_cat")
	var aggregate: HullStations = boat.hull_stations
	var demi: HullStations = PassengerCatamaran.make_demihull_stations()
	var offset := (PassengerCatamaran.BEAM_M - PassengerCatamaran.DEMIHULL_BEAM_M) * 0.5
	print("  demihull centres at x = +/- %.3f, demihull half-beam amidships %.3f"
		% [offset, _half_breadth_at(demi, 0.0)])
	print("  %8s %10s %10s %12s %12s %12s"
		% ["z", "grid_half", "plate_half", "aggregate", "demi_outer", "demi_inner"])
	var zs: Array[float] = []
	for k in range(10):
		zs.append(-22.25 + float(k) * 0.5)
	zs.append(-15.0)
	zs.append(-5.0)
	zs.append(0.0)
	zs.append(20.0)
	zs.append(22.25)
	for z in zs:
		var d := _half_breadth_at(demi, z)
		print("  %8.3f %10.3f %10.3f %12.3f %12.3f %12.3f"
			% [z, grid.half_beam, PassengerCatamaran.BEAM_M * 0.5,
				_half_breadth_at(aggregate, z), offset + d, maxf(offset - d, 0.0)])
	boat.free()


# ── A ────────────────────────────────────────────────────────────────────────

func _audit(hull_id: String) -> void:
	var grid := HullRegistry.make_grid(hull_id)
	var boat := HullRegistry.build_hull(hull_id)
	if grid == null or boat == null:
		print("  %-15s COULD NOT BUILD" % hull_id)
		return
	var st: HullStations = boat.hull_stations
	if st == null or st.stations.is_empty():
		print("  %-15s NO STATIONS" % hull_id)
		boat.free()
		return
	var first := float(st.stations[0]["z"])
	var last := float(st.stations[st.stations.size() - 1]["z"])

	var worst := -1e18
	var worst_z := 0.0
	var worst_x := 0.0
	var worst_loft := 0.0
	var worst_long := -1e18
	var offending_rows := 0
	var rows := 0
	var offending_cells := 0
	var total_cells := 0
	var rowlines: Array[String] = []
	for iz in range(grid.length):
		var row_worst := -1e18
		var row_any := false
		var centre_z := 0.0
		for ix in range(grid.width):
			if grid.cell_shape(ix, iz) == DeckGrid.CellShape.NONE:
				continue
			row_any = true
			total_cells += 1
			var c := grid.cell_center_local(Vector3i(ix, 0, iz))
			centre_z = c.z
			var loft := _half_breadth_at(st, c.z)
			var over := absf(c.x) - loft
			if over > 1e-6:
				offending_cells += 1
			if over > row_worst:
				row_worst = over
			if over > worst:
				worst = over
				worst_z = c.z
				worst_x = absf(c.x)
				worst_loft = loft
		if not row_any:
			continue
		rows += 1
		var long_over := maxf(first - centre_z, centre_z - last)
		worst_long = maxf(worst_long, long_over)
		if row_worst > 1e-6:
			offending_rows += 1
			rowlines.append("      iz=%-4d z=%+8.3f worst %+8.3f  long %+7.3f  loft %.3f"
				% [iz, centre_z, row_worst, long_over, _half_breadth_at(st, centre_z)])

	print(
		"%-15s %-4s %6.1f %6.1f %5d %5d %+10.3f %+10.3f %+9.3f  %d/%d rows  %d/%d cells"
		% [
			hull_id, "yes" if KIT_HULLS.has(hull_id) else "-",
			float(grid.length) * DeckGrid.CELL_M, float(grid.width) * DeckGrid.CELL_M,
			grid.bow_taper_cells, grid.width * grid.length,
			worst, worst_z, worst_long,
			offending_rows, rows, offending_cells, total_cells,
		]
	)
	print("      widest offered |x| %.3f at z=%+.3f where the loft is %.3f"
		% [worst_x, worst_z, worst_loft])
	if offending_rows > 0:
		## Print the first and last few offending rows so the SHAPE is visible.
		var shown := 0
		for line in rowlines:
			if not line.contains("worst +"):
				continue
			if shown < 6 or shown >= offending_rows - 2:
				print(line)
			elif shown == 6:
				print("      … %d more offending rows …" % (offending_rows - 8))
			shown += 1
	boat.free()


## The loft's widest plan half-breadth at ship-local z.
##
## Written here rather than borrowed: `stations[i]["section"]` is documented as
## Array[Vector2] of (y, half_beam) sorted by y, and the loft joins level j of
## station i to level j of station i+1, so the silhouette between two stations is
## the per-level linear blend. Maximised over levels afterwards.
func _half_breadth_at(st: HullStations, z: float) -> float:
	var list: Array = st.stations
	var n := list.size()
	if n == 0:
		return 0.0
	if n == 1:
		return _widest(list[0]["section"] as Array, list[0]["section"] as Array, 0.0)
	var i := 0
	while i < n - 2 and float(list[i + 1]["z"]) < z:
		i += 1
	var z0 := float(list[i]["z"])
	var z1 := float(list[i + 1]["z"])
	var t := clampf((z - z0) / maxf(z1 - z0, 1e-6), 0.0, 1.0)
	return _widest(list[i]["section"] as Array, list[i + 1]["section"] as Array, t)


func _widest(a: Array, b: Array, t: float) -> float:
	var best := 0.0
	var levels := mini(a.size(), b.size())
	for j in range(levels):
		var va := a[j] as Vector2
		var vb := b[j] as Vector2
		best = maxf(best, lerpf(va.y, vb.y, t))
	return best


# ── B ────────────────────────────────────────────────────────────────────────

## The shipped reader lives on `vessel_render_capture`, which is a Node script.
## Instantiate one, hand it the same stations, and compare on a dense z sweep.
func _cross_check() -> void:
	var vrc_script := load("res://tests/vessel_render_capture.gd")
	for hull_id in ["hull_28x10", "hull_45x16_cat", "hull_150x32"]:
		var boat := HullRegistry.build_hull(hull_id)
		var st: HullStations = boat.hull_stations
		var rig: Node = vrc_script.new()
		rig.set("_hull_stations", st)
		var worst_delta := 0.0
		var at_z := 0.0
		var first := float(st.stations[0]["z"])
		var last := float(st.stations[st.stations.size() - 1]["z"])
		for k in range(401):
			var z := lerpf(first, last, float(k) / 400.0)
			var mine := _half_breadth_at(st, z)
			var theirs := float(rig.call("_hull_half_breadth_at", z))
			if absf(mine - theirs) > worst_delta:
				worst_delta = absf(mine - theirs)
				at_z = z
		print("  %-15s 401 samples, worst |mine - shipped| = %.9f m at z=%+.3f"
			% [hull_id, worst_delta, at_z])
		rig.free()
		boat.free()


# ── C ────────────────────────────────────────────────────────────────────────

func _geometry_at_worst(hull_id: String) -> void:
	var grid := HullRegistry.make_grid(hull_id)
	var boat := HullRegistry.build_hull(hull_id)
	var st: HullStations = boat.hull_stations
	print("\n  %s — grid %d x %d cells, deck_y %.3f, stations deck_y %.3f"
		% [hull_id, grid.width, grid.length, grid.deck_y, st.deck_y])

	## Every MeshInstance3D under the body, boat-local AABB.
	var mesh_bounds := AABB()
	var have_mesh := false
	for node in _all_descendants(boat):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local := mi.mesh.get_aabb()
		var xf := _relative_transform(boat, mi)
		var world_a := xf * local
		print("      MESH  %-28s aabb pos %v size %v"
			% [str(mi.name), world_a.position.snappedf(0.001), world_a.size.snappedf(0.001)])
		if have_mesh:
			mesh_bounds = mesh_bounds.merge(world_a)
		else:
			mesh_bounds = world_a
			have_mesh = true

	var col_bounds := AABB()
	var have_col := false
	var col_count := 0
	for node in _all_descendants(boat):
		var cs := node as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		col_count += 1
		var a := _shape_aabb(cs.shape)
		var xf := _relative_transform(boat, cs)
		var wa := xf * a
		if have_col:
			col_bounds = col_bounds.merge(wa)
		else:
			col_bounds = wa
			have_col = true
	print("      MESH   union   pos %v size %v" % [mesh_bounds.position.snappedf(0.001), mesh_bounds.size.snappedf(0.001)])
	print("      COLL   %d shapes union pos %v size %v"
		% [col_count, col_bounds.position.snappedf(0.001), col_bounds.size.snappedf(0.001)])
	print("      GRID   offered x in [%.3f, %.3f], z in [%.3f, %.3f]"
		% [-grid.half_beam, grid.half_beam, -grid.half_loa, grid.half_loa])
	print("      LOFT   half-breadth amidships %.3f, at stem+1m %.3f, beam_m/2 %.3f"
		% [
			_half_breadth_at(st, 0.0),
			_half_breadth_at(st, float(st.stations[0]["z"]) + 1.0),
			st.beam_m * 0.5,
		])
	boat.free()


func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var b := (shape as BoxShape3D).size
		return AABB(-b * 0.5, b)
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points
		if pts.is_empty():
			return AABB()
		var a := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			a = a.expand(p)
		return a
	return AABB()


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur := node
	while cur != null and cur != root:
		xf = cur.transform * xf
		cur = cur.get_parent() as Node3D
	return xf


func _all_descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_all_descendants(child))
	return out
