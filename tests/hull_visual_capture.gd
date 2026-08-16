extends Node

## Hull-form captures, WITH a verdict.
##
## This unit reported NOTRUN on every gate run: it wrote fifteen correct PNGs
## and then quit without saying anything a results table could score. It is not
## `staged_vessel_visual_demo` — there is no orbiting camera, no HUD, no
## `_unhandled_input`, nothing interactive; it is a deterministic, data-driven
## capture harness, which `CONVENTIONS.md` §3 keeps in `tests/` on one condition:
## "Pair every capture with at least one machine-checkable claim". It had none.
## So it gets claims and a verdict rather than an eviction, the way
## `structure_ao_capture` already does.
##
## Two other things were wrong with it and are fixed here:
##
##  - It wrote to `/opt/cursor/artifacts/hull-forms`, outside the repository.
##    §3 puts captures under `screenshots/<area>/` with stable names so a re-run
##    overwrites and the images can be diffed.
##  - It carried NO scale figure. §3a: "a capture without one has no absolute
##    scale, and a wrongly-proportioned build looks entirely plausible" — the
##    exact reading error that twice convinced people this world was double
##    scale. There is a 1.8 m figure on every frame now, and — §8, because the
##    first attempt at this elsewhere put the figure inside the wheelhouse where
##    it rendered perfectly and appeared in no frame — each view is rendered
##    twice, with and without the figure, and the check is that the two images
##    DIFFER. That measures visibility, not placement.
##
## ── The word "deterministic" above was a claim, and it was WRONG. 2026-08-16 ─
##
## Run twice with no code change, this rig moved 2 of its 18 frames —
## `hull_15x5__three_quarter` 0.8628% and `hull_28x10__three_quarter` 0.8104%,
## with per-channel deltas up to 241/255. Another pair moved 1 frame at 0.5579%,
## another moved 0. It is INTERMITTENT, and it lands on exactly the two views
## that yaw the hull (`rotation_degrees.y = -18.0`); `front` and `side` are
## byte-identical every time.
##
## The subject was cleared before the rig was blamed (REALITY §7). Across two
## processes the yawed body's global transform is bit-identical — all twelve
## float words, hex-compared, at every frame from 1 to 8 after the yaw — and its
## visual-instance AABBs hash identical. A synthetic scene of four yawed boxes
## under this renderer is byte-identical across processes, with and without
## shadows, in a SubViewport and in the main viewport. The geometry does not
## move and the rasteriser is not noisy.
##
## What was left is the GRAB. This rig awaited three `process_frame`s and then
## read `viewport.get_texture()`, never `RenderingServer.frame_post_draw`. Every
## byte-stable capture rig in this repo awaits `frame_post_draw`
## (`vessel_render_capture` and its three subclasses: 60 frames, 0 moved);
## every unstable one did not. The difference shows up as a one-pixel outline
## along silhouette edges — visible in the diff mask as a wireframe of the boat
## — which is what a frame grabbed a draw early or late looks like when there is
## no anti-aliasing to soften an edge that moved by a fraction of a pixel.
##
## So the grab now goes through `CaptureClock.settle`, and the clock is pinned
## with it. Pinning changes nothing HERE — `HullRegistry.build_hull` carries no
## `ShipLight`, so there is nothing on a bare hull for the time of day to scale
## — and it is done anyway so this rig cannot acquire the dependency by someone
## later photographing a fitted-out vessel through it.

const OUTPUT_DIR := "res://screenshots/hulls"
const TestReport := preload("res://tests/support/test_report.gd")
const CaptureClock := preload("res://tests/support/capture_clock.gd")
## A frame that is entirely background, or entirely subject, is a broken camera
## rather than a hull. Coverage is the fraction of pixels away from the clear
## colour.
const MIN_COVERAGE := 0.02
const MAX_COVERAGE := 0.92
const BACKGROUND := Color(0.055, 0.075, 0.095)
const HULL_IDS := [
	## The smallest hull in the game, and the one a beginner starts from. It is
	## FIRST because the figure-visibility check is hardest to satisfy on the
	## smallest deck, so a rig that has drifted fails here first.
	"hull_15x5",
	"hull_28x10",
	"hull_45x16_cat",
	"hull_150x32",
	"hull_100x24",
	"hull_130x28",
]


var _t := TestReport.new("hull_visual_capture", false)


