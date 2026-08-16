extends Node

## CRITIC SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Lane B. Attacks the WINDOW, not the pairing.
##
## Even correctly paired, begin/end takes the WalkDeck out of its physics space
## for the whole fit-out loop. Measured here, on the heaviest shipped fixture:
##   E1. does a physics frame ever land inside the window?
##   E2. refit cost on a quiet tree, batched vs the same loop unbatched.
##   E3. a real CharacterBody3D standing on the deck: where does it end up
##       across a refit, and where does it end up if it is stepped INSIDE the
##       window.
##   E4. the staged path (>1000 bricks): does it batch at all?

const CaptureSubject := preload("res://tests/support/capture_subject.gd")

const FEEDER := "res://resources/data/structures/probe_container_feeder.json"
const BULWARK := "res://resources/data/structures/probe_trawler_bulwark.json"
const WORKBOAT := "res://resources/data/structures/demo_workboat.json"
const HULL_ID := "hull_28x10"
const REGISTRATION := "fishing_vessel"
const LAYER_BOAT_WALK := 4
const LAYER_PLAYER := 8


func _ready() -> void:
	await _e1_and_e3()
	await _e2()
	await _e4()
	get_tree().quit()


func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


# ── E1 / E3 ─────────────────────────────────────────────────────────────────

func _e1_and_e3() -> void:
	print("\n=== E1/E3. a player on the deck across a real refit ===")
	var layout := _load(FEEDER)
	var plan := StructurePlan.from_dict(layout)
	var boat: Node3D = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
	add_child(boat)
	for _i in 4:
		await get_tree().physics_frame
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	var deck_y := walk.global_transform.origin.y

	## A player-sized CharacterBody3D on the boat_walk layer, exactly as
	## scenes/shared/player.tscn masks it.
	var body := CharacterBody3D.new()
	body.collision_layer = LAYER_PLAYER
	body.collision_mask = LAYER_BOAT_WALK
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(0.0, deck_y + 1.2, 0.0)
	for _i in 40:
		body.velocity.y -= 9.8 / 60.0
		body.move_and_slide()
		if body.is_on_floor():
			body.velocity.y = 0.0
		await get_tree().physics_frame
	var settled := body.global_position.y
	print("[E3] settled on deck at y = %.3f m (deck slab y = %.3f, on_floor=%s)"
		% [settled, deck_y, str(body.is_on_floor())])

	var frames_before := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	DeckFitout.apply_plan(boat as BoatBody, plan)
	var refit_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var frames_after := Engine.get_physics_frames()
	print("[E1] apply_plan took %.1f ms; physics frames advanced during it: %d"
		% [refit_ms, frames_after - frames_before])
	print("[E3] player y immediately after apply_plan returned: %.3f m (moved %.4f m)"
		% [body.global_position.y, body.global_position.y - settled])
	for _i in 30:
		body.velocity.y -= 9.8 / 60.0
		body.move_and_slide()
		if body.is_on_floor():
			body.velocity.y = 0.0
		await get_tree().physics_frame
	print("[E3] player y after 30 more physics frames: %.3f m (moved %.4f m from settled)"
		% [body.global_position.y, body.global_position.y - settled])

	## What a single physics step INSIDE the window would cost, if anything ever
	## managed to land one there. Stepped by hand — no frame is allowed to pass.
	var before_window := body.global_position.y
	(boat as BoatBody).begin_walk_collider_batch()
	for _i in 30:
		body.velocity.y -= 9.8 / 60.0
		body.move_and_slide()
		if body.is_on_floor():
			body.velocity.y = 0.0
	(boat as BoatBody).end_walk_collider_batch()
	print("[E3] 30 hand-driven move_and_slide steps INSIDE an open window: "
		+ "y %.3f -> %.3f m (fell %.3f m, on_floor=%s)"
		% [before_window, body.global_position.y,
			before_window - body.global_position.y, str(body.is_on_floor())])
	body.queue_free()
	boat.queue_free()
	await get_tree().physics_frame


# ── E2 ──────────────────────────────────────────────────────────────────────

