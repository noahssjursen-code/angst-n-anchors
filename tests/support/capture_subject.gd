extends RefCounted

## NO `class_name`: reached by `preload`, so it registers no global identifier
## and cannot break the `--script` lane (CONVENTIONS §2).

## HOLD THE SUBJECT STILL, so a capture photographs a stated pose instead of
## whatever point of a buoyancy transient the frame happened to land on.
##
## ── Why this exists ────────────────────────────────────────────────────────
##
## Every capture rig in this repo that stands a vessel up writes
##
##     boat.freeze = true
##
## and believes the hull is now static. **It is not.** `BoatBody._physics_process`
## accumulates `_physics_lod_timer` and, one second after the hull enters the
## tree, runs `_update_automatic_physics_quality()`. In a capture rig there is no
## node in the `PlayerVessel` group, so `nearest_distance` stays `INF` and the
## first branch taken is
##
##     if nearest_distance == INF or nearest_distance < medium_physics_distance_m:
##         set_physics_quality(PhysicsQuality.FULL)
##
## and `set_physics_quality` then executes `freeze = physics_quality == SLEEP`,
## i.e. **`freeze = false`**, and re-enables `StripBuoyancyComponent`. The rig's
## freeze is silently revoked and the hull sinks to its buoyancy equilibrium.
##
## ── The measurement, 2026-08-16 ────────────────────────────────────────────
##
## `tests/_repro_diag_probe.gd`, one process, one static camera, 60 consecutive
## grabs of a scene in which nothing is animated:
##
##   * grabs 0–6 byte-identical (the hull is still frozen);
##   * grab 7 onward the hull moves — `linear_velocity.y` leaves zero and
##     `global_transform.origin.y` walks from −3.049999952 to −3.048851490, a
##     damped oscillation of **1.15 mm** lasting ~32 further frames;
##   * grabs 39–59 byte-identical again (it has come to rest).
##
## 1.15 mm is **0.2 px** at `hull_15x5__bow_on_ortho`'s 9 m across 1600 px. That
## is invisible and it moves every silhouette and every shadow boundary by a
## pixel, which is why the residue was read as "a sub-pixel edge race" and why
## it moves every md5.
##
## On the `VesselSpawn` path (`tests/_fittings_diag_probe.gd`) the same thing
## happens: the hull drops **1.45 mm** and settles, while `time_of_day`,
## `fog_density`, `daylight_factor()` and `artificial_light_scale()` are constant
## in their exact float bits for the whole run.
##
## ── Why it is nondeterministic between runs rather than merely wrong ───────
##
## `CaptureClock.settle()` counts PROCESS frames. Physics ticks are driven by
## the wall clock, and under llvmpipe a process frame here costs 250–430 ms, so
## **15 to 26 physics ticks elapse per rendered frame** and the exact number
## depends on machine load. Each run therefore samples the transient at a
## different phase. That is why these rigs move more when another chain is live
## on the box, and why a fast back-to-back pair can agree by luck.
##
## ── What to do ─────────────────────────────────────────────────────────────
##
## Call `hold_still(boat)` after `add_child` and before positioning. It is the
## recipe `scripts/apps/shipyard_brick_editor.gd` already uses, for this exact
## reason, in a comment that has been in the tree longer than any of these rigs:
## *"After enter-tree, BoatBody LOD would flip freeze off and buoyancy lifts the
## hull."*
##
## `tests/capture_subject_still_test.gd` is the scored unit for this guarantee.
static func hold_still(boat: Node) -> void:
	if boat == null:
		return
	## Order matters: stop the LOD from running at all, THEN state the quality.
	## Disabling the LOD alone would leave whatever quality was last applied.
	if "automatic_physics_lod" in boat:
		boat.set("automatic_physics_lod", false)
	if boat.has_method("set_physics_quality"):
		boat.call("set_physics_quality", BoatBody.PhysicsQuality.SLEEP)
	if "freeze" in boat:
		boat.set("freeze", true)
	if boat is RigidBody3D:
		var body := boat as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
