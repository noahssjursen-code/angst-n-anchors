extends "res://tests/vessel_render_capture.gd"

## Lane B. Photographs the PIECE-BUILT vessels from the canonical angles, so they
## can be laid beside the hand-authored one and judged by a person.
##
##   xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/piece_kit_capture.tscn -- [stem ...]
##
## A SUBCLASS for the same reason `trawler_render_capture.gd` is one: the parent
## belongs to other agents this wave and two agents editing one GDScript clobber
## each other (CONVENTIONS §5). The 35 degree lens, the four canonical angles,
## the stable file names, the 1.8 m figure, the draw-call counter read off
## RenderingServer and every edge / rigging / fall-protection claim are inherited
## unchanged, so these PNGs diff against the rest of the fleet's.
##
## ── The one thing this rig does that the parent cannot ──────────────────────
##
## Its fixtures carry a `pieces[]` array and NOT plate corners. `PieceKit`
## resolves them into `items[]` before the plan is ever built, and the resolved
## copy is written to `user://` — never into the repo. That is the whole point:
## THE FIXTURE ON DISK CONTAINS NO GEOMETRY. If the resolver were wrong, or
## quietly dropped a piece, there would be nothing to photograph.
##
## Two inherited claims are restated rather than relaxed:
##
##  - `_check_fittings` learns the `plate` primitive. The parent counts anything
##    that is not a spar or a wire as MUTE, which was right when no fixture in
##    its list carried a plate. The restatement is STRICTLY STRONGER for plates:
##    one is only counted as drawn when `plate_problem` clears it, where a tube
##    only has to have two path points. Identical in substance to the override
##    `trawler_render_capture.gd` already carries.
##  - `_check_cost` carries these fixtures' own numbers, because `COST_BUDGET` is
##    a `const` and GDScript will not let a subclass shadow one. The DRAW-CALL
##    number is the assertion that matters, and the claim being made is that
##    BUILDING FROM PIECES COSTS NOTHING AT THE DRAW CALL: 50 placements, six
##    piece types and eight colours all bucket on MATERIAL alone.

const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const RESOLVED_DIR := "user://piece_kit"

const FIXTURES_HERE: Array[String] = [
	## The comparison. Same hull, same bulwark, same rig, same bow, same gallows
	## as probe_trawler_bulwark — and a deckhouse with no authored corners in it.
	"res://resources/data/structures/probe_piece_trawler.json",
	## The strict one: not a single hand-authored plate corner in the file.
	"res://resources/data/structures/probe_piece_house.json",
]

## Measured on the first clean run, then given ~8% headroom on triangles. Draw
## calls are exact and are the load-bearing half.
const PIECE_BUDGET := {
	## probe_trawler_bulwark, the hand-authored vessel this one replaces the
	## deckhouse of, is budgeted at 8 draw calls. The piece-built version draws
	## THE SAME 8: 43 placements, six piece types and eight colours all bucket on
	## MATERIAL alone, and building from a kit costs nothing at the draw call.
	"probe_piece_trawler": {"draw_calls": 8, "triangles": 33000},
	## The bare hull plus a bulwark loop measures 6 (probe_sheer_bulwark); the
	## whole piece-built superstructure adds ONE.
	"probe_piece_house": {"draw_calls": 7, "triangles": 21000},
}

var _resolved_report: Dictionary = {}


func _run() -> void:
	_t = TestReport.new("piece_kit_capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESOLVED_DIR))
	_hide_autoload_ui()
	var wanted := _requested_stems()
	var ran := 0
	for fixture in FIXTURES_HERE:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		var resolved_path := _resolve_to_user(fixture, stem)
		if resolved_path.is_empty():
			continue
		await _capture_plan(resolved_path, stem)
		ran += 1
	if ran == 0:
		_t.fail("no fixture matched %s" % [wanted])
	_t.finish(get_tree())


## pieces[] -> items[], written to user://. Returns the path to feed the parent,
## or "" when the fixture could not be resolved — in which case the failure is
## recorded and nothing is photographed, rather than a half-built vessel being
## quietly shot and passed off as the kit's work.
func _resolve_to_user(path: String, stem: String) -> String:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		_t.fail("%s: fixture is not a JSON object" % stem)
		return ""
	var doc := raw as Dictionary
	var authored := PieceKitScript.authored_plate_count(doc)
	var placements := (doc.get("pieces", []) as Array).size() if doc.get("pieces") is Array else 0
	_t.check("%s: the fixture carries %d piece placements" % [stem, placements], placements > 0)

	var result := PieceKitScript.resolve_document(doc)
	for message in result["errors"] as PackedStringArray:
		_t.fail("%s: %s" % [stem, message])
	_t.check(
		"%s: %d placements resolve with no errors" % [stem, int(result["placed"])],
		(result["errors"] as PackedStringArray).is_empty()
	)
	_t.check(
		"%s: they become %d plate items" % [stem, int(result["items"])],
		int(result["items"]) > 0
	)
	## Stated out loud on every run, because it is the claim of the whole wave and
	## it is the one that decays silently if somebody pastes a quad back in.
	print("  [pieces] %s  placements=%d -> plates=%d  hand-authored plates still in the file=%d"
		% [stem, int(result["placed"]), int(result["items"]), authored])
	_resolved_report[stem] = {
		"placed": int(result["placed"]), "made": int(result["items"]), "authored": authored,
	}
	if stem == "probe_piece_house":
		_t.equal("%s: ZERO hand-authored plate corners in the file" % stem, authored, 0)

	var out_path := "%s/%s.json" % [RESOLVED_DIR, stem]
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		_t.fail("%s: cannot write %s" % [stem, out_path])
		return ""
	file.store_string(JSON.stringify(result["doc"], "\t"))
	file.close()
	return out_path


## The parent counts anything that is not a spar or a wire as MUTE. Restated over
## all three primitives; a plate is only counted as drawn when the baker's own
## `plate_problem` clears it, which is stricter than the two-point test tubes get.
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
	if not PIECE_BUDGET.has(stem):
		super._check_cost(stem, meshes)
		return
	var budget := PIECE_BUDGET[stem] as Dictionary
	## x2 on both: the sun casts, and a shadow pass issues its own draw calls over
	## the same surfaces and counts every triangle a second time.
	var calls := int(budget["draw_calls"]) * 2
	_t.check(
		"%s: %d draw calls against the %d a piece-built vessel is allowed"
		% [stem, _draw_calls, calls],
		_draw_calls <= calls
	)
	var tris := int(budget["triangles"]) * 2
	_t.check("%s: %d triangles, budget %d" % [stem, _primitives, tris], _primitives <= tris)
	print("  [cost] %s  bake surfaces=%d (bounded by MATERIALS, not asserted)" % [stem, meshes])
