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
##    BUILDING FROM PIECES COSTS NOTHING AT THE DRAW CALL: every placement, every
##    piece type and every tint buckets on MATERIAL alone.
##  - `_add_scale_figure` and `_shoot` are overridden so the 1.8 m figure is
##    placed where it can be SEEN and then checked that it was — see the block
##    above `FIGURE_CHANGED_MIN`. That check found a shipped capture with no
##    visible figure in it.

const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const RESOLVED_DIR := "user://piece_kit"

const FIXTURES_HERE: Array[String] = [
	## The comparison. Same hull, same bulwark, same rig, same bow, same gallows
	## as probe_trawler_bulwark — and a deckhouse with no authored corners in it.
	"res://resources/data/structures/probe_piece_trawler.json",
	## The strict one: not a single hand-authored plate corner in the file.
	"res://resources/data/structures/probe_piece_house.json",
	## BUILT THROUGH THE STUDIO'S PIECE TOOL, not typed. A harbour tug's pilot
	## house: a plated casing with a raked front, a tall all-round-glazed
	## wheelhouse chamfered at every corner, a sloped VISOR over the windscreen
	## (`roof_slope`, which no vessel in this repo had used) and an exhaust casing
	## aft. `structure_studio.gd`'s own self-check replays the same 33 palette /
	## stepper / rotate / click actions and requires them to reproduce this file
	## placement for placement, so "built through the tool" is a checked claim.
	"res://resources/data/structures/probe_piece_tug.json",
]

