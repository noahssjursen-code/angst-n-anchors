class_name CustomPortWorldImport
extends Node3D

## Explicit local presentation import. Files are never rewritten and this node
## owns no company, fleet, money, bookings or gameplay authority.
const WORLD_POLICY = preload("res://scripts/port/building/custom_port_world_policy.gd")
const MAX_DOCUMENTS := 32
const ARGUMENT_PREFIX := "--custom-port-document="
var report: Dictionary = {"ok":true,"code":"disabled","errors":[]}
var streamer: CustomPortStreamer
var _directory: Node
var _published_ids: Array[String] = []


static func document_arguments(arguments: PackedStringArray) -> PackedStringArray:
	var paths := PackedStringArray()
	for argument in arguments:
		if argument.begins_with(ARGUMENT_PREFIX): paths.append(argument.substr(ARGUMENT_PREFIX.length()))
	return paths


static func world_identity(context: Dictionary) -> Dictionary:
	return {"seed":context.get("seed"),"generation_version":context.get("generation_version"),
		"checksum":context.get("layout_checksum")}


## Preflight is complete before creating scenery or publishing a chart entry.
## Remote rejection deliberately precedes path checks and ALL filesystem reads.
static func preflight(paths: PackedStringArray, expected_world: Dictionary, remote: bool,
		generated_ids: Array, reserved_zones: Array, catalog: Dictionary = {}) -> Dictionary:
	if paths.is_empty(): return {"ok":true,"code":"disabled","records":[],"summaries":[],"errors":[]}
	if remote: return _failure("remote_import_forbidden","Local port files are unavailable in multiplayer.")
	if paths.size()>MAX_DOCUMENTS: return _failure("too_many_documents","Choose at most %d port files."%MAX_DOCUMENTS)
	if expected_world.size()!=3 or not expected_world.get("seed") is int or not expected_world.get("generation_version") is int or not expected_world.get("checksum") is String or str(expected_world.checksum).is_empty():
		return _failure("invalid_world_identity","The finalized world identity is required.")
	var definitions := CustomPortCatalog.definitions() if catalog.is_empty() else catalog
	var records: Array = []
	var summaries: Array = []
	var loaded_paths: Array = []
	var warnings: Array = []
	for path in paths:
		var loaded := CustomPortRepository.load_state(path,expected_world,definitions)
		if not loaded.ok: return {"ok":false,"code":loaded.code,"path":path,"errors":loaded.errors}
		var snapshot: Dictionary = loaded.snapshot
		if generated_ids.has(str(snapshot.id)): return _failure("generated_port_id_conflict","Port %s uses an existing generated port identifier."%snapshot.id)
		var plane: Dictionary = WORLD_POLICY.validate_deck_plane(snapshot)
		if not plane.ok:return plane
		var vessels := CustomPortVesselProjection.validate_snapshot(snapshot)
		if not vessels.ok:return vessels
		records.append(snapshot)
		loaded_paths.append(loaded.loaded_path)
		warnings.append_array(loaded.warnings)
		summaries.append(CustomPortChartProjection.project(snapshot,definitions,loaded.state.derived_berths()))
	var collection := CustomPortCollection.validate(records)
	if not collection.ok:return collection
	var reserved := reserved_polygons(reserved_zones)
	for record: Dictionary in records:
		for plot: Dictionary in record.plots:
			var rect: Array = plot.rect_m
			var x := float(record.origin_m[0])+float(rect[0])
			var z := float(record.origin_m[2])+float(rect[1])
			var polygon := PackedVector2Array([Vector2(x,z),Vector2(x+rect[2],z),Vector2(x+rect[2],z+rect[3]),Vector2(x,z+rect[3])])
			for obstacle: PackedVector2Array in reserved:
				for overlap: PackedVector2Array in Geometry2D.intersect_polygons(polygon,obstacle):
					if _polygon_area(overlap)>.000001:
						return _failure("generated_footprint_conflict","Plot %s in %s overlaps a reserved generated structure."%[plot.id,record.id])
	return {"ok":true,"code":"validated","records":records,"summaries":summaries,
		"loaded_paths":loaded_paths,"warnings":warnings,"errors":[]}


## Generated terrain/forest exclusions are trusted geometry, not imported data.
## Ellipse bounds are conservatively reserved as an oriented rectangle.
static func reserved_polygons(zones: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for zone: Dictionary in zones:
		if zone.has("polygon"):
			var polygon := PackedVector2Array(zone.polygon)
			if polygon.size()>=3:result.append(polygon)
		elif zone.has("center") and zone.has("half_size"):
			var center: Vector2 = zone.center
			var half: Vector2 = zone.half_size
			var polygon := PackedVector2Array()
			for point in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y)]:
				polygon.append(center+point.rotated(float(zone.get("yaw",0))))
			result.append(polygon)
	return result


func load_documents(paths: PackedStringArray, context: Dictionary, remote: bool,
		generated_ids: Array, reserved_zones: Array, directory: Node,
		terrain: WorldTerrainStreamer = null, forest: WorldForestStreamer = null) -> Dictionary:
	# One-shot source; callers replace the owning node for another selected batch.
	if streamer!=null:return _failure("already_loaded","This port source is already installed.")
	report = preflight(paths,world_identity(context),remote,generated_ids,reserved_zones)
	if not report.ok or report.code=="disabled":return report
	var candidate := CustomPortStreamer.new()
	candidate.name="CustomPortStreamer"
	candidate.passive_services=true
	add_child(candidate)
	candidate.configure(world_identity(context))
	# Install the whole batch before binding environment/directory publication.
	candidate.loader.set_process(false)
	for snapshot: Dictionary in report.records:
		var installed := candidate.upsert_record(snapshot)
		if not installed.ok:
			candidate.free()
			report=installed
			return report
	_directory=directory
	for summary: Dictionary in report.summaries:
		var registered: bool = _directory.register_custom_summary(summary,self)
		if not registered:
			_unregister_directory()
			candidate.free()
			report=_failure("directory_conflict","The passive port directory changed during import.")
			return report
		_published_ids.append(str(summary.id))
	streamer=candidate
	streamer.operator_selected.connect(_on_operator_selected)
	streamer.bind_environment(terrain,forest)
	streamer.loader.set_process(true)
	report.code="imported"
	return report


func _on_operator_selected(_port_id: String, _placement_id: String) -> void:
	GameMenu.notify("This imported harbour is read-only. Cargo and docking services are not connected yet.")


func _unregister_directory() -> void:
	if is_instance_valid(_directory):
		for id in _published_ids:_directory.unregister_custom_summary(id,self)
	_published_ids.clear()


func _exit_tree() -> void:
	_unregister_directory()


static func _polygon_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index in polygon.size():twice_area+=polygon[index].cross(polygon[(index+1)%polygon.size()])
	return absf(twice_area)*.5


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":code,"errors":[message]}
