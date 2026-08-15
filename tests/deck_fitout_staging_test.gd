extends Node

const HULL_ID := "hull_90x24"
const REMOTE_DRAWING_SCRIPT := preload(
	"res://scripts/network/replication_drawing_service.gd"
)
const BRICK_SHELL_CLASSIFIER := preload(
	"res://scripts/ship/brick_shell_classifier.gd"
)
const TestReport := preload("res://tests/support/test_report.gd")

## Origin of the 5x5x3 cabin fixture, in deck cells.
##
## This USED to be (5, 0, 10), and every cell of it was off the hull. The
## hull_90x24 grid is 48 x 180 cells with a 24-cell bow taper, so at z=10 the
## deck only exists for x in [14, 33] — `DeckGrid.in_bounds` returned false for
## the whole cabin, `DeckFitout.create_item_visual` returned null for every
## brick, and the fitout root ended up with ZERO children. Two checks failed
## honestly ("exterior wall appears first", "interior appears after promotion")
## and one passed vacuously ("interior waits after shell" is
## `get_node_or_null(...) == null`, which is true when nothing is ever built).
## `_assert_fixture_on_deck` now holds the fixture to the deck so that cannot
## recur silently.
const CABIN_ORIGIN := Vector3i(20, 0, 60)
## Shell cell (the loop's x==0/z==0 corner) and the sealed interior cell.
const CABIN_SHELL_CELL := CABIN_ORIGIN
const CABIN_INNER_CELL := Vector3i(
	CABIN_ORIGIN.x + 2, CABIN_ORIGIN.y + 1, CABIN_ORIGIN.z + 2
)

var _t := TestReport.new("deck_fitout_staging_test", false)


func _ready() -> void:
	_test_shell_classifier()
	_test_remote_distance_rule()
	await _test_exterior_precedes_interior()
	await _test_sync_staged_parity()
	await _test_threshold_and_completion()
	await _test_remote_pause_and_promotion()
	await _test_reapply_cancels_job()
	_t.finish(get_tree())


## The 5x5x3 hollow cabin every staging fixture is built from. `sealed` adds the
## interior block the shell/interior split is measured against.
func _cabin_layout(sealed: bool) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					layout.set_brick(
						Vector3i(
							CABIN_ORIGIN.x + x, CABIN_ORIGIN.y + y, CABIN_ORIGIN.z + z
						),
						"block",
						0,
					)
	if sealed:
		layout.set_brick(CABIN_INNER_CELL, "block", 0)
	return layout


## A fixture that is off the hull draws nothing, and a test that asks "is this
## node absent" then passes for the wrong reason. Hold the fixture to the deck.
func _assert_fixture_on_deck(grid: DeckGrid, layout: BrickLayout) -> void:
	var off_deck := 0
	for item_raw in layout.iter_primary_cells():
		var cell: Vector3i = (item_raw as Dictionary).get("cell", Vector3i(-1, -1, -1))
		if not grid.in_bounds(cell):
			off_deck += 1
	_check(
		off_deck == 0,
		"cabin fixture sits on the deck (%d of %d cells are off the hull)"
		% [off_deck, layout.iter_primary_cells().size()],
	)


func _visual_name(cell: Vector3i) -> String:
	return "block_%d_%d_%d" % [cell.x, cell.y, cell.z]


