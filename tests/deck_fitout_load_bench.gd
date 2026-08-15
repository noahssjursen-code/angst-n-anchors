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
## THE FRAME BUDGET IS ASSERTED AS DIVISIBILITY, NOT AS A MILLISECOND WALL.
## `DeckFitoutJob._process` checks the clock BEFORE starting each unit of work
## and never during one. The relative form of that contract — "a frame overruns
## FRAME_BUDGET_USEC by at most one unit" — was asserted here and is arithmetic,
## not a property: see `_check_staged_budget` for the mutation that walked a
## 200 ms unit straight through it. What is asserted now is that each phase is
## cut into one step per brick, which is clock-free and therefore says the same
## thing on a fast box and on llvmpipe, plus the pinned set of steps that are
## admittedly not cut at all.

const HULL_ID := "hull_90x24"
## 1000 and 1001 straddle `DeckFitout.LARGE_LAYOUT_THRESHOLD`, so the same
## layout goes through the synchronous path and the staged one at effectively
## the same size. That pair is the whole subject of this bench: they must draw
## the same handful of meshes, and for months the staged side of it drew one per
## brick.
const COUNTS := [100, 500, 1000, 1001, 3000]
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
	var steps_by_phase: Dictionary = boat.get_meta("fitout_steps_by_phase", {})
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
		_check_staged_budget(placed, divisible_ms, indivisible, steps_by_phase, layout, grid)
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


## What the staged path promises. Stated as DIVISIBILITY, which is clock-free,
## plus one soft wall-clock tripwire — not as a millisecond bound on a unit.
##
## WHY THE PREVIOUS FORM OF THIS CHECK WAS WORTHLESS, MEASURED. It asserted
## `worst_budgeted_frame <= FRAME_BUDGET + worst_unit`, both numbers off the
## same run. `DeckFitoutJob._process` reads the clock BEFORE each unit and never
## during one, so a frame is arithmetically incapable of exceeding budget + the
## worst unit it contains — the right-hand side inflates to meet the left every
## time. MUTATION-VERIFIED at n=1001: a 200 ms busy-wait inside `_commit_skin`
## — a step the loop treats as budgetable — produced `budgeted_frame` 204.9 ms
## against an allowance of 4.0 + `unit` 202.10 = 206.1 ms, and the check PASSED.
## Only the absolute 100 ms tripwire below noticed. In production it absorbed a
## 31.59 ms unit in silence.
##
## AND A MILLISECOND BOUND CANNOT REPLACE IT ON THIS BOX. Two runs of identical
## code measured the worst divisible unit at 31.59 ms (EXTERIOR_VISUALS) and
## 4.59 ms (GAMEPLAY): it is wall clock around GDScript sharing four cores with
## llvmpipe. The seam probe times the same work at 0.026 ms/item, worst single
## 1.95 ms, when nothing is rendering. Asserting 4 ms there buys a coin flip.
##
## So what is asserted is the property a frame budget actually rests on: the
## work is CUT INTO UNITS, one per brick, in every phase — and the steps that
## are NOT cut are named. `VesselCompliance.validate` is a single O(n) GDScript
## pass, 113 ms at n=3000 on this box (stable within 0.6% across three runs
## while wall clock swung 130-150 s), 28x the job's own 4 ms budget, in ONE
## `_step`; `finish_fitout` serialises the layout in one `to_dict()`, 15 ms.
## This bench does not pretend either is budgeted and it does not raise the
## budget to cover them: it pins the SET, so a third monolith cannot join them
## quietly, and prints what each one costs. 72% of the compliance pass is
## `VesselOutfit.validate`, which walks the layout brick by brick and therefore
## does have a seam — splitting it is a change to two files this wave does not
## own, so the measurement is the deliverable and the decision is the owner's.
func _check_staged_budget(
	placed: int,
	divisible_ms: float,
	indivisible: Array,
	steps_by_phase: Dictionary,
	layout: BrickLayout,
	grid: DeckGrid,
) -> void:
	_check(
		divisible_ms > 0.0,
		"n=%d staged job reports its own frame timings" % placed,
	)
	## Kept: an absolute "minutes, not ms" tripwire, soft by 3x against the
	## noise measured above, and the one thing here that can still catch a
	## frame-loop that stops yielding at all.
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
	## Divisibility, phase by phase, against item counts this test derives for
	## itself rather than reading back off the job. MUTATION-VERIFIED at n=1001:
	## collapsing EXTERIOR_VISUALS into a single `while` that emits all 1001
	## items in one step reddens only this — `budgeted_frame` 47.5 ms and `unit`
	## 47.36 ms both stayed inside their bounds, and the run would otherwise have
	## been a clean PASS.
	##
	## REGISTER_SKIN is on this list deliberately. `DeckFitout.skin_enabled =
	## false` skips that phase entirely, which is the measured way to turn both
	## of this file's historic reds green while making every vessel worse; it
	## turns this one red instead.
	var shell: Dictionary = BrickShellClassifier.classify(layout, grid)
	var expected_steps := {
		"REGISTER_SKIN": placed,
		"EXTERIOR_VISUALS": (shell.get("exterior", []) as Array).size(),
		"INTERIOR_VISUALS": (shell.get("interior", []) as Array).size(),
		"GAMEPLAY": placed,
	}
	for phase in expected_steps:
		var want := int(expected_steps[phase])
		var got := int(steps_by_phase.get(phase, 0))
		_check(
			got >= want,
			"n=%d phase %s spent %d steps on %d items — it is not divided per brick"
			% [placed, phase, got, want],
		)


func _step_names(steps: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for step_raw in steps:
		out.append(str((step_raw as Dictionary).get("name", "?")))
	return out


## See the same helper in `deck_fitout_staging_test.gd`: with no job node the
## readiness meta can never advance, so spinning the rest of `max_frames` turns
## a compile error in `deck_fitout_job.gd` into a TIMEOUT instead of a message.
func _wait_for_readiness(boat: BoatBody, target: int, max_frames: int) -> void:
	for _frame in range(max_frames):
		if DeckFitout.readiness_of(boat) >= target:
			return
		if boat.get_node_or_null(DeckFitout.FITOUT_JOB) == null:
			_check(
				false,
				"no staged job exists to reach readiness %d (readiness stuck at %d)"
				% [target, DeckFitout.readiness_of(boat)],
			)
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
