class_name QuayEquipmentJob
extends Node

## Harbour equipment that can plug into a moored ship (all crane / tool kinds).
## HarbourController is the only caller of start_job / stop_job.

const MODE_LOAD := "load"
const MODE_UNLOAD := "unload"

signal job_started(context: Dictionary)
signal job_completed(context: Dictionary, report: Dictionary)
signal job_stopped(context: Dictionary)
## Presentation changes within a running job (phase, progress, failure reason).
signal status_changed()

var _equipment_id := ""
var _equipment_kind := ""
var _berth_id := ""
var _served_ship: BoatBody = null
var _job_mode := ""
var _commodity_id := ""
var _authority_context: Dictionary = {}


func setup(equip_id: String, kind: String, berth_id: String) -> void:
	_equipment_id = equip_id.strip_edges()
	_equipment_kind = kind.strip_edges()
	_berth_id = berth_id.strip_edges()
	name = _equipment_id.get_file() if not _equipment_id.is_empty() else "EquipmentJob"


func equipment_id() -> String:
	return _equipment_id


func equipment_kind() -> String:
	return _equipment_kind


func berth_id() -> String:
	return _berth_id


func served_ship() -> BoatBody:
	return _served_ship if is_instance_valid(_served_ship) else null


func job_mode() -> String:
	return _job_mode


func commodity_id() -> String:
	return _commodity_id


func operation_id() -> String:
	return str(_authority_context.get("operation_id", ""))


func authority_context() -> Dictionary:
	return _authority_context.duplicate(true)


func is_job_active() -> bool:
	return served_ship() != null and not _job_mode.is_empty()


func can_serve(_ship: BoatBody, _mode: String) -> bool:
	return false


## Spatial compatibility used before freight is staged. Equipment subclasses
## must verify their real reach rather than assuming every yard on a berth works.
func can_reach_yard(_yard: Node) -> bool:
	return false


func start_job(ship: BoatBody, mode: String, commodity_id: String = "", context: Dictionary = {}) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var m := mode.strip_edges().to_lower()
	if m != MODE_LOAD and m != MODE_UNLOAD:
		return false
	if not can_serve(ship, m):
		return false
	## Publish the complete job identity before equipment starts. Some adapters
	## can complete synchronously (or emit callbacks from their first update), so
	## assigning this afterwards loses the authoritative operation id.
	_served_ship = ship
	_job_mode = m
	_commodity_id = commodity_id.strip_edges()
	_authority_context = context.duplicate(true)
	if not _begin_job(ship, m, commodity_id.strip_edges()):
		_clear_job_state()
		return false
	if is_job_active():
		job_started.emit(_job_snapshot())
	return true


func stop_job() -> void:
	if not is_job_active():
		return
	var context := _job_snapshot()
	_end_job()
	## Some equipment emits its own stopped callback synchronously from _end_job.
	## Only publish once if that callback has not already cleared the job.
	if not is_job_active():
		return
	_clear_job_state()
	job_stopped.emit(context)


func notify_job_completed(report: Dictionary = {}) -> void:
	if not is_job_active():
		return
	var context := _job_snapshot()
	_clear_job_state()
	job_completed.emit(context, report.duplicate(true))


func notify_job_stopped() -> void:
	if not is_job_active():
		return
	var context := _job_snapshot()
	_clear_job_state()
	job_stopped.emit(context)


func _clear_job_state() -> void:
	_served_ship = null
	_job_mode = ""
	_commodity_id = ""
	_authority_context.clear()


func _job_snapshot() -> Dictionary:
	var context := _authority_context.duplicate(true)
	context["equipment_id"] = _equipment_id
	context["berth_id"] = _berth_id
	context["mode"] = _job_mode
	context["commodity_id"] = _commodity_id
	context["vessel_id"] = HarbourController.ship_id_of(served_ship())
	return context


func status_lines() -> PackedStringArray:
	var ship := served_ship()
	var ship_label := "—"
	if ship != null:
		var named := str(ship.get_meta("network_ship_id", ""))
		ship_label = named if not named.is_empty() else ship.name
	return PackedStringArray([
		"Equip  %s" % _equipment_kind,
		"Berth  %s" % _berth_id,
		"Job    %s" % (_job_mode if not _job_mode.is_empty() else "idle"),
		"Ship   %s" % ship_label,
	])


func _begin_job(_ship: BoatBody, _mode: String, _commodity_id: String) -> bool:
	return false


func _end_job() -> void:
	pass
