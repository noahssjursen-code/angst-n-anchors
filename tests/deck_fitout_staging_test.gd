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
	await _test_staged_collision_is_delivered_and_never_absent()
	await _test_abandoned_staging_window_is_flushed()
	_test_off_deck_bricks_reach_no_geometry()
	_test_off_deck_bricks_reach_no_shell()
	_t.finish(get_tree())


## STRIP TEST for the off-deck drop (REALITY.md §3d): fit a boat out twice —
## once with off-deck bricks in the layout, once without — and compare what the
## GAME's own path produced. If the numbers differ, an off-deck brick reached
## geometry.
##
## It has to go through `apply_sync` rather than `create_item_visual`, because
## `create_item_visual` was never the leak. `_item_is_valid` gated it and the
## survey duly measured "0 of 8 drawn" — but `apply_sync` offers every item to
## `VesselSkinBaker.Session` FIRST, and that class never asked the grid. Measured
## at 9912ada on a 10 x 30 grid, an off-deck `block` registered, emitted and
## committed **36 vertices, the same 36 an on-deck one produces**, and most
## bricks on a vessel are baked. The survey's zero held only because a helm, a
## bollard and a nav light are all LIVE bricks.
func _test_off_deck_bricks_reach_no_geometry() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var clean := _cabin_layout(true)
	var smuggled := _cabin_layout(true)
	## Off the deck by a wide margin, and BAKED bricks — the ones that go through
	## the skin session rather than through `create_item_visual`.
	var off_cells := [
		Vector3i(grid.width + 6, 0, grid.length + 6),
		Vector3i(grid.width + 7, 0, grid.length + 6),
		Vector3i(-5, 0, 30),
	]
	for cell_raw in off_cells:
		var cell: Vector3i = cell_raw
		_check(
			not smuggled.set_brick(grid, cell, "block", 0),
			"the setter refuses (%d, %d, %d)" % [cell.x, cell.y, cell.z],
		)
		smuggled._store_cell(cell, "block", 0)
	_check(
		smuggled.count() == clean.count() + off_cells.size(),
		"the smuggled layout carries %d more cells than the clean one"
		% off_cells.size(),
	)
	_check(
		VesselSkinBaker.is_baked_brick("block"),
		"the smuggled bricks go through the merged skin, not through create_item_visual",
	)

	var clean_boat := _new_boat()
	DeckFitout.apply_sync(clean_boat, clean, grid, "general_vessel")
	var clean_stats := _fitout_stats(clean_boat)
	clean_boat.queue_free()

	var dirty_boat := _new_boat()
	DeckFitout.apply_sync(dirty_boat, smuggled, grid, "general_vessel")
	var dirty_stats := _fitout_stats(dirty_boat)
	dirty_boat.queue_free()

	_check(
		int(clean_stats["vertices"]) > 0 and int(clean_stats["nodes"]) > 0,
		"the control fitout drew something at all (%d vertices, %d nodes)"
		% [int(clean_stats["vertices"]), int(clean_stats["nodes"])],
	)
	_check(
		int(dirty_stats["vertices"]) == int(clean_stats["vertices"]),
		"three bricks off the deck contribute no vertices (%d vs %d)"
		% [int(dirty_stats["vertices"]), int(clean_stats["vertices"])],
	)
	_check(
		int(dirty_stats["nodes"]) == int(clean_stats["nodes"]),
		"three bricks off the deck contribute no nodes (%d vs %d)"
		% [int(dirty_stats["nodes"]), int(clean_stats["nodes"])],
	)
	## And the drop is REPORTED rather than silent — the whole point of the wave.
	_check(
		DeckFitout.placement_faults(grid, smuggled).size() == off_cells.size(),
		"the fitout can name every brick it refused to draw",
	)
	_check(
		DeckFitout.placement_faults(grid, clean).is_empty(),
		"and names none on a layout that is entirely on the deck",
	)


