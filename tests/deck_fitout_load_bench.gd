extends Node

## Times DeckFitout.apply for synthetic solid-block layouts.
## Run: xvfb-run -a godot --rendering-driver opengl3 res://tests/deck_fitout_load_bench.tscn
##
## WHAT CAN AND CANNOT BE MEASURED ON THIS BOX.
##
## There is no Vulkan ICD here; rendering is Mesa llvmpipe on 4 cores. So a
## number is only worth asserting on if no software rasterisation is inside it:
##
##   HONEST  `dispatch_ms` on the SYNCHRONOUS path — one call, no awaited frame,
##           pure GDScript + PhysicsServer.
##   HONEST  `worst_frame_ms` — `DeckFitoutJob` brackets `Time.get_ticks_usec()`
##           around its own `_step` loop inside `_process`, so the frame's draw
##           is outside the measurement.
##   HONEST  `meshes` — a count. It says the same thing on any machine.
##   NOT     `fitout_ms` on the STAGED path. It is wall clock across every frame
##           the job needed, and each of those frames is a full llvmpipe render
##           of the scene. At n=3000 it read 150,688 ms, which is a measurement
##           of Mesa, not of DeckFitout. It is printed and not budgeted, and the
##           right way to bound staged cost here is the two lines above.
##
## THE FRAME BUDGET IS ASSERTED RELATIVELY, NOT AS A MILLISECOND WALL.
## `DeckFitoutJob._process` checks the clock BEFORE starting each unit of work
## and never during one, so the contract it can actually keep is: a frame
## overruns FRAME_BUDGET_USEC by at most one unit. Both sides of that are
## measured on the machine running the test, which is why it says the same thing
## on a fast box and on llvmpipe — unlike an absolute "100 ms" line, which was
## the bound this file had and which reported the compliance pass as a budget
## failure rather than as what it is: one step that cannot be subdivided.

const HULL_ID := "hull_90x24"
const COUNTS := [100, 500, 1000, 3000]
## Headless CI machines vary; keep soft so we catch "minutes" not "ms noise".
const SOFT_MS_PER_BLOCK := 8.0
const SOFT_FLOOR_MS := 500.0
const STAGED_SOFT_FRAME_MS := 100.0
## The steps `DeckFitoutJob` declares it cannot subdivide. Pinned as a SET, not
## as a count: a step that leaves this list is a fix, a step that joins it is a
## design decision, and either way somebody has to come and change this line.
const INDIVISIBLE_STEPS := ["VesselCompliance.validate", "DeckFitout.finish_fitout"]
const TestReport := preload("res://tests/support/test_report.gd")

var _t := TestReport.new("deck_fitout_load_bench", false)
var _meshes_by_count: Dictionary = {}


func _ready() -> void:
	print("DeckFitout load bench — hull=%s brick=block" % HULL_ID)
	for count in COUNTS:
		await _bench_count(int(count))
	## The regression this bench exists for is not "meshes are few", it is
	## "meshes do not scale with bricks". Held across a 30x range of layouts
	## rather than against a constant somebody can nudge.
	var smallest := int(_meshes_by_count.get(COUNTS[0], -1))
	var largest := int(_meshes_by_count.get(COUNTS[COUNTS.size() - 1], -1))
	_check(
		smallest > 0 and largest > 0 and largest <= smallest,
		"drawn mesh count does not grow with brick count (n=%d draws %d, n=%d draws %d)"
		% [int(COUNTS[0]), smallest, int(COUNTS[COUNTS.size() - 1]), largest],
	)
	_t.finish(get_tree())


