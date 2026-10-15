extends Node3D
## Complete authored harbour; 100 timed picks over four varied ray families.
const PICKER = preload("res://scripts/port/building/custom_port_placement_picker.gd")
const PRESENTER = preload("res://scripts/port/building/custom_port_presenter.gd")
const EXAMPLE = preload("res://scripts/port/building/custom_port_example.gd")
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
var failures: Array[String] = []
var measurements: Dictionary = {}
var presenter: CustomPortPresenter
var picker

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()

func _run() -> void:
	var world := {"seed": 73119, "generation_version": 1, "checksum": "performance-coast"}
	var plots: Array = [{"id": "plot", "rect_m": [-200, -200, 400, 400], "owner_company_id": EXAMPLE.OWNER}]
	var record: Dictionary = EXAMPLE.build(Vector3.ZERO, plots, world)
	record.erase("_site_yaw")
	record.water_regions = [{"rect_m": [-200, -400, 400, 400], "depth_m": 12}]
	var started := Time.get_ticks_usec()
	var state: CustomPortState = STATE.from_dict(record, world, CustomPortCatalog.definitions())
	measurements.state_reconstruct_ms = _elapsed(started)
	_check(state.validation_errors.is_empty(), "Complete example validates with one water region: " + str(state.validation_errors))
	_check(record.placements.size() >= 1000, "Benchmark uses the complete expanded waterfront example")
	if not failures.is_empty(): _finish(); return
	var snapshot := state.to_dict()
	var berths := state.derived_berths()
	presenter = PRESENTER.new()
	add_child(presenter)
	started = Time.get_ticks_usec()
	presenter.load_record(snapshot, berths)
	measurements.presenter_load_ms = _elapsed(started)
	for frame in 2: await get_tree().process_frame
	measurements.placements = snapshot.placements.size()
	measurements.water_regions = snapshot.water_regions.size()
	measurements.berths = berths.size()
	measurements.scene_mesh_instances = presenter.find_children("*", "MeshInstance3D", true, false).size()
	picker = PICKER.new()
	started = Time.get_ticks_usec()
	picker.configure(presenter)
	measurements.configure_cold_ms = _elapsed(started)
	measurements.cold_stats = picker.stats()
	started = Time.get_ticks_usec()
	picker.rebuild()
	measurements.rebuild_warm_ms = _elapsed(started)
	measurements.warm_stats = picker.stats()
	var groups := {"deck": [], "gutter": [], "crane": [], "miss": []}
	# Work equipment can occlude individual slabs. Select exposed platform rays
	# at widely separated record indices, before measuring any steady picks.
	for index in range(0, snapshot.placements.size(), 37):
		var row: Dictionary = snapshot.placements[index]
		if str(row.asset_id) not in ["foundation", "quay"]: continue
		var at := CustomPortCatalog.vector3(row.position_m)
		var ray := {"origin": at + Vector3(.2, 40, .1), "direction": Vector3.DOWN, "expected": str(row.id)}
		if picker.pick(ray.origin, ray.direction, 500).get("placement_id", "") != row.id: continue
		groups.deck.append(ray)
		if groups.deck.size() == 5: break
	for id in ["warehouse-roof-0", "workshop-roof-1", "office-roof-0", "warehouse-roof-0", "office-roof-1"]:
		var ray := _surface_ray(id, 8, groups.gutter.size() * 6)
		_check(not ray.is_empty(), "Find an external ray to actual gutter " + id)
		if not ray.is_empty(): groups.gutter.append(ray)
	for id in ["container-terminal", "bulk-terminal", "container-terminal", "bulk-terminal", "container-terminal"]:
		var ray := _surface_ray(id, 12, groups.crane.size() * 12)
		_check(not ray.is_empty(), "Find an external ray to actual crane " + id)
		if not ray.is_empty(): groups.crane.append(ray)
	for index in 5:
		groups.miss.append({"origin": Vector3(-40 + index * 20, 80, 10 + index * 9), "direction": Vector3(.1 * (index - 2), 1, .07 * index).normalized(), "expected": ""})
	# Verify the representative targets before timing; setup scans are excluded.
	for label in groups:
		_check(groups[label].size() == 5, str(label) + " has five distinct ray variants")
		for ray in groups[label]:
			var hit: Dictionary = picker.pick(ray.origin, ray.direction, 500)
			_check(hit.get("placement_id", "") == ray.expected, str(label) + " preflight targets " + str(ray.expected))
	if failures.is_empty():
		var all_times: Array[float] = []
		var per_target: Dictionary = {}
		var hit_counts: Dictionary = {}
		var query_totals: Dictionary = {}
		for label in groups:
			per_target[label] = []
			hit_counts[label] = 0
			query_totals[label] = 0
		# Interleave categories so one family does not own all cache warm-up.
		for repetition in 25:
			for label in groups:
				var ray: Dictionary = groups[label][repetition % 5]
				started = Time.get_ticks_usec()
				var hit: Dictionary = picker.pick(ray.origin, ray.direction, 500)
				var elapsed := _elapsed(started)
				all_times.append(elapsed)
				per_target[label].append(elapsed)
				if not hit.is_empty(): hit_counts[label] += 1
				query_totals[label] += int(picker.stats().exact_queries)
				_check(hit.get("placement_id", "") == ray.expected, "Timed " + str(label) + " ray remains correct")
		measurements.targets = {}
		for label in groups:
			measurements.targets[label] = _summary(per_target[label])
			measurements.targets[label].ray_variants = groups[label].size()
			measurements.targets[label].hits = hit_counts[label]
			measurements.targets[label].mean_exact_queries = query_totals[label] / 25.0
		measurements.aggregate = _summary(all_times)
		measurements.stats = picker.stats()
		measurements.mean_exceeds_2ms = float(measurements.aggregate.mean_ms) > 2
		if measurements.mean_exceeds_2ms:
			push_warning("Complete harbour picker mean exceeds 2 ms: " + str(measurements.aggregate.mean_ms))
		print("PORT_PICKER_PERFORMANCE ", JSON.stringify(measurements))
	picker.clear()
	presenter.clear_record()
	presenter.queue_free()
	await get_tree().process_frame
	_finish()

