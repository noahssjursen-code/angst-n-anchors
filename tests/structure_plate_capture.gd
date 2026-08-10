extends "res://tests/vessel_render_capture.gd"

## Lane B. Photographs the sloped-plate deckhouse from the canonical angles.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/structure_plate_capture.tscn
##
## It is a SUBCLASS of the vessel capture rather than another entry in that
## file's FIXTURES list, for one reason and one reason only: `vessel_render_
## capture.gd` belongs to another agent this wave, and two agents editing one
## GDScript clobber each other (CONVENTIONS §5). Everything that makes a capture
## comparable — the 35 degree lens, the four canonical angles, the stable file
## names, the 1.8 m figure, the draw-call counter read off RenderingServer — is
## inherited unchanged, so these PNGs sit beside the other fixtures' and diff
## against them.
##
## Two overrides, both narrow:
##
##  - `_run` shoots one fixture instead of the list;
##  - `_check_fittings` learns the `plate` primitive. The inherited version
##    counts anything that is not a spar or a wire as MUTE and fails, which is
##    correct today and would fail this fixture's eighteen plates. It is not a
##    check worth losing, so it is re-stated here over all three primitives —
##    and a plate is only counted as drawn when `plate_problem` clears it, which
##    is strictly stronger than the path-length test the tubes get.
##
## When the plate primitive lands in the main capture, this file's whole reason
## to exist goes with it: delete it and add the fixture to FIXTURES.

const PLATE_FIXTURE := "res://resources/data/structures/probe_plate_deckhouse.json"


func _run() -> void:
	_t = TestReport.new("structure_plate_capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_autoload_ui()
	await _capture_plan(PLATE_FIXTURE, PLATE_FIXTURE.get_file().get_basename())
	_t.finish(get_tree())


func _check_fittings(plan: StructurePlan, stem: String) -> void:
	if plan.items.is_empty():
		return
	var drawable := 0
	var mute := 0
	var plates := 0
	var first_problem := ""
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var primitive := StructureBaker.item_primitive(item)
		match primitive:
			"plate":
				plates += 1
				var problem := StructureBaker.plate_problem(StructurePlan.item_props(item))
				if problem.is_empty():
					drawable += 1
				else:
					mute += 1
					if first_problem.is_empty():
						first_problem = "id %d: %s" % [int(item.get("id", -1)), problem]
			"spar", "wire":
				if StructureBaker.spar_path(StructurePlan.item_props(item)).size() >= 2:
					drawable += 1
				else:
					mute += 1
			_:
				mute += 1
	print("  [plates] %s: %d plates of %d fittings" % [stem, plates, plan.items.size()])
	_t.check(
		"%s: all %d fittings resolve to drawn geometry (%d mute%s)" % [
			stem, plan.items.size(), mute,
			"" if first_problem.is_empty() else ", first " + first_problem,
		],
		mute == 0 and drawable == plan.items.size()
	)
	_t.check("%s: the deckhouse is built from plates (%d)" % [stem, plates], plates >= 15)