## Where the 1.8 m figure stands for these fixtures.
##
## The parent's default (2.5, 0, 7.0) is a spot on the 28 m hulls' open foredeck,
## and it is fine for the trawler and the house — but the tug's casing runs from
## x = 2.5 m, so the default puts the figure INSIDE its port wall. That is the
## exact failure CONVENTIONS §3a records three variants of, so the spot is data
## here as it is upstream. `FIGURE_SPOT` is a `const` and GDScript will not let a
## subclass shadow one, hence the override below rather than a second entry.
const PIECE_FIGURE_SPOT := {
	## Centreline, 5 m from the stem: clear of the casing (which starts at z = 9 m)
	## and clear of the 5 m bow taper, with open sky behind it from every angle.
	##
	## Re-measured 2026-08-16 rather than taken on trust, because this entry was
	## being reported as DEFAULTED by a check reading the wrong table and nobody
	## had put a number against it. Resolved: CLEAR, 2.94 m from the nearest
	## structure, open sky. Shot: 180 / 332 / 47 / 492 px over profile /
	## bow_quarter / stern_quarter / plan. The 47 is thin — the casing stands
	## between an after quarter and the foredeck — and the after towing deck at
	## (5.0, 0, 22.0) measures 309 / 342 / 579 / 511, better in every view. The
	## foredeck is kept anyway: 47 px clears the floor honestly, and a tug's
	## towing deck is the one part of it that is meant to be empty.
	"probe_piece_tug": Vector3(5.0, 0.0, 5.0),
	## FOUND BY THE CHECK BELOW, not by inspection. `probe_piece_house__profile_port`
	## shipped with NO VISIBLE FIGURE — 4 samples, and looking at the PNG confirms
	## it: the bulwark hides the figure completely. That is not this fixture's
	## fault. At 3 degrees of elevation a 1.1 m bulwark on a sheered hull hides a
	## 1.8 m figure standing on the main deck, so a fourth spot down there would
	## have moved the problem rather than fixed it. It stands on the wheelhouse
	## roof instead (plan y = 5.0 m, the `deck_tile` at cell y = 10), which is
	## clear of everything on this vessel and has sky behind it from all four
	## angles.
	##
	## ⚠ THAT SENTENCE USED TO SAY "ANYWHERE ON THE MAIN DECK", AND ANYWHERE IS
	## MEASURABLY TOO STRONG — 2026-08-16. The bulwark run on this fixture spans
	## z 5.29..27.98, so the deck FORWARD of it is unprotected. Figure pixels over
	## profile / bow_quarter / stern_quarter / plan, one spot per line:
	##
	##     (4.5, 5.00, 20.5)  wheelhouse roof   813 / 366 / 531 / 626   ← kept
	##     (5.0, 0.00,  3.0)  foredeck, no bulwark forward of it
	##                                          908 / 840 / 317 / 520
	##     (5.0, 0.00,  8.0)  main deck, inside the bulwark
	##                                           48 / 667 / 305 / 507
	##
	## So the claim holds where the bulwark is (48 px is a scalp), and does not
	## hold forward of z = 5.29. The roof is kept because it reads best of the
	## three in the frame and not because the deck is impossible; the numbers for
	## the alternative are here so the next reader does not have to re-measure.
	##
	## Standing surface, measured through `StructureBaker.entity_colliders`: the
	## sloped `deck_tile` under this spot has its collider top at y = 4.965, so
	## the figure hovers 0.035 m. That is one pixel at this framing — the crop
	## shows its sole against the roof's own eave with no sky between — and it is
	## inside the dicing step of a tile that falls 0.25 m over 4.0 m. Recorded
	## rather than nudged, because moving it would change a committed frame to
	## chase something no view can resolve.
	"probe_piece_house": Vector3(4.5, 5.0, 20.5),
	## ⚠ THE THIRD FIXTURE HAD NO ENTRY AT ALL, AND ITS DEFAULT WAS INSIDE A WALL.
	##
	## `probe_piece_trawler` fell through to the parent's `FIGURE_SPOT_DEFAULT`,
	## (2.5, 0, 7.0), for as long as this rig has existed. That is not merely
	## undecided — it is WRONG. The fixture carries a V-shaped breakwater across
	## the fore end of the working deck (`walls[]` 1 and 2, from (1, 8.4) and
	## (9, 8.4) on the diagonal axes, 0.18 m thick and 1.0 m high, meeting on the
	## centreline at z = 4.4). Resolved through `StructureBaker.entity_colliders`
	## the default lands 0.07 m off that plating's centre line, inside a 0.18 m
	## wall: the figure was standing IN the breakwater, with the top 0.8 m of it
	## showing over the cap.
	##
	## It passed every check. `_shoot` measured 63 / 139 / 218 / 228 px, all four
	## comfortably over the floor, because a scale figure sunk to the waist in a
	## bulwark is still a scale figure to a pixel counter. REALITY §4: the check
	## measures VISIBILITY and cannot see EMBEDDING, and the two are not the same
	## property.
	##
	## Four spots were resolved against the colliders and then shot, profile /
	## bow_quarter / stern_quarter / plan:
	##
	##     (2.5, 0.00,  7.0)  BLOCKED, in the breakwater   63 / 139 / 218 / 228
	##     (5.0, 0.00,  2.5)  forecastle head               0 /  13 / 214 / 434
	##     (1.35, 0.00, 12.5) port side deck              178 / 285 /   0 / 297
	##     (5.0, 0.65, 12.5)  ON THE FISH HATCH COVER     see the log — chosen
	##
	## The forecastle is illegal: the sheer rises 0.896 m forward and the bulwark
	## with it, and at 3 degrees of elevation it buries the figure whole — a hard
	## FAIL on `profile_port`. The port side deck is legal but thin, 178 px of
	## scalp above the cap rail, and it is 0 px from the stern quarter, which this
	## rig ASSERTS on all four views rather than two.
	##
	## The hatch cover is the answer, and it is not a dodge: the fish hatch
	## (`decks[]` 5-7, x 2.10..7.90, z 9.10..15.90) is where a hand stands with
	## the gear on deck, it is 4.5 m clear of the deckhouse front and 2.83 m from
	## anything else, it has open sky over it, and the extra 0.65 m lifts the
	## figure clear of the bulwark cap in profile.
	##
	## y = 0.65 AND NOT 0.77, and the difference is the whole reason this was
	## measured rather than computed from the fixture. `StructureBaker._plate_span`
	## reads a deck's `origin.y` as the plate's TOP and hangs `thickness` BELOW it,
	## so the hatch authored at `origin.y = 0.65, thickness = 0.12` has its walking
	## surface at 0.65. Standing the figure on 0.65 + 0.12 floats it 0.120 m, and
	## the bulwark hides the feet from every asserted view, so no frame could ever
	## have shown it.
	"probe_piece_trawler": Vector3(5.0, 0.65, 12.5),
}

## ── The figure is VISIBLE, not merely placed ────────────────────────────────
##
## REALITY.md §8 and CONVENTIONS §3a: a capture with no visible scale figure has
## no absolute scale, and this repo has shipped that bug three times — a figure
## inside a wheelhouse, a figure inside a saloon, a figure off the side of the
## ship. Every one of them rendered perfectly and appeared in zero frames, and
## every check that existed at the time was green, because the checks asked
## whether the figure had been ADDED.
##
## THE INSTRUMENT, and two wrong ones before it. Both wrong ones are recorded
## because the shape of the mistake is the useful part:
##
##  1. COUNT THE HI-VIZ ORANGE IN THE FRAME. Blind. The suit is (0.95, 0.55,
##     0.10) and `probe_trawler_bulwark`'s ochre sheer stripe is (0.62, 0.36,
##     0.11) — the same hue to two decimal places — so the whole-frame count
##     returned 3292 "figure" samples on a frame whose figure contributes about
##     forty. It would have stayed in the thousands with the figure deleted.
##  2. COUNT IT INSIDE THE FIGURE'S PROJECTED BOX. Sharper, and still wrong: it
##     answers with the head excluded (skin is not orange) and with whatever the
##     projection maths got wrong, and the projection maths was wrong.
##
## What is used instead needs no colour and no projection. THE FRAME IS RENDERED
## AGAIN WITH THE FIGURE HIDDEN, and the two images are compared. Pixels that
## change are pixels the figure is responsible for. A figure standing inside a
## deckhouse changes nothing. A figure off the side of the ship changes nothing.
## A figure behind a bulwark changes exactly the head and shoulders you can see,
## which is the honest answer — and it is the same answer in a plan view, where
## the figure is a nine-pixel disc, and in a profile, where it is a sliver over
## the bulwark cap.
##
## Measured on these twelve frames: the honest views change 21 to 335 samples.
## A hidden figure changes 0. The floor is 12.
const FIGURE_CHANGED_MIN := 12
## Sampled every other pixel on both axes: 1280x720 becomes 230k comparisons per
## frame rather than 921k, and the floor is stated in those samples.
const FIGURE_SAMPLE_STEP := 2
## Any channel differing by more than this counts as changed. One step above the
## renderer's own dither, and the noise control below measures what that is
## rather than assuming it.
const FIGURE_PIXEL_DELTA := 0.03

