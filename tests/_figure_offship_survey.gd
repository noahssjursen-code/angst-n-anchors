extends "res://tests/vessel_render_capture.gd"

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_figure_offship_survey.tscn
##
## WHERE IS THE HULL, AT THE STATION THE FIGURE STANDS ON?
##
## Runs `_check_figure_on_the_ship`'s own arithmetic over every fixture any of the
## five rigs photographs — including the three `critic_*` plans, whose rig writes
## committed frames this probe has no business overwriting — and prints the
## authored spot beside the parent's DEFAULT spot, which is the case the check was
## built for. A SUBCLASS, so the half-breadth comes from the shipped
## `_hull_half_breadth_at` and not from a second copy of it that could disagree.
##
## No rendering and no bake: it stands each hull up and reads its station table.

const PKC := preload("res://tests/piece_kit_capture.gd")
const TRC := preload("res://tests/trawler_render_capture.gd")
const SPC := preload("res://tests/structure_plate_capture.gd")
const CRITIC := preload("res://tests/support/_piece_kit_critic_capture.gd")


func _run() -> void:
	var jobs: Array = []
	for path in FIXTURES:
		jobs.append(["vessel_render_capture", path, FIGURE_SPOT])
	for path in TRC.FIXTURES_HERE:
		jobs.append(["trawler_render_capture", path, FIGURE_SPOT])
	jobs.append(["structure_plate_capture", SPC.PLATE_FIXTURE, FIGURE_SPOT])
	for path in PKC.FIXTURES_HERE:
		jobs.append(["piece_kit_capture", path, PKC.PIECE_FIGURE_SPOT])
	for path in CRITIC.FIXTURES_HERE:
		jobs.append(["_piece_kit_critic_capture", path, FIGURE_SPOT])

	print(
		"%-26s %-27s %-15s %-24s %8s %8s %10s %10s %9s %s"
		% [
			"rig", "fixture", "hull", "spot", "x_ship", "z_ship",
			"half_brdth", "outboard", "past_end", "verdict",
		]
	)
	var seen := {}
	for job in jobs:
		var rig := str(job[0])
		var path := str(job[1])
		var stem := path.get_file().get_basename()
		var key := "%s|%s" % [rig, stem]
		if seen.has(key):
			continue
		seen[key] = true
		_report(rig, path, stem, job[2] as Dictionary)
	_grid_against_loft()
	get_tree().quit()


## HOW STRICT IS THIS CHECK AGAINST THE DECK A PLAYER CAN ACTUALLY BUILD ON?
##
## `_check_figure_on_the_ship` asks the LOFT. A builder places things on the
## `DeckGrid`, and the two are separate producers of the same outline. Where the
## grid is wider than the loft, the check will refuse a cell the grid offers — so
## sweep every cell row of every hull in the fleet and print the worst overhang.
func _grid_against_loft() -> void:
	print("\nDECK GRID AGAINST THE LOFT — positive = the grid offers deck the loft"
		+ " calls water, i.e. how strict this check is")
	for hull_id in ["hull_28x10", "hull_45x16_cat", "hull_150x32"]:
		var grid := HullRegistry.make_grid(hull_id)
		var boat: Node3D = VesselSpawn.instantiate(hull_id, {}, "")
		if grid == null or boat == null:
			continue
		add_child(boat)
		_hull_stations = boat.get("hull_stations") as HullStations
		var worst := -1e18
		var worst_z := 0.0
		var worst_grid := 0.0
		var worst_loft := 0.0
		var worst_centre := -1e18
		for iz in range(grid.length):
			var outer := -1
			for ix in range(grid.width):
				if grid.cell_shape(ix, iz) != DeckGrid.CellShape.NONE:
					outer = maxi(outer, ix)
			if outer < 0:
				continue
			var centre := grid.cell_center_local(Vector3i(outer, 0, iz))
			var grid_half := absf(centre.x) + DeckGrid.CELL_M * 0.5
			var loft_half := _hull_half_breadth_at(centre.z)
			var delta := grid_half - loft_half
			if delta > worst:
				worst = delta
				worst_z = centre.z
				worst_grid = grid_half
				worst_loft = loft_half
			## The figure stands at a POINT, so the number that decides whether a
			## buildable cell is refused is the cell CENTRE, not its outer edge.
			worst_centre = maxf(worst_centre, absf(centre.x) - loft_half)
		print(
			"  %-15s bow_taper_cells=%-3d worst EDGE overhang %+.3f m at z=%+.3f"
			% [hull_id, grid.bow_taper_cells, worst, worst_z]
			+ "  (grid %.3f, loft %.3f)  worst CELL-CENTRE overhang %+.3f m"
			% [worst_grid, worst_loft, worst_centre]
		)
		remove_child(boat)
		boat.free()


func _report(rig: String, path: String, stem: String, table: Dictionary) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		print("%-26s %-27s COULD NOT PARSE" % [rig, stem])
		return
	var plan := StructurePlan.from_dict(raw as Dictionary)
	if plan.context != "vessel" or plan.hull_id == "":
		print("%-26s %-27s NO HULL (context=%s)" % [rig, stem, plan.context])
		return
	var grid := HullRegistry.make_grid(plan.hull_id)
	var boat: Node3D = VesselSpawn.instantiate(plan.hull_id, {}, "")
	if boat == null or grid == null:
		print("%-26s %-27s HULL WOULD NOT INSTANTIATE" % [rig, stem])
		return
	add_child(boat)
	_hull_stations = boat.get("hull_stations") as HullStations
	if _hull_stations == null:
		print("%-26s %-27s NO STATIONS ON THE BUILT HULL" % [rig, stem])
	else:
		var offset := Vector3(-grid.half_beam, 0.0, -grid.half_loa)
		var authored: Variant = table.get(stem)
		if authored != null:
			_row(rig, stem, plan.hull_id, offset, authored as Vector3, "AUTHORED")
		_row(
			rig, stem, plan.hull_id, offset, FIGURE_SPOT_DEFAULT,
			"the parent DEFAULT" if authored != null else "DEFAULTED — this is live",
		)
	remove_child(boat)
	boat.free()


func _row(
	rig: String, stem: String, hull_id: String, offset: Vector3, spot: Vector3, tag: String
) -> void:
	var x := offset.x + spot.x
	var z := offset.z + spot.z
	var first := float(_hull_stations.stations[0]["z"])
	var last := float(_hull_stations.stations[_hull_stations.stations.size() - 1]["z"])
	var long_over := maxf(first - z, z - last)
	var half_breadth := _hull_half_breadth_at(z)
	var beam_over := absf(x) - half_breadth
	var worst := maxf(beam_over, long_over)
	print(
		"%-26s %-27s %-15s %-24s %8.3f %8.3f %10.3f %10.3f %9.3f %s  (%s)"
		% [
			rig, stem, hull_id, str(spot), x, z, half_breadth, beam_over, long_over,
			"ON THE SHIP " if worst <= FIGURE_OFF_SHIP_MAX else "*** OFF THE SHIP",
			tag,
		]
	)
