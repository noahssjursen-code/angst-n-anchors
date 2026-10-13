extends Node

const Assembly = preload("res://scripts/network/authority_vessel_assembly.gd")
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("_run")

func _run() -> void:
	var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/showcases/authority_builds.json"))
	for stock_id: String in builds:
		var build: Dictionary = builds[stock_id]
		var view := {"id": "replica-" + stock_id, "name": stock_id, "construction_id": build.id, "cargo": []}
		var boat := Assembly.instantiate(view, build)
		check(boat != null, "Construction reconstructs: " + stock_id)
		if boat == null: continue
		boat.freeze = true
		add_child(boat)
		boat.process_mode = Node.PROCESS_MODE_DISABLED
		var pads := boat.get_cargo_pads()
		check(pads.size() == build.cargo_slots.size(), "Authority/runtime capacity agrees: " + stock_id)
		for slot: Dictionary in build.cargo_slots:
			var found := false
			for pad in pads:
				if str(pad.get_meta("authority_slot_id", "")) != str(slot.id): continue
				found = true
				var p: Array = slot.local_position
				check(boat.to_local(pad.global_position).distance_to(Vector3(p[0], p[1], p[2])) < 0.002, "Server CargoDatum matches the authored model")
			check(found, "Stable cargo slot identity survives assembly")
			view.cargo.append({"id": "container-" + str(slot.id), "slot_id": slot.id, "container_type": slot.container_type, "paint_variant": 3, "mass_kg": 8000})
		check(Assembly.apply_contents(boat, view, build).is_empty(), "Hydrates cargo from data only")
		check(Assembly.apply_contents(boat, view, build).is_empty(), "Repeated snapshot is idempotent")
		for pad in pads:
			check(pad.get_containers().size() == 1, "One container per slot")
			check(pad.get_containers()[0].paint_variant == 3, "Container paint restored")
		view.cargo = []
		check(Assembly.apply_contents(boat, view, build).is_empty(), "Unloaded snapshot removes cargo")
		for pad in pads: check(pad.get_containers().is_empty(), "No stale cargo remains")
		boat.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	if not failed: print("AUTHORITY VESSEL ASSEMBLY PASS: five real builds, capacity parity, CargoDatum positions, stable slot IDs, cargo identities, paint, repeat hydration and unloading")
	get_tree().quit(1 if failed else 0)
