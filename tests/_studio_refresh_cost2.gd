extends Node3D

## SCRATCH PROBE. `_refresh_panel` and `_rebake` only, so it runs against the
## pristine studio as well as the checklist one.

const REPS := 200


func _ready() -> void:
	var studio: Node = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(studio)
	await get_tree().process_frame
	studio.call("_place_deck", Vector3(1, 0, 8), Vector3(9, 0, 24))
	await get_tree().process_frame
	var refresh := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		studio.call("_refresh_panel")
		refresh += Time.get_ticks_usec() - t0
	var rebake := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		studio.call("_rebake")
		rebake += Time.get_ticks_usec() - t0
	print("REFRESH %7.3f ms   REBAKE %7.3f ms   (entities=%d reps=%d)" % [
		float(refresh) / float(REPS) / 1000.0,
		float(rebake) / float(REPS) / 1000.0,
		(studio.get("_plan")).entity_count(), REPS
	])
	get_tree().quit(0)
