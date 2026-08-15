extends Node

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Lane B: needs the autoloads `VesselSpawn` / `HullRegistry` reach for.
##
## What does building a REAL vessel's collision cost, on the production path,
## on the four fixtures the wave named? `_plate_cost_probe` timed a synthetic
## StaticBody3D; this one times `VesselSpawn` and `DeckFitout` themselves.
##
## Two paths, because they are not the same price and conflating them would
## claim a fix for a stall that only one of them ever paid:
##
##   spawn    VesselSpawn.instantiate(hull, plan) — the fit-out runs with the
##            boat still OUT of the tree, so the WalkDeck has no physics space
##            and the adds were already linear. Then add_child + 2 physics
##            frames, which is where the finished shape set reaches the server.
##   refit    DeckFitout.apply_plan on a boat ALREADY IN THE TREE, with a live
##            space on its WalkDeck. This is what the shipyard editor does when
##            you change a plan, what `apply_brick_layout` does, and what
##            `ReplicationDrawingService` does for every remote vessel drawing.
##            It is the quadratic one.
##
## `shapes` is read back off the WalkDeck body through PhysicsServer3D after the
## refit, so a "fast" refit that quietly attached nothing cannot be reported as
## a win.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURES := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_piece_house.json",
	"res://resources/data/structures/probe_container_feeder.json",
]


func _ready() -> void:
	print("%-28s %7s %10s %10s %10s %8s"
		% ["fixture", "boxes", "spawn ms", "attach ms", "refit ms", "shapes"])
	for path in FIXTURES:
		await _survey(str(path))
	get_tree().quit()


func _survey(path: String) -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	if doc == null:
		print("%-28s unparseable" % path.get_file())
		return
	var plan := StructurePlan.from_dict(doc)
	var boxes := StructureBaker.collect_colliders(plan).size()
	var hull_id := str(doc.get("hull_id", "hull_28x10"))

	var t0 := Time.get_ticks_usec()
	var boat: Node3D = VesselSpawn.instantiate(hull_id, doc, "")
	var spawn_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if boat == null:
		print("%-28s spawn failed" % path.get_file())
		return

	var t1 := Time.get_ticks_usec()
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var attach_ms := float(Time.get_ticks_usec() - t1) / 1000.0

	## The in-tree re-fit-out: same plan, same boat, live physics space.
	var t2 := Time.get_ticks_usec()
	DeckFitout.apply_plan(boat as BoatBody, plan)
	var refit_ms := float(Time.get_ticks_usec() - t2) / 1000.0
	await get_tree().physics_frame

	var walk := (boat as BoatBody).call("get_walk_deck") as CollisionObject3D
	var shapes := 0
	if walk != null:
		shapes = PhysicsServer3D.body_get_shape_count(walk.get_rid())

	print("%-28s %7d %10.1f %10.1f %10.1f %8d"
		% [path.get_file().get_basename(), boxes, spawn_ms, attach_ms, refit_ms, shapes])
	boat.queue_free()
	if walk != null and is_instance_valid(walk) and walk.get_parent() == self:
		walk.queue_free()
	await get_tree().physics_frame