func _ready() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	var hour := CaptureClock.pin(get_tree())
	print("Hull visual capture: game clock pinned at time_of_day %.3f" % hour)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.70)
	env.ambient_light_energy = 0.85
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.55
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	world.add_child(camera)

	for hull_id in HULL_IDS:
		var boat := HullRegistry.build_hull(hull_id)
		if not _t.check("hull builds: %s" % hull_id, boat != null):
			continue
		boat.freeze = true
		world.add_child(boat)
		var length := maxf(boat.length_m, 10.0)
		var beam := maxf(boat.beam_m, 5.0)
		var height := maxf(boat.depth_m, 3.0)
		## Rides on the boat so it stays on deck through the three-quarter yaw.
		var deck_y := (
			boat.hull_stations.deck_y if boat.hull_stations != null else height * 0.85
		)
		var figure := _make_scale_figure()
		## Well forward on the open foredeck: the front view looks down the bow
		## axis, and at z = -length * 0.12 the figure was BEHIND the bow on the
		## three biggest hulls — zero pixels, which is precisely the failure §8
		## records (rendered perfectly, present in no frame).
		figure.position = Vector3(beam * 0.18, deck_y, -length * 0.40)
		boat.add_child(figure)
		for view in ["front", "side", "three_quarter"]:
			match view:
				"front":
					boat.rotation_degrees.y = 0.0
					camera.position = Vector3(
						0.0,
						height * 0.82,
						-length * 0.5 - maxf(beam * 1.15, height * 2.6)
					)
				"side":
					boat.rotation_degrees.y = 0.0
					camera.position = Vector3(
						beam * 0.5 + maxf(length * 0.76, height * 5.0),
						height * 0.68,
						0.0
					)
				_:
					boat.rotation_degrees.y = -18.0
					var distance := maxf(length * 0.64, beam * 1.45)
					camera.position = Vector3(
						distance * 0.55,
						height * 1.35,
						-distance
					)
			camera.look_at_from_position(
				camera.position,
				Vector3(0.0, height * 0.48, 0.0),
				Vector3.UP
			)
			## Reference frame with no figure, then the real one with it.
			## `CaptureClock.settle` rather than a bare `process_frame` loop —
			## see the note at the top of this file about the yawed views.
			figure.visible = false
			await CaptureClock.settle(get_tree(), 3)
			var without := viewport.get_texture().get_image()
			figure.visible = true
			await CaptureClock.settle(get_tree(), 3)
			var image := viewport.get_texture().get_image()

			var case := "%s__%s" % [hull_id, view]
			var path := "%s/%s.png" % [OUTPUT_DIR, case]
			_t.check(
				"capture writes %s" % case,
				image.save_png(ProjectSettings.globalize_path(path)) == OK,
			)
			var coverage := _coverage(image)
			_t.check(
				"%s frames the hull (coverage %.3f, want %.2f..%.2f)"
				% [case, coverage, MIN_COVERAGE, MAX_COVERAGE],
				coverage >= MIN_COVERAGE and coverage <= MAX_COVERAGE,
			)
			var moved := _changed_pixels(without, image)
			_t.check(
				"%s shows the 1.8 m scale figure (%d pixels differ with it hidden)"
				% [case, moved],
				moved > 0,
			)
			print("Hull visual capture: %s coverage=%.3f figure_px=%d" % [path, coverage, moved])
		world.remove_child(boat)
		boat.free()

	viewport.queue_free()
	_t.finish(get_tree())


## Fraction of pixels that are not the environment's clear colour.
func _coverage(image: Image) -> float:
	var w := image.get_width()
	var h := image.get_height()
	var hit := 0
	var total := 0
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			total += 1
			var c := image.get_pixel(x, y)
			if (
				absf(c.r - BACKGROUND.r) > 0.02
				or absf(c.g - BACKGROUND.g) > 0.02
				or absf(c.b - BACKGROUND.b) > 0.02
			):
				hit += 1
	return float(hit) / float(maxi(total, 1))


## How many sampled pixels changed between two frames of the same view. Used to
## prove the scale figure is VISIBLE rather than merely present in the tree.
func _changed_pixels(before: Image, after: Image) -> int:
	if before.get_width() != after.get_width() or before.get_height() != after.get_height():
		return 0
	## Stride 1: a 1.8 m figure against a 150 m hull is a handful of pixels, and
	## subsampling can miss it entirely — the count has to be of real pixels.
	var n := 0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
				n += 1
	return n


## The 1.8 m figure §3a requires on every vessel capture: a 1.5 m capsule with a
## 0.28 m head on top, matching `vessel_render_capture` and the studio mannequin.
func _make_scale_figure() -> Node3D:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.95, 0.55, 0.1)
	body.material_override = suit
	figure.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.70, 0.55)
	head.material_override = skin
	figure.add_child(head)
	return figure