func _surface_ray(id: String, offset: float, skip: int) -> Dictionary:
	var root: Node3D = presenter.placement_nodes[id]
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree(): continue
		var faces := visual.mesh.get_faces()
		for index in range(mini(skip, maxi(0, faces.size() - 3)), faces.size(), 3):
			var a: Vector3 = visual.global_transform * faces[index]
			var b: Vector3 = visual.global_transform * faces[index + 1]
			var c: Vector3 = visual.global_transform * faces[index + 2]
			var normal := (b-a).cross(c-a)
			if normal.length_squared() < .000001: continue
			normal = normal.normalized()
			var target := (a+b+c) / 3.0
			for side in [1.0, -1.0]:
				var origin: Vector3 = target + normal * offset * side
				if origin.y < .2: continue
				var direction: Vector3 = normal * -side
				var hit: Dictionary = picker.pick(origin, direction, 500)
				if hit.get("placement_id", "") == id:
					return {"origin": origin, "direction": direction, "expected": id}
	return {}

func _summary(raw: Array) -> Dictionary:
	var values := raw.duplicate()
	values.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"samples": values.size(), "mean_ms": total / values.size(), "p95_ms": values[ceili(values.size() * .95) - 1], "max_ms": values.back()}

func _elapsed(started: int) -> float:
	return (Time.get_ticks_usec() - started) / 1000.0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _finish() -> void:
	measurements.failures = failures.duplicate()
	var args := OS.get_cmdline_user_args()
	var index := args.find("--port-picker-performance-output")
	if index >= 0 and index + 1 < args.size():
		var file := FileAccess.open(args[index + 1], FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(measurements, "\t", false, true))
			file.close()
		else: _check(false, "Cannot write benchmark JSON")
	else: _check(false, "Provide --port-picker-performance-output with an absolute output path")
	print("CUSTOM PORT PICKER PERFORMANCE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
