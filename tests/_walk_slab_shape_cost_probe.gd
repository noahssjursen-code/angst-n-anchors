extends Node3D

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_walk_slab_shape_cost_probe.tscn
##
## WHAT WOULD A WALK SLAB THAT MATCHES THE DRAWN DECK COST?
##
## `_walk_bow_body_drive` shows a player body walks 3.3 m (trawler) / 10.7 m
## (freighter) outboard of the drawn deck on the rectangular slab. "Trim it to
## the loft" is the obvious fix and it is NOT obviously affordable — the whole
## reason `_walk_deck_box_size` is a box is that `boat_body.gd`'s own measured
## table says Jolt rebuilds a body's compound shape on every `body_add_shape`,
## O(shapes already on the body). So this measures the candidates instead of
## assuming.
##
## Four candidates, all built from the SAME ring the deck plate is extruded
## from (`plate_args.ring`), never from `hull_size` — a slab derived from the
## same source as the defect cannot be checked against it (REALITY.md §3b):
##
##   rect       what ships: one BoxShape3D, hull_size.x by hull_size.z.
##   convex     one ConvexPolygonShape3D — the ring extruded 0.14 m. The fleet's
##              rings are convex pentagons, so this is EXACT at one shape.
##   staircase  one box over the parallel body plus K inscribed boxes stepping
##              the 45 degree chamfer at STAIR_STEP_M.
##   wedge      one box over the parallel body plus one convex prism over the
##              bow triangle. Also exact, at two shapes.
##
## Costs measured, one input varied at a time (REALITY.md §4e): shapes added,
## time to build and attach them to a body that is IN ITS SPACE, the per-step
## cost a walking player pays, and the cost of the downward ray the game casts
## on this mask. Milliseconds are llvmpipe / 4 cores and are not portable; the
## RATIOS and the shape counts are.
##
## `CaptureSubject.hold_still` is called on every hull — a BoatBody's LOD
## revokes `freeze` a second after it enters the tree and a drifting hull would
## move every stance in here.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")

const LAYER_WORLD := 1
const LAYER_BOAT_WALK := 4
const LAYER_PLAYER := 8

const CAPSULE_R := 0.35
const CAPSULE_H := 1.8
const WALK_SPEED := 4.5
const GRAVITY := 20.0
const STEP_DT := 1.0 / 60.0

const SLAB_HALF_Y := 0.07     ## the shipped slab is 0.14 m thick
const STAIR_STEP_M := 0.5     ## one deck-grid cell
const BUILD_REPS := 20
## A shuttle: this many steps forward, then the same back, three times over.
## A one-way march would run one candidate off the bow and time a FALL against
## the others' walk, which is not the same measurement.
const SHUTTLE_STEPS := 100
const SHUTTLE_LEGS := 6
const TIMING_REPS := 3
const RAY_CASTS := 5000

