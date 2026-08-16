extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_sealed_room_probe.gd
##
## QUESTION: does ANYTHING in the pipeline notice a room with no way into it?
## Walks every shipped structure_plan_v1 fixture through PlanOutfit.enclosure and
## PlanOutfit.validate and prints, per fixture: door count, enclosure verdict,
## sealed area, whether validate produced an ERROR or a WARNING, and what the
## capability dictionary publishes. Then asks the compliance/registration layer
## whether any licence rule in the shipped catalogue names has_cabin at all.

const PO := preload("res://scripts/ship/plan_outfit.gd")
const DIR := "res://resources/data/structures/"


func _initialize() -> void:
	print("== per-fixture enclosure + validate ==")
	var dir := DirAccess.open(DIR)
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for name in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + name))
		if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
			print("  %-32s NOT A PLAN" % name)
			continue
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		var stem := name.trim_suffix(".json")
		var report := PO.enclosure(plan)
		var result := PO.validate(plan, plan.hull_id)
		var caps: Dictionary = result["capabilities"]
		var errors: Array = result.get("errors", [])
		var warnings: Array = result.get("warnings", [])
		print("  %-30s doors=%d cabin=%s cabins=%d area=%7.1f  ok=%s errors=%d warnings=%d"
			% [stem, PO.door_count(plan), str(bool(report["cabin"])),
				int(report["cabins"]), float(report["area_m2"]),
				str(bool(result.get("ok", false))), errors.size(), warnings.size()])
		print("      why: %s" % str(report["why"]))
		print("      caps: has_cabin=%s cabins=%d cabin_area_m2=%.1f doors=%d windows=%d"
			% [str(caps.get("has_cabin", false)), int(caps.get("cabins", 0)),
				float(caps.get("cabin_area_m2", 0.0)), int(caps.get("doors", 0)),
				int(caps.get("windows", 0))])
		for e in errors:
			print("      ERROR: %s" % str(e))
		for w in warnings:
			print("      WARN : %s" % str(w))

	print("\n== does any shipped licence rule name has_cabin? ==")
	_scan_catalogue()
	quit()


func _scan_catalogue() -> void:
	_walk("res://resources/data/")


func _walk(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string(path + f)
		if text.contains("has_cabin"):
			print("  NAMES has_cabin: %s%s" % [path, f])
			for line in text.split("\n"):
				if line.contains("has_cabin"):
					print("      %s" % line.strip_edges())
	for d in dir.get_directories():
		_walk(path + d + "/")
