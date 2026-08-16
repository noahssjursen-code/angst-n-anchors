extends "res://tests/piece_kit_capture.gd"

## SCRATCH PROBE (leading underscore, not gate-scored).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_figure_spot_shot.tscn
##
## Stands the 1.8 m figure at each CANDIDATE spot in turn and reports what the
## rig's own hidden/shown pixel difference measures in each of the four views, so
## a spot is CHOSEN on a measurement rather than argued from a coordinate.
##
## It subclasses the piece rig so the piece fixtures go through the same
## `pieces[] -> items[]` resolution the real capture uses, and it writes its
## frames under `screenshots/studio/_spot/` (scratch, underscore) so it can never
## overwrite a committed reference frame.
##
## The spot under test is a VARIABLE here, which is exactly what it must not be
## in the real rig — hence `_figure_spot` is overridden rather than the tables
## edited.

const SPOT_DIR := "res://screenshots/studio/_spot"

const PLATE_FIXTURE_HERE := "res://resources/data/structures/probe_plate_deckhouse.json"

## Fixtures of the PARENT rig, shot through `_capture_plan` directly the same way
## the plate fixture is: they carry no `pieces[]`, so nothing to resolve. They are
## here because two of them — the bulwark pair — are authored with the figure
## inside a wall, and because `demo_workboat` is where the attack on
## `FIGURE_REQUIRED_VIEWS` lands.
const PARENT_FIXTURES_HERE := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
	"res://resources/data/structures/probe_ferry_catamaran.json",
]

## fixture stem -> [spot, ...]. Every entry is a point `_figure_spot_pick.gd`
## already showed CLEAR of the resolved colliders, plus the spot each fixture is
## being shot at today, as the control.
const CANDIDATES := {
	"probe_piece_trawler": [
		Vector3(5.0, 0.65, 12.5),  ## control: AUTHORED TODAY, on the fish hatch cover
		Vector3(1.35, 0.0, 12.5),  ## port side deck, between bulwark and hatch
		Vector3(8.65, 0.0, 12.5),  ## starboard side deck — the quarters shoot from +X
		Vector3(5.0, 0.0, 7.0),    ## centreline working deck, abaft the breakwater apex
	],
	"probe_piece_house": [
		Vector3(4.5, 5.0, 20.5),   ## control: the wheelhouse roof it is shot at today
		Vector3(5.0, 0.0, 3.0),    ## foredeck, centreline
		Vector3(5.0, 0.0, 8.0),    ## main deck forward of the house
	],
	"probe_piece_tug": [
		Vector3(5.0, 0.0, 5.0),    ## control: today's spot, foredeck
		Vector3(5.0, 0.0, 22.0),   ## the after towing deck
	],
	"probe_plate_deckhouse": [
		Vector3(2.5, 0.0, 7.0),    ## control: today's DEFAULT
		Vector3(5.0, 0.0, 10.0),   ## foredeck, centreline, clear of the raked front
	],
	## ── THE ATTACK ON `FIGURE_REQUIRED_VIEWS`, AND WHY IT FAILED ────────────
	##
	## The parent asserts the figure in `profile_port` and `plan` only, on the
	## argument that hiding from BOTH means being inside something. To break that
	## you need a spot that is ROOFED (so `plan` cannot see it) and screened to
	## port (so a 3-degree `profile_port` cannot) while still being open air.
	## `_figure_roof_sweep.gd` sweeps every fixture's resolved colliders for one
	## and offered these: `decks[]` 5 spans x 1..9, z 8..16 with its top at y 3.00
	## and its underside at 2.85, and the sweep's sight lines escaped from under it
	## to the stern quarter.
	##
	## SHOT, and the pixels say the argument holds. Profile / bow_quarter /
	## stern_quarter / plan:
	##
	##     (2.50, 0, 7.00)   authored today        112 / 295 /   0 /  79
	##     (2.25, 0, 12.25)                           0 /   0 /  96 /   0
	##     (3.25, 0, 13.25)                           0 /   0 / 148 /   0
	##     (6.25, 0, 10.75)                           0 /   0 /  46 /   0
	##     (7.25, 0, 12.25)                           0 /   0 / 131 /   0
	##
	## Four spots hidden from both asserted views and plainly counted in the stern
	## quarter — and CROPPING THE FRAME SETTLES IT: `decks[]` 5 is the DECKHOUSE
	## ROOF, not a canopy, and the figure is standing in the saloon. The stern
	## quarter's 148 samples are a slice of an orange capsule seen through the
	## open doorway. The sweep found the door, not a legal spot.
	##
	## So: hidden from `profile_port` AND `plan` still means inside something, and
	## a "visible in at least one view" rule would have PASSED a figure standing
	## in a deckhouse at 148 px. Kept here as the record of an attack that ran.
	"demo_workboat": [
		Vector3(2.5, 0.0, 7.0),    ## control: the spot it is authored at today
		Vector3(2.25, 0.0, 12.25), ## under the shelter deck, port side
		Vector3(3.25, 0.0, 13.25), ## under the shelter deck, port of centre
		Vector3(6.25, 0.0, 10.75), ## under the shelter deck, starboard of centre
		Vector3(7.25, 0.0, 12.25), ## under the shelter deck, starboard side
		Vector3(5.0, 0.0, 12.0),   ## dead centre under it, for comparison
	],
	## THE SECOND HALF OF THE ATTACK. `demo_workboat`'s counter-examples turned out
	## to be a figure inside a deckhouse seen through its door, which is a hole in
	## the collider set rather than a legal spot. The catamaran offers the shape
	## that is NOT that: an open PROMENADE at y = 3.0 (`decks[]` 30, x 1.2..14.8,
	## z 7..37) under a SUN DECK at y = 6.0 (`decks[]` 31, x 1.6..14.4, z 9..33),
	## with 2.82 m of headroom and no bulkhead between them — a covered walkway, not
	## a room. `_figure_roof_sweep.gd` calls it hidden from both asserted views and
	## seen from the stern quarter. If the pixels agree here, the parent's argument
	## IS false and the strict rule is right.
	"probe_ferry_catamaran": [
		Vector3(12.0, 0.0, 39.0),   ## control: the spot it is authored at today
		Vector3(4.25, 3.0, 26.75),  ## the promenade, under the sun deck
		Vector3(2.75, 0.0, 31.75),  ## main deck aft, under the promenade
	],
	## The two shipped fixtures authored INSIDE the breakwater. Candidates are the
	## same deck this vessel's piece-built sister was scored on.
	"probe_trawler_bulwark": [
		Vector3(2.5, 0.0, 7.0),    ## control: AUTHORED TODAY, inside the breakwater
		Vector3(5.0, 0.0, 7.0),    ## centreline working deck, abaft the apex
		Vector3(1.35, 0.0, 12.5),  ## port side deck
		Vector3(8.65, 0.0, 12.5),  ## starboard side deck
		Vector3(5.0, 0.65, 12.5),  ## on the fish hatch cover
	],
	"probe_trawler_bow_bulwark": [
		Vector3(2.5, 0.0, 7.0),
		Vector3(5.0, 0.0, 7.0),
		Vector3(1.35, 0.0, 12.5),
		Vector3(8.65, 0.0, 12.5),
		Vector3(5.0, 0.65, 12.5),
	],
}