const HULLS: Array[String] = ["hull_28x10", "hull_150x32"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for hull_id in HULLS:
		await _measure(hull_id)
	get_tree().quit(0)


func _measure(hull_id: String) -> void:
	var boat: Node3D = VesselSpawn.instantiate(hull_id, {}, "")
	add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3.ZERO
	for i in range(10):
		await get_tree().physics_frame

	var hull_size: Vector3 = boat.get("hull_size")
	var walk := _walk_deck(boat) as CollisionObject3D
	var slab := walk.get_node_or_null("WalkDeckCollider") as CollisionShape3D
	var ring := _ring(boat)
	var geom := _ring_geometry(ring)
	var rect_area := hull_size.x * hull_size.z
	print("\n=== %s ===" % hull_id)
	print("  ring %d pts · half-beam %.3f · stem z %+.3f · shoulder z %+.3f · taper %.3f m"
		% [ring.size(), geom["half_beam"], geom["z_tip"], geom["z_shoulder"], geom["bow_len"]])
	print("  drawn plate area %.1f m2 · walk rectangle %.1f m2 · INVISIBLE FLOOR %.1f m2 (%.1f%%)"
		% [geom["area"], rect_area, rect_area - geom["area"],
			100.0 * (rect_area - geom["area"]) / rect_area])

	await _what_else_holds_it_up(boat, walk, slab, ring, geom)

	print("  %-10s %6s %10s %12s %12s %10s %s"
		% ["candidate", "shapes", "build ms", "walk ms/600", "ray ms/5000", "stands?",
			"slab alone holds a stance over water?"])
	## The hull box is a rectangle too and holds a capsule out there on its own
	## (measured just above), so it is taken OUT for this comparison — otherwise
	## every candidate reads "held" and the column says nothing about the slab.
	var hull_col := walk.get_node_or_null("WalkHullCollider") as CollisionShape3D
	if hull_col != null:
		hull_col.disabled = true
	await get_tree().physics_frame
	for candidate in ["rect", "convex", "staircase", "wedge"]:
		await _one_candidate(candidate, boat, walk, slab, ring, geom, hull_size)
	if hull_col != null:
		hull_col.disabled = false

	## Put the shipped shape back before the hull is torn down.
	_apply(candidate_shapes("rect", ring, geom, hull_size), walk, slab)
	remove_child(boat)
	boat.queue_free()
	if walk != null and is_instance_valid(walk) and walk.get_parent() != null:
		walk.get_parent().remove_child(walk)
		walk.queue_free()
	await get_tree().process_frame


## Trimming the SLAB is only half a fix if something else on the same mask is
## also a rectangle. `WalkHullCollider` is `hull_size.x` by `hull_size.z` too.
func _what_else_holds_it_up(
	boat: Node3D, walk: CollisionObject3D, slab: CollisionShape3D,
	ring: PackedVector2Array, geom: Dictionary
) -> void:
	var spot := Vector2(geom["half_beam"] * 0.95, geom["z_tip"] + geom["bow_len"] * 0.4)
	var outside := _outside_by(ring, spot)
	slab.disabled = true
	await get_tree().physics_frame
	var body := _make_body()
	add_child(body)
	body.global_position = Vector3(spot.x, slab.global_position.y + 1.0, spot.y)
	for i in range(400):
		_step(body, Vector3.ZERO)
		if body.is_on_floor() and absf(body.velocity.y) < 0.001:
			break
	print("  with WalkDeckCollider DISABLED, a capsule dropped at (%.3f, %.3f) — %.3f m"
		% [spot.x, spot.y, outside]
		+ " outside the drawn deck — %s"
		% ("comes to rest at y %.3f on %s"
			% [body.global_position.y, _floor_under(body)] if body.is_on_floor()
			else "falls through (y %.3f)" % body.global_position.y))
	body.queue_free()
	slab.disabled = false
	await get_tree().physics_frame


func _one_candidate(
	name: String, boat: Node3D, walk: CollisionObject3D, slab: CollisionShape3D,
	ring: PackedVector2Array, geom: Dictionary, hull_size: Vector3
) -> void:
	var shapes := candidate_shapes(name, ring, geom, hull_size)

	## BUILD — construct the shapes and attach them to a body that is IN ITS
	## SPACE, which is the case `boat_body.gd`'s own table says is quadratic.
	var t0 := Time.get_ticks_usec()
	for rep in range(BUILD_REPS):
		var probe := AnimatableBody3D.new()
		probe.collision_layer = LAYER_BOAT_WALK
		probe.collision_mask = LAYER_PLAYER
		add_child(probe)
		for entry in candidate_shapes(name, ring, geom, hull_size):
			var cs := CollisionShape3D.new()
			cs.shape = entry["shape"]
			cs.position = entry["offset"]
			probe.add_child(cs)
		remove_child(probe)
		probe.queue_free()
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(BUILD_REPS)

	_apply(shapes, walk, slab)
	await get_tree().physics_frame

	## WALK — the per-step price a player pays on this shape, shuttled over the
	## parallel body where every candidate has floor. Best of TIMING_REPS: the
	## slowest passes are contention, and the fastest is the one that measures
	## the shape.
	var body := _make_body()
	add_child(body)
	body.global_position = Vector3(0.0, slab.global_position.y + 1.0, hull_size.z * 0.2)
	for i in range(400):
		_step(body, Vector3.ZERO)
		if body.is_on_floor() and absf(body.velocity.y) < 0.001:
			break
	var stands := body.is_on_floor()
	var stand_y := body.global_position.y
	var walk_ms := 1e18
	for rep in range(TIMING_REPS):
		t0 = Time.get_ticks_usec()
		for leg in range(SHUTTLE_LEGS):
			var dir := Vector3(0.0, 0.0, -1.0 if leg % 2 == 0 else 1.0)
			for i in range(SHUTTLE_STEPS):
				_step(body, dir)
		walk_ms = minf(walk_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
	body.queue_free()

	## RAY — the query `_walk_slab_over_water_probe` and the game's ground
	## checks use, cast amidships.
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(0.0, slab.global_position.y + 3.0, hull_size.z * 0.2)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
	query.collision_mask = LAYER_BOAT_WALK
	var ray_ms := 1e18
	for rep in range(TIMING_REPS):
		t0 = Time.get_ticks_usec()
		for i in range(RAY_CASTS):
			space.intersect_ray(query)
		ray_ms = minf(ray_ms, float(Time.get_ticks_usec() - t0) / 1000.0)

	## OVER WATER — the property. Drop a capsule at the station the drive probe
	## reached and ask whether this shape still holds it up out there.
	var spot := Vector2(geom["half_beam"] * 0.95, geom["z_tip"] + geom["bow_len"] * 0.4)
	var over := _make_body()
	add_child(over)
	over.global_position = Vector3(spot.x, slab.global_position.y + 0.5, spot.y)
	for i in range(400):
		_step(over, Vector3.ZERO)
		if over.is_on_floor() and absf(over.velocity.y) < 0.001:
			break
	var held := over.is_on_floor()
	over.queue_free()

	print("  %-10s %6d %10.3f %12.1f %12.1f %10s %s"
		% [name, shapes.size(), build_ms, walk_ms, ray_ms,
			("y %.3f" % stand_y) if stands else "NO",
			"HELD (bad)" if held else "falls (good)"])


func _apply(shapes: Array, walk: CollisionObject3D, slab: CollisionShape3D) -> void:
	for child in walk.get_children():
		if child != slab and str(child.name).begins_with("CandidateCol_"):
			walk.remove_child(child)
			child.queue_free()
	slab.shape = shapes[0]["shape"]
	slab.position = shapes[0]["offset"]
	for i in range(1, shapes.size()):
		var cs := CollisionShape3D.new()
		cs.name = "CandidateCol_%d" % i
		cs.shape = shapes[i]["shape"]
		cs.position = shapes[i]["offset"]
		walk.add_child(cs)


## Each entry is `{shape, offset}` in the WalkDeck's own frame. The shipped slab
## sits at offset zero, so every candidate is authored around that.
func candidate_shapes(
	name: String, ring: PackedVector2Array, geom: Dictionary, hull_size: Vector3
) -> Array:
	var half_beam: float = geom["half_beam"]
	var z_tip: float = geom["z_tip"]
	var z_shoulder: float = geom["z_shoulder"]
	var z_aft: float = geom["z_aft"]
	match name:
		"rect":
			var box := BoxShape3D.new()
			box.size = Vector3(hull_size.x, SLAB_HALF_Y * 2.0, hull_size.z)
			return [{"shape": box, "offset": Vector3.ZERO}]
		"convex":
			var convex := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for p in ring:
				points.append(Vector3(p.x, -SLAB_HALF_Y, p.y))
				points.append(Vector3(p.x, SLAB_HALF_Y, p.y))
			convex.points = points
			return [{"shape": convex, "offset": Vector3.ZERO}]
		"staircase":
			var out: Array = []
			var body_box := BoxShape3D.new()
			body_box.size = Vector3(
				half_beam * 2.0, SLAB_HALF_Y * 2.0, z_aft - z_shoulder
			)
			out.append({
				"shape": body_box,
				"offset": Vector3(0.0, 0.0, (z_aft + z_shoulder) * 0.5),
			})
			var bow_len: float = geom["bow_len"]
			var steps := int(ceil(bow_len / STAIR_STEP_M))
			for j in range(steps):
				var z_from := z_shoulder - float(j) * STAIR_STEP_M
				var z_to := maxf(z_shoulder - float(j + 1) * STAIR_STEP_M, z_tip)
				## Inscribed: the step is only as wide as its NARROW end, so no
				## corner of it stands outside the chamfer.
				var w := maxf(half_beam * (z_to - z_tip) / bow_len, 0.001)
				var step_box := BoxShape3D.new()
				step_box.size = Vector3(w * 2.0, SLAB_HALF_Y * 2.0, z_from - z_to)
				out.append({
					"shape": step_box,
					"offset": Vector3(0.0, 0.0, (z_from + z_to) * 0.5),
				})
			return out
		"wedge":
			var out2: Array = []
			var body2 := BoxShape3D.new()
			body2.size = Vector3(half_beam * 2.0, SLAB_HALF_Y * 2.0, z_aft - z_shoulder)
			out2.append({
				"shape": body2,
				"offset": Vector3(0.0, 0.0, (z_aft + z_shoulder) * 0.5),
			})
			var prism := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for p in [
				Vector2(half_beam, z_shoulder), Vector2(-half_beam, z_shoulder),
				Vector2(0.0, z_tip),
			]:
				pts.append(Vector3(p.x, -SLAB_HALF_Y, p.y))
				pts.append(Vector3(p.x, SLAB_HALF_Y, p.y))
			prism.points = pts
			out2.append({"shape": prism, "offset": Vector3.ZERO})
			return out2
	return []


func _ring_geometry(ring: PackedVector2Array) -> Dictionary:
	var half_beam := 0.0
	var z_tip := 1e18
	var z_aft := -1e18
	for p in ring:
		half_beam = maxf(half_beam, absf(p.x))
		z_tip = minf(z_tip, p.y)
		z_aft = maxf(z_aft, p.y)
	var z_shoulder := 1e18
	for p in ring:
		if absf(absf(p.x) - half_beam) < 1e-6:
			z_shoulder = minf(z_shoulder, p.y)
	var area := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
	return {
		"half_beam": half_beam,
		"z_tip": z_tip,
		"z_aft": z_aft,
		"z_shoulder": z_shoulder,
		"bow_len": z_shoulder - z_tip,
		"area": absf(area) * 0.5,
	}


func _step(body: CharacterBody3D, dir: Vector3) -> void:
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * STEP_DT
	elif body.velocity.y < 0.0:
		body.velocity.y = 0.0
	body.velocity.x = dir.x * WALK_SPEED
	body.velocity.z = dir.z * WALK_SPEED
	body.move_and_slide()


func _make_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = LAYER_PLAYER
	body.collision_mask = LAYER_WORLD | LAYER_BOAT_WALK
	body.floor_snap_length = 0.35
	body.floor_stop_on_slope = true
	body.floor_max_angle = deg_to_rad(48.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_R
	cap.height = CAPSULE_H
	cs.shape = cap
	cs.position = Vector3(0.0, CAPSULE_H * 0.5, 0.0)
	body.add_child(cs)
	return body


func _floor_under(body: CharacterBody3D) -> String:
	var space := get_viewport().world_3d.direct_space_state
	var from := body.global_position + Vector3.UP * 0.10
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5)
	query.collision_mask = LAYER_WORLD | LAYER_BOAT_WALK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "(nothing)"
	var collider: Object = hit.get("collider")
	var shape_name := "?"
	if collider is CollisionObject3D:
		var owner_id := (collider as CollisionObject3D).shape_find_owner(int(hit.get("shape", 0)))
		var owner_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if owner_node != null:
			shape_name = str(owner_node.name)
	return "%s/%s" % [str(collider.name) if collider != null else "?", shape_name]


func _walk_deck(boat: Node) -> Node:
	var parent := boat.get_parent()
	var walk: Node = null
	if parent != null:
		walk = parent.get_node_or_null("WalkDeck")
	if walk == null:
		walk = boat.get_node_or_null("WalkDeck")
	return walk


func _ring(boat: Node) -> PackedVector2Array:
	var mi := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if mi == null or not mi.has_meta("plate_args"):
		return PackedVector2Array()
	var args: Dictionary = mi.get_meta("plate_args")
	var raw: PackedVector2Array = args.get("ring", PackedVector2Array())
	var shift := Vector2(mi.position.x, mi.position.z)
	var out := PackedVector2Array()
	for point in raw:
		out.append(point + shift)
	return out


func _outside_by(ring: PackedVector2Array, point: Vector2) -> float:
	var n := ring.size()
	if n < 3:
		return 0.0
	var area := 0.0
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sign := 1.0 if area >= 0.0 else -1.0
	var worst := -1e18
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var edge := b - a
		var length := edge.length()
		if length < 1e-9:
			continue
		var cross := (edge.x * (point.y - a.y) - edge.y * (point.x - a.x)) * sign
		worst = maxf(worst, -cross / length)
	return maxf(worst, 0.0)
