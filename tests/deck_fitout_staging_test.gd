extends Node

const HULL_ID := "hull_90x24"
const REMOTE_DRAWING_SCRIPT := preload(
	"res://scripts/network/replication_drawing_service.gd"
)
const BRICK_SHELL_CLASSIFIER := preload(
	"res://scripts/ship/brick_shell_classifier.gd"
)

var _failures := PackedStringArray()


func _ready() -> void:
	_test_shell_classifier()
	_test_remote_distance_rule()
	await _test_exterior_precedes_interior()
	await _test_sync_staged_parity()
	await _test_threshold_and_completion()
	await _test_remote_pause_and_promotion()
	await _test_reapply_cancels_job()
	if _failures.is_empty():
		print("DeckFitout staging: shell, threshold, readiness, and promotion checks passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("DeckFitout staging: " + failure)
		get_tree().quit(1)


func _test_shell_classifier() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					layout.set_brick(Vector3i(x + 5, y, z + 10), "block", 0)
	var host := Vector3i(5, 1, 12)
	_check(layout.attach_sign(host, "wall_text", 0, "TEST"), "exterior host accepts sign")
	_check(layout.attach_light(host, "light_external", 0), "exterior host accepts light")
	var inner := Vector3i(7, 1, 12)
	layout.set_brick(inner, "block", 0)
	var result: Dictionary = BRICK_SHELL_CLASSIFIER.classify(layout, grid)
	var exterior_keys: Dictionary = result.get("exterior_keys", {})
	_check(exterior_keys.has(BrickLayout.cell_key(host)), "cabin wall is exterior")
	_check(not exterior_keys.has(BrickLayout.cell_key(inner)), "sealed cabin block is interior")
	var host_item := _item_at(result.get("exterior", []) as Array, host)
	_check(str(host_item.get("sign_id", "")) == "wall_text", "mounted sign follows exterior host")
	_check(
		str(host_item.get("light_id", "")) == "light_external",
		"mounted light follows exterior host",
	)

	var bow_layout := BrickLayout.new()
	bow_layout.hull_id = HULL_ID
	var partial := _first_partial_cell(grid)
	if partial.x >= 0:
		bow_layout.set_brick(
			partial, "block_45", grid.partial_bow_yaw_degrees(partial)
		)
		var bow_result: Dictionary = BRICK_SHELL_CLASSIFIER.classify(bow_layout, grid)
		_check(
			(bow_result.get("exterior", []) as Array).size() == 1,
			"tapered bow brick classifies as exterior",
		)


func _test_remote_distance_rule() -> void:
	_check(
		REMOTE_DRAWING_SCRIPT.should_promote_large_ship(Vector3.ZERO, Vector3(50.0, 0.0, 0.0)),
		"remote detail promotes at 50 m",
	)
	_check(
		not REMOTE_DRAWING_SCRIPT.should_promote_large_ship(
			Vector3.ZERO, Vector3(50.1, 0.0, 0.0)
		),
		"remote detail remains exterior beyond 50 m",
	)


func _test_exterior_precedes_interior() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					layout.set_brick(Vector3i(x + 5, y, z + 10), "block", 0)
	var inner := Vector3i(7, 1, 12)
	layout.set_brick(inner, "block", 0)
	var boat := _new_boat()
	boat.set_meta("remote_replica", true)
	DeckFitout.apply_staged(boat, layout, grid, "general_vessel")
	await _wait_for_readiness(boat, DeckFitout.READINESS_EXTERIOR, 300)
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	_check(root != null, "staged shell creates fitout root")
	if root != null:
		_check(root.get_node_or_null("block_5_0_10") != null, "exterior wall appears first")
		_check(root.get_node_or_null("block_7_1_12") == null, "interior waits after shell")
	DeckFitout.request_full_detail(boat)
	await _wait_for_readiness(boat, DeckFitout.READINESS_FULL_VISUAL, 300)
	if root != null:
		_check(root.get_node_or_null("block_7_1_12") != null, "interior appears after promotion")
	await _wait_for_readiness(boat, DeckFitout.READINESS_INTERACTIVE, 300)
	boat.queue_free()
	await get_tree().process_frame


func _test_threshold_and_completion() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var small_layout := _fill_blocks(grid, DeckFitout.LARGE_LAYOUT_THRESHOLD)
	var small_boat := _new_boat()
	DeckFitout.apply(small_boat, small_layout, grid, "general_vessel")
	_check(
		small_boat.get_node_or_null(DeckFitout.FITOUT_JOB) == null,
		"1000 primary bricks use synchronous fitout",
	)
	small_boat.queue_free()
	await get_tree().process_frame

	var large_layout := _fill_blocks(grid, DeckFitout.LARGE_LAYOUT_THRESHOLD + 1)
	var large_boat := _new_boat()
	DeckFitout.apply(large_boat, large_layout, grid, "general_vessel")
	_check(
		large_boat.get_node_or_null(DeckFitout.FITOUT_JOB) != null,
		"1001 primary bricks use staged fitout",
	)
	_check(
		DeckFitout.readiness_of(large_boat) == DeckFitout.READINESS_HULL,
		"large fitout returns with hull readiness",
	)
	await _wait_for_readiness(large_boat, 3, 600)
	_check(DeckFitout.readiness_of(large_boat) == 3, "local large fitout becomes interactive")
	_check(
		_count_primary_visuals(large_boat) == large_layout.iter_primary_cells().size(),
		"staged fitout creates every primary visual",
	)
	large_boat.queue_free()
	await get_tree().process_frame


func _test_sync_staged_parity() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, 30)
	var sync_boat := _new_boat()
	DeckFitout.apply_sync(sync_boat, layout, grid, "general_vessel")
	var sync_caps := (
		sync_boat.get_meta("brick_capabilities", {}) as Dictionary
	).duplicate(true)
	var sync_outfit := (
		sync_boat.get_meta("vessel_outfit", {}) as Dictionary
	).duplicate(true)
	var sync_visuals := _count_primary_visuals(sync_boat)

	var staged_boat := _new_boat()
	DeckFitout.apply_staged(staged_boat, layout, grid, "general_vessel")
	await _wait_for_readiness(staged_boat, DeckFitout.READINESS_INTERACTIVE, 300)
	_check(
		staged_boat.get_meta("brick_capabilities", {}) == sync_caps,
		"staged capabilities match synchronous fitout",
	)
	_check(
		staged_boat.get_meta("vessel_outfit", {}) == sync_outfit,
		"staged compliance metadata matches synchronous fitout",
	)
	_check(
		_count_primary_visuals(staged_boat) == sync_visuals,
		"staged final visuals match synchronous fitout",
	)
	sync_boat.queue_free()
	staged_boat.queue_free()
	await get_tree().process_frame