func _test_shell_classifier() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _cabin_layout(false)
	var host := Vector3i(CABIN_ORIGIN.x, CABIN_ORIGIN.y + 1, CABIN_ORIGIN.z + 2)
	_check(layout.attach_sign(host, "wall_text", 0, "TEST"), "exterior host accepts sign")
	_check(layout.attach_light(host, "light_external", 0), "exterior host accepts light")
	var inner := CABIN_INNER_CELL
	layout.set_brick(inner, "block", 0)
	_assert_fixture_on_deck(grid, layout)
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
	var layout := _cabin_layout(true)
	_assert_fixture_on_deck(grid, layout)
	var boat := _new_boat()
	boat.set_meta("remote_replica", true)
	DeckFitout.apply_staged(boat, layout, grid, "general_vessel")
	await _wait_for_readiness(boat, DeckFitout.READINESS_EXTERIOR, 300)
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	_check(root != null, "staged shell creates fitout root")
	if root != null:
		## Named nodes (`block_20_0_60`) used to stand in for "this brick is
		## drawn". Static bricks now merge into one skin and have no node of
		## their own, so ask the renderer instead: how many drawn triangles have
		## their centroid inside this cell? That is the same question the node
		## lookup was a proxy for, and it survives the merge.
		var shell_before := _triangles_in_cell(boat, grid, CABIN_SHELL_CELL)
		var inner_before := _triangles_in_cell(boat, grid, CABIN_INNER_CELL)
		_check(shell_before > 0, "exterior wall is drawn first (%d triangles)" % shell_before)
		## Paired with the check above so neither can pass on an empty root:
		## "interior is absent" is only evidence of staging when the shell is
		## present in the same breath.
		_check(
			inner_before == 0,
			"interior waits after shell (%d triangles already drawn)" % inner_before,
		)
	DeckFitout.request_full_detail(boat)
	await _wait_for_readiness(boat, DeckFitout.READINESS_FULL_VISUAL, 300)
	if root != null:
		var inner_after := _triangles_in_cell(boat, grid, CABIN_INNER_CELL)
		_check(
			inner_after > 0,
			"interior is drawn after promotion (%d triangles)" % inner_after,
		)
	await _wait_for_readiness(boat, DeckFitout.READINESS_INTERACTIVE, 300)

	## Same fixture, synchronous: the staged skin must end up as the geometry
	## the immediate path builds, not merely as "some merged thing".
	var sync_boat := _new_boat()
	DeckFitout.apply_sync(sync_boat, layout, grid, "general_vessel")
	_check(
		_triangles_in_cell(boat, grid, CABIN_INNER_CELL)
		== _triangles_in_cell(sync_boat, grid, CABIN_INNER_CELL),
		"promoted interior cell matches the synchronous bake (staged %d, sync %d)"
		% [
			_triangles_in_cell(boat, grid, CABIN_INNER_CELL),
			_triangles_in_cell(sync_boat, grid, CABIN_INNER_CELL),
		],
	)
	sync_boat.queue_free()
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

	## This used to count scene nodes and demand one per brick, which is the
	## defect rather than the property: the staged path met it by drawing 1001
	## MeshInstance3Ds for a layout the synchronous path draws in one. What it
	## was for — the staged run drops no brick — is the same 1001 bricks through
	## the immediate path as the oracle. Triangles, not nodes.
	var oracle_boat := _new_boat()
	DeckFitout.apply_sync(oracle_boat, large_layout, grid, "general_vessel")
	var staged_triangles := _triangle_centroids(large_boat).size()
	var sync_triangles := _triangle_centroids(oracle_boat).size()
	_check(sync_triangles > 0, "oracle fitout draws geometry for 1001 bricks")
	_check(
		staged_triangles == sync_triangles,
		"staged fitout draws every brick the synchronous one does (staged %d, sync %d triangles)"
		% [staged_triangles, sync_triangles],
	)
	_check(
		_count_mesh_instances(large_boat) == _count_mesh_instances(oracle_boat),
		"1001-brick staged fitout merges like the synchronous one (staged %d, sync %d meshes)"
		% [_count_mesh_instances(large_boat), _count_mesh_instances(oracle_boat)],
	)
	## EVERY parity check in this file — mesh counts, triangle counts, cell
	## histograms, colliders, mass — is satisfied by two paths that are equally
	## UNMERGED. `DeckFitout.skin_enabled = false` produces exactly that, and it
	## is the measured way to fake this file green while making every vessel
	## worse: with it off this test dropped to 1/43 and the one survivor was an
	## unrelated probe artifact. Parity is not the property on its own. State
	## the merge itself, on both entry points, or nothing here holds it.
	var brick_n := large_layout.iter_primary_cells().size()
	_check(
		_count_mesh_instances(large_boat) < brick_n,
		"staged fitout merges %d static bricks into fewer meshes (drew %d)"
		% [brick_n, _count_mesh_instances(large_boat)],
	)
	_check(
		_count_mesh_instances(oracle_boat) < brick_n,
		"synchronous fitout merges %d static bricks into fewer meshes (drew %d)"
		% [brick_n, _count_mesh_instances(oracle_boat)],
	)
	oracle_boat.queue_free()
	large_boat.queue_free()
	await get_tree().process_frame


