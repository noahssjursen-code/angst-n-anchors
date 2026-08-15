extends Node

## Scratch probe (leading underscore = not a gate unit).
##
## Two questions the deck-fitout wave has to answer with numbers rather than
## prose:
##
##  1. `VesselCompliance.validate` is declared un-budgetable. WHERE does its
##     140 ms go, and does the hot part have a per-brick seam a resumable
##     version could stop at?
##  2. `VesselSkinBaker.Session.commit()` shows up as a 31.6 ms DIVISIBLE unit
##     inside DeckFitoutJob's exterior phase. How much of that is one
##     SurfaceTool.commit(), and does splitting per material bucket get any
##     single unit under the 4 ms frame budget?

const HULL_ID := "hull_90x24"
const COUNTS := [1000, 3000]


func _ready() -> void:
	for count in COUNTS:
		_probe(int(count))
	get_tree().quit(0)


func _probe(count: int) -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, count)
	var items := layout.iter_primary_cells()
	print("n=%d (%d primary items)" % [count, items.size()])

	var caps: Dictionary = VesselRegistrationCatalog.resolved_registration(
		"general_vessel"
	).get("budget_caps", {})
	var t0 := Time.get_ticks_usec()
	var outfit := VesselOutfit.validate(layout, HULL_ID, grid, caps)
	var outfit_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var full := VesselCompliance.validate(layout, HULL_ID, "general_vessel", grid)
	var validate_us := Time.get_ticks_usec() - t0
	print(
		"  VesselCompliance.validate = %.1f ms  of which VesselOutfit.validate = %.1f ms (%.0f%%), rest = %.1f ms"
		% [
			validate_us / 1000.0,
			outfit_us / 1000.0,
			100.0 * float(outfit_us) / maxf(float(validate_us), 1.0),
			(validate_us - outfit_us) / 1000.0,
		]
	)
	print("    checklist items: %d" % (full.get("checklist", []) as Array).size())

	var session := VesselSkinBaker.Session.new(grid)
	t0 = Time.get_ticks_usec()
	for item_raw in items:
		session.register_item(item_raw as Dictionary)
	var register_us := Time.get_ticks_usec() - t0
	## Per-item, not just the total: DeckFitoutJob spends ONE `_step` per item and
	## its budget check is against the worst single unit, so a mean hides exactly
	## the thing that breaks the budget.
	var emit_worst_us := 0
	var emit_worst_i := -1
	var emit_over_budget := 0
	t0 = Time.get_ticks_usec()
	var i := 0
	for item_raw in items:
		var u0 := Time.get_ticks_usec()
		session.emit_item(item_raw as Dictionary)
		var u := Time.get_ticks_usec() - u0
		if u > emit_worst_us:
			emit_worst_us = u
			emit_worst_i = i
		if u > DeckFitoutJob.FRAME_BUDGET_USEC:
			emit_over_budget += 1
		i += 1
	var emit_us := Time.get_ticks_usec() - t0
	print(
		"    worst single emit_item = %.2f ms (item #%d of %d); %d items exceed the %.1f ms frame budget on their own"
		% [
			emit_worst_us / 1000.0,
			emit_worst_i,
			items.size(),
			emit_over_budget,
			float(DeckFitoutJob.FRAME_BUDGET_USEC) / 1000.0,
		]
	)
	t0 = Time.get_ticks_usec()
	session.commit()
	var commit_us := Time.get_ticks_usec() - t0
	print(
		"  skin: register %d items = %.1f ms (%.4f ms/item) · emit = %.1f ms (%.4f ms/item) · commit = %.1f ms"
		% [
			items.size(),
			register_us / 1000.0,
			register_us / 1000.0 / float(items.size()),
			emit_us / 1000.0,
			emit_us / 1000.0 / float(items.size()),
			commit_us / 1000.0,
		]
	)
	## Per-bucket, because that is the only seam commit() has: one SurfaceTool
	## per material, committed independently.
	var buckets := 0
	for child in session.root.get_children():
		if child is MeshInstance3D:
			buckets += 1
	print("    %d material buckets -> mean %.1f ms per bucket commit" % [
		buckets, commit_us / 1000.0 / float(maxi(buckets, 1))
	])
	t0 = Time.get_ticks_usec()
	session.commit()
	print("    second commit (same session, re-commit) = %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))

	## The job commits and then PARENTS the bake. Attaching a MeshInstance3D
	## whose mesh has just been built is where the renderer first sees the
	## geometry, so time that separately from the SurfaceTool work — one of the
	## two is a GDScript cost that exists on any machine and the other is an
	## llvmpipe upload that does not.
	var holder := Node3D.new()
	add_child(holder)
	t0 = Time.get_ticks_usec()
	DeckFitout.attach_skin(holder, session)
	print("    attach_skin (add_child into live tree) = %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	## And a re-commit while the instance is already parented: this is what the
	## interior stage does, and it assigns a new mesh to a live instance.
	t0 = Time.get_ticks_usec()
	session.commit()
	print("    re-commit while parented = %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	holder.queue_free()


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
				if not layout.set_brick(grid, cell, "block", 0):
					continue
				remaining -= 1
		y += 1
		if y > 64:
			break
	return layout