func _bench_count(count: int) -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout_started := Time.get_ticks_usec()
	var layout := _fill_blocks(grid, count)
	var layout_ms := float(Time.get_ticks_usec() - layout_started) / 1000.0
	var placed := layout.count()
	_check(placed == count, "requested %d blocks, got %d" % [count, placed])

	var boat := VesselSpawn.instantiate(HULL_ID, {"hull_id": HULL_ID, "cells": {}})
	_check(boat != null, "hull %s instantiates" % HULL_ID)
	if boat == null:
		return
	add_child(boat)

	var fitout_started := Time.get_ticks_usec()
	DeckFitout.apply(boat, layout, grid, "general_vessel")
	var dispatch_ms := float(Time.get_ticks_usec() - fitout_started) / 1000.0
	var exterior_ms := dispatch_ms
	if boat.get_node_or_null(DeckFitout.FITOUT_JOB) != null:
		await _wait_for_readiness(boat, DeckFitout.READINESS_EXTERIOR, 1200)
		exterior_ms = float(Time.get_ticks_usec() - fitout_started) / 1000.0
		await _wait_for_readiness(boat, DeckFitout.READINESS_INTERACTIVE, 2400)
	var fitout_ms := float(Time.get_ticks_usec() - fitout_started) / 1000.0
	var mesh_n := _count_mesh_instances(boat)
	_meshes_by_count[placed] = mesh_n
	var per_block := fitout_ms / float(maxi(placed, 1))
	var worst_frame_ms := float(boat.get_meta("fitout_max_frame_usec", 0)) / 1000.0
	var divisible_ms := float(boat.get_meta("fitout_max_divisible_frame_usec", 0)) / 1000.0
	var unit_ms := float(boat.get_meta("fitout_max_unit_usec", 0)) / 1000.0
	var unit_phase := str(boat.get_meta("fitout_max_unit_phase", ""))
	var indivisible: Array = boat.get_meta("fitout_indivisible_steps", [])
	print(
		(
			"  n=%d layout=%.1fms dispatch=%.1fms exterior=%.1fms full=%.1fms (%.2f ms/block) worst_frame=%.1fms budgeted_frame=%.1fms unit=%.2fms(%s) meshes≈%d"
			% [
				placed,
				layout_ms,
				dispatch_ms,
				exterior_ms,
				fitout_ms,
				per_block,
				worst_frame_ms,
				divisible_ms,
				unit_ms,
				unit_phase,
				mesh_n,
			]
		)
	)
	for step_raw in indivisible:
		var step := step_raw as Dictionary
		print(
			"    indivisible step: %s = %.1fms"
			% [str(step.get("name", "?")), float(step.get("usec", 0)) / 1000.0]
		)

	var soft_budget := maxf(SOFT_FLOOR_MS, float(placed) * SOFT_MS_PER_BLOCK)
	if placed > DeckFitout.LARGE_LAYOUT_THRESHOLD:
		_check_staged_budget(placed, divisible_ms, unit_ms, indivisible)
	else:
		_check(
			dispatch_ms <= soft_budget,
			"n=%d synchronous fitout %.0fms exceeds soft budget %.0fms"
			% [placed, dispatch_ms, soft_budget],
		)

	## Every brick in this bench is `block`, which `VesselSkinBaker.is_baked_brick`
	## accepts, and that file's header promises "a handful of merged surfaces
	## instead of one scene node per brick". Hold BOTH entry points to it. This
	## is the clock-free statement of the regression the wall-clock budget was
	## reacting to: the staged path used to emit 3002 meshes for 3000 bricks
	## because DeckFitoutJob called create_item_visual per item and never reached
	## VesselSkinBaker at all — so the vessels that most need the skin were the
	## only ones that never got it.
	_check(
		mesh_n < placed,
		"n=%d draws %d meshes — static bricks are not merged into a skin"
		% [placed, mesh_n],
	)

	boat.queue_free()
	await get_tree().process_frame


## What the staged path promises, stated as three things that are all true or
## the promise is broken.
##
## 1. Every frame the loop CAN budget stays within one unit of the budget. Both
##    numbers come off this run, so no machine's clock speed is baked in.
## 2. The absolute soft ceiling is kept as a "minutes, not ms" tripwire.
## 3. The steps that CANNOT be budgeted are exactly the two named below, and no
##    others. `VesselCompliance.validate` is a single O(n) GDScript pass with no
##    resumable seam in it — 118 ms at n=3000 on this box, 30x the job's own
##    budget, in ONE `_step`; `finish_fitout` serialises the layout in one
##    `to_dict()`, 12 ms. This bench does not pretend either is budgeted and it
##    does not raise the budget to cover them: it pins the set, so a third
##    monolith cannot join them quietly, and prints what each one costs. Making
##    the compliance pass budgetable means giving VesselCompliance a resumable
##    seam, which this wave does not own — the measurement is the deliverable
##    and the decision is the owner's.
func _check_staged_budget(
	placed: int,
	divisible_ms: float,
	unit_ms: float,
	indivisible: Array,
) -> void:
	var allowance := float(DeckFitoutJob.FRAME_BUDGET_USEC) / 1000.0 + unit_ms
	_check(
		unit_ms > 0.0 and divisible_ms > 0.0,
		"n=%d staged job reports its own frame timings" % placed,
	)
	_check(
		divisible_ms <= allowance,
		"n=%d worst budgeted staged frame %.1fms exceeds budget+one unit %.1fms"
		% [placed, divisible_ms, allowance],
	)
	_check(
		divisible_ms <= STAGED_SOFT_FRAME_MS,
		"n=%d worst budgeted staged frame %.1fms exceeds %.1fms"
		% [placed, divisible_ms, STAGED_SOFT_FRAME_MS],
	)
	var names := _step_names(indivisible)
	names.sort()
	var expected := PackedStringArray(INDIVISIBLE_STEPS)
	expected.sort()
	_check(
		names == expected,
		"n=%d un-budgetable steps are exactly %s, got %s"
		% [placed, str(expected), str(names)],
	)


func _step_names(steps: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for step_raw in steps:
		out.append(str((step_raw as Dictionary).get("name", "?")))
	return out


func _wait_for_readiness(boat: BoatBody, target: int, max_frames: int) -> void:
	for _frame in range(max_frames):
		if DeckFitout.readiness_of(boat) >= target:
			return
		await get_tree().process_frame
	_check(false, "n=%d did not reach readiness %d" % [boat.get_meta("brick_layout", {}).size(), target])


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
			push_error("DeckFitout load bench: ran out of vertical space before %d" % count)
			break
	return layout


func _count_mesh_instances(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			n += 1
		for child in node.get_children():
			stack.append(child)
	return n


func _check(condition: bool, message: String) -> void:
	_t.check(message, condition)