func _test_sync_staged_parity() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, 30)
	## A layout of nothing but `block` would never exercise the live-brick
	## branch, and "everything merged" would pass it. A bollard must stay its own
	## node, and a sign mounted on a merged block must keep its own node too.
	var live_cell := _first_free_cell(grid, layout)
	if live_cell.x >= 0:
		layout.set_brick(live_cell, "bollard", 0)
	_check(
		live_cell.x >= 0 and not VesselSkinBaker.is_baked_brick("bollard"),
		"parity fixture places a live (unmergeable) brick",
	)
	var sign_host: Vector3i = (layout.iter_primary_cells()[0] as Dictionary).get("cell")
	_check(layout.attach_sign(sign_host, "wall_text", 0, "PARITY"), "parity fixture mounts a sign")
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
	## Same layout, two entry points, and what actually reaches the renderer is
	## the property that matters — `apply_sync` merges static bricks through
	## VesselSkinBaker, `DeckFitoutJob` did not, so a large vessel paid one
	## MeshInstance3D per brick where a small one pays a handful. Stated as a
	## count of drawn meshes rather than of scene nodes, because the count of
	## drawn meshes is what the divergence costs.
	_check(
		_count_mesh_instances(staged_boat) == _count_mesh_instances(sync_boat),
		"staged fitout draws the same mesh count as synchronous fitout (staged %d, sync %d)"
		% [_count_mesh_instances(staged_boat), _count_mesh_instances(sync_boat)],
	)
	## Equal mesh COUNTS would also be satisfied by two merged skins that drew
	## different geometry — say one that culled faces against a half-registered
	## solid field. Same triangles, in the same cells, is the property.
	var staged_tris := _triangle_centroids(staged_boat)
	var sync_tris := _triangle_centroids(sync_boat)
	_check(sync_tris.size() > 0, "synchronous fitout draws geometry at all")
	_check(
		staged_tris.size() == sync_tris.size(),
		"staged fitout draws the same triangle count (staged %d, sync %d)"
		% [staged_tris.size(), sync_tris.size()],
	)
	_check(
		_cell_histogram(grid, staged_tris) == _cell_histogram(grid, sync_tris),
		"staged fitout puts the same triangles in the same cells as synchronous",
	)
	## The merged path hands `mount_item_gameplay` a null visual for every baked
	## brick. Mass and colliders do not need a node and must not be skipped with
	## it — a merged deck you fall through would pass every check above.
	_check(
		_count_brick_colliders(staged_boat) == _count_brick_colliders(sync_boat),
		"staged fitout builds the same brick colliders (staged %d, sync %d)"
		% [_count_brick_colliders(staged_boat), _count_brick_colliders(sync_boat)],
	)
	_check(_count_brick_colliders(sync_boat) > 0, "synchronous fitout builds brick colliders")
	_check(
		is_equal_approx(staged_boat.mass, sync_boat.mass),
		"staged fitout registers the same brick mass (staged %.1f, sync %.1f)"
		% [staged_boat.mass, sync_boat.mass],
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
	## `== 10` restated the input and, worse, assumed one scene node per brick —
	## it went red the day `apply_sync` started merging static bricks into one
	## skin, which has nothing to do with cancellation. What this test is named
	## for is that NOTHING of the 1001-brick layout survives the reapply, so
	## state that: everything drawn lies inside the replacement's ten cells.
	var drawn := _drawn_aabb(boat)
	var expected := _layout_aabb(grid, replacement)
	_check(drawn.size.length_squared() > 0.0, "replacement layout draws something at all")
	_check(
		expected.encloses(drawn),
		"replacement layout owns final visuals (drawn %s outside %s)" % [drawn, expected],
	)
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


## Bail on the CONDITION, not only on the frame count. `DeckFitout.clear` is the
## only thing that removes the job node, so once a staged fitout has lost it the
## readiness meta can never advance and every remaining frame of `max_frames` is
## spent for nothing.
##
## Found by accident while mutating this wave: a parse error in
## `deck_fitout_job.gd` makes `load(FITOUT_JOB_SCRIPT).new()` return null,
## `apply_staged` adds no job, and all five waits here spin their full 300-600
## frames. Measured with the same injected parse error: 30 s and a wall of
## consequential failures without this guard, 5 s and "no staged job exists to
## reach readiness N" with it. That is a diagnosability fix — a compile failure
## and a genuine assertion failure are otherwise indistinguishable in a results
## table (REALITY.md 4a).
##
## IT IS NOT A PROVEN FIX FOR THE INTERMITTENT HANG THIS FILE IS RECORDED AS
## HAVING. That hang was not reproduced: this test ran clean 4 times, and the
## pre-wave version of it ran in 19 s.
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


func _count_mesh_instances(boat: BoatBody) -> int:
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	if root == null:
		return 0
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			n += 1
		for child in node.get_children():
			stack.append(child)
	return n


## Centroid, in fitout-root space, of every triangle the fitout draws.
##
## The unit both entry points can be compared in. A brick used to be a scene
## node you could look up by name; a merged brick is a handful of faces inside
## somebody else's mesh, and "is this brick on screen" has to be asked of the
## geometry or it cannot be asked of the merged path at all.
func _triangle_centroids(boat: BoatBody) -> PackedVector3Array:
	var out := PackedVector3Array()
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT) as Node3D
	if root == null:
		return out
	var inverse := root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var instance := node as MeshInstance3D
		if instance != null and instance.mesh != null:
			var to_root := inverse * instance.global_transform
			for surface in instance.mesh.get_surface_count():
				var arrays := instance.mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var index_raw: Variant = arrays[Mesh.ARRAY_INDEX]
				var indices := (
					index_raw as PackedInt32Array if index_raw is PackedInt32Array
					else PackedInt32Array()
				)
				if indices.is_empty():
					indices = PackedInt32Array(range(verts.size()))
				var i := 0
				while i + 2 < indices.size():
					out.append(
						to_root
						* (
							(verts[indices[i]] + verts[indices[i + 1]] + verts[indices[i + 2]])
							/ 3.0
						)
					)
					i += 3
		for child in node.get_children():
			stack.append(child)
	return out


