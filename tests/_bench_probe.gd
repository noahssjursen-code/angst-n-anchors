extends Node

## Where does the staged fitout's 118 ms frame come from, and why is n=3000
## 240x slower per block than n=1000? Times the individual steps the job takes.

const HULL_ID := "hull_90x24"


func _ready() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, 3000)
	print("layout cells=%d" % layout.count())
	var items := layout.iter_primary_cells()

	var t := Time.get_ticks_usec()
	var shell: Dictionary = preload(
		"res://scripts/ship/brick_shell_classifier.gd"
	).classify(layout, grid, items)
	print("classify(3000) = %.1f ms  exterior=%d interior=%d" % [
		float(Time.get_ticks_usec() - t) / 1000.0,
		(shell.get("exterior", []) as Array).size(),
		(shell.get("interior", []) as Array).size(),
	])

	t = Time.get_ticks_usec()
	var outfit := VesselCompliance.validate(layout, HULL_ID, "general_vessel", grid)
	print("VesselCompliance.validate(3000) = %.1f ms" % [
		float(Time.get_ticks_usec() - t) / 1000.0
	])
	print("  (job runs this as ONE _step, so it cannot be frame-budgeted)")

	## One create_item_visual, measured on a warm catalog.
	var boat := VesselSpawn.instantiate(HULL_ID, {"hull_id": HULL_ID, "cells": {}})
	add_child(boat)
	var root := Node3D.new()
	boat.add_child(root)
	DeckFitout.create_item_visual(root, grid, items[0] as Dictionary)
	t = Time.get_ticks_usec()
	for i in range(200):
		DeckFitout.create_item_visual(root, grid, items[i] as Dictionary)
	print("create_item_visual x200 = %.1f ms (%.3f ms each)" % [
		float(Time.get_ticks_usec() - t) / 1000.0,
		float(Time.get_ticks_usec() - t) / 1000.0 / 200.0,
	])

	## finish_fitout on a 3000-brick layout — also one _step.
	t = Time.get_ticks_usec()
	DeckFitout.finish_fitout(
		boat, root, layout, grid, outfit, "general_vessel", {"brick_i": 0, "ladder_n": 0}
	)
	print("finish_fitout(3000) = %.1f ms" % [float(Time.get_ticks_usec() - t) / 1000.0])

	## The skin bake the SYNC path uses and the staged path does not.
	var baked: Array = []
	for item_raw in items:
		var item := item_raw as Dictionary
		if VesselSkinBaker.is_baked_brick(str(item.get("brick_id", ""))):
			baked.append(item)
	t = Time.get_ticks_usec()
	var skin := VesselSkinBaker.bake_items(grid, baked)
	print("VesselSkinBaker.bake_items(%d) = %.1f ms -> %d mesh nodes" % [
		baked.size(),
		float(Time.get_ticks_usec() - t) / 1000.0,
		_count_meshes(skin),
	])
	skin.free()
	get_tree().quit()


func _count_meshes(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			n += 1
		for child in node.get_children():
			stack.append(child)
	return n


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
