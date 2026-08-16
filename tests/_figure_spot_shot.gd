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

## fixture stem -> [spot, ...]. Every entry is a point `_figure_spot_pick.gd`
## already showed CLEAR of the resolved colliders, plus the spot each fixture is
## being shot at today, as the control.
const CANDIDATES := {
	"probe_piece_trawler": [
		Vector3(2.5, 0.0, 7.0),    ## control: today's DEFAULT — inside the breakwater
		Vector3(5.0, 0.0, 2.5),    ## forecastle head, centreline, forward of the breakwater
		Vector3(1.35, 0.0, 12.5),  ## port side deck, between bulwark and hatch
		Vector3(5.0, 0.77, 12.5),  ## standing on the fish hatch cover
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

	var plate_stem := PLATE_FIXTURE_HERE.get_file().get_basename()
	if wanted.is_empty() or wanted.has(plate_stem):
		await _shoot_candidates(PLATE_FIXTURE_HERE, plate_stem)

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