var _spot := Vector3.ZERO


func _run() -> void:
	_t = TestReport.new("_figure_spot_shot")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPOT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESOLVED_DIR))
	_hide_autoload_ui()
	var wanted := _requested_stems()

	for fixture in FIXTURES_HERE:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		var resolved_path := _resolve_to_user(fixture, stem)
		if resolved_path.is_empty():
			continue
		await _shoot_candidates(resolved_path, stem)

	for fixture in PARENT_FIXTURES_HERE + [PLATE_FIXTURE_HERE]:
		var stem := str(fixture).get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		await _shoot_candidates(str(fixture), stem)

	_t.finish(get_tree())


func _shoot_candidates(path: String, stem: String) -> void:
	var index := 0
	for spot_variant in CANDIDATES.get(stem, []) as Array:
		_spot = spot_variant as Vector3
		print("\n##### %s  candidate %d  spot (%.2f, %.2f, %.2f)"
			% [stem, index, _spot.x, _spot.y, _spot.z])
		await _capture_plan(path, "_spot/%s_c%d" % [stem, index])
		index += 1


## The spot under test, whatever the stem. `_capture_plan` is handed a scratch
## stem so its PNGs land in `_spot/`, which is also why the tables cannot be
## consulted here.
func _figure_spot(_stem: String) -> Variant:
	return _spot


## WHERE in the frame the figure is, not just how many samples it moved. A count
## says a scale reference exists; the box says whether it is a person on a deck
## or a scalp over a rail, and it is what tells a reader which 60 pixels of a
## 1280x720 render to go and look at.
func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	await super._shoot(bounds, name, view)
	var figure := _stage.get_node_or_null("ScaleFigure") as Node3D
	if figure == null:
		return
	## SETTLE FIRST. `piece_kit_capture._shoot` leaves the figure visible but the
	## last frame it drew is the one with the figure HIDDEN, so grabbing the
	## viewport here without settling returns that stale frame — and every box came
	## back "NO FIGURE PIXELS AT ALL" on frames the same run had just measured at
	## 148 px. The instrument, not the subject (REALITY §8).
	await _settle()
	var with_figure := get_viewport().get_texture().get_image()
	figure.visible = false
	await _settle()
	var without := get_viewport().get_texture().get_image()
	figure.visible = true
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for y in range(without.get_height()):
		for x in range(without.get_width()):
			var a := without.get_pixel(x, y)
			var b := with_figure.get_pixel(x, y)
			if absf(a.r - b.r) <= FIGURE_PIXEL_DELTA \
					and absf(a.g - b.g) <= FIGURE_PIXEL_DELTA \
					and absf(a.b - b.b) <= FIGURE_PIXEL_DELTA:
				continue
			lo.x = mini(lo.x, x)
			lo.y = mini(lo.y, y)
			hi.x = maxi(hi.x, x)
			hi.y = maxi(hi.y, y)
	if hi.x < 0:
		print("  [box] %s  NO FIGURE PIXELS AT ALL" % name)
		return
	print("  [box] %s  x %d..%d  y %d..%d  (%d x %d px)"
		% [name, lo.x, hi.x, lo.y, hi.y, hi.x - lo.x + 1, hi.y - lo.y + 1])