## Measured on the first clean run, then given ~8% headroom on triangles. Draw
## calls are exact and are the load-bearing half.
const PIECE_BUDGET := {
	## probe_trawler_bulwark, the hand-authored vessel this one replaces the
	## deckhouse of, is budgeted at 8 draw calls. The piece-built version draws
	## THE SAME 8: 49 placements, six piece types and eight colours all bucket on
	## MATERIAL alone, and building from a kit costs nothing at the draw call.
	"probe_piece_trawler": {"draw_calls": 8, "triangles": 33000},
	## The bare hull plus a bulwark loop measures 6 (probe_sheer_bulwark); the
	## whole piece-built superstructure adds ONE.
	"probe_piece_house": {"draw_calls": 7, "triangles": 21000},
	## The tug, BUILT THROUGH THE STUDIO. Same 7 as the house: a whole pilot house
	## in 33 placements, five tints and six piece types costs the same draw calls
	## as the bare hull and its bulwark plus one, because every one of them buckets
	## on MATERIAL alone and they are all "painted". Triangles are the measured
	## 25 726 (shadow pass included) plus 8%, halved because `_check_cost` doubles
	## it — so this line has 8% of slack in it and no more.
	"probe_piece_tug": {"draw_calls": 7, "triangles": 13900},
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


## Stands the figure somewhere it can be SEEN on this fixture. Same geometry as
## the parent's — same capsule, same head, same colours — only the spot differs,
## so a tug photographs at the same scale as everything else in the folder.
##
## This used to reposition the figure AFTER `super._add_scale_figure` had already
## placed it and already run the "authored, not defaulted" check — so the check
## judged the parent's table while the figure stood at this one's, and reported
## `probe_piece_house` and `probe_piece_tug` as defaulted when they were not.
## Answering the parent's question instead means the position and the claim come
## from one call, and no override of the placement itself is needed.
func _figure_spot(stem: String) -> Variant:
	if PIECE_FIGURE_SPOT.has(stem):
		return PIECE_FIGURE_SPOT[stem]
	return super._figure_spot(stem)


## Every frame is photographed by the parent, then SHOT AGAIN WITH THE FIGURE
## HIDDEN and the two compared. See the note above the constants for why this
## rather than a colour count.
func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	await super._shoot(bounds, name, view)
	var figure := _stage.get_node_or_null("ScaleFigure") as Node3D
	if figure == null:
		_t.fail("%s: no 1.8 m figure on the stage at all" % name)
		return
	var with_figure := get_viewport().get_texture().get_image()

	## NOISE CONTROL, once per run. If two renders of the SAME scene already
	## differed, the difference below would measure the renderer and every frame
	## would pass. Measured rather than assumed — llvmpipe is deterministic here,
	## and this is what says so.
	if not _noise_measured:
		_noise_measured = true
		await _settle()
		var again := get_viewport().get_texture().get_image()
		var noise := _changed_samples(with_figure, again)
		_t.check(
			"two renders of one frame are identical (%d samples differ)" % noise, noise == 0
		)

	figure.visible = false
	await _settle()
	var without := get_viewport().get_texture().get_image()
	figure.visible = true
	var changed := _changed_samples(with_figure, without)
	_t.check(
		"%s: the 1.8 m figure is VISIBLE in the frame (%d samples change when it is hidden, floor %d)"
		% [name, changed, FIGURE_CHANGED_MIN],
		changed >= FIGURE_CHANGED_MIN
	)


var _noise_measured := false


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## Samples where two frames of the same size differ. Both are sampled on the same
## grid, so the number is comparable between views and between fixtures.
func _changed_samples(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return 0
	var count := 0
	for y in range(0, a.get_height(), FIGURE_SAMPLE_STEP):
		for x in range(0, a.get_width(), FIGURE_SAMPLE_STEP):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) > FIGURE_PIXEL_DELTA \
					or absf(pa.g - pb.g) > FIGURE_PIXEL_DELTA \
					or absf(pa.b - pb.b) > FIGURE_PIXEL_DELTA:
				count += 1
	return count


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
