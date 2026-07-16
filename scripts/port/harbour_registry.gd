class_name HarbourRegistry
extends Object

## Process-wide `port_id → HarbourController` lookup.

static var _by_port: Dictionary = {}


static func register(controller: HarbourController) -> void:
	if controller == null:
		return
	var pid := controller.port_id()
	if pid.is_empty():
		push_warning("HarbourRegistry: refuse register with empty port_id")
		return
	var existing: HarbourController = _by_port.get(pid) as HarbourController
	if existing != null and existing != controller and is_instance_valid(existing):
		push_warning("HarbourRegistry: replacing controller for %s" % pid)
	_by_port[pid] = controller


static func unregister(port_id: String) -> void:
	var pid := port_id.strip_edges()
	if pid.is_empty():
		return
	_by_port.erase(pid)


static func unregister_controller(controller: HarbourController) -> void:
	if controller == null:
		return
	var pid := controller.port_id()
	if _by_port.get(pid) == controller:
		_by_port.erase(pid)


static func controller(port_id: String) -> HarbourController:
	return _by_port.get(port_id.strip_edges()) as HarbourController


static func snapshot(port_id: String) -> Dictionary:
	var hc := controller(port_id)
	if hc == null:
		return {"port_id": port_id.strip_edges(), "berths": [], "ships": [], "equipment": [], "jobs": []}
	return hc.snapshot()


static func all_port_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key in _by_port.keys():
		ids.append(str(key))
	ids.sort()
	return ids


static func clear_all() -> void:
	_by_port.clear()