## THE SAME STRIP TEST, ONE LAYER UP — and the layer the one above could not see.
##
## `_test_off_deck_bricks_reach_no_geometry` runs through `apply_sync`, which
## filters its item list before anything draws, so it goes green whatever
## `BrickShellClassifier` believes. The classifier is on the OTHER entry point:
## `apply_staged` -> `DeckFitoutJob.configure` -> `classify`, and it built its
## occupancy field by walking `layout.cells` verbatim while its grid argument sat
## unused behind an underscore.
##
## WHAT EVERY FIXTURE IN THIS FILE DOES NOT CONTAIN, which is why nothing here
## reddened for it: an off-deck cell. `_assert_fixture_on_deck` exists to keep
## them out — correctly, it was added after a fixture that was entirely off the
## hull passed a check vacuously — and `_cabin_layout` builds through `set_brick`,
## which refuses one. So the classifier had never once been shown a layout of the
## shape it mishandled. The two checks it did have ("cabin wall is exterior",
## "sealed cabin block is interior") are true of a clean layout and stay true of a
## dirty one; they are pointed at the split, and the split is not where it broke.
##
## Measured at c531076 on hull_90x24 (`tests/_shell_cost.gd`): one smuggled cell
## at (-40, 0, -40) took this cabin's `exterior_air_count` from 121 to 28600 and
## `classify` from 1.16 ms to 131.56 ms; four cells carrying hull_150x32 indices
## took a 3000-brick vessel from 67.23 ms to 311.11 ms, synchronously, inside
## `apply_staged`. `exterior_air_count` is what is asserted here — it is a count,
## so it says the same thing on a fast box and on llvmpipe.
func _test_off_deck_bricks_reach_no_shell() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var clean := _cabin_layout(true)
	var smuggled := _cabin_layout(true)
	## The far cell is the cost case. The deck-edge cell is the correctness case
	## and needs a fixture nobody had built: a brick standing at the outboard edge,
	## walled in on its other four in-plane sides and roofed, so its ONLY opening
	## faces the water. The one cell that could seal it is a cell this deck cannot
	## carry. Both layouts get the pocket; only the dirty one gets the plug.
	var edge := _edge_cell_with_surround(grid)
	_check(edge.x >= 0, "the fixture found an on-deck cell whose +X neighbour is off the deck")
	for layout in [clean, smuggled]:
		for offset in [Vector3i.ZERO, Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
				Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
			_check(
				(layout as BrickLayout).set_brick(grid, edge + (offset as Vector3i), "block", 0),
				"the edge pocket cell %s is on the deck" % str(edge + (offset as Vector3i)),
			)
	_check(
		_shell_of(grid, clean).has(BrickLayout.cell_key(edge)),
		"with nothing beside it, the edge brick faces open water and is EXTERIOR",
	)
	for cell_raw in [Vector3i(-40, 0, -40), edge + Vector3i(1, 0, 0)]:
		var cell: Vector3i = cell_raw
		_check(
			not smuggled.set_brick(grid, cell, "block", 0),
			"the setter refuses (%d, %d, %d) for the shell fixture" % [cell.x, cell.y, cell.z],
		)
		## A doctored or stale save reaches a live layout exactly like this:
		## `BrickLayout.from_dict` trusts a record's cells verbatim, deliberately.
		smuggled._store_cell(cell, "block", 0)
	_check(
		smuggled.count() == clean.count() + 2,
		"the shell fixture carries two cells this deck cannot hold",
	)

	var kept_clean: Array = DeckFitout.on_deck_items(grid, clean.iter_primary_cells())["kept"]
	var kept_dirty: Array = DeckFitout.on_deck_items(grid, smuggled.iter_primary_cells())["kept"]
	_check(
		kept_dirty.size() == kept_clean.size(),
		"the fit-out's own filter drops both (%d kept vs %d)" % [kept_dirty.size(), kept_clean.size()],
	)
	var shell_clean: Dictionary = BRICK_SHELL_CLASSIFIER.classify(clean, grid, kept_clean)
	var shell_dirty: Dictionary = BRICK_SHELL_CLASSIFIER.classify(smuggled, grid, kept_dirty)
	_check(
		int(shell_clean.get("exterior_air_count", -1)) > 0,
		"the control shell floods some air at all (%d cells)"
		% int(shell_clean.get("exterior_air_count", -1)),
	)
	## THE COST PROPERTY. A brick the deck cannot carry does not enlarge the
	## volume the flood fill has to cross, because it is not there.
	_check(
		int(shell_dirty.get("exterior_air_count", -1))
			== int(shell_clean.get("exterior_air_count", -1)),
		"a cell off the deck does not stretch the flood fill (%d air cells vs %d)"
		% [
			int(shell_dirty.get("exterior_air_count", -1)),
			int(shell_clean.get("exterior_air_count", -1)),
		],
	)
	## THE CORRECTNESS PROPERTY, and it is the half the 2026-08-15 measurement
	## missed by putting its smuggled cell 40 cells from anything. A brick that
	## will never be built must not seal the brick beside it: an INTERIOR brick is
	## drawn in INTERIOR_VISUALS, and a remote replica stops after EXTERIOR_VISUALS.
	_check(
		(shell_dirty.get("interior", []) as Array).size()
			== (shell_clean.get("interior", []) as Array).size(),
		"a cell off the deck seals nothing into the interior (%d interior vs %d)"
		% [
			(shell_dirty.get("interior", []) as Array).size(),
			(shell_clean.get("interior", []) as Array).size(),
		],
	)
	var keys_clean: Dictionary = shell_clean.get("exterior_keys", {})
	var keys_dirty: Dictionary = shell_dirty.get("exterior_keys", {})
	_check(
		keys_dirty.size() == keys_clean.size(),
		"the exterior set is the same size with the off-deck cells in (%d vs %d)"
		% [keys_dirty.size(), keys_clean.size()],
	)
	var moved := 0
	for key in keys_clean.keys():
		if not keys_dirty.has(key):
			moved += 1
	_check(moved == 0, "no on-deck brick left the exterior set (%d did)" % moved)
	_check(
		keys_dirty.has(BrickLayout.cell_key(edge)),
		"the edge brick is STILL exterior with a never-built cell smuggled beside it",
	)
	_check(
		not keys_dirty.has(BrickLayout.cell_key(edge + Vector3i(1, 0, 0))),
		"and the off-deck cell itself is in neither list",
	)

	## THE OTHER CALL SHAPE. `deck_fitout_load_bench` and `_test_shell_classifier`
	## hand over a layout and no item list, so nothing has filtered for them; that
	## is the shape the grid argument exists for.
	var shell_raw: Dictionary = BRICK_SHELL_CLASSIFIER.classify(smuggled, grid)
	_check(
		int(shell_raw.get("exterior_air_count", -1))
			== int(shell_clean.get("exterior_air_count", -1)),
		"classify(layout, grid) with no item list refuses the same cells (%d air vs %d)"
		% [
			int(shell_raw.get("exterior_air_count", -1)),
			int(shell_clean.get("exterior_air_count", -1)),
		],
	)
	var off_deck_out := 0
	for list_name in ["exterior", "interior"]:
		for item_raw in shell_raw.get(list_name, []) as Array:
			var item := item_raw as Dictionary
			if not BrickLayout.cell_on_grid(
				grid,
				item.get("cell", Vector3i.ZERO) as Vector3i,
				str(item.get("brick_id", "")),
				int(item.get("yaw", 0)),
			):
				off_deck_out += 1
	_check(
		off_deck_out == 0,
		"and returns no off-deck brick for either stage to draw (%d)" % off_deck_out,
	)

	_check_footprint_fillers_stay_solid(grid)


## The exterior key set of a layout, taken through the fit-out's own filter so
## the helper cannot disagree with the production path about what is built.
func _shell_of(grid: DeckGrid, layout: BrickLayout) -> Dictionary:
	var kept: Array = DeckFitout.on_deck_items(grid, layout.iter_primary_cells())["kept"]
	return BRICK_SHELL_CLASSIFIER.classify(layout, grid, kept).get("exterior_keys", {})


## A MULTI-CELL BRICK IS ACCEPTED ONCE AND OCCUPIES SIX CELLS, and the fix above
## turns on that distinction: a cell is solid iff its PRIMARY was accepted, and a
## footprint's five filler cells carry `occupied_by` and no verdict of their own.
## Nothing in this file had ever placed one — every fixture here is `set_brick`,
## which is 1x1x1 — so a fix that dropped fillers from the occupancy field would
## have opened a hole in every door and shown up first as a player seeing daylight
## through a deckhouse.
##
## Stated as a substitution: the same six cells built as one `block_door_fixed`
## and as six blocks must flood the same air and seal the same cabin.
func _check_footprint_fillers_stay_solid(grid: DeckGrid) -> void:
	var blocks := _cabin_layout(true)
	var blocks_kept: Array = DeckFitout.on_deck_items(grid, blocks.iter_primary_cells())["kept"]
	var blocks_shell: Dictionary = BRICK_SHELL_CLASSIFIER.classify(blocks, grid, blocks_kept)
	var door_origin := Vector3i(CABIN_ORIGIN.x + 1, CABIN_ORIGIN.y, CABIN_ORIGIN.z)
	var want := {}
	for dx in range(2):
		for dy in range(3):
			want[BrickLayout.cell_key(door_origin + Vector3i(dx, dy, 0))] = true
	var doored := _cabin_layout(true)
	for key in want.keys():
		doored.erase_cell(BrickLayout.parse_key(str(key)))
	_check(
		doored.place_footprint(door_origin, "block_door_fixed", 0, grid),
		"a 2x3x1 door lands in the cabin's forward wall",
	)
	var got := 0
	for key in want.keys():
		if doored.cells.has(key):
			got += 1
	_check(
		got == want.size() and doored.count() == _cabin_layout(true).count(),
		"the door occupies exactly the six cells the six blocks did (%d of %d, %d cells total)"
		% [got, want.size(), doored.count()],
	)
	_check(
		doored.iter_primary_cells().size() == _cabin_layout(true).iter_primary_cells().size() - 5,
		"and it is ONE primary item where the blocks were six",
	)
	var kept: Array = DeckFitout.on_deck_items(grid, doored.iter_primary_cells())["kept"]
	var shell: Dictionary = BRICK_SHELL_CLASSIFIER.classify(doored, grid, kept)
	_check(
		int(shell.get("exterior_air_count", -1))
			== int(blocks_shell.get("exterior_air_count", -1)),
		"a footprint brick's filler cells are as solid as the blocks they replace (%d air vs %d)"
		% [
			int(shell.get("exterior_air_count", -1)),
			int(blocks_shell.get("exterior_air_count", -1)),
		],
	)
	_check(
		not (shell.get("exterior_keys", {}) as Dictionary).has(
			BrickLayout.cell_key(CABIN_INNER_CELL)
		),
		"and the cabin behind the door is still sealed",
	)


## First on-deck cell whose +X neighbour is off the deck and whose other four
## in-plane neighbours are on it, so a single smuggled cell is the only thing
## standing between the target and open air.
func _edge_cell_with_surround(grid: DeckGrid) -> Vector3i:
	for z in range(2, grid.length - 2):
		for x in range(grid.width - 1, 0, -1):
			var cell := Vector3i(x, 0, z)
			if not grid.in_bounds(cell) or grid.in_bounds(cell + Vector3i(1, 0, 0)):
				continue
			if (grid.in_bounds(cell + Vector3i(-1, 0, 0))
					and grid.in_bounds(cell + Vector3i(0, 0, 1))
					and grid.in_bounds(cell + Vector3i(0, 0, -1))):
				return cell
	return Vector3i(-1, -1, -1)


func _fitout_stats(boat: BoatBody) -> Dictionary:
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	if root == null:
		return {"vertices": 0, "nodes": 0}
	return {"vertices": _vertices_of(root), "nodes": _descendants_of(root)}


func _vertices_of(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				n += mi.mesh.surface_get_array_len(i)
	for c in node.get_children():
		n += _vertices_of(c)
	return n


func _descendants_of(node: Node) -> int:
	var n := node.get_child_count()
	for c in node.get_children():
		n += _descendants_of(c)
	return n


## The 5x5x3 hollow cabin every staging fixture is built from. `sealed` adds the
## interior block the shell/interior split is measured against.
func _cabin_layout(sealed: bool) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	var grid := HullRegistry.make_grid(HULL_ID)
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					layout.set_brick(
						grid,
						Vector3i(
							CABIN_ORIGIN.x + x, CABIN_ORIGIN.y + y, CABIN_ORIGIN.z + z
						),
						"block",
						0,
					)
	if sealed:
		layout.set_brick(grid, CABIN_INNER_CELL, "block", 0)
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
	_check(layout.set_brick(grid, inner, "block", 0), "sealed cabin block lands on the deck")
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
		_check(
			bow_layout.set_brick(
				grid, partial, "block_45", grid.partial_bow_yaw_degrees(partial)
			),
			"a diagonal brick yawed outboard is accepted on a bow HALF cell",
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
		layout.set_brick(grid, live_cell, "bollard", 0)
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
				if not layout.set_brick(grid, cell, "block", 0):
					continue
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


## ── The staged path's collision contract ─────────────────────────────────────
##
## `plan_collision_physics_test` §5 holds the SYNCHRONOUS fit-out to two things:
## when `apply_plan` returns, with no frame allowed to pass, the WalkDeck is in
## THE WORLD'S space and already carries a shape for every box the baker emitted.
## It exists because an earlier version passed on a vessel that was 69 of 69
## stations walk-through. The staged path had no equivalent, and it is the path
## where the risk is real: a >1000-brick vessel mounts across hundreds of frames,
## in the tree, with a player able to be standing on it the whole time.
##
## Three properties, and each one is a different failure:
##
##   A. THE VESSEL IS NEVER NON-COLLIDING. Sampled EVERY frame of the fit-out:
##      the WalkDeck is in the world's space and its deck slab is present and
##      enabled. This is the check that forbids the obvious fix — wrapping the
##      mount phase in `begin/end_walk_collider_batch` and letting it span
##      frames — which is quadratic-free and leaves a player falling through the
##      deck of a vessel he is standing on.
##   B. THE COLLIDERS ARE ACTUALLY DELIVERED, and delivered by the time anything
##      can observe completion. Read inside the `readiness_changed` emission, so
##      the same "nothing awaited" discipline as §5: a flush moved to
##      `call_deferred` or dropped altogether reddens here and nowhere else.
##   C. THE FLUSH HAD SOMETHING TO FLUSH. Without it, B is `0 == 0` on a vessel
##      with no walls, which is precisely the shape §4 warns about.
const STAGED_COLLIDER_BRICKS := 1200

var _watch_walk: CollisionObject3D = null
var _watch_world_space := RID()
var _watch_frames := 0
var _watch_no_space := 0
var _watch_no_slab := 0
var _interactive_snapshot: Dictionary = {}


func _test_staged_collision_is_delivered_and_never_absent() -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var layout := _fill_blocks(grid, STAGED_COLLIDER_BRICKS)
	var placed := layout.count()
	_check(
		placed > DeckFitout.LARGE_LAYOUT_THRESHOLD,
		"the collision fixture is over the staging threshold (%d bricks > %d)"
		% [placed, DeckFitout.LARGE_LAYOUT_THRESHOLD],
	)
	var boat := VesselSpawn.instantiate(HULL_ID, {"hull_id": HULL_ID, "cells": {}}) as BoatBody
	if not _t.check("a vessel spawned for the staged collision check", boat != null):
		return
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_watch_walk = boat.get_walk_deck() as CollisionObject3D
	if not _t.check("the staged vessel has a WalkDeck body", _watch_walk != null):
		boat.queue_free()
		return
	var rid := _watch_walk.get_rid()
	var world := _watch_walk.get_world_3d()
	_watch_world_space = world.space if world != null else RID()
	_check(
		_watch_world_space.is_valid()
		and PhysicsServer3D.body_get_space(rid) == _watch_world_space,
		"the WalkDeck is in the world's space before the staged fit-out begins",
	)
	_watch_frames = 0
	_watch_no_space = 0
	_watch_no_slab = 0
	_interactive_snapshot = {}

	DeckFitout.apply(boat, layout, grid, "general_vessel")
	var job := boat.get_node_or_null(DeckFitout.FITOUT_JOB)
	if not _t.check("the staged fit-out dispatched a job", job != null):
		boat.queue_free()
		return
	job.connect("readiness_changed", _snapshot_at_interactive)

	for _frame in range(20000):
		if DeckFitout.readiness_of(boat) >= DeckFitout.READINESS_INTERACTIVE:
			break
		if boat.get_node_or_null(DeckFitout.FITOUT_JOB) == null:
			break
		_sample_walk_deck()
		await get_tree().physics_frame
	print(
		"[staged collision] %d bricks, sampled %d physics frames of the fit-out: "
		% [placed, _watch_frames]
		+ "%d out of the world's space, %d without an enabled deck slab"
		% [_watch_no_space, _watch_no_slab]
	)
	_check(
		_watch_frames >= 8,
		"the staged fit-out was sampled across many frames (%d) — a run that "
		% _watch_frames
		+ "finished in one frame would make the sampling below vacuous",
	)
	_check(
		_watch_no_space == 0,
		"the WalkDeck stayed in the world's space on every frame of the staged "
		+ "fit-out (%d of %d frames out of it)" % [_watch_no_space, _watch_frames],
	)
	_check(
		_watch_no_slab == 0,
		"the WalkDeck's deck slab stayed present and enabled on every frame of "
		+ "the staged fit-out (%d of %d frames without it)"
		% [_watch_no_slab, _watch_frames],
	)

	var expected := _count_expected_brick_colliders(grid, layout)
	_check(
		expected > 8,
		"the staged collision fixture emits colliders to count (%d)" % expected,
	)
	_check(
		not _interactive_snapshot.is_empty(),
		"the job announced INTERACTIVE readiness (the snapshot below was taken)",
	)
	if not _interactive_snapshot.is_empty():
		_check(
			bool(_interactive_snapshot.get("space_is_world", false)),
			"the staged fit-out reaches INTERACTIVE with the WalkDeck in THE "
			+ "WORLD'S space (body %s, world %s)"
			% [
				str(_interactive_snapshot.get("space", RID())),
				str(_watch_world_space),
			],
		)
		_t.equal(
			"the staged fit-out reaches INTERACTIVE with every brick collider "
			+ "already on the body, in the same call stack",
			int(_interactive_snapshot.get("brick_shapes", -1)),
			expected,
		)
	_t.equal(
		"the closing flush moved every staged collider onto the body",
		int(boat.get_meta("fitout_staged_colliders_flushed", -1)),
		expected,
	)
	## The scene-tree half of the same statement. A shape count with no node
	## behind it, or a node the physics server never heard of, are both
	## walk-through — `_count_brick_colliders` reads the tree,
	## `_interactive_snapshot.brick_shapes` reads PhysicsServer3D.
	_t.equal(
		"every staged collider is a WalkDeck child once the fit-out completes",
		_count_brick_colliders(boat),
		expected,
	)
	_t.equal(
		"no collider is left behind in the staging window",
		boat.walk_collider_staged_count(),
		0,
	)
	boat.queue_free()
	await get_tree().process_frame


## The net under staging, and the reason it needs one. A collider batch is
## illegal across a frame boundary and `BoatBody._physics_process` forces one
## closed; a staging window is LEGAL across frames, so that rule cannot police
## it. What replaces it is ownership — and the failure it catches is silent:
## colliders built into an orphan node, a vessel with no walls, no error
## anywhere. `BoatBody.begin_walk_collider_staging`'s header claims the flush
## happens; REALITY.md §3c says go and find the check that holds it to that.
##
## Driven through the public API rather than through a fit-out, because the
## trigger is a fit-out that DIED — there is no way to reach it from a job that
## is behaving.
func _test_abandoned_staging_window_is_flushed() -> void:
	var boat := _new_boat()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walk := boat.get_walk_deck() as CollisionObject3D
	if not _t.check("the watchdog fixture has a WalkDeck body", walk != null):
		boat.queue_free()
		return
	var rid := walk.get_rid()
	var before := PhysicsServer3D.body_get_shape_count(rid)
	var owner_node := Node.new()
	owner_node.name = "PretendFitoutJob"
	boat.add_child(owner_node)
	boat.begin_walk_collider_staging(owner_node)
	boat.add_walk_brick_collider("watchdog_0", Vector3(0.0, 1.0, 0.0), Vector3.ONE, 0.0)
	boat.add_walk_brick_collider("watchdog_1", Vector3(0.0, 1.0, 2.0), Vector3.ONE, 0.0)
	_t.equal("colliders built in a staging window are not on the body yet",
		PhysicsServer3D.body_get_shape_count(rid), before)
	_t.equal("...they are held in the window", boat.walk_collider_staged_count(), 2)

	## The window survives frames while its owner lives — otherwise the watchdog
	## would be closing every staged fit-out on its first frame and this whole
	## design would be inert.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_t.equal("a staging window whose owner is alive survives a frame boundary",
		boat.walk_collider_staged_count(), 2)

	boat.remove_child(owner_node)
	owner_node.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_t.equal("an abandoned staging window is flushed, not stranded",
		boat.walk_collider_staged_count(), 0)
	_t.equal("...and its colliders land on the body",
		PhysicsServer3D.body_get_shape_count(rid), before + 2)
	boat.queue_free()
	await get_tree().process_frame


func _sample_walk_deck() -> void:
	if _watch_walk == null or not is_instance_valid(_watch_walk):
		return
	_watch_frames += 1
	if PhysicsServer3D.body_get_space(_watch_walk.get_rid()) != _watch_world_space:
		_watch_no_space += 1
	var slab := _watch_walk.get_node_or_null(
		BoatBody.WALK_DECK_COLLIDER_NAME
	) as CollisionShape3D
	if slab == null or slab.disabled or slab.shape == null:
		_watch_no_slab += 1


## Runs INSIDE `DeckFitoutJob._set_readiness`'s emission — the staged equivalent
## of §5's "nothing awaited". Every number here is read from PhysicsServer3D in
## the job's own call stack, before `_process` has returned and before any frame
## boundary, so a flush that is deferred by even one idle frame is visible.
func _snapshot_at_interactive(readiness: int) -> void:
	if readiness != DeckFitout.READINESS_INTERACTIVE:
		return
	if _watch_walk == null or not is_instance_valid(_watch_walk):
		return
	var rid := _watch_walk.get_rid()
	var brick_shapes := 0
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner_node := _watch_walk.shape_owner_get_owner(
			_watch_walk.shape_find_owner(i)
		) as Node
		if owner_node != null and str(owner_node.name).begins_with(
			BoatBody.BRICK_COL_PREFIX
		):
			brick_shapes += 1
	var space := PhysicsServer3D.body_get_space(rid)
	_interactive_snapshot = {
		"space": space,
		"space_is_world": space.is_valid() and space == _watch_world_space,
		"shapes": PhysicsServer3D.body_get_shape_count(rid),
		"brick_shapes": brick_shapes,
	}


## How many colliders this layout OUGHT to produce, derived from the catalogue
## rather than read back off the thing under test. `block` carries none of the
## tags `DeckFitout.mount_item_gameplay` diverts, so it is one box per brick —
## but deriving it means a fixture that later gains a door or a stair still
## states the right number instead of quietly agreeing with whatever was built.
func _count_expected_brick_colliders(grid: DeckGrid, layout: BrickLayout) -> int:
	var n := 0
	for item_raw in layout.iter_primary_cells():
		var item := item_raw as Dictionary
		var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
		var brick_id := str(item.get("brick_id", ""))
		if not grid.in_bounds(cell) or not BrickCatalog.has(brick_id):
			continue
		if BrickCatalog.has_tag(brick_id, "text"):
			continue
		if (
			BrickCatalog.has_tag(brick_id, "door")
			or BrickCatalog.has_tag(brick_id, "stairs")
			or BrickCatalog.has_tag(brick_id, "helm")
			or BrickCatalog.has_tag(brick_id, "light")
		):
			continue
		n += 1
	return n


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
