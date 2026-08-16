extends Node3D

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_walk_bow_body_drive.tscn
##
## CAN A PLAYER BODY ACTUALLY REACH THE WALK SLAB PAST THE BOW?
##
## `_walk_slab_over_water_probe` casts a downward RAY on the `boat_walk` mask and
## finds floor well outside the drawn plate. A ray proves the collider exists. It
## does not prove a `CharacterBody3D` can get there: a bulwark, a rail or the
## hull box could be in the way. This drives the real thing.
##
## The body is `scenes/shared/player.tscn`'s: a capsule radius 0.35 / height 1.8
## (0.70 m across), collision_layer `LAYER_PLAYER`, collision_mask
## `1 | LAYER_BOAT_WALK` — the exact masks `player.gd:_ready` sets. It is dropped
## amidships, allowed to settle on whatever holds it up, then driven at
## `walk_speed` = 4.5 m/s toward the stem with `player.gd`'s gravity (20.0),
## `floor_snap_length` 0.35, `floor_max_angle` 48 degrees and its 0.45 m step-up.
##
## Steps are HAND-DRIVEN (`move_and_slide` with no frame passing), which is the
## technique `_critic_window` uses: the vessel is held still, so the world the
## capsule queries is static and stepping it would change nothing but the wall
## clock. `_frames_control` re-runs one lane awaiting a real `physics_frame`
## between every step, as a control on exactly that assumption.
##
## `CaptureSubject.hold_still` is called before anything is measured — a
## BoatBody's LOD revokes `freeze` one second after it enters the tree, and a
## drifting hull would move every number here.
##
## ── WHAT IT MEASURED, 2026-08-16 ────────────────────────────────────────────
##
## BEFORE (`_walk_deck_box_size` a rectangle, as shipped): on a BARE hull the
## body walked out over open sea and kept standing.
##
##   hull          lane x   crossed the drawn edge at   furthest supported stance
##   hull_28x10      2.50        z −11.550                +1.732 m at z −13.950
##   hull_28x10      4.75        z  −9.300                +3.323 m at z −13.950
##   hull_150x32     8.00        z −67.050                +5.604 m at z −74.925
##   hull_150x32    15.20        z −59.850               +10.695 m at z −74.925
##
## and in every case it then walked off the forward face of the rectangle at
## z = −L/2 and fell into the sea. The centreline lane never left the drawn deck
## because the plate's point IS at z = −L/2. The control — the same lane with a
## real `physics_frame` awaited between every step — reproduced +3.323 m
## exactly, so the hand-driven technique is not what produced the number.
##
## AFTER (both walk shapes cut from `plate_args.ring`): every lane of both bare
## hulls reads "never stood outside the drawn deck". The body walks to the deck
## edge and falls, control +0.000 m.
##
## THE FITTED VESSELS NEVER GOT THERE, before or after. `probe_trawler_bulwark`
## stops the body on its bow bulwark at z ≈ −14.3 and its deckhouse at z ≈ −6.5;
## `probe_container_feeder` stops it at z ≈ −73.5. So the defect was live on the
## hull a player has just BOUGHT — `VesselSpawn.default_brick_layout` is "bare
## deck — humans place every brick" — and fenced on the two shipped fixtures.
## That is two fixtures and three lanes each, not a proof about fitted vessels
## in general: a plan with a gangway gap in its bulwark was not tried.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")

const LAYER_WORLD := 1
const LAYER_BOAT_WALK := 4
const LAYER_PLAYER := 8

## scenes/shared/player.tscn
const CAPSULE_R := 0.35
const CAPSULE_H := 1.8
## scripts/player/player.gd
const WALK_SPEED := 4.5
const GRAVITY := 20.0
const STEP_HEIGHT := 0.45
const SNAP := 0.35
const FLOOR_MAX_ANGLE_DEG := 48.0

const STEP_DT := 1.0 / 60.0
## Stop the march when the body has fallen this far below the deck it started on.
const FELL_BELOW := 3.0
## Progress under this in one step, with the drive still pushing, is "stopped".
const STALL_M := 0.002
const STALL_STEPS := 12
## How far AFT of the drawn deck edge the `foredeck` march starts.
const APPROACH_M := 3.0

