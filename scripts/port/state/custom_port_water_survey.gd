class_name CustomPortWaterSurvey
extends RefCounted
## Incremental geography adapter. Callers supply the real world's seabed sampler;
## this class never invents terrain, changes a port, or authorizes its own result.
## Depths are minima on a 2m lattice with a 1m safety allowance, not a proof that
## unsampled terrain between points has no sharper obstruction.

const CELL_M := 8.0
const SAMPLE_M := 2.0
const DEPTH_MARGIN_M := 1.0
const DEFAULT_APRON_M := 96.0
const DEFAULT_MAX_CELLS := 32768
const HARD_MAX_CELLS := 65536
const EPS := 0.0001

var _sampler: Callable
var _origin := Vector2.ZERO
var _sea_level := 0.0
var _port_id := ""
var _world: Dictionary = {}
var _revision := 0
var _pending: Array[Vector2i] = []
var _regions: Array[Dictionary] = []
var _completed := 0
var _skipped := 0
var _samples := 0
var _sampling_usec := 0
var _error := ""
var _cancelled := false


static func begin(record: Dictionary, seabed: Callable, sea_level: float, options: Dictionary = {}) -> Dictionary:
	if not seabed.is_valid() or not is_finite(sea_level):
		return _failure("invalid_sampler")
	if not record.get("id") is String or str(record.id).is_empty() or not record.get("world") is Dictionary:
		return _failure("invalid_port_identity")
	if not _numbers(record.get("origin_m"), 3) or not record.get("plots") is Array:
		return _failure("invalid_survey_geometry")
	var revision: Variant = record.get("revision", 0)
	if not _number(revision) or float(revision) < 0 or float(revision) != floorf(float(revision)):
		return _failure("invalid_revision")
	var raw_apron: Variant = options.get("apron_m", DEFAULT_APRON_M)
	var raw_limit: Variant = options.get("max_cells", DEFAULT_MAX_CELLS)
	if not _number(raw_apron) or float(raw_apron) < 0 or float(raw_apron) > 512 or not _number(raw_limit):
		return _failure("invalid_survey_options")
	var apron := float(raw_apron)
	var limit := clampi(int(raw_limit), 1, HARD_MAX_CELLS)
	var cells: Dictionary = {}
	var bounds := Rect2()
	var has_bounds := false
	for plot in record.plots:
		if not plot is Dictionary or not _rectangle(plot.get("rect_m")):
			return _failure("invalid_survey_geometry")
		# Survey only the port's acquired land. Authority remains responsible for
		# validating ownership and accepting the resulting survey context.
		if str(plot.get("owner_company_id", "")) != str(record.get("owner_company_id", "")):
			continue
		var rect := _rect(plot.rect_m).grow(apron)
		var first := Vector2i(floori(rect.position.x / CELL_M), floori(rect.position.y / CELL_M))
		var end := Vector2i(ceili(rect.end.x / CELL_M), ceili(rect.end.y / CELL_M))
		if (end.x - first.x) * (end.y - first.y) > limit:
			return _failure("survey_area_too_large")
		for z in range(first.y, end.y):
			for x in range(first.x, end.x):
				cells[Vector2i(x, z)] = true
				if cells.size() > limit: return _failure("survey_area_too_large")
		bounds = bounds.merge(rect) if has_bounds else rect
		has_bounds = true
	var existing: Variant = record.get("water_regions", [])
	if not existing is Array or existing.size() > HARD_MAX_CELLS:
		return _failure("invalid_existing_survey")
	var already_covered: Dictionary = {}
	var work := 0
	for region in existing:
		if not region is Dictionary or not _rectangle(region.get("rect_m")) or not _number(region.get("depth_m")) or float(region.depth_m) < 0:
			return _failure("invalid_existing_survey")
		if not has_bounds: continue
		var rect := _rect(region.rect_m)
		var intersection := rect.intersection(bounds)
		if intersection.size.x <= 0 or intersection.size.y <= 0: continue
		var first := Vector2i(floori(intersection.position.x / CELL_M), floori(intersection.position.y / CELL_M))
		var end := Vector2i(ceili(intersection.end.x / CELL_M), ceili(intersection.end.y / CELL_M))
		for z in range(first.y, end.y):
			for x in range(first.x, end.x):
				work += 1
				if work > HARD_MAX_CELLS * 16: return _failure("survey_area_too_large")
				var key := Vector2i(x, z)
				# Even a partially covered old cell is skipped. Emitting a full
				# replacement would overlap trusted prior evidence in the authority.
				if cells.has(key) and rect.intersects(Rect2(Vector2(key) * CELL_M, Vector2.ONE * CELL_M)):
					already_covered[key] = true
	var job := CustomPortWaterSurvey.new()
	job._sampler = seabed
	job._origin = Vector2(float(record.origin_m[0]), float(record.origin_m[2]))
	job._sea_level = sea_level
	job._port_id = str(record.id)
	job._world = record.world.duplicate(true)
	job._revision = int(revision)
	job._skipped = already_covered.size()
	for key in cells:
		if not already_covered.has(key): job._pending.append(key)
	job._pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return {"ok": true, "code": "ready", "job": job, "total": job._pending.size(), "skipped": job._skipped}