func _test_remote_pause_and_promotion() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, DeckFitout.LARGE_LAYOUT_THRESHOLD + 1)
	var boat := _new_boat()
	boat.set_meta("remote_replica", true)
	DeckFitout.apply(boat, layout, grid, "general_vessel")
	await _wait_for_readiness(boat, 1, 600)
	_check(DeckFitout.readiness_of(boat) == 1, "remote large fitout pauses at exterior")
	await get_tree().process_frame
	_check(DeckFitout.readiness_of(boat) == 1, "remote exterior does not self-promote")
	DeckFitout.request_full_detail(boat)
	await _wait_for_readiness(boat, 3, 600)
	_check(DeckFitout.readiness_of(boat) == 3, "remote fitout promotes to interactive")
	boat.queue_free()
	await get_tree().process_frame


func _test_reapply_cancels_job() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var boat := _new_boat()
	var large := _fill_blocks(grid, DeckFitout.LARGE_LAYOUT_THRESHOLD + 1)
	DeckFitout.apply(boat, large, grid, "general_vessel")
	var old_job := boat.get_node_or_null(DeckFitout.FITOUT_JOB)
	_check(old_job != null, "cancellation fixture starts staged job")
	var replacement := _fill_blocks(grid, 10)
	DeckFitout.apply(boat, replacement, grid, "general_vessel")
	_check(
		boat.get_node_or_null(DeckFitout.FITOUT_JOB) == null,
		"small reapply removes in-flight staged job",
	)
	_check(not is_instance_valid(old_job), "old staged job is freed immediately")
	_check(_count_primary_visuals(boat) == 10, "replacement layout owns final visuals")
	boat.queue_free()
	await get_tree().process_frame


func _new_boat() -> BoatBody:
	var boat := VesselSpawn.instantiate(
		HULL_ID, {"hull_id": HULL_ID, "cells": {}}, "general_vessel"
	)
	add_child(boat)
	return boat


func _fill_blocks(grid: DeckGrid, count: int) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	var remaining := count
	var y := 0
	while remaining > 0:
		for z in range(grid.length):
			for x in range(grid.width):
				if remaining <= 0:
					return layout
				var cell := Vector3i(x, y, z)
				if not grid.in_bounds(cell):
					continue
				layout.set_brick(cell, "block", 0)
				remaining -= 1
		y += 1
	return layout


func _wait_for_readiness(boat: BoatBody, target: int, max_frames: int) -> void:
	for _frame in range(max_frames):
		if DeckFitout.readiness_of(boat) >= target:
			return
		await get_tree().process_frame
	_check(false, "fitout did not reach readiness %d within %d frames" % [target, max_frames])


func _count_primary_visuals(boat: BoatBody) -> int:
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	if root == null:
		return 0
	var count := 0
	for child in root.get_children():
		if child is Node3D and not str(child.name).begins_with("Sign_") \
				and not str(child.name).begins_with("Light_") \
				and not str(child.name).begins_with("CargoSlotPad_"):
			count += 1
	return count


func _item_at(items: Array, cell: Vector3i) -> Dictionary:
	for item_raw in items:
		var item := item_raw as Dictionary
		if item.get("cell", Vector3i(-1, -1, -1)) == cell:
			return item
	return {}


func _first_partial_cell(grid: DeckGrid) -> Vector3i:
	for z in range(grid.length):
		for x in range(grid.width):
			var cell := Vector3i(x, 0, z)
			if grid.is_partial_bow_cell(cell):
				return cell
	return Vector3i(-1, -1, -1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