const CASES: Array[Dictionary] = [
	{"hull": "hull_28x10", "plan": "", "lanes": [0.0, 2.5, 4.75]},
	{
		"hull": "hull_28x10",
		"plan": "res://resources/data/structures/probe_trawler_bulwark.json",
		"lanes": [0.0, 2.5, 4.75],
	},
	{"hull": "hull_150x32", "plan": "", "lanes": [0.0, 8.0, 15.2]},
	{
		"hull": "hull_150x32",
		"plan": "res://resources/data/structures/probe_container_feeder.json",
		"lanes": [0.0, 8.0, 15.2],
	},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for case in CASES:
		await _drive_case(case)
	await _frames_control()
	get_tree().quit(0)


## THE CONTROL ON THE HAND-DRIVEN STEP. Same lane, same drive, but a real
## `physics_frame` is awaited between every step, so the physics server is
## actually ticked. If the two disagree, every number above is an artefact of
## the technique rather than a fact about the vessel.
func _frames_control() -> void:
	print("\n=== CONTROL — hull_28x10, lane x=+4.75, one real physics frame per step ===")
	var boat: Node3D = VesselSpawn.instantiate("hull_28x10", {}, "")
	add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3.ZERO
	for i in range(10):
		await get_tree().physics_frame
	var ring := _ring(boat)
	var walk := _walk_deck(boat)
	var body := _make_body()
	add_child(body)
	body.global_position = Vector3(4.75, _slab_top(walk) + 0.60, 0.0)
	for i in range(120):
		_step(body, Vector3.ZERO)
		await get_tree().physics_frame
		if body.is_on_floor() and absf(body.velocity.y) < 0.001:
			break
	var worst := 0.0
	var worst_at := Vector3.ZERO
	for i in range(400):
		_step(body, Vector3(0.0, 0.0, -1.0))
		await get_tree().physics_frame
		var p := body.global_position
		var outside := _outside_by(ring, Vector2(p.x, p.z))
		if outside > worst and body.is_on_floor() and _floor_under(body) != "(nothing)":
			worst = outside
			worst_at = p
		if p.y < 2.0 or p.z < -18.0:
			break
	print("  furthest supported stance over water: %+.3f m at (%.3f, %.3f, %.3f)"
		% [worst, worst_at.x, worst_at.y, worst_at.z])
	body.queue_free()
	remove_child(boat)
	boat.queue_free()
	await get_tree().process_frame


func _drive_case(case: Dictionary) -> void:
	var hull_id := str(case["hull"])
	var plan_path := str(case["plan"])
	var layout: Dictionary = {}
	if not plan_path.is_empty():
		layout = _load(plan_path)
	var boat: Node3D = VesselSpawn.instantiate(hull_id, layout, "")
	add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3.ZERO
	for i in range(10):
		await get_tree().physics_frame

	var stations: HullStations = boat.get("hull_stations")
	var hull_size: Vector3 = boat.get("hull_size")
	var walk := _walk_deck(boat)
	var slab_top := _slab_top(walk)
	var ring := _ring(boat)
	print("\n=== %s%s ===" % [
		hull_id, "" if plan_path.is_empty() else "  +  " + plan_path.get_file(),
	])
	print("  hull_size %v · deck_y %.3f · walk slab top y %.3f · %d walk shapes · ring %d pts"
		% [hull_size, stations.deck_y, slab_top, _shape_count(walk), ring.size()])
	print("  drawn plate reaches z = %+.3f on the centreline; hull rectangle ends at z = %+.3f"
		% [_ring_min_z_at(ring, 0.0), -hull_size.z * 0.5])

	for lane in case["lanes"]:
		## Two starts. AMIDSHIPS is the whole journey and is the honest one on a
		## bare hull. FOREDECK exists because a fitted vessel's deckhouse and
		## cargo stop an amidships march long before the bow, which answers
		## nothing about the bow: it drops the figure on the last drawn deck of
		## that lane and asks whether it can cross the deck EDGE.
		await _march_lane(boat, walk, ring, float(lane), slab_top, hull_size, 0.0, "amidships")
		var edge_z := _ring_min_z_at(ring, float(lane))
		if edge_z < 1e17:
			await _march_lane(
				boat, walk, ring, float(lane), slab_top, hull_size,
				edge_z + APPROACH_M, "foredeck"
			)

	remove_child(boat)
	boat.queue_free()
	if walk != null and is_instance_valid(walk) and walk.get_parent() != null:
		walk.get_parent().remove_child(walk)
		walk.queue_free()
	await get_tree().process_frame


func _march_lane(
	boat: Node3D,
	walk: Node,
	ring: PackedVector2Array,
	lane_x: float,
	slab_top: float,
	hull_size: Vector3,
	start_z_at: float,
	label: String,
) -> void:
	var body := _make_body()
	add_child(body)
	## Above the deck, and let it fall onto whatever is there.
	body.global_position = Vector3(lane_x, slab_top + 0.60, start_z_at)
	var settled := _settle(body, 240)
	if not settled:
		print("  lane x=%+.2f %-9s : NEVER SETTLED at z %+.3f (y %.3f)"
			% [lane_x, label, start_z_at, body.global_position.y])
		body.queue_free()
		return
	var start_y := body.global_position.y
	var start_z := body.global_position.z

	var stalled := 0
	var steps := 0
	var fell := false
	var out_of_slab := false
	var last_z := start_z
	## The money number: the furthest OUTSIDE THE DRAWN DECK the figure ever
	## stands while something is holding it up.
	var worst_supported := 0.0
	var worst_at := Vector3.ZERO
	var worst_on := ""
	var first_over_water := Vector3.ZERO
	var have_crossing := false
	var max_steps := int((hull_size.z * 0.5 + 25.0) / (WALK_SPEED * STEP_DT)) + 240
	while steps < max_steps:
		steps += 1
		_step(body, Vector3(0.0, 0.0, -1.0))
		var p := body.global_position
		var outside_now := _outside_by(ring, Vector2(p.x, p.z))
		var under := _floor_under(body)
		if outside_now > 0.001 and body.is_on_floor() and under != "(nothing)":
			if not have_crossing:
				first_over_water = p
				have_crossing = true
			if outside_now > worst_supported:
				worst_supported = outside_now
				worst_at = p
				worst_on = under
		if absf(p.z - last_z) < STALL_M:
			stalled += 1
		else:
			stalled = 0
		last_z = p.z
		if p.y < start_y - FELL_BELOW:
			fell = true
			break
		if p.z < -hull_size.z * 0.5 - 2.0:
			out_of_slab = true
			break
		if stalled >= STALL_STEPS:
			break

	var final := body.global_position
	var why := ""
	if fell:
		why = "FELL — dropped %.3f m below the deck it started on" % (start_y - final.y)
	elif out_of_slab:
		why = "walked clean off the forward end of the hull rectangle and fell"
	else:
		why = _why_blocked(body)
	print("  lane x=%+.2f %-9s : start z %+.3f y %.3f -> stop z %+.3f y %.3f (%d steps)"
		% [lane_x, label, start_z, start_y, final.z, final.y, steps])
	if have_crossing:
		print("      crossed the drawn deck edge at z %+.3f (still supported)"
			% first_over_water.z)
		print("      FURTHEST SUPPORTED STANCE OVER WATER: %+.3f m outboard of the drawn"
			% worst_supported
			+ " deck, at (%.3f, %.3f, %.3f), on %s"
				% [worst_at.x, worst_at.y, worst_at.z, worst_on])
	else:
		print("      never stood outside the drawn deck")
	print("      stopped because: %s" % why)
	body.queue_free()


## One physics step of `player.gd`'s ground movement: drive, gravity, slide, and
## the ghost-cast step-up that lets a player mount a 0.45 m lip.
func _step(body: CharacterBody3D, dir: Vector3) -> void:
	var on_floor := body.is_on_floor()
	if not on_floor:
		body.velocity.y -= GRAVITY * STEP_DT
	elif body.velocity.y < 0.0:
		body.velocity.y = 0.0
	body.velocity.x = dir.x * WALK_SPEED
	body.velocity.z = dir.z * WALK_SPEED
	var before := body.global_position
	body.move_and_slide()
	if not body.is_on_wall():
		return
	## Step-up: lift, try the same motion, drop back on.
	var lifted := body.global_transform
	lifted.origin += Vector3.UP * STEP_HEIGHT
	var motion := dir * WALK_SPEED * STEP_DT
	var probe := PhysicsTestMotionParameters3D.new()
	probe.from = lifted
	probe.motion = motion
	var result := PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(body.get_rid(), probe, result):
		return
	var landed := lifted
	landed.origin += motion
	var down := PhysicsTestMotionParameters3D.new()
	down.from = landed
	down.motion = Vector3.DOWN * (STEP_HEIGHT + 0.02)
	var down_result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), down, down_result):
		return
	landed.origin += Vector3.DOWN * (STEP_HEIGHT + 0.02) * down_result.get_collision_safe_fraction()
	if landed.origin.distance_to(before) > 0.001:
		body.global_transform = landed


