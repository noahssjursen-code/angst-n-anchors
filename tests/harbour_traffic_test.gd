extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var harbour := HarbourController.new()
	harbour.setup("port-test")
	root.add_child(harbour)
	var first := _slot("port-test/a", "a")
	var second := _slot("port-test/b", "b")
	harbour.add_child(first)
	harbour.add_child(second)
	harbour.register_berth(first)
	harbour.register_berth(second)

	var a := harbour.request_berth_reservation("npc-a", 20.0, "general")
	var b := harbour.request_berth_reservation("npc-b", 20.0, "general")
	var c := harbour.request_berth_reservation("npc-c", 20.0, "general")
	_check(not a.is_empty(), "first NPC receives berth")
	_check(not b.is_empty() and b != a, "second NPC receives different berth")
	_check(c.is_empty(), "third NPC waits when harbour is reserved")
	_check(harbour.request_lane_lock(a, "npc-a", "departure"), "reservation owner locks lane")
	_check(not harbour.request_lane_lock(b, "npc-b", "approach"), "second manoeuvre waits for lane")
	_check(harbour.release_lane_lock("npc-a"), "lane owner releases lock")
	_check(harbour.request_lane_lock(b, "npc-b", "approach"), "waiting manoeuvre acquires released lane")
	_check(not harbour.release_berth_reservation(a, "npc-b"), "foreign reservation cannot release")
	_check(harbour.release_berth_reservation(a, "npc-a"), "reservation owner releases berth")
	_finish()


func _slot(id: String, station: String) -> QuayBerthSlot:
	var slot := QuayBerthSlot.new()
	slot.setup(id, station, "general", PackedStringArray(["general_cargo"]), 80.0, 18.0)
	return slot


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("Harbour traffic tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Harbour traffic test: " + failure)
	quit(1)