func step(max_cells: int = 16, budget_ms: float = 4.0) -> Dictionary:
	if not _error.is_empty() or _cancelled or _completed >= _pending.size(): return progress()
	if not is_finite(budget_ms) or budget_ms < 0:
		_error = "invalid_step_budget"
		return progress()
	var count := clampi(max_cells, 1, 256)
	var started := Time.get_ticks_usec()
	for index in mini(count, _pending.size() - _completed):
		var cell := _pending[_completed]
		var local := Vector2(cell) * CELL_M
		var depth := INF
		for z in 5:
			for x in 5:
				var height: Variant = _sampler.call(_origin + local + Vector2(x, z) * SAMPLE_M)
				_samples += 1
				if not _number(height):
					_error = "invalid_seabed_sample"
					_sampling_usec += Time.get_ticks_usec() - started
					return progress()
				depth = minf(depth, _sea_level - float(height))
		if depth > DEPTH_MARGIN_M:
			_regions.append({"rect_m": [local.x, local.y, CELL_M, CELL_M], "depth_m": depth - DEPTH_MARGIN_M})
		_completed += 1
		if budget_ms > 0 and Time.get_ticks_usec() - started >= minf(budget_ms, 50.0) * 1000.0: break
	_sampling_usec += Time.get_ticks_usec() - started
	return progress()


func progress() -> Dictionary:
	var done := _cancelled or not _error.is_empty() or _completed >= _pending.size()
	return {"ok": _error.is_empty() and not _cancelled, "code": "cancelled" if _cancelled else (_error if not _error.is_empty() else ("complete" if done else "surveying")),
		"done": done, "completed": _completed, "total": _pending.size(), "skipped": _skipped,
		"progress": 1.0 if _pending.is_empty() else float(_completed) / _pending.size(),
		"water_cells": _regions.size(), "samples": _samples, "sampling_ms": _sampling_usec / 1000.0}


func authority_context() -> Dictionary:
	var status := progress()
	if not status.ok or not status.done: return {}
	# Send additions only. The authority preserves old cells and rejects overlaps,
	# a stale revision, or a different world. Clients cannot grant this context.
	return {"water_survey": {"port_id": _port_id, "world": _world.duplicate(true), "for_revision": _revision, "regions": _regions.duplicate(true)}}


func cancel() -> void:
	_cancelled = true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for entry in value:
		if not _number(entry): return false
	return true


static func _rectangle(value: Variant) -> bool:
	return _numbers(value, 4) and float(value[2]) > 0 and float(value[3]) > 0


static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}