func _settle(body: CharacterBody3D, max_steps: int) -> bool:
	for i in range(max_steps):
		_step(body, Vector3.ZERO)
		if body.is_on_floor() and absf(body.velocity.y) < 0.001:
			return true
		if body.global_position.y < -200.0:
			return false
	return body.is_on_floor()


func _why_blocked(body: CharacterBody3D) -> String:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = body.global_transform
	params.motion = Vector3(0.0, 0.0, -0.25)
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return "nothing blocks it — the drive simply stopped advancing"
	var collider := result.get_collider()
	var shape_index := result.get_collider_shape()
	var shape_name := "?"
	if collider is CollisionObject3D:
		var owner_id := (collider as CollisionObject3D).shape_find_owner(shape_index)
		var owner_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if owner_node != null:
			shape_name = str(owner_node.name)
	return "BLOCKED by %s / shape %s at %v" % [
		str(collider.name) if collider != null else "?",
		shape_name,
		result.get_collision_point().snappedf(0.001),
	]


func _floor_under(body: CharacterBody3D) -> String:
	var space := get_viewport().world_3d.direct_space_state
	var from := body.global_position + Vector3.UP * 0.10
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5)
	query.collision_mask = LAYER_WORLD | LAYER_BOAT_WALK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "(nothing)"
	var collider: Object = hit.get("collider")
	var name := str(collider.name) if collider != null else "?"
	var shape_name := "?"
	if collider is CollisionObject3D:
		var owner_id := (collider as CollisionObject3D).shape_find_owner(int(hit.get("shape", 0)))
		var owner_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if owner_node != null:
			shape_name = str(owner_node.name)
	return "%s/%s at y %.3f" % [name, shape_name, (hit["position"] as Vector3).y]


