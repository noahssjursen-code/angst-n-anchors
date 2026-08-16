extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). SCENE LANE:
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_sealed_advice_probe.tscn
##
## Does the studio's capability panel actually SAY anything about a room with no
## way into it? `_capability_advice("has_cabin")` is the only sentence in the app
## that names the case. It reads `_compliance["capabilities"]`, so this feeds it
## the real capabilities dictionary that `PlanOutfit.validate` produces for the
## shipped fixtures and prints what comes back. Scene lane because
## structure_studio.gd names autoload globals at compile time.

const PO := preload("res://scripts/ship/plan_outfit.gd")
const StudioScript := preload("res://scripts/apps/structure_studio.gd")


func _ready() -> void:
	for stem in ["critic_barge", "critic_ferry", "probe_piece_house"]:
		var path := "res://resources/data/structures/%s.json" % stem
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		var result := PO.validate(plan, plan.hull_id)
		var caps: Dictionary = result["capabilities"]
		var studio: Node = StudioScript.new()
		studio.set("_compliance", {"capabilities": caps})
		var advice: String = studio.call("_capability_advice", "has_cabin")
		print("== %s" % stem)
		print("   has_cabin=%s  cabin_area_m2=%.1f  doors=%d  validate.ok=%s errors=%d warnings=%d"
			% [str(caps.get("has_cabin", false)), float(caps.get("cabin_area_m2", 0.0)),
				int(caps.get("doors", 0)), str(bool(result.get("ok", false))),
				(result.get("errors", []) as Array).size(),
				(result.get("warnings", []) as Array).size()])
		print("   advice: %s" % advice)
		studio.free()
	get_tree().quit()
