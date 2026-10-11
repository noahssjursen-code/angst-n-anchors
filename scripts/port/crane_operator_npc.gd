class_name CraneOperatorNpc
extends NpcInteractable

## Walk-up harbour equipment operator. Jobs go only through HarbourController.
## Each NPC is bound to one crane (`equip_id`) — out-of-reach tools stay unavailable.


@export var harbour_port_id := ""
@export var berth_id := ""
@export var equip_id := ""
@export var operator_role := "crane operator"

var _harbour: HarbourController


func configure(harbour: HarbourController, berth: String, equipment: String = "") -> void:
	_harbour = harbour
	if harbour != null:
		harbour_port_id = harbour.port_id()
	berth_id = berth.strip_edges()
	equip_id = equipment.strip_edges()


func _harbour_controller() -> HarbourController:
	if _harbour != null and is_instance_valid(_harbour):
		return _harbour
	if not harbour_port_id.is_empty():
		_harbour = HarbourRegistry.controller(harbour_port_id)
	return _harbour


func _this_equipment(hc: HarbourController) -> QuayEquipmentJob:
	if hc == null:
		return null
	if not equip_id.is_empty():
		return hc.get_equipment(equip_id)
	return hc.primary_equipment(berth_id)


func _on_request_load() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	var ship := hc.moored_ship(berth_id)
	var equip := _this_equipment(hc)
	if ship == null or equip == null:
		return
	hc.plug_equipment(equip.equipment_id(), ship, QuayEquipmentJob.MODE_LOAD)


func _on_request_unload() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	var ship := hc.moored_ship(berth_id)
	var equip := _this_equipment(hc)
	if ship == null or equip == null:
		return
	hc.plug_equipment(equip.equipment_id(), ship, QuayEquipmentJob.MODE_UNLOAD)


func _on_request_stop() -> void:
	var hc := _harbour_controller()
	if hc == null:
		return
	if not equip_id.is_empty():
		hc.stop_equipment(equip_id)
	else:
		hc.stop_berth_equipment(berth_id)