func _make_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = LAYER_PLAYER
	body.collision_mask = LAYER_WORLD | LAYER_BOAT_WALK
	body.floor_snap_length = SNAP
	body.floor_stop_on_slope = true
	body.floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE_DEG)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_R
	cap.height = CAPSULE_H
	cs.shape = cap
	cs.position = Vector3(0.0, CAPSULE_H * 0.5, 0.0)
	body.add_child(cs)
	return body


func _walk_deck(boat: Node) -> Node:
	var parent := boat.get_parent()
	var walk: Node = null
	if parent != null:
		walk = parent.get_node_or_null("WalkDeck")
	if walk == null:
		walk = boat.get_node_or_null("WalkDeck")
	return walk


## The top of the walk slab, whatever shape it carries. Reading `.size.y` off a
## `BoxShape3D` cast silently returns the slab's mid-plane once the slab is a
## convex prism.
func _slab_top(walk: Node) -> float:
	if walk == null:
		return 0.0
	var cs := walk.get_node_or_null("WalkDeckCollider") as CollisionShape3D
	if cs == null:
		return 0.0
	var box := cs.shape as BoxShape3D
	if box != null:
		return cs.global_position.y + box.size.y * 0.5
	var convex := cs.shape as ConvexPolygonShape3D
	if convex != null:
		var top := -1e18
		for point in convex.points:
			top = maxf(top, point.y)
		return cs.global_position.y + top
	return cs.global_position.y


func _shape_count(walk: Node) -> int:
	if walk == null:
		return 0
	return (walk as CollisionObject3D).get_shape_owners().size()


func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


## The weather deck's own plan polygon, ship-local. Same reader as
## `grid_deck_outline_test`: the ring the drawn mesh was extruded from.
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


func _ring_min_z_at(ring: PackedVector2Array, x: float) -> float:
	var best := 1e18
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if absf(b.x - a.x) < 1e-9:
			if absf(a.x - x) < 1e-6:
				best = minf(best, minf(a.y, b.y))
			continue
		var t := (x - a.x) / (b.x - a.x)
		if t < 0.0 or t > 1.0:
			continue
		best = minf(best, a.y + t * (b.y - a.y))
	return best


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
