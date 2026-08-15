extends Node

## Scratch probe (leading underscore = not a gate unit). Lane B: needs autoloads.
##
## THE QUESTION. `DeckFitout.apply_staged` (>1000 bricks) was left paying the
## quadratic that `begin/end_walk_collider_batch` removed from the synchronous
## path, on the stated ground that a batch cannot span frames. Before proposing
## anything: WHICH PHASE is the cost in, what SHAPE is it, and how much of a
## >1000-brick fit-out is collision rather than everything else?
##
## REALITY.md §4e: a profile says where, never why. So this varies ONE input —
## whether the WalkDeck body is in a physics space — with the box count, the
## sizes, the yaws and the order held identical, and reports both curves.
##
## Timings are wall clock on Mesa llvmpipe / 4 cores. `usec_by_phase` brackets
## only DeckFitoutJob's own `_step` loop, never the frame's draw, so the SHAPE of
## these curves is machine-independent and the milliseconds are not.

const HULL_ID := "hull_90x24"
const REGISTRATION := "general_vessel"

var _counts: Array = [1001, 1500, 2000]
var _rows: Array = []
var _timeline: Array = []


func _ready() -> void:
	var arg_counts: Array = []
	for arg in OS.get_cmdline_user_args():
		if str(arg).is_valid_int():
			arg_counts.append(int(arg))
	if not arg_counts.is_empty():
		_counts = arg_counts
	print("staged collision probe — hull=%s counts=%s" % [HULL_ID, str(_counts)])
	for count in _counts:
		await _run(int(count), true)
		await _run(int(count), false)
	_summarise()
	get_tree().quit(0)


## `in_space` false is the CONTROL: the WalkDeck body is pulled out of its
## physics space for the whole staged run, by hand, through PhysicsServer3D —
## not through `begin_walk_collider_batch`, whose depth counter would make
## `BoatBody._physics_process`'s watchdog force it closed again. Everything else
## about the run is identical. This is not a proposed fix; it is the one-input
## variation that says how much of the phase is the Jolt compound rebuild.
func _run(count: int, in_space: bool) -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, count)
	var placed := layout.count()
	var boat := VesselSpawn.instantiate(HULL_ID, {"hull_id": HULL_ID, "cells": {}})
	if boat == null:
		print("  n=%d SPAWN FAILED" % count)
		return
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walk := boat.get_walk_deck() as CollisionObject3D
	if walk == null:
		print("  n=%d NO WALKDECK" % count)
		boat.queue_free()
		return
	var rid := walk.get_rid()
	var world_space := PhysicsServer3D.body_get_space(rid)
	if not in_space:
		PhysicsServer3D.body_set_space(rid, RID())

	var frames_before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	DeckFitout.apply(boat, layout, grid, REGISTRATION)
	## THE BINDING CONSTRAINT, sampled rather than argued. Every physics frame of
	## the fit-out, how many brick colliders are actually on the body — so "for how
	## long is a vessel a player is standing on missing its walls" is a measured
	## number on both sides of the change, not a claim about which design ought to
	## be safer. `missing_ms` integrates the MISSING FRACTION over wall time, which
	## is the figure that moves when colliders arrive progressively rather than all
	## at once.
	_timeline.clear()
	await _wait_for_sampling(boat, walk, DeckFitout.READINESS_INTERACTIVE, 20000, t0)
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var frames := Engine.get_frames_drawn() - frames_before
	var expected_cols := placed
	var first_col_ms := -1.0
	var all_col_ms := -1.0
	var missing_ms := 0.0
	var prev_ms := 0.0
	for sample_raw in _timeline:
		var sample := sample_raw as Dictionary
		var at := float(sample["ms"])
		var live := int(sample["cols"])
		missing_ms += (at - prev_ms) * (1.0 - float(live) / float(maxi(expected_cols, 1)))
		prev_ms = at
		if live > 0 and first_col_ms < 0.0:
			first_col_ms = at
		if live >= expected_cols and all_col_ms < 0.0:
			all_col_ms = at
	print(
		"      collider timeline: first box at %.0fms, all %d at %.0fms, "
		% [first_col_ms, expected_cols, all_col_ms]
		+ "brick collision missing for %.0fms of %.0fms wall (%d samples)"
		% [missing_ms, wall_ms, _timeline.size()]
	)

	if not in_space:
		PhysicsServer3D.body_set_space(rid, world_space)
	var by_phase: Dictionary = boat.get_meta("fitout_usec_by_phase", {})
	var steps: Dictionary = boat.get_meta("fitout_steps_by_phase", {})
	var indivisible: Array = boat.get_meta("fitout_indivisible_steps", [])
	var shapes := PhysicsServer3D.body_get_shape_count(rid)
	var brick_children := 0
	for child in walk.get_children():
		if child is CollisionShape3D and str(child.name).begins_with("BrickCol_"):
			brick_children += 1
	var row := {
		"n": placed,
		"in_space": in_space,
		"wall_ms": wall_ms,
		"frames": frames,
		"shapes": shapes,
		"brick_children": brick_children,
		"indivisible_ms": _indivisible_ms(indivisible),
	}
	var total_step_ms := 0.0
	for phase in by_phase:
		row["ph_%s" % phase] = float(by_phase[phase]) / 1000.0
		total_step_ms += float(by_phase[phase]) / 1000.0
	row["step_total_ms"] = total_step_ms
	_rows.append(row)
	print(
		"  n=%d in_space=%s wall=%.0fms frames=%d step_total=%.0fms shapes=%d brickcols=%d"
		% [placed, str(in_space), wall_ms, frames, total_step_ms, shapes, brick_children]
	)
	var phase_bits := PackedStringArray()
	for phase in ["REGISTER_SKIN", "EXTERIOR_VISUALS", "INTERIOR_VISUALS", "GAMEPLAY"]:
		phase_bits.append(
			"%s=%.0fms/%dsteps"
			% [phase, float(by_phase.get(phase, 0)) / 1000.0, int(steps.get(phase, 0))]
		)
	print("      " + "  ".join(phase_bits))
	for step_raw in indivisible:
		var step := step_raw as Dictionary
		print(
			"      indivisible %s = %.1fms"
			% [str(step.get("name", "?")), float(step.get("usec", 0)) / 1000.0]
		)
	boat.queue_free()
	await get_tree().process_frame


