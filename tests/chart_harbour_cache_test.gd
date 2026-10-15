extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	ChartHarbourPlan.clear_cache()
	var first := _snapshot(101, [{"id": "a", "position": Vector3(20, 0, 40)},
		{"id": "b", "position": Vector3(60, 0, 80)}])
	ChartHarbourPlan.prepare_snapshot(first)
	var a := ChartHarbourPlan.new()
	var b := ChartHarbourPlan.new()
	ChartHarbourPlan._cache["a"] = a
	ChartHarbourPlan._cache["b"] = b
	# New directory snapshot: retain both existing plans and permit a new port.
	var added := _snapshot(101, first.ports.duplicate(true))
	added.ports.append({"id": "c", "position": Vector3(100, 0, 120)})
	added.catalog_revision = 99
	assert(ChartHarbourPlan.for_port("a", null, added) == a,
		"Adding a port must not rebuild an unchanged harbour")
	assert(ChartHarbourPlan.for_port("b", null, added) == b)
	# A changed pose invalidates its plan, while its neighbour stays warm.
	var changed := _snapshot(101, added.ports.duplicate(true))
	changed.ports[0]["position"] = Vector3(40, 0, 80)
	ChartHarbourPlan.prepare_snapshot(changed)
	assert(not ChartHarbourPlan.is_cached("a"))
	assert(ChartHarbourPlan.for_port("b", null, changed) == b)
	# Removal must not leave a stale silhouette in the retained cache.
	var removed := _snapshot(101, [{"id": "a", "position": Vector3(40, 0, 80)}])
	ChartHarbourPlan.prepare_snapshot(removed)
	assert(not ChartHarbourPlan.is_cached("b"))
	ChartHarbourPlan._cache["a"] = a
	# Same geography in a replacement world cannot retain references to old data.
	var replacement := _snapshot(102, removed.ports.duplicate(true))
	ChartHarbourPlan.prepare_snapshot(replacement)
	assert(not ChartHarbourPlan.is_cached("a"))
	ChartHarbourPlan._cache["a"] = a
	var preview := _snapshot(102, replacement.ports.duplicate(true))
	preview.preview = true
	ChartHarbourPlan.prepare_snapshot(preview)
	assert(not ChartHarbourPlan.is_cached("a"), "Preview and gameplay have distinct caches")
	ChartHarbourPlan._cache["a"] = a
	var geography := _snapshot(102, preview.ports.duplicate(true))
	geography.preview = true
	geography.layout_checksum = "different-layout"
	ChartHarbourPlan.prepare_snapshot(geography)
	assert(not ChartHarbourPlan.is_cached("a"))
	ChartHarbourPlan.clear_cache()
	print("HARBOUR CACHE PASS: directory additions, changed poses, removals, world replacement and preview isolation")
	get_tree().quit()


func _snapshot(world_id: int, records: Array) -> ChartDataSnapshot:
	var out := ChartDataSnapshot.new()
	out.live_world_id = world_id
	out.layout_checksum = "same-geography"
	out.ports.assign(records)
	return out
