extends SceneTree

## SCRATCH PROBE (leading underscore -> skipped by tools/gate.sh discovery).
## Runs `PlanOutfit.enclosure` over every shipped fixture and over the synthetic
## cases the criterion is argued on, with timings. Prints numbers; asserts
## nothing — `tests/plan_enclosure_test.gd` is where the claims live.

const StructurePlanScript := preload("res://scripts/construction/structure_plan.gd")

const FIXTURES := "res://resources/data/structures/"


func _initialize() -> void:
	_synthetic()
	var dir := DirAccess.open(FIXTURES)
	if dir == null:
		quit(1)
		return
	var names := dir.get_files()
	names.sort()
	for name in names:
		if not name.ends_with(".json"):
			continue
		var doc := _load(name)
		if doc.is_empty() or not StructurePlanScript.is_plan(doc):
			continue
		var plan := StructurePlanScript.from_dict(doc)
		var t0 := Time.get_ticks_usec()
		var report := PlanOutfit.enclosure(plan)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		print("%-32s cabin=%-5s cabins=%d %8.1f ms   %s"
			% [name, str(bool(report["cabin"])), int(report["cabins"]), ms, str(report["why"])])
	quit(0)


func _synthetic() -> void:
	print("A fence, 8 walls in a ring + door, NO roof: ", _say(_fence()))
	var house := _fence()
	house.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	print("B the same ring WITH a roof:               ", _say(house))
	var gapped := _fence()
	gapped.walls.remove_at(3)
	gapped.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	print("C ring + roof, one side missing:           ", _say(gapped))
	print("D an empty plan:                           ", _say(StructurePlanScript.new()))
	var crate := _fence()
	(crate.walls[0]["openings"] as Array).clear()
	crate.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	print("E a sealed crate, no opening at all:       ", _say(crate))
	var low := _fence()
	low.add_deck(Vector3(1.0, 1.5, 6.0), Vector2(6.0, 6.0))
	print("F ring + roof, 1.5 m of headroom:          ", _say(low))
	for short_by in [3.5, 1.0, 0.5, 0.25]:
		var slot := _fence()
		(slot.walls[1] as Dictionary)["length"] = 6.0 - float(short_by)
		slot.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
		print("G a %.2f m hole in one wall:                " % float(short_by), _say(slot))
	## A box in the air: walls and roof at boat-deck level, no sole, nothing under.
	var floating := StructurePlanScript.new()
	floating.hull_id = "hull_28x10"
	var front := floating.add_wall(Vector3(1.0, 3.0, 6.0), "x", 6.0, 2.6)
	floating.add_wall(Vector3(1.0, 3.0, 12.0), "x", 6.0, 2.6)
	floating.add_wall(Vector3(1.0, 3.0, 6.0), "z", 6.0, 2.6)
	floating.add_wall(Vector3(7.0, 3.0, 6.0), "z", 6.0, 2.6)
	(front["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	floating.add_deck(Vector3(1.0, 5.6, 6.0), Vector2(6.0, 6.0))
	print("H a box 3 m in the air with no floor:      ", _say(floating))
	var floored := StructurePlanScript.from_dict(floating.to_dict())
	floored.add_deck(Vector3(1.0, 3.0, 6.0), Vector2(6.0, 6.0))
	print("I the same box with a sole under it:       ", _say(floored))


func _say(plan: StructurePlan) -> String:
	var report := PlanOutfit.enclosure(plan)
	return "cabin=%-5s cabins=%d  %s" % [
		str(bool(report["cabin"])), int(report["cabins"]), str(report["why"])
	]


## Eight walls in a ring with a door — four round a 6 x 6 m square and four in a
## line beside it, so the brick-era `wall_n >= 8` would also fire.
func _fence() -> StructurePlan:
	var plan := StructurePlanScript.new()
	plan.hull_id = "hull_28x10"
	var front := plan.add_wall(Vector3(1.0, 0.0, 6.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, 0.0, 12.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, 0.0, 6.0), "z", 6.0, 2.6)
	plan.add_wall(Vector3(7.0, 0.0, 6.0), "z", 6.0, 2.6)
	plan.add_wall(Vector3(9.0, 0.0, 6.0), "x", 2.0, 2.6)
	plan.add_wall(Vector3(9.0, 0.0, 8.0), "x", 2.0, 2.6)
	plan.add_wall(Vector3(9.0, 0.0, 10.0), "x", 2.0, 2.6)
	plan.add_wall(Vector3(9.0, 0.0, 12.0), "x", 2.0, 2.6)
	(front["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	return plan


func _load(name: String) -> Dictionary:
	var f := FileAccess.open(FIXTURES + name, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
