class_name HarbourRegistry
extends Object

## Process-wide `port_id → HarbourController` lookup.

static var _by_port: Dictionary = {}


static func register(controller: HarbourController) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var pid := controller.port_id()
	if pid.is_empty():
		push_warning("HarbourRegistry: refuse register with empty port_id")
		return
	var existing := _live_controller(_by_port.get(pid))
	if existing != null and existing != controller:
		push_warning("HarbourRegistry: replacing controller for %s" % pid)
	_by_port[pid] = controller


static func unregister(port_id: String) -> void:
	var pid := port_id.strip_edges()
	if pid.is_empty():
		return
	_by_port.erase(pid)


static func unregister_controller(controller: HarbourController) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var pid := controller.port_id()
	if _by_port.get(pid) == controller:
		_by_port.erase(pid)


static func controller(port_id: String) -> HarbourController:
	var pid := port_id.strip_edges()
	var live := _live_controller(_by_port.get(pid))
	if live == null:
		_by_port.erase(pid)
	return live


static func _live_controller(value: Variant) -> HarbourController:
	# Casting a previously freed Object is itself an engine error in GDScript.
	# Streaming may free a port between registry publication and an NPC tick, so
	# validity must be established before the typed cast.
	if value == null or not is_instance_valid(value):
		return null
	return value as HarbourController


static func snapshot(port_id: String) -> Dictionary:
	var hc := controller(port_id)
	if hc == null:
		return {"port_id": port_id.strip_edges(), "berths": [], "ships": [], "equipment": [], "jobs": []}
	return hc.snapshot()


static func all_port_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key in _by_port.keys():
		if _live_controller(_by_port.get(key)) == null:
			_by_port.erase(key)
			continue
		ids.append(str(key))
	ids.sort()
	return ids


static func clear_all() -> void:
	_by_port.clear()
