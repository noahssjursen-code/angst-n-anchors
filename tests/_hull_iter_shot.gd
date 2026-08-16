extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## The iteration rig for the hull-form work. Identical stage, lights, sea, lens
## and metres-per-pixel to `tests/_small_hull_shot.gd` — the only difference is
## that every frame is written under `screenshots/vessels/iter/<tag>__…` so a
## series can be laid side by side. Same rig across variants, or you are
## comparing your camera and not your hull (REALITY §8).
##
## Tag comes from the command line: `-- --tag=v2`.
##
## Every frame is shot twice (figure hidden / shown) and the differing-pixel
## count is printed, so an empty render cannot pass unnoticed.
##
## ── REPRODUCIBILITY, 2026-08-16 ────────────────────────────────────────────
##
## This rig used to produce different pixels on every run. The cause is written
## up in full at the top of `tests/_starter_shot.gd`, and in one line it is:
## `WorldClock` runs a 24-REAL-MINUTE day off the Unix clock and
## `ShipLighting` rescales every light on the vessel from it, so two runs a few
## real minutes apart are a few GAME HOURS apart. The subject does not move —
## the boat's transform, meshes and materials are bit-identical across
## processes — the light does. Two fixes, both mechanical: the clock is pinned
## at noon, and each frame is grabbed after `frame_post_draw` rather than after
## a bare `process_frame` count.
##
## ══ THIS RIG IS NOT FULLY REPRODUCIBLE. THERE IS A FLOOR, AND IT IS 150 px. ═
##
## Both fixes applied, three runs, pairwise: **3 to 4 of 7 frames still move,
## by 0.0004% to 0.0102% of their pixels** — measured 23 and 147 pixels out of
## 1 440 000 on the two worst. The shape is the silhouette-edge race described
## above and NOT the light: almost every differing pixel is off by 1/255, with a
## handful of edge pixels flipping by 110 to 146 where an outline lands on the
## other side of a pixel centre. The residue was not traced further and is
## reported rather than papered over (REALITY §6).
##
## **So: a difference under about 150 pixels (0.011%) in a frame from this rig
## is NOISE, and anything above it is real.** That floor is printed on every run
## so nobody has to open this file to find it. Do not md5-compare these frames.
##
## The shipped `v0…v12` series predates all of this and was shot at whatever
## game hour each run happened at, so **the series is not comparable
## frame-to-frame** — including the file's own claim that v1 and v2 are
## "indistinguishable". Re-shooting it needs the historical variants and is a
## job for whoever owns the hull loft, not for the rig.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
## Measured 2026-08-16 over three runs of the fixed rig, worst pair.
const REPRO_NOISE_FLOOR_PX := 150
const OUT_DIR := "res://screenshots/vessels/iter"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _tag := "x"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--tag="):
			_tag = str(arg).substr(6)
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f (noon) — the HOUR is fixed; see this file's header for what that closes"
		% CaptureClock.pin(get_tree()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()

	var small := _place("hull_15x5", Vector3.ZERO)
	await _ortho("profile", Vector3(60.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 19.0)
	await _ortho("bow_on", Vector3(0.0, WL + 0.6, -60.0), Vector3(0.0, WL + 0.6, 0.0), 9.0)
	await _ortho_plan("plan", 30.0)
	await _persp("bow_quarter", Vector3(-11.0, 4.2, -13.0), Vector3(0.0, WL + 0.8, -1.0))
	await _persp("stern_quarter", Vector3(10.0, 3.8, 13.0), Vector3(0.0, WL + 0.8, 1.0))
	small.free()
	await get_tree().process_frame

	var a := _place("hull_15x5", Vector3(0.0, 0.0, -17.0))
	var b := _place("hull_28x10", Vector3(0.0, 0.0, 7.0))
	await _ortho("beside_28x10", Vector3(90.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 60.0)
	a.free()
	b.free()
	await get_tree().process_frame

	var big := _place("hull_28x10", Vector3.ZERO)
	await _ortho("profile_28x10", Vector3(90.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 35.5)
	big.free()

	print("ITER SHOT DONE tag=%s" % _tag)
	## Stated on every run, because the header is not where anyone stands when
	## they put two of these frames side by side. Measured 2026-08-16 over three
	## runs of this rig with the clock pinned and `frame_post_draw` awaited.
	print(
		"REPRO FLOOR %d px — two runs of THIS rig still differ by up to that many "
		% REPRO_NOISE_FLOOR_PX
		+ "pixels (0.011%) at silhouette edges. A smaller difference between two of "
		+ "these frames is noise, not a change in the hull. Never md5-compare them. "
		+ "The shipped v0..v12 series predates the clock pin and is not "
		+ "frame-to-frame comparable at all."
	)
	get_tree().quit(0)


func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(_viewport)

	_world = Node3D.new()
	_viewport.add_child(_world)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.70, 0.78)
	env.ambient_light_energy = 0.85
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 138.0, 0.0)
	fill.light_energy = 0.45
	_world.add_child(fill)

	var sea := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(600.0, 40.0, 600.0)
	sea.mesh = box
	sea.position = Vector3(0.0, WL - 20.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sea.material_override = mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(sea)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.near = 0.05
	_camera.far = 800.0
	_world.add_child(_camera)


func _place(hull_id: String, at: Vector3) -> BoatBody:
	var boat := HullRegistry.build_hull(hull_id)
	boat.freeze = true
	_world.add_child(boat)
	boat.position = Vector3(at.x, WL - boat.draft_m - boat.hull_stations.keel_y, at.z)
	var figure := _make_figure()
	figure.position = Vector3(
		boat.beam_m * 0.20, boat.hull_stations.deck_y + 0.12, boat.length_m * 0.18
	)
	boat.add_child(figure)
	boat.set_meta("scale_figure", figure)
	return boat


func _figures() -> Array:
	var out: Array = []
	for child in _world.get_children():
		if child is BoatBody and child.has_meta("scale_figure"):
			out.append(child.get_meta("scale_figure"))
	return out


func _ortho(case: String, from: Vector3, look_at: Vector3, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case, "ortho %.1f m across" % width_m)


## Straight down. `look_at` with UP parallel to the view direction is degenerate —
## the old plan shot did exactly that and produced a 4.5 m crop of bare deck.
func _ortho_plan(case: String, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(Vector3(0.0, 60.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	await _save(case, "plan ortho %.1f m across" % width_m)


func _persp(case: String, from: Vector3, look_at: Vector3) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 40.0
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case, "persp 40 deg")


func _save(case: String, lens: String) -> void:
	var figures := _figures()
	for f in figures:
		f.visible = false
	await CaptureClock.settle(get_tree(), 4)
	var without := _viewport.get_texture().get_image()
	for f in figures:
		f.visible = true
	await CaptureClock.settle(get_tree(), 4)
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(
		"%s/%s__%s.png" % [OUT_DIR, _tag, case]
	))
	var moved := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := without.get_pixel(x, y)
			var b := image.get_pixel(x, y)
			if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
				moved += 1
	print("ITER %-8s %-16s %-22s figure_px=%d %s" % [
		_tag, case, lens, moved, "<<< FIGURE IN NO FRAME" if moved == 0 else "",
	])


func _make_figure() -> Node3D:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.98, 0.42, 0.05)
	body.material_override = suit
	figure.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.90, 0.74, 0.58)
	head.material_override = skin
	figure.add_child(head)
	return figure
