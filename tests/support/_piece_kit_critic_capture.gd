extends "res://tests/vessel_render_capture.gd"

## SCRATCH CAPTURE RIG — leading underscore, and it lives under tests/support/
## so tools/gate.sh (which globs tests/*.tscn for lane B) never picks it up.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/support/_piece_kit_critic_capture.tscn
##
## A subclass for the same reason piece_kit_capture.gd is one: the parent belongs
## to other agents this wave. Identical resolve-to-user:// step, so the fixtures
## on disk carry no geometry; identical lens, angles, lighting and 1.8 m figure,
## so these PNGs sit beside the shipped ones and can be compared by eye.

const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const RESOLVED_DIR := "user://piece_kit_critic"
const CRITIC_OUT := "res://screenshots/critic"

const FIXTURES_HERE: Array[String] = [
	"res://resources/data/structures/critic_barge.json",
	"res://resources/data/structures/critic_coaster.json",
	"res://resources/data/structures/critic_ferry.json",
	"res://resources/data/structures/critic_yacht.json",
]

## The parent's `FIGURE_SPOT` is a `const` and GDScript will not let a subclass
## extend one, so a fixture this file photographs and the parent has never heard
## of gets its spot here — the same arrangement `piece_kit_capture` uses, and the
## reason `_figure_spot` is a METHOD in the parent rather than a dictionary
## lookup at the call site.
##
## critic_coaster: the whole claim of that fixture is that the house is pulled in
## far enough to leave a SIDE DECK, so the figure stands on one. The house's port
## plating is at x = 2.00 and the deck edge at x = 0.00, so x = 1.00 is the
## middle of a 2.0 m side deck, 0.78 m clear of the plating at the figure's own
## 0.22 m radius; the eave over it stands out to x = 1.70 at y = 2.875, well over
## a 1.8 m head. z = 13.0 is amidships, beside the long saloon light, which is
## the picture that has to be true for the fixture to have made its point.
const CRITIC_FIGURE_SPOT := {
	"critic_coaster": Vector3(1.0, 0.0, 13.0),
}


func _run() -> void:
	_t = TestReport.new("piece_kit_critic_capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CRITIC_OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESOLVED_DIR))
	_hide_autoload_ui()
	var wanted := _requested_stems()
	for fixture in FIXTURES_HERE:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		var resolved := _resolve_to_user(fixture, stem)
		if resolved.is_empty():
			continue
		await _capture_plan(resolved, stem)
	_t.finish(get_tree())


func _resolve_to_user(path: String, stem: String) -> String:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		_t.fail("%s: not a JSON object" % stem)
		return ""
	var doc := raw as Dictionary
	var result := PieceKitScript.resolve_document(doc)
	for message in result["errors"] as PackedStringArray:
		_t.fail("%s: %s" % [stem, message])
	print("  [pieces] %s  placements=%d -> plates=%d  hand-authored=%d"
		% [stem, int(result["placed"]), int(result["items"]),
			PieceKitScript.authored_plate_count(doc)])
	var out_path := "%s/%s.json" % [RESOLVED_DIR, stem]
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		_t.fail("%s: cannot write %s" % [stem, out_path])
		return ""
	file.store_string(JSON.stringify(result["doc"], "\t"))
	file.close()
	return out_path


## Shots land in screenshots/critic/, not beside the shipped fixtures.
func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	await super._shoot(bounds, name, view)
	var src := "%s/%s.png" % [OUT_DIR, name]
	if FileAccess.file_exists(src):
		var img := Image.load_from_file(ProjectSettings.globalize_path(src))
		if img != null:
			img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [CRITIC_OUT, name]))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(src))


func _figure_spot(stem: String) -> Variant:
	if CRITIC_FIGURE_SPOT.has(stem):
		return CRITIC_FIGURE_SPOT[stem]
	return super._figure_spot(stem)


## The parent's plate accounting; these fixtures are all plates.
func _check_fittings(plan: StructurePlan, stem: String) -> void:
	if plan.items.is_empty():
		return
	var mute := 0
	var plates := 0
	var first := ""
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			mute += 1
			continue
		plates += 1
		var problem := StructureBaker.plate_problem(StructurePlan.item_props(item))
		if not problem.is_empty():
			mute += 1
			if first.is_empty():
				first = "item %d: %s" % [int(item.get("id", -1)), problem]
	_t.check("%s: %d plates, %d mute (%s)" % [stem, plates, mute, "none" if first.is_empty() else first],
		mute == 0)


## No budget for a critic fixture — the number is printed, not asserted.
func _check_cost(stem: String, meshes: int) -> void:
	print("  [cost] %s  draw_calls=%d triangles=%d surfaces=%d" % [stem, _draw_calls, _primitives, meshes])
