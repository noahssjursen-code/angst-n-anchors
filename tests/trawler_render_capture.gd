extends "res://tests/vessel_render_capture.gd"

## Lane B. Photographs the two rebuilt trawler fixtures from the canonical angles.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/trawler_render_capture.tscn -- [stem ...]
##
## A SUBCLASS of the vessel capture, for the same reason `structure_plate_capture.gd`
## is one: `vessel_render_capture.gd` belongs to another agent this wave and two
## agents editing one GDScript clobber each other (CONVENTIONS §5). Everything
## that makes a capture comparable — the 35° lens, the four canonical angles, the
## stable file names, the 1.8 m figure, the draw-call counter read off
## RenderingServer, the edge/rigging/collider claims — is inherited unchanged, so
## these PNGs sit beside the other fixtures' and diff against them.
##
## Two overrides, both narrow, and NEITHER of them weakens a claim:
##
##  - `_check_fittings` learns the `plate` primitive. The inherited version counts
##    anything that is not a spar or a wire as MUTE and fails, which was correct
##    when no fixture in its list carried a plate and is wrong now that these two
##    are built out of twenty-three of them. Restated over all three primitives,
##    and a plate is only counted as drawn when `plate_problem` clears it — which
##    is STRICTLY STRONGER than the path-length test the tubes get. Identical in
##    substance to the override `structure_plate_capture.gd` already carries.
##
##  - `_check_cost` carries the rebuilt fixtures' own numbers. The parent's
##    COST_BUDGET is a `const` and GDScript will not let a subclass shadow one, so
##    the budget is restated here rather than relaxed there. The DRAW-CALL number
##    is the assertion that matters and it is UNCHANGED at 8 undressed / 16 with
##    the shadow pass: a deckhouse, a swept bulwark and a hundred colours of paint
##    all bucket on material alone. Triangles went 19 942 -> the number below,
##    because geometry is what a sheer curve and a raked deckhouse actually cost.
##
## When the plate primitive lands in the main capture and its budget is refreshed,
## this file's whole reason to exist goes with it: delete it.

const FIXTURES_HERE: Array[String] = [
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
]

## Same shape as the parent's COST_BUDGET, restated because a const cannot be
## shadowed. Draw calls are the load-bearing half: put one fitting in a fifth
## material and this goes red by exactly one.
const REBUILT_BUDGET := {
	"probe_trawler_bulwark": {"draw_calls": 8, "triangles": 16800},
	"probe_trawler_bow_bulwark": {"draw_calls": 8, "triangles": 17200},
}


func _run() -> void:
	_t = TestReport.new("trawler_render_capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_autoload_ui()
	var wanted := _requested_stems()
	var ran := 0
	for fixture in FIXTURES_HERE:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		await _capture_plan(fixture, stem)
		ran += 1
	if ran == 0:
		_t.fail("no fixture matched %s" % [wanted])
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
		match StructureBaker.item_primitive(item):
			"plate":
				plates += 1
				var problem := StructureBaker.plate_problem(StructurePlan.item_props(item))
				if problem.is_empty():
					drawable += 1
				else:
					mute += 1
					if first_problem.is_empty():
						first_problem = "item %d: %s" % [int(item.get("id", -1)), problem]
			"spar", "wire":
				if StructureBaker.spar_path(StructurePlan.item_props(item)).size() >= 2:
					drawable += 1
				else:
					mute += 1
					if first_problem.is_empty():
						first_problem = "item %d: fewer than 2 path points" % int(item.get("id", -1))
			_:
				mute += 1
				if first_problem.is_empty():
					first_problem = "item %d: unknown primitive" % int(item.get("id", -1))
	_t.check(
		"%s: all %d fittings draw — %d plates, %d mute (%s)" % [
			stem, plan.items.size(), plates, mute,
			"none" if first_problem.is_empty() else first_problem,
		],
		mute == 0 and drawable == plan.items.size()
	)


func _check_cost(stem: String, meshes: int) -> void:
	if not REBUILT_BUDGET.has(stem):
		super._check_cost(stem, meshes)
		return
	var budget := REBUILT_BUDGET[stem] as Dictionary
	## x2 on both: the sun casts, and a shadow pass issues its own draw calls over
	## the same surfaces and counts every triangle a second time.
	var calls := int(budget["draw_calls"]) * 2
	_t.check(
		"%s: %d draw calls against the %d it drew undressed" % [stem, _draw_calls, calls],
		_draw_calls <= calls
	)
	var tris := int(budget["triangles"]) * 2
	_t.check("%s: %d triangles, budget %d" % [stem, _primitives, tris], _primitives <= tris)
	print("  [cost] %s  bake surfaces=%d (bounded by MATERIALS, not asserted)" % [stem, meshes])