func _e2() -> void:
	print("\n=== E2. refit cost on a quiet tree ===")
	print("%-30s %7s %12s %14s %12s %9s"
		% ["fixture", "boxes", "apply_plan", "loop unbatched", "loop batched", "speedup"])
	for path in [WORKBOAT, BULWARK, FEEDER]:
		var layout := _load(path)
		var plan := StructurePlan.from_dict(layout)
		var boxes := StructureBaker.collect_colliders(plan)
		var boat: Node3D = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
		add_child(boat)
		for _i in 4:
			await get_tree().physics_frame
		var bb := boat as BoatBody

		var t0 := Time.get_ticks_usec()
		DeckFitout.apply_plan(bb, plan)
		var full_ms := float(Time.get_ticks_usec() - t0) / 1000.0

		## Same boxes, same order, at the same seam apply_plan uses — once with
		## the window and once without, so the pair isolates the window.
		bb.clear_walk_brick_colliders()
		t0 = Time.get_ticks_usec()
		_emit(bb, boxes, false)
		var slow_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		bb.clear_walk_brick_colliders()
		t0 = Time.get_ticks_usec()
		_emit(bb, boxes, true)
		var fast_ms := float(Time.get_ticks_usec() - t0) / 1000.0

		print("%-30s %7d %10.1f ms %12.1f ms %10.1f ms %8.1fx"
			% [path.get_file(), boxes.size(), full_ms, slow_ms, fast_ms,
				slow_ms / maxf(fast_ms, 0.001)])
		boat.queue_free()
		await get_tree().physics_frame


func _emit(boat: BoatBody, boxes: Array, batched: bool) -> void:
	if batched:
		boat.begin_walk_collider_batch()
	var i := 0
	for b_variant in boxes:
		var b := b_variant as Dictionary
		boat.add_walk_brick_collider(
			"plan_%d" % i, b["center"] as Vector3, b["size"] as Vector3,
			float(b.get("yaw_deg", 0.0)))
		i += 1
	if batched:
		boat.end_walk_collider_batch()


# ── E4 ──────────────────────────────────────────────────────────────────────

func _e4() -> void:
	print("\n=== E4. the staged path (>1000 bricks) ===")
	var layout := BrickLayout.new()
	layout.hull_id = "fishing_trawler_small"
	## Was `range(-20, 20)` on both axes — 800 of the 1600 cells had a negative
	## index and were written into the sea, which is exactly the defect this
	## probe's own subject now refuses. Anchored on the real grid instead, so the
	## staged path is still exercised by >1000 bricks that are all ON the deck.
	var grid := HullRegistry.make_grid("fishing_trawler_small")
	var n := 0
	for x in range(grid.width):
		for z in range(grid.length):
			if layout.set_brick(grid, Vector3i(x, 0, z), "block", 0):
				n += 1
	print("[E4] layout has %d primary cells (threshold is %d)"
		% [layout.iter_primary_cells().size(), DeckFitout.LARGE_LAYOUT_THRESHOLD])
	var boat := BoatBody.new()
	boat.freeze = true
	boat.gravity_scale = 0.0
	boat.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	add_child(boat)
	## E4's boat is meant to be inert scaffolding for a fit-out timing, so it gets
	## the shared hold. `automatic_physics_lod` would otherwise revoke the `freeze`
	## above — see `tests/support/capture_subject.gd`.
	##
	## The E1/E3 vessels at the top of this file deliberately do NOT get it: they
	## are `VesselSpawn.instantiate` boats carrying a player across a real refit,
	## with no `freeze` of their own, and `hold_still` would put them in SLEEP —
	## which stops `StripBuoyancyComponent`, `HydrodynamicsComponent` and three
	## more from processing and so changes the very cost E1/E3 measure.
	CaptureSubject.hold_still(boat)
	boat.ensure_walk_deck()
	for _i in 3:
		await get_tree().physics_frame
	var walk := boat.get_walk_deck()
	var t0 := Time.get_ticks_usec()
	DeckFitout.apply(boat, layout)
	print("[E4] DeckFitout.apply returned in %.1f ms, staged=%s"
		% [float(Time.get_ticks_usec() - t0) / 1000.0,
			str(DeckFitout.capabilities_of(boat).get("staged", false))])
	var max_depth := 0
	var out_of_space_frames := 0
	var frames := 0
	while frames < 900:
		await get_tree().process_frame
		frames += 1
		max_depth = maxi(max_depth, int(boat.get("_walk_collider_batch_depth")))
		if not PhysicsServer3D.body_get_space(walk.get_rid()).is_valid():
			out_of_space_frames += 1
		var job := boat.get_node_or_null(DeckFitout.FITOUT_JOB)
		if job == null or bool(job.call("is_complete")):
			break
		if frames == 1:
			DeckFitout.request_full_detail(boat)
	print("[E4] staged mount finished after %d frames; "
		% frames
		+ "max collider-batch depth observed = %d; frames with the WalkDeck out of its space = %d"
		% [max_depth, out_of_space_frames])
	print("[E4] shapes on the body at the end: %d"
		% PhysicsServer3D.body_get_shape_count(walk.get_rid()))
	boat.queue_free()
	await get_tree().physics_frame
