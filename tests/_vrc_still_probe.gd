extends "res://tests/vessel_render_capture.gd"

## SCRATCH PROBE — leading underscore, so `tools/gate.sh` skips both this and its
## `.tscn` (it excludes `_*` basenames in lane A and lane B alike).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_vrc_still_probe.tscn -- demo_workboat
##
## Does the subject of `vessel_render_capture` actually move while that rig is
## photographing it? Its frames cannot answer: a "before" run of a rig carrying
## this defect has come back byte-green three separate times, once across eight
## runs and 28 pairs (STATE.md 2026-08-16). So this asks the SUBJECT.
##
## It is a SUBCLASS rather than a re-implementation, for the reason
## `_hvc_still_probe` could not be one: the whole point is to measure the parent's
## own `_capture_plan` — its `VesselSpawn` path, its `freeze`, its
## `process_mode`, its bake and its eight settle points per fixture. `_shoot` is
## overridden to do the same WORK (two `_settle()`s and two viewport grabs, the
## real llvmpipe frame cost, which is what the LOD timer is racing) while writing
## no PNG, so this probe cannot touch a committed frame.
##
##   VRC_PROBE_HOLD=1     apply `CaptureSubject.hold_still` (the fix)
##   VRC_PROBE_LIVE=1     put `process_mode` back to INHERIT, i.e. let
##                        `_physics_process` run and the LOD timer accumulate —
##                        this is the rig WITHOUT the accidental protection
##   VRC_PROBE_FORCE=1    call `_update_automatic_physics_quality()` by hand at
##                        the first grab: what a run looks like when the 1.0 s
##                        timer crosses inside the capture window
##
## Combinations are meaningful and are the point: LIVE alone measures how far the
## timer actually gets, LIVE+FORCE measures what the subject does when the freeze
## is revoked with buoyancy live, FORCE alone measures it with buoyancy disabled.
##
## ── WHAT IT MEASURED, `demo_workboat`, 2026-08-16 ──────────────────────────
##
##   rig as it stands   origin.y −5.719999790 at all eight grabs, span 0.000 mm,
##                      `lod_timer` 0.0000 after 140 physics frames — the LOD
##                      never runs, because `process_mode` is DISABLED.
##   FORCE only         `freeze=false quality=FULL`, span still 0.000 mm and
##                      `in_space=false`: `disable_mode` is `DISABLE_MODE_REMOVE`,
##                      so a disabled BoatBody is out of the physics space and
##                      cannot move whatever `freeze` says.
##   LIVE only          the timer crosses 1.0 s between the third and fourth grab
##                      on its own; the hull then RISES **1.742 m at +2.17 m/s**
##                      across the remaining grabs. Up, not down: buoyancy is live
##                      on this stage and the rig has sunk the hull by `deck_y`.
##   LIVE, after the fix `auto_lod=false quality=SLEEP freeze=true in_space=true`,
##                      span **0.000 mm** over 155 physics frames.

## NO `const CaptureSubject` here: the parent declares one now, and a subclass
## that redeclares a parent const is a PARSE ERROR — which loads no main scene and
## leaves the process sitting under xvfb until something kills it, with the reason
## printed once at the top of a log nobody is tailing.

var _hold := false
var _live := false
var _force := false
var _armed := false
var _lo := 1e18
var _hi := -1e18
var _worst_walk := 0.0
var _worst_stem := ""
var _stem := ""


func _run() -> void:
	_hold = OS.get_environment("VRC_PROBE_HOLD").strip_edges() == "1"
	_live = OS.get_environment("VRC_PROBE_LIVE").strip_edges() == "1"
	_force = OS.get_environment("VRC_PROBE_FORCE").strip_edges() == "1"
	print(
		"=== VRC STILL PROBE: hold=%s live_process=%s force_lod=%s ==="
		% [_hold, _live, _force]
	)
	_t = TestReport.new("vrc_still_probe")
	_hide_autoload_ui()
	var wanted := _requested_stems()
	for fixture in FIXTURES:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		_stem = stem
		_armed = false
		_lo = 1e18
		_hi = -1e18
		await _capture_plan(fixture, stem)
		if _lo < 1e17:
			var walk := _hi - _lo
			print(
				"  %-28s origin.y span across its eight grabs = %.9f m (%.3f mm)"
				% [stem, walk, walk * 1000.0]
			)
			if walk > _worst_walk:
				_worst_walk = walk
				_worst_stem = stem
	print(
		"=== VRC STILL PROBE: hold=%s live=%s force=%s  WORST origin.y walk = %.9f m (%.3f mm) on %s ==="
		% [_hold, _live, _force, _worst_walk, _worst_walk * 1000.0, _worst_stem]
	)
	_t.finish(get_tree())


## Same cost, same order, no file. The camera framing is the parent's job and is
## irrelevant here; what matters is that the subject sits in the tree for exactly
## as many process frames, physics ticks and draws as it does in a real run.
func _shoot(_bounds: AABB, name: String, _view: Dictionary) -> void:
	var boat := _find_boat(_stage)
	if boat != null and not _armed:
		_armed = true
		if _live:
			boat.process_mode = Node.PROCESS_MODE_INHERIT
		if _hold:
			CaptureSubject.hold_still(boat)
		if _force and not _hold:
			boat.call("_update_automatic_physics_quality")
			print(
				"    LOD FORCED BY HAND -> freeze=%s quality=%s"
				% [str(boat.get("freeze")), boat.call("get_physics_quality_name")]
			)
	if _figure != null:
		_figure.visible = false
		await _settle()
	var _without := get_viewport().get_texture().get_image()
	_sample(boat, name, "no-figure")
	if _figure != null:
		_figure.visible = true
	await _settle()
	var _with := get_viewport().get_texture().get_image()
	_sample(boat, name, "GRABBED")


func _find_boat(node: Node) -> Node3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is BoatBody:
			return child as Node3D
	return null


func _sample(boat: Node3D, name: String, tag: String) -> void:
	if boat == null:
		print("    %-34s %-10s NO BOATBODY ON THE STAGE" % [name, tag])
		return
	var body := boat as RigidBody3D
	var origin := boat.global_transform.origin
	print(
		(
			"    %-34s %-10s origin=(%.9f, %.9f, %.9f) vy=%.9f freeze=%s"
			+ " quality=%s auto_lod=%s lod_timer=%.4f pframes=%d proc=%s"
			+ " disable_mode=%s in_space=%s"
		)
		% [
			name,
			tag,
			origin.x,
			origin.y,
			origin.z,
			body.linear_velocity.y if body != null else 0.0,
			str(boat.get("freeze")),
			(
				boat.call("get_physics_quality_name")
				if boat.has_method("get_physics_quality_name")
				else "?"
			),
			str(boat.get("automatic_physics_lod")),
			float(boat.get("_physics_lod_timer")),
			Engine.get_physics_frames(),
			str(boat.process_mode),
			str(boat.get("disable_mode")),
			str(PhysicsServer3D.body_get_space(body.get_rid()) != RID()) if body != null else "?",
		]
	)
	_lo = minf(_lo, origin.y)
	_hi = maxf(_hi, origin.y)
