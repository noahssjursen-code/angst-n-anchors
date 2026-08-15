extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## WHAT THE FINER DICE COSTS ON A REAL HULL, priced on the 150 m container
## feeder as well as on the two 28 m boats the predecessor measured.
##
## It names NO constant from `StructureBaker`, on purpose: it has to run
## unchanged against the pre-65b6a0a baker (`PLATE_COLLIDER_STEP`, fixed grid)
## and against the current one (`PLATE_COLLIDER_SLOP`, adaptive dice), so the two
## tables are comparable line for line. Check out either version of the baker and
## re-run.
##
## Four costs, because "collider count" alone is not a price:
##
##   boxes    what collect_colliders() emits — the production call DeckFitout
##            makes, so this is the number of CollisionShape3D nodes a spawned
##            vessel carries.
##   coll/bake wall-clock of collect_colliders() and bake(), median of 5. Load
##            time, paid once per spawn.
##   build    wall-clock of putting those boxes into a real physics world the way
##            `BoatBody.add_walk_brick_collider` does — a StaticBody3D with one
##            BoxShape3D CollisionShape3D child per box, yaw on the node. Also
##            paid once per spawn, and it is the term nobody had measured.
##   local    median microseconds of ONE player-capsule `intersect_shape` in a
##            DENSE part of the vessel — the capsule dropped on a sample of the
##            collider boxes themselves. This is the per-frame term:
##            `move_and_slide` costs several shape queries every physics tick for
##            every character on the deck, and its cost is set by how many shapes
##            sit inside the capsule's own swept AABB, which is exactly what
##            dicing multiplies.
##   sweep    median microseconds of one 40 m `cast_motion` at standing height
##            straight through the vessel — the broadphase term, which scales
##            with total shape count rather than with local density.
##
## Stations laid on a grid over the whole collider bound were tried first and are
## NOT what is reported: 144 of 144 landed in open air and every fixture came back
## at 0.2 us, which measures the empty sky over a boat. A cost probe that cannot
## tell a 3086-box hull from a 675-box one is measuring the wrong place.

const CAPSULE_R := 0.35
const CAPSULE_H := 1.8

const FIXTURES := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_plate_deckhouse.json",
	"res://resources/data/structures/probe_container_feeder.json",
]

## Collider boxes sampled for the local query, evenly spread through the list.
const LOCAL_STATIONS := 160
## Queries timed per station, so one scheduling hiccup is not the number.
const QUERIES_PER_STATION := 8
## Results one local query may return. High enough that a dense pile is fully
## resolved rather than cut short — cutting it short is what would hide the cost.
const LOCAL_RESULTS := 64
## Sweeps timed, spread across the vessel's beam.
const SWEEPS := 24
## Plan-space deck plane. Every fixture in FIXTURES is authored on y = 0.
const DECK_Y := 0.0

var _plan: StructurePlan = null
var _boxes: Array = []
var _collected := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("%-30s %7s %7s %8s %8s %8s %8s %9s %9s"
		% ["fixture", "boxes", "plate", "axis m", "coll ms", "bake ms", "bld ms",
		   "local us", "sweep us"])
	for path in FIXTURES:
		await _survey(str(path))
	quit()


func _time_collect() -> void:
	_collected = StructureBaker.collect_colliders(_plan).size()


func _time_bake() -> void:
	var root := StructureBaker.bake(_plan)
	root.free()


