extends RefCounted

## NO `class_name`: this is reached by `preload`, so it registers no global
## identifier and cannot break the `--script` lane (CONVENTIONS §2).

## PIN THE WORLD CLOCK, so a capture photographs a stated hour instead of the
## minute it happened to run at.
##
## ── Why this exists ────────────────────────────────────────────────────────
##
## `WorldClock.get_time_of_day()` is
##
##     fmod(Time.get_unix_time_from_system(), 1440.0) / 1440.0
##
## — a 24-REAL-MINUTE game day anchored to the Unix epoch, pushed into
## `WeatherLighting.time_of_day` every frame. `ShipLighting._process` reads
## `WeatherLighting.artificial_light_scale()` (= `lerpf(1.0, 0.05, daylight)`)
## twice a second and rescales every `ShipLight` on the vessel.
##
## **So two runs of the same capture rig twelve real minutes apart are twelve
## GAME HOURS apart, and the boat's deck lights are full on in one and off in
## the other.** Measured 2026-08-16 on `tests/_starter_shot.gd`:
##
##     grabbed 01:36:40 UTC -> game hour  0.67 -> artificial_light_scale 1.00
##     grabbed 01:48:30 UTC -> game hour 12.50 -> artificial_light_scale 0.05
##     starter__plan_ortho: 94.96% of pixels differ, deltas to 166/255
##
## and two runs four minutes apart (game hours 0.67 and 5.00, both night) differ
## only by the residual ramp — 21.7% of pixels, every one of them by 1..3/255.
## That second number is the dangerous one: it looks like noise, it moves every
## md5, and it is a real lighting change measured too small to see.
##
## The subject is NOT what moves. On the same rig, across two processes, the
## granted vessel's body transform is bit-identical (all twelve float words),
## its 138 mesh surfaces hash identical and its 141 materials hash identical.
## The hull does not settle; the light changes.
##
## ── What this does ─────────────────────────────────────────────────────────
##
## `WorldClock._process` pushes the wall clock into `WeatherLighting` every
## frame, so pinning means stopping that push and then writing the hour you
## want. `WorldClock.snap_time_of_day()` is NOT enough on its own: it re-anchors
## the epoch so that *now* is the requested fraction and then keeps running, so
## a rig that takes two minutes to shoot still drifts two game hours across its
## own frames.
##
## Lane A (`--script`) registers no autoloads, so both lookups may miss; that is
## not an error, it means there was no clock to pin.
##
## ── WHAT `pin()` DOES NOT PIN — measured, not assumed ──────────────────────
##
## It pins the HOUR. It does not pin the WEATHER, and the weather is on the same
## wall clock by a different route: `WeatherField.current_game_time()` calls
## `WorldClock.get_game_hours_elapsed()`, which is computed live from
## `Time.get_unix_time_from_system()` whether or not `WorldClock` is processing.
## Anything that samples `WorldWeather` per frame therefore still drifts, and
## `ShipLighting._update_auto_nav` reads `fog_density` as well as daylight.
##
## Nine rigs came back byte-identical across a gap with the hour pinned, so for
## those the hour was the whole story. **`tests/_fittings_shot.gd` did not** — 2
## of its 7 frames still move by 3.49% and 3.79% across a six-minute gap. That
## rig declares the residue in its own header rather than this one pretending to
## have closed it (REALITY §6).

## Noon. Full daylight, `artificial_light_scale` at its 0.05 floor, so the
## vessel is read by its form rather than by its own deck lights — which is what
## every one of these rigs exists to photograph.
const NOON := 0.5


## Returns the hour actually pinned, or -1.0 when there was no clock to pin
## (lane A). Callers print it, so the frame can say what hour it is.
static func pin(tree: SceneTree, time_of_day: float = NOON) -> float:
	if tree == null or tree.root == null:
		return -1.0
	var pinned := -1.0
	var clock := tree.root.get_node_or_null("WorldClock")
	if clock != null:
		clock.set_process(false)
		pinned = time_of_day
	var weather := tree.root.get_node_or_null("WeatherLighting")
	if weather != null:
		weather.set("time_of_day", time_of_day)
		pinned = time_of_day
	return pinned


## The settle every byte-stable rig in this repo performs and every unstable one
## skipped: N idle frames, THEN `frame_post_draw`. Awaiting `process_frame`
## alone returns whatever the render target last held, which is why the yawed
## views in `hull_visual_capture` came back with a one-pixel outline around
## every silhouette edge on some runs and not others.
static func settle(tree: SceneTree, frames: int = 4) -> void:
	for _i in frames:
		await tree.process_frame
	await RenderingServer.frame_post_draw
