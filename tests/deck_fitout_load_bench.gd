extends Node

## Times DeckFitout.apply for synthetic solid-block layouts.
## Run: godot --headless --path <project> res://tests/deck_fitout_load_bench.tscn
## Soft budgets catch pathological regressions; print lines are the real signal.

const HULL_ID := "hull_90x24"
const COUNTS := [100, 500, 1000, 3000]
## Headless CI machines vary; keep soft so we catch "minutes" not "ms noise".
const SOFT_MS_PER_BLOCK := 8.0
const SOFT_FLOOR_MS := 500.0
const STAGED_SOFT_FRAME_MS := 100.0

var _failures := PackedStringArray()


func _ready() -> void:
	print("DeckFitout load bench — hull=%s brick=block" % HULL_ID)
	for count in COUNTS:
		await _bench_count(int(count))
	if _failures.is_empty():
		print("DeckFitout load bench: completed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("DeckFitout load bench: " + failure)
		get_tree().quit(1)


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
	var per_block := fitout_ms / float(maxi(placed, 1))
	var worst_frame_ms := float(boat.get_meta("fitout_max_frame_usec", 0)) / 1000.0
	print(
		(
			"  n=%d layout=%.1fms dispatch=%.1fms exterior=%.1fms full=%.1fms (%.2f ms/block) worst_frame=%.1fms meshes≈%d"
			% [
				placed,
				layout_ms,
				dispatch_ms,
				exterior_ms,
				fitout_ms,
				per_block,
				worst_frame_ms,
				mesh_n,
			]
		)
	)

	var soft_budget := maxf(SOFT_FLOOR_MS, float(placed) * SOFT_MS_PER_BLOCK)
	_check(
		fitout_ms <= soft_budget,
		"n=%d fitout %.0fms exceeds soft budget %.0fms" % [placed, fitout_ms, soft_budget],
	)
	if placed > DeckFitout.LARGE_LAYOUT_THRESHOLD:
		_check(
			worst_frame_ms <= STAGED_SOFT_FRAME_MS,
			"n=%d worst staged frame %.1fms exceeds %.1fms"
			% [placed, worst_frame_ms, STAGED_SOFT_FRAME_MS],
		)

	boat.queue_free()
	await get_tree().process_frame


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
	if not condition:
		_failures.append(message)