func _indivisible_ms(steps: Array) -> float:
	var total := 0.0
	for step_raw in steps:
		total += float((step_raw as Dictionary).get("usec", 0)) / 1000.0
	return total


func _summarise() -> void:
	print("\n== staged fit-out, phase totals (ms of DeckFitoutJob's own _step loop) ==")
	print("n\tspace\tREGISTER\tEXTERIOR\tINTERIOR\tGAMEPLAY\tindivisible\tstep_total\tshapes")
	for row_raw in _rows:
		var row := row_raw as Dictionary
		print(
			"%d\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%d"
			% [
				int(row["n"]),
				"yes" if bool(row["in_space"]) else "NO",
				float(row.get("ph_REGISTER_SKIN", 0.0)),
				float(row.get("ph_EXTERIOR_VISUALS", 0.0)),
				float(row.get("ph_INTERIOR_VISUALS", 0.0)),
				float(row.get("ph_GAMEPLAY", 0.0)),
				float(row.get("indivisible_ms", 0.0)),
				float(row.get("step_total_ms", 0.0)),
				int(row["shapes"]),
			]
		)
	print("\n== GAMEPLAY phase: in-space vs out-of-space, same boxes ==")
	var prev_in := 0.0
	var prev_out := 0.0
	var prev_n := 0
	for count in _counts:
		var in_row := _row_for(int(count), true)
		var out_row := _row_for(int(count), false)
		if in_row.is_empty() or out_row.is_empty():
			continue
		var a := float(in_row.get("ph_GAMEPLAY", 0.0))
		var b := float(out_row.get("ph_GAMEPLAY", 0.0))
		var growth_in := "-"
		var growth_out := "-"
		if prev_n > 0:
			var ratio_n := float(int(count)) / float(prev_n)
			growth_in = "x%.2f (n x%.2f)" % [a / maxf(prev_in, 0.001), ratio_n]
			growth_out = "x%.2f" % (b / maxf(prev_out, 0.001))
		print(
			"n=%d  GAMEPLAY in-space %.0fms %s | out-of-space %.0fms %s | rebuild share %.0f%%"
			% [int(count), a, growth_in, b, growth_out, 100.0 * (a - b) / maxf(a, 0.001)]
		)
		prev_in = a
		prev_out = b
		prev_n = int(count)


func _row_for(count: int, in_space: bool) -> Dictionary:
	for row_raw in _rows:
		var row := row_raw as Dictionary
		if int(row["n"]) == count and bool(row["in_space"]) == in_space:
			return row
	return {}


func _wait_for_sampling(
	boat: BoatBody,
	walk: CollisionObject3D,
	target: int,
	max_frames: int,
	t0: int,
) -> void:
	for _frame in range(max_frames):
		if DeckFitout.readiness_of(boat) >= target:
			_sample(walk, t0)
			return
		if boat.get_node_or_null(DeckFitout.FITOUT_JOB) == null:
			print("      !! no staged job; readiness stuck at %d" % DeckFitout.readiness_of(boat))
			return
		_sample(walk, t0)
		await get_tree().physics_frame
	print("      !! never reached readiness %d" % target)


## O(1). REALITY.md §8 — suspect the instrument. The first version of this walked
## every WalkDeck child per frame; on the unfixed code that is 2853 frames x up to
## 3000 children, and it inflated the very wall clock the missing-collision
## integral is taken over, from 21.3 s to 47.6 s. `body_get_shape_count` is one
## call and the two non-brick shapes (deck slab, hull shell) are subtracted.
func _sample(walk: CollisionObject3D, t0: int) -> void:
	var live := maxi(PhysicsServer3D.body_get_shape_count(walk.get_rid()) - 2, 0)
	_timeline.append({
		"ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"cols": live,
	})


func _fill_blocks(grid: DeckGrid, count: int) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	var remaining := count
	var y := 0
	while remaining > 0:
		for iz in range(grid.length):
			for ix in range(grid.width):
				if remaining <= 0:
					return layout
				var cell := Vector3i(ix, y, iz)
				if not grid.in_bounds(cell):
					continue
				layout.set_brick(cell, "block", 0)
				remaining -= 1
		y += 1
		if y > 64:
			break
	return layout
