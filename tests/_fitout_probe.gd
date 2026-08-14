extends Node

const HULL_ID := "hull_90x24"


func _ready() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	print("grid width=%d length=%d deck_y=%.3f" % [grid.width, grid.length, grid.deck_y])
	print("skin_enabled=%s  is_baked_brick(block)=%s" % [
		DeckFitout.skin_enabled, VesselSkinBaker.is_baked_brick("block")
	])

	# --- the exterior/interior fixture from deck_fitout_staging_test ---
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					layout.set_brick(Vector3i(x + 5, y, z + 10), "block", 0)
	var inner := Vector3i(7, 1, 12)
	layout.set_brick(inner, "block", 0)
	print("fixture primary cells=%d" % layout.iter_primary_cells().size())
	print("is_partial_bow_cell(5,0,10)=%s in_bounds=%s" % [
		grid.is_partial_bow_cell(Vector3i(5, 0, 10)), grid.in_bounds(Vector3i(5, 0, 10))
	])

	var boat := _new_boat()
	boat.set_meta("remote_replica", true)
	DeckFitout.apply_staged(boat, layout, grid, "general_vessel")
	for _i in range(400):
		if DeckFitout.readiness_of(boat) >= DeckFitout.READINESS_EXTERIOR:
			break
		await get_tree().process_frame
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	print("[staged exterior] root=%s children=%d" % [root, root.get_child_count() if root else -1])
	if root != null:
		var names := PackedStringArray()
		for c in root.get_children():
			names.append(str(c.name))
		print("[staged exterior] child names: %s" % ", ".join(names))
	DeckFitout.request_full_detail(boat)
	for _i in range(400):
		if DeckFitout.readiness_of(boat) >= DeckFitout.READINESS_FULL_VISUAL:
			break
		await get_tree().process_frame
	if root != null:
		var names2 := PackedStringArray()
		for c in root.get_children():
			names2.append(str(c.name))
		print("[staged full] children=%d: %s" % [root.get_child_count(), ", ".join(names2)])
	boat.queue_free()
	await get_tree().process_frame

	# --- sync vs staged parity fixture, 30 blocks ---
	var flat := _fill_blocks(grid, 30)
	var sync_boat := _new_boat()
	DeckFitout.apply_sync(sync_boat, flat, grid, "general_vessel")
	var sroot := sync_boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	var snames := PackedStringArray()
	for c in sroot.get_children():
		snames.append("%s(%s)" % [c.name, c.get_class()])
	print("[sync 30] root children=%d: %s" % [sroot.get_child_count(), ", ".join(snames)])

	var staged_boat := _new_boat()
	DeckFitout.apply_staged(staged_boat, flat, grid, "general_vessel")
	for _i in range(400):
		if DeckFitout.readiness_of(staged_boat) >= DeckFitout.READINESS_INTERACTIVE:
			break
		await get_tree().process_frame
	var groot := staged_boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	print("[staged 30] root children=%d readiness=%d" % [
		groot.get_child_count(), DeckFitout.readiness_of(staged_boat)
	])
	get_tree().quit()


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