## How many of the fitout's triangles sit in one deck cell. A voxel face lies ON
## the cell boundary, so the box is grown a hair; a neighbouring cell's faces sit
## a half-cell away and are never picked up by that slack.
##
## KNOWN IMPRECISION, measured rather than assumed. The grown box also contains
## the SHARED face between this cell and a solid neighbour, because that face
## lies exactly on the boundary and its triangle centroids do too. So "0
## triangles in an empty cell" is only true while that cell's solid neighbours
## have their shared faces culled — which the merged skin does, since the whole
## solid field including the interior is registered before any face is emitted.
## With `skin_enabled = false` the same query on `CABIN_INNER_CELL` returns 2:
## the un-culled underside of the roof brick directly above it, not the interior
## brick this test is watching for.
func _triangles_in_cell(boat: BoatBody, grid: DeckGrid, cell: Vector3i) -> int:
	var box := _cell_box(grid, cell)
	var n := 0
	for centroid in _triangle_centroids(boat):
		if box.has_point(centroid):
			n += 1
	return n


func _cell_box(grid: DeckGrid, cell: Vector3i) -> AABB:
	var base := grid.cell_base_local(cell)
	var half := DeckGrid.CELL_M * 0.5
	return AABB(
		Vector3(base.x - half, base.y, base.z - half),
		Vector3.ONE * DeckGrid.CELL_M,
	).grow(0.001)


## cell key -> triangle count, so two bakes can be compared without depending on
## the order their vertices were emitted in (the staged path emits the exterior
## first; the synchronous one walks the layout straight through).
func _cell_histogram(grid: DeckGrid, centroids: PackedVector3Array) -> Dictionary:
	var out := {}
	for centroid in centroids:
		var cell := grid.local_to_cell(centroid)
		var key := BrickLayout.cell_key(cell)
		out[key] = int(out.get(key, 0)) + 1
	return out


func _count_brick_colliders(boat: BoatBody) -> int:
	var walk := boat.get_walk_deck()
	if walk == null:
		return 0
	var n := 0
	for child in walk.get_children():
		if child is CollisionShape3D and str(child.name).begins_with(BoatBody.BRICK_COL_PREFIX):
			n += 1
	return n


func _first_free_cell(grid: DeckGrid, layout: BrickLayout) -> Vector3i:
	for z in range(grid.length):
		for x in range(grid.width):
			var cell := Vector3i(x, 0, z)
			if grid.in_bounds(cell) and not layout.has_cell(cell):
				return cell
	return Vector3i(-1, -1, -1)


## Boat-local AABB of every mesh the fitout actually draws.
func _drawn_aabb(boat: BoatBody) -> AABB:
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT) as Node3D
	if root == null:
		return AABB()
	var out := AABB()
	var seeded := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var local := root.global_transform.affine_inverse() * mesh.global_transform
			var box := local * mesh.mesh.get_aabb()
			out = box if not seeded else out.merge(box)
			seeded = true
		for child in node.get_children():
			stack.append(child)
	return out


## Boat-local AABB of the cells a layout occupies, padded by one cell so a brick
## that overhangs its own cell (railings, roofs) does not read as a leftover.
func _layout_aabb(grid: DeckGrid, layout: BrickLayout) -> AABB:
	var out := AABB()
	var seeded := false
	for item_raw in layout.iter_primary_cells():
		var cell: Vector3i = (item_raw as Dictionary).get("cell", Vector3i(-1, -1, -1))
		var centre := grid.cell_center_local(cell)
		var box := AABB(
			centre - Vector3.ONE * DeckGrid.CELL_M,
			Vector3.ONE * DeckGrid.CELL_M * 2.0,
		)
		out = box if not seeded else out.merge(box)
		seeded = true
	return out


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
	_t.check(message, condition)