func _survey(path: String) -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	if doc == null:
		print("%-30s unparseable" % path.get_file())
		return
	_plan = StructurePlan.from_dict(doc)

	_collected = 0
	var collect_ms := _median(_time_collect)
	var bake_ms := _median(_time_bake)
	_boxes = StructureBaker.collect_colliders(_plan)

	## How many of those boxes are PLATE boxes, and the worst thickness excess
	## among them — the two quantities the dice actually moves. Everything else
	## (edges, spars, cylinders, containers) is emitted identically by both bakes,
	## so quoting only the total understates the change on a plate-heavy vessel
	## and overstates it on a container ship.
	var resolved := StructureBaker.resolved(_plan)
	var plate_boxes := 0
	var worst_axis := 0.0
	for item_variant in resolved.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		if not bool(props.get("solid", true)):
			continue
		var corners := StructureBaker.plate_corners(props)
		if corners.size() != 4:
			continue
		for slab_variant in StructureBaker.plate_slabs(props):
			var slab := slab_variant as Dictionary
			var thickness := float(slab["thickness"])
			for cell_variant in StructureBaker._plate_panel_colliders(
					corners, thickness, Vector3.ZERO,
					float(slab["u0"]), float(slab["u1"]),
					float(slab["v0"]), float(slab["v1"])):
				plate_boxes += 1
				var size := (cell_variant as Dictionary)["size"] as Vector3
				worst_axis = maxf(
					worst_axis, minf(size.x, minf(size.y, size.z)) - thickness)

	## The physics world, built the way BoatBody builds it.
	var world := Node3D.new()
	root.add_child(world)
	var body := StaticBody3D.new()
	world.add_child(body)
	var t0 := Time.get_ticks_usec()
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box["size"] as Vector3
		cs.shape = shape
		cs.position = box["center"] as Vector3
		cs.rotation_degrees = Vector3(0.0, float(box.get("yaw_deg", 0.0)), 0.0)
		body.add_child(cs)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	## Shapes reach the server on the next physics step, not on add_child.
	await physics_frame
	await physics_frame

	var space := body.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_R
	capsule.height = CAPSULE_H
	query.shape = capsule
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF

	var lo := Vector3.INF
	var hi := -Vector3.INF
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		var c := box["center"] as Vector3
		var h := (box["size"] as Vector3).length() * 0.5
		lo = Vector3(minf(lo.x, c.x - h), minf(lo.y, c.y - h), minf(lo.z, c.z - h))
		hi = Vector3(maxf(hi.x, c.x + h), maxf(hi.y, c.y + h), maxf(hi.z, c.z + h))

	## LOCAL: the capsule put where the structure actually is. Sampling the
	## collider boxes themselves means the station density follows the geometry,
	## so both bakes are asked about the same walls rather than about the same
	## arbitrary lattice.
	var local := PackedFloat64Array()
	var stations := 0
	if _boxes.size() > 0:
		var stride: int = maxi(1, _boxes.size() / LOCAL_STATIONS)
		var index := 0
		while index < _boxes.size():
			var centre := (_boxes[index] as Dictionary)["center"] as Vector3
			query.transform = Transform3D(Basis.IDENTITY, centre)
			stations += 1
			var t1 := Time.get_ticks_usec()
			for _k in QUERIES_PER_STATION:
				space.intersect_shape(query, LOCAL_RESULTS)
			local.append(float(Time.get_ticks_usec() - t1) / float(QUERIES_PER_STATION))
			index += stride
	local.sort()
	var local_us := 0.0 if local.is_empty() else local[local.size() / 2]

	## SWEEP: a 40 m horizontal cast at standing height, one per station along the
	## vessel's beam, so every sweep crosses the whole structure end to end.
	var sweeps := PackedFloat64Array()
	if _boxes.size() > 0:
		for i in SWEEPS:
			## Plan space: the deck plane is y = 0 on every fixture here, so the
			## sweep is at the standing figure's centre height. Hanging it off the
			## collider bound's own floor was tried and put the capsule 10 m under
			## the feeder's below-deck containers, where every sweep read 0.2 us.
			var p := Vector3(
				lerpf(lo.x, hi.x, (float(i) + 0.5) / float(SWEEPS)),
				DECK_Y + 0.09 + CAPSULE_H * 0.5, lo.z - 1.0)
			query.transform = Transform3D(Basis.IDENTITY, p)
			query.motion = Vector3(0.0, 0.0, (hi.z - lo.z) + 2.0)
			var t1 := Time.get_ticks_usec()
			for _k in QUERIES_PER_STATION:
				space.cast_motion(query)
			sweeps.append(float(Time.get_ticks_usec() - t1) / float(QUERIES_PER_STATION))
	sweeps.sort()
	var sweep_us := 0.0 if sweeps.is_empty() else sweeps[sweeps.size() / 2]

	print("%-30s %7d %7d %8.4f %8.1f %8.1f %8.1f %9.1f %9.1f   (%d stns)"
		% [path.get_file().get_basename(), _boxes.size(), plate_boxes, worst_axis,
		   collect_ms, bake_ms, build_ms, local_us, sweep_us, stations])
	world.queue_free()
	await physics_frame


func _median(body: Callable) -> float:
	var runs := PackedFloat64Array()
	for _i in 5:
		var t0 := Time.get_ticks_usec()
		body.call()
		runs.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	runs.sort()
	return runs[2]
