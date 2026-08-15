extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## The trade-off curve for `StructureBaker.PLATE_COLLIDER_SLOP`. Re-run after
## changing that constant and diff the two tables.
##
## Reports, per fixture:
##   boxes        total colliders from collect_colliders() — the production path
##   plate        how many of those come from plate_colliders()
##   axis         worst AXIS excess: thinnest box dimension minus the slab's own
##                thickness. Same instrument as _casing_extent_probe, so the
##                numbers are comparable with STATE.md's.
##   phant        worst PHANTOM: how far the deepest corner of a collider box is
##                from anything the plate draws. Measured by nearest point on the
##                slab's own bilinear patch, so a WARPED plate is not charged for
##                its own warp — which is what a slab-plane measure did.
##   collect/bake wall-clock for collect_colliders() and bake(), median of 3.

const FIXTURE_DIR := "res://resources/data/structures/"


func _initialize() -> void:
	var names := PackedStringArray()
	var dir := DirAccess.open(FIXTURE_DIR)
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	print("PLATE_COLLIDER_SLOP = %.4f   PLATE_MAX_COLLIDER_CELLS = %d"
		% [StructureBaker.PLATE_COLLIDER_SLOP, StructureBaker.PLATE_MAX_COLLIDER_CELLS])
	print("%-32s %7s %7s %9s %9s %9s %9s"
		% ["fixture", "boxes", "plate", "axis m", "phant m", "coll ms", "bake ms"])
	var total_boxes := 0
	var total_plate := 0
	for n in names:
		total_boxes += _survey(FIXTURE_DIR + n)[0]
		total_plate += _survey_last_plate
	print("%-32s %7d %7d" % ["TOTAL", total_boxes, total_plate])
	quit()


var _survey_last_plate := 0
var _collected := 0
var _plan: StructurePlan = null


func _time_collect() -> void:
	_collected = StructureBaker.collect_colliders(_plan).size()


func _time_bake() -> void:
	var root := StructureBaker.bake(_plan)
	root.free()


func _survey(path: String) -> Array:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	if doc == null:
		print("%-32s  unparseable" % path.get_file())
		return [0]
	var plan := StructurePlan.from_dict(doc)

	## GDScript lambdas capture locals BY VALUE, so the result goes to a member.
	_collected = 0
	_plan = plan
	var collect_ms := _median(_time_collect)
	var bake_ms := _median(_time_bake)
	var boxes_size := _collected

	## Plate boxes and their excess, walked from the RESOLVED plan so piece
	## fixtures contribute the plates their placements resolve to.
	var resolved := StructureBaker.resolved(plan)
	var plate_boxes := 0
	var worst_axis := 0.0
	var worst_perp := 0.0
	var note_axis := ""
	var note_perp := ""
	for item_variant in resolved.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		if not bool(props.get("solid", true)):
			continue
		var note := str(props.get("__is", "item %d" % int(item.get("id", -1))))
		var corners := StructureBaker.plate_corners(props)
		if corners.size() != 4:
			continue
		for slab_variant in StructureBaker.plate_slabs(props):
			var slab := slab_variant as Dictionary
			var thickness := float(slab["thickness"])
			var u0 := float(slab["u0"])
			var u1 := float(slab["u1"])
			var v0 := float(slab["v0"])
			var v1 := float(slab["v1"])
			var cells: Array = StructureBaker._plate_panel_colliders(
				corners, thickness, Vector3.ZERO, u0, u1, v0, v1)
			var quad := StructureBaker.plate_subquad(corners, u0, u1, v0, v1)
			for cell_variant in cells:
				plate_boxes += 1
				var cell := cell_variant as Dictionary
				var size := cell["size"] as Vector3
				var axis := minf(size.x, minf(size.y, size.z)) - thickness
				if axis > worst_axis:
					worst_axis = axis
					note_axis = note.substr(0, 40)
				var basis := Basis(Vector3.UP, deg_to_rad(float(cell["yaw_deg"])))
				var half := size * 0.5
				var centre := cell["center"] as Vector3
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							var corner := centre + basis * Vector3(
								half.x * float(sx), half.y * float(sy), half.z * float(sz))
							var perp := _phantom(quad, thickness, corner)
							if perp > worst_perp:
								worst_perp = perp
								note_perp = note.substr(0, 40)

	print("%-32s %7d %7d %9.4f %9.4f %9.1f %9.1f   %s | %s"
		% [path.get_file().get_basename(), boxes_size, plate_boxes,
		   worst_axis, worst_perp, collect_ms, bake_ms, note_axis, note_perp])
	_survey_last_plate = plate_boxes
	return [boxes_size]


## How far `p` is from the drawn slab: the bilinear patch `quad` thickened by
## `thickness` along its own normal. Nearest point found by coordinate descent in
## (u, v) — fix v and project onto the u iso-line, fix u and project onto the v
## one — which converges in a handful of passes on a patch this near-flat and is
## EXACT for a planar quad. Clamped to the patch, so a corner that overhangs the
## slab's edge is charged for the overhang, which is the point.
func _phantom(quad: PackedVector3Array, thickness: float, p: Vector3) -> float:
	var u := 0.5
	var v := 0.5
	for _pass in 8:
		u = clampf(_project(StructureBaker.plate_point(quad, 0.0, v),
			StructureBaker.plate_point(quad, 1.0, v), p), 0.0, 1.0)
		v = clampf(_project(StructureBaker.plate_point(quad, u, 0.0),
			StructureBaker.plate_point(quad, u, 1.0), p), 0.0, 1.0)
	var near := StructureBaker.plate_point(quad, u, v)
	var n := StructureBaker.plate_normal(quad)
	var d := p - near
	var along := d.dot(n)
	var across := (d - n * along).length()
	var out := maxf(absf(along) - thickness * 0.5, 0.0)
	return sqrt(out * out + across * across)


func _project(a: Vector3, b: Vector3, p: Vector3) -> float:
	var run := b - a
	var len2 := run.length_squared()
	return 0.5 if len2 < 1e-12 else (p - a).dot(run) / len2


## Median of three so one scheduling hiccup does not become the number.
func _median(body: Callable) -> float:
	var runs := PackedFloat64Array()
	for _i in 3:
		var t0 := Time.get_ticks_usec()
		body.call()
		runs.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	runs.sort()
	return runs[1]
