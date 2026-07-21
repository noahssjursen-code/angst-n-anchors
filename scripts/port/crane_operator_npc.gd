class_name CraneOperatorNpc
extends NpcInteractable

## Walk-up harbour equipment operator. Jobs go only through HarbourController.
## Each NPC is bound to one crane (`equip_id`) — out-of-reach tools stay unavailable.

const PANEL_SCRIPT := preload("res://scripts/port/crane_operator_panel.gd")

@export var harbour_port_id := ""
@export var berth_id := ""
@export var equip_id := ""
@export var operator_role := "crane operator"

var _harbour: HarbourController
var _panel: Control
var _panel_layer: CanvasLayer


func configure(harbour: HarbourController, berth: String, equipment: String = "") -> void:
	_unbind_harbour_signals()
	_harbour = harbour
	if harbour != null:
		harbour_port_id = harbour.port_id()
	berth_id = berth.strip_edges()
	equip_id = equipment.strip_edges()
	_bind_harbour_signals()
	_update_prompt()


func _ready() -> void:
	super._ready()
	_update_prompt()
	if not Engine.is_editor_hint():
		_build_panel()


func _build_panel() -> void:
	_panel_layer = CanvasLayer.new()
	_panel_layer.name = "OperatorPanelLayer"
	_panel_layer.layer = 20
	add_child(_panel_layer)
	_panel = PANEL_SCRIPT.new() as Control
	_panel.name = "OperatorPanel"
	_panel.visible = false
	_panel.request_load.connect(_on_request_load)
	_panel.request_unload.connect(_on_request_unload)
	_panel.request_stop.connect(_on_request_stop)
	_panel.request_close.connect(_on_ui_cancel)
	_panel_layer.add_child(_panel)
	_panel.set_title(operator_role)


func _on_interact() -> void:
	_refresh_panel()
	open_ui()
	if _panel != null:
		_panel.visible = true


func _on_ui_cancel() -> void:
	if _panel != null:
		_panel.visible = false
	close_ui()


func _harbour_controller() -> HarbourController:
	if _harbour != null and is_instance_valid(_harbour):
		return _harbour
	if not harbour_port_id.is_empty():
		_harbour = HarbourRegistry.controller(harbour_port_id)
	return _harbour


func _bind_harbour_signals() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	if not hc.ship_plugged.is_connected(_on_harbour_changed):
		hc.ship_plugged.connect(_on_harbour_changed)
	if not hc.ship_unplugged.is_connected(_on_harbour_changed):
		hc.ship_unplugged.connect(_on_harbour_changed)


func _unbind_harbour_signals() -> void:
	if _harbour == null or not is_instance_valid(_harbour):
		return
	if _harbour.ship_plugged.is_connected(_on_harbour_changed):
		_harbour.ship_plugged.disconnect(_on_harbour_changed)
	if _harbour.ship_unplugged.is_connected(_on_harbour_changed):
		_harbour.ship_unplugged.disconnect(_on_harbour_changed)


func _on_harbour_changed(_berth_id: String = "", _ship: BoatBody = null) -> void:
	_update_prompt()
	if _panel != null and _panel.visible:
		_refresh_panel()


func _this_equipment(hc: HarbourController) -> QuayEquipmentJob:
	if hc == null:
		return null
	if not equip_id.is_empty():
		return hc.get_equipment(equip_id)
	return hc.primary_equipment(berth_id)


func _update_prompt() -> void:
	var hc := _harbour_controller()
	var ship: BoatBody = null
	var equip: QuayEquipmentJob = null
	if hc != null:
		ship = hc.moored_ship(berth_id)
		equip = _this_equipment(hc)
	if ship == null or equip == null:
		prompt_text = "Talk to %s" % operator_role
		return
	var reach_ok := true
	if equip.has_method("can_reach_ship"):
		reach_ok = bool(equip.call("can_reach_ship", ship))
	var available := (
		equip.can_serve(ship, QuayEquipmentJob.MODE_LOAD)
		or equip.can_serve(ship, QuayEquipmentJob.MODE_UNLOAD)
	)
	if available:
		prompt_text = "Talk to %s (available)" % operator_role
	elif not reach_ok:
		prompt_text = "Talk to %s (out of reach)" % operator_role
	else:
		prompt_text = "Talk to %s" % operator_role


func _refresh_panel() -> void:
	if _panel == null:
		return
	_update_prompt()
	var hc := _harbour_controller()
	var ship: BoatBody = null
	var job_line := "idle"
	var can_load := false
	var can_unload := false
	var hint := ""
	var equip: QuayEquipmentJob = null
	if hc != null:
		ship = hc.moored_ship(berth_id)
		equip = _this_equipment(hc)
		if equip != null and equip.is_job_active():
			job_line = "%s · %s" % [equip.job_mode(), HarbourController.ship_id_of(equip.served_ship())]
		if ship == null:
			hint = "No ship plugged at this berth"
		elif equip == null:
			hint = "No equipment on this berth"
		else:
			can_load = equip.can_serve(ship, QuayEquipmentJob.MODE_LOAD)
			can_unload = equip.can_serve(ship, QuayEquipmentJob.MODE_UNLOAD)
			if equip.is_job_active():
				hint = ""
			elif not can_load and not can_unload:
				if equip.has_method("serve_hint"):
					hint = str(equip.call("serve_hint", ship, QuayEquipmentJob.MODE_LOAD))
					if hint.is_empty():
						hint = str(equip.call("serve_hint", ship, QuayEquipmentJob.MODE_UNLOAD))
				if hint.is_empty():
					hint = "Cannot start a job"
			elif not can_load and equip.has_method("serve_hint"):
				hint = str(equip.call("serve_hint", ship, QuayEquipmentJob.MODE_LOAD))
			elif not can_unload and equip.has_method("serve_hint"):
				hint = str(equip.call("serve_hint", ship, QuayEquipmentJob.MODE_UNLOAD))
	_panel.set_status(
		berth_id,
		HarbourController.ship_id_of(ship) if ship != null else "— none —",
		job_line,
		ship != null,
		can_load,
		can_unload,
		hint,
	)


func _on_request_load() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	var ship := hc.moored_ship(berth_id)
	var equip := _this_equipment(hc)
	if ship == null or equip == null:
		_refresh_panel()
		return
	hc.plug_equipment(equip.equipment_id(), ship, QuayEquipmentJob.MODE_LOAD)
	_refresh_panel()


func _on_request_unload() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	var ship := hc.moored_ship(berth_id)
	var equip := _this_equipment(hc)
	if ship == null or equip == null:
		_refresh_panel()
		return
	hc.plug_equipment(equip.equipment_id(), ship, QuayEquipmentJob.MODE_UNLOAD)
	_refresh_panel()


func _on_request_stop() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	if not equip_id.is_empty():
		hc.stop_equipment(equip_id)
	else:
		hc.stop_berth_equipment(berth_id)
	_refresh_panel()
