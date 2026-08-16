extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## THE 28 m WHEELHOUSE ITERATION RIG. Same camera rig, sky, sea, shadows and
## two-pass figure count as `tests/_starter_28m_shot.gd`, so a frame here is
## comparable with the baseline frames in `screenshots/vessels/starter_28m/`.
## Writes to `screenshots/vessels/iter_house28/` under a variant tag passed as
## the first user arg, so a series accumulates instead of overwriting itself.
##
## It photographs the SHIPPED presets, so the loop is: edit `_prebuilt_gen.gd`,
## re-run it, re-run this. There is no second authoring path here to drift.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_house28_iter.tscn -- v1
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

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const OUT_DIR := "res://screenshots/vessels/iter_house28"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5
const CELL := 0.5

const SUBJECTS := ["fishing_trawler", "28_10_m", "bulk_small", "sjark_15m"]

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _variant := "v0"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_variant = str(arg).strip_edges()
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f (noon) — the HOUR is fixed; see this file's header for what that closes"
		% CaptureClock.pin(get_tree()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	for prebuilt_id in SUBJECTS:
		await _shoot(prebuilt_id)
	print("SHOT DONE")
	get_tree().quit(0)


func _shoot(prebuilt_id: String) -> void:
	var entry := {}
	for candidate in PrebuiltVesselCatalog.catalog_entries():
		if str(candidate.get("prebuilt_id", "")) == prebuilt_id:
			entry = candidate
			break
	if entry.is_empty():
		print("SHOT ABORTED — no preset '%s'" % prebuilt_id)
		return
	var hull_id := str(entry.get("hull_id", ""))
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var boat := VesselSpawn.instantiate(
		hull_id, layout_dict, str(entry.get("registration_id", ""))
	)
	if boat == null:
		print("SHOT ABORTED — '%s' would not spawn" % prebuilt_id)
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	_world.add_child(boat)
	## A layout over `DeckFitout.LARGE_LAYOUT_THRESHOLD` primaries spawns through
	## the STAGED job and is a bare hull for the first frames. v2 of this series
	## was photographed four frames after spawning at 1014 primaries and every
	## frame came back as an empty deck — the house was not missing, it had not
	## been built yet (`v2__*` in this directory is that evidence). Wait for the
	## readiness the job publishes rather than assuming the sync path.
	DeckFitout.request_full_detail(boat)
	var spins := 0
	while DeckFitout.readiness_of(boat) < DeckFitout.READINESS_FULL_VISUAL and spins < 900:
		spins += 1
		await get_tree().process_frame
	if spins > 0:
		print("    STAGED — waited %d frames for readiness %d" % [
			spins, DeckFitout.readiness_of(boat),
		])
	boat.position = Vector3(0.0, WL - boat.draft_m - boat.hull_stations.keel_y, 0.0)

	## Where the house is on THIS preset — forward on the trawler, aft on the two
	## coasters — taken from the roof-tagged cells rather than typed.
	var grid := HullRegistry.make_grid(hull_id)
	var layout := BrickLayout.from_dict(layout_dict)
	## ── THE FIGURE STOOD INSIDE THE HOUSE, a1 -> a2 (REALITY.md §8) ────────────
	##
	## `z_lo` / `z_hi` used to be taken from the ROOF-tagged cells only, and the
	## near figure was parked at `house_z + 2.4` — a constant that fitted clear of
	## a 4.0 m house and lands INSIDE a 7.5 m one. It rendered perfectly and was
	## visible only THROUGH the accommodation windows, which is why every a1
	## `house_profile_ortho` reported the same `figure_px=1229` on all three 28 m
	## presets, and why cutting that tier to one row of windows in a2 dropped it to
	## **0 — figure in no frame**. Same failure as the sjark capture that put the
	## figure in the wheelhouse, one wave later.
	##
	## Two corrections, both derived: the house extent is every cell ABOVE the deck
	## level (the roof plan is only the top tier, which on a two-tier house stops
	## 2.0 m short of the after face), and the figure stands 1.2 m clear of the
	## near face on whichever side the open working deck is.
	var z_lo := 1e9
	var z_hi := -1e9
	var roof_top := 0.0
	for item in layout.iter_primary_cells():
		var c: Vector3i = item["cell"]
		if c.y < 1:
			continue
		var z := -grid.half_loa + (float(c.z) + 0.5) * CELL
		z_lo = minf(z_lo, z)
		z_hi = maxf(z_hi, z)
		if BrickCatalog.has_tag(str(item.get("brick_id", "")), "roof"):
			roof_top = maxf(roof_top, float(c.y + 1) * CELL)
	var house_z := (z_lo + z_hi) * 0.5
	var deck_y := boat.position.y + boat.hull_stations.deck_y
	print("SUBJECT %-16s hull=%s  %.1f x %.1f m  house z %+.2f..%+.2f  deck at y=%.2f  roof %.2f m above deck" % [
		prebuilt_id, hull_id, boat.length_m, boat.beam_m,
		z_lo - CELL * 0.5, z_hi + CELL * 0.5, deck_y, roof_top,
	])

	## Figures: one hard against the deckhouse's face that the open working deck
	## presents, which is the whole comparison — a 1.8 m person standing beside a
	## house drawn for a 15 m boat — and one further off so no frame is figure-less.
	var open_dir := -1.0 if house_z > 0.0 else 1.0
	var near_face := (z_lo - CELL * 0.5) if open_dir < 0.0 else (z_hi + CELL * 0.5)
	var figures: Array[Node3D] = []
	var beside := _make_figure()
	beside.position = Vector3(
		boat.beam_m * 0.14, boat.hull_stations.deck_y + 0.12, near_face + open_dir * 1.2
	)
	boat.add_child(beside)
	figures.append(beside)
	var far := _make_figure()
	far.position = Vector3(
		-boat.beam_m * 0.16, boat.hull_stations.deck_y + 0.12,
		house_z - 8.0 if house_z > 0.0 else house_z + 8.0
	)
	boat.add_child(far)
	figures.append(far)
	boat.set_meta("scale_figures", figures)

	var tag := "%s__%s" % [_variant, prebuilt_id]
	var frame_m := boat.length_m * 1.22
	await _ortho(tag + "__profile_port_ortho",
		Vector3(-90.0, WL + 3.4, 0.0), Vector3(0.0, WL + 3.4, 0.0), frame_m)
	## The house alone, at 11 m across — roughly the framing the sjark's own
	## profile shot uses, so the two houses are comparable at the same scale.
	var house_eye := deck_y + roof_top * 0.55
	await _ortho(tag + "__house_profile_ortho",
		Vector3(-90.0, house_eye, house_z), Vector3(0.0, house_eye, house_z),
		maxf(11.0, boat.beam_m * 1.5))
	await _ortho(tag + "__bow_on_ortho",
		Vector3(0.0, house_eye, -90.0), Vector3(0.0, house_eye, 0.0), boat.beam_m * 1.7)
	await _persp(tag + "__bow_quarter",
		Vector3(-boat.length_m * 0.86, boat.length_m * 0.39, -boat.length_m * 1.07),
		Vector3(0.0, WL + 2.4, -2.0))
	## Deck level, standing where the figure stands.
	## Standing on the working deck looking at the after face, far enough back
	## that the whole house is in frame — the shot the "cottage gable" reading
	## came from.
	## Two eye-level frames, because the house has two faces a person stands in
	## front of and the complaint that started this wave was about the AFTER one.
	## `__on_deck` looks at whichever face the open working deck presents;
	## `__stern_quarter` comes at it from astern.
	await _persp(tag + "__on_deck",
		Vector3(
			boat.beam_m * 0.26, deck_y + 1.7,
			house_z + open_dir * maxf(boat.length_m * 0.62, 14.0)
		),
		Vector3(0.0, deck_y + roof_top * 0.45, house_z))
	await _persp(tag + "__stern_quarter",
		Vector3(
			-boat.beam_m * 2.10, deck_y + boat.length_m * 0.30,
			boat.length_m * 1.05
		),
		Vector3(0.0, deck_y + roof_top * 0.40, house_z))
	boat.free()
	await get_tree().process_frame


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
	_camera.far = 900.0
	_world.add_child(_camera)


func _figures() -> Array:
	var out: Array = []
	for child in _world.get_children():
		if child is BoatBody and child.has_meta("scale_figures"):
			out.append_array(child.get_meta("scale_figures") as Array)
	return out


func _ortho(case: String, from: Vector3, look_at: Vector3, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case, "ortho %.1f m across" % width_m)


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
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, case]))
	var moved := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := without.get_pixel(x, y)
			var b := image.get_pixel(x, y)
			if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
				moved += 1
	print("SHOT %-44s %-22s figure_px=%d %s" % [
		case, lens, moved, "<<< FIGURE IN NO FRAME" if moved == 0 else "",
	])


func _make_figure() -> Node3D:
	## 1.8 m overall: a 1.5 m capsule with a 0.28 m head.
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
