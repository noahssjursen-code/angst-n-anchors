extends Node

## SCRATCH PROBE (leading underscore — the gate must not discover it). Lane B.
##
## Photographs the catalogue fittings now that they draw, so a person can judge
## them. Before this wave every one of these frames would have been empty deck.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_fittings_shot.tscn
##
## The rig is `_small_hull_shot.gd`'s, unchanged where it can be, for the reasons
## that file argues (REALITY §8, CONVENTIONS §3a):
##   • ORTHOGRAPHIC with `keep_aspect = KEEP_WIDTH`, so the camera's `size` is
##     metres across the frame — a bollard is exactly the thing a perspective
##     lens lies about;
##   • a 1.8 m figure in EVERY frame, and every frame shot twice (figure hidden /
##     shown) so "visible" is MEASURED — the figure-pixel count is printed and a
##     0 means the frame has no scale reference at all;
##   • pale sky, so a mast has a boundary against its ground;
##   • shadows ON.
##
## Two subjects. The KIT SHEET stands one of every part in a row on bare ground
## beside the figure, which is the frame that answers "is a bollard bollard-sized".
## The VESSEL puts them on `hull_28x10` through `VesselSpawn` -> `apply_plan`,
## which is the frame that answers "does this read as a working boat".
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
## ══ AND IT IS STILL NOT REPRODUCIBLE. THE CLOCK PIN IS NOT ENOUGH HERE. ════
##
## Two back-to-back runs of this rig agree exactly (7 frames, 0.0000%) — which
## is why the drift was invisible. Two runs **six real minutes apart**, with the
## clock pinned and `frame_post_draw` awaited, still move **2 of 7 frames, by
## 3.4908% (`vessel__bow_quarter`) and 3.7904% (`vessel__deck_close`)**.
##
## `CaptureClock.pin` pins the HOUR and not the WEATHER, and the weather is on
## the same wall clock by another route: `WeatherField.current_game_time()`
## calls `WorldClock.get_game_hours_elapsed()`, which is computed live from
## `Time.get_unix_time_from_system()` whether or not `WorldClock` is processing.
## `ShipLighting._update_auto_nav` reads `fog_density` as well as daylight. Nine
## other rigs closed completely with the hour pinned; this one did not, and the
## remaining path was identified but NOT closed (REALITY §6).
##
## **So: two frames from this rig are comparable only above about 3.8% of
## pixels. Never md5-compare them.** Stated on stdout on every run.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
## Measured 2026-08-16, two runs six real minutes apart with the clock pinned.
const REPRO_FLOOR_PCT := 3.8
const OUT_DIR := "res://screenshots/vessels/fittings"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5 ## WaveSurface.WATER_LEVEL, named here so the rig is standalone
const HULL_ID := "hull_28x10"
const REGISTRATION := "general_vessel"

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _figures: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f (noon) — the HOUR is fixed; see this file's header for what that closes"
		% CaptureClock.pin(get_tree()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	await _kit_sheet()
	await _on_the_vessel()
	print("SHOT DONE")
	print(
		"REPRO FLOOR %.1f%% — two runs of THIS rig minutes apart still differ by up to "
		% REPRO_FLOOR_PCT
		+ "that fraction of the frame. The clock pin fixes the HOUR, not the WEATHER "
		+ "(WeatherField reads the Unix clock directly). A smaller difference between "
		+ "two of these frames is noise. Never md5-compare them."
	)
	get_tree().quit(0)


# ── 1. The kit sheet ─────────────────────────────────────────────────────────

func _kit_sheet() -> void:
	var ground := _ground()
	_world.add_child(ground)
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	var ids := PartCatalog.ids()
	var x := 0.0
	var spacing := 4.0
	var labels := PackedStringArray()
	for id_variant in ids:
		var id := str(id_variant)
		plan.add_item(id, Vector3(x, 0.0, 0.0))
		labels.append("%.1f m: %s" % [x, id])
		x += spacing
	var baked := StructureBaker.bake(plan)
	_world.add_child(baked)
	print("[fit] kit sheet holds %d parts across %.1f m: %s"
		% [ids.size(), x - spacing, ", ".join(labels)])

	var figure := _make_figure()
	figure.position = Vector3(-3.0, 0.0, 0.0)
	_world.add_child(figure)
	_figures = [figure]

	var centre := Vector3((x - spacing) * 0.5 - 1.0, 2.4, 0.0)
	await _ortho("kit_sheet__elevation", centre + Vector3(0.0, 0.0, -70.0), centre, x + 6.0)
	## Half the row, twice the magnification — at 64 m across a 0.55 m bollard is
	## a dozen pixels and nothing about it can be judged.
	var left := Vector3(8.0, 2.0, 0.0)
	figure.position = Vector3(-1.6, 0.0, 0.0)
	await _ortho("kit_sheet__elevation_left", left + Vector3(0.0, 0.0, -70.0), left, 26.0)
	var right := Vector3(38.0, 2.0, 0.0)
	figure.position = Vector3(26.5, 0.0, 0.0)
	await _ortho("kit_sheet__elevation_right", right + Vector3(0.0, 0.0, -70.0), right, 26.0)
	## Raking, because a row of round members reads flat dead square on. The
	## figure goes NEXT TO THE SUBJECT rather than at the row's origin — the first
	## take left it behind the camera and reported figure_px=0, which is REALITY
	## §8's "rendered perfectly, appeared in zero frames" for the third time in
	## this project.
	figure.position = Vector3(10.0, 0.0, 2.6)
	await _persp("kit_sheet__quarter", Vector3(-6.0, 6.0, -22.0), Vector3(14.0, 2.0, 0.0))

	baked.free()
	figure.free()
	ground.free()
	_figures = []
	await get_tree().process_frame


# ── 2. On the vessel, through the production path ────────────────────────────

func _on_the_vessel() -> void:
	var sea := _sea()
	_world.add_child(sea)
	var plan := _vessel_plan()
	_report_refusals(plan)
	var boat: BoatBody = VesselSpawn.instantiate(HULL_ID, plan.to_dict(), REGISTRATION)
	if boat == null:
		printerr("[fit] VesselSpawn returned null")
		return
	boat.freeze = true
	_world.add_child(boat)
	boat.position = Vector3(0.0, WL - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	await get_tree().physics_frame

	var deck_y: float = boat.hull_stations.deck_y
	var figure := _make_figure()
	## Amidships on the working deck, on the near side so nothing stands between
	## it and the camera — and clear of the funnel, in front of which the first
	## take put it (REALITY §8: a figure that renders perfectly against a white
	## drum has no read).
	figure.position = Vector3(-2.2, deck_y + 0.10, -3.0)
	boat.add_child(figure)
	_figures = [figure]

	var centre := Vector3(0.0, WL + 2.6, 0.0)
	await _ortho("vessel__profile", centre + Vector3(-90.0, 0.0, 0.0), centre, 34.0)
	## The working deck, close: the frame that shows whether a bollard is
	## something a person ties a rope to or a bump in the paint.
	var deck := Vector3(0.0, WL + 2.2, 6.0)
	figure.position = Vector3(-2.2, deck_y + 0.10, 4.0)
	await _ortho("vessel__deck_close", deck + Vector3(-60.0, 0.0, 0.0), deck, 12.0)
	await _persp("vessel__bow_quarter", Vector3(-16.0, 8.0, -18.0), Vector3(0.0, WL + 2.0, -2.0))
	_figures = []


## A working arrangement rather than a row: bollards down both deck edges, the
## mast amidships with the lantern on it, the gallows aft, a helm console and a
## bench in the working space, a hold coaming forward. Plan space is grid-corner
## space — x in [0, beam], z in [0, loa] — so the centreline of a 10 m hull is
## x = 5 and the hull runs z 0..28.
func _vessel_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	plan.add_deck(Vector3(1.0, 0.0, 3.0), Vector2(8.0, 22.0))
	for z in [5.0, 10.0, 18.0, 24.0]:
		plan.add_item("bollard_pair", Vector3(1.6, 0.0, float(z)), 90.0)
		plan.add_item("bollard_pair", Vector3(8.4, 0.0, float(z)), 90.0)
	plan.add_item("hold_coaming", Vector3(5.0, 0.0, 8.5), 0.0, {"length": 5.0, "width": 4.0})
	plan.add_item("mast_with_platform", Vector3(5.0, 0.0, 14.0), 0.0, {"height": 7.5})
	plan.add_item("lantern_all_round", Vector3(5.0, 7.5, 14.0))
	plan.add_item("funnel_tapered", Vector3(3.4, 0.0, 16.5))
	plan.add_item("helm_console", Vector3(5.0, 0.0, 20.0), 180.0)
	plan.add_item("bench_seat", Vector3(6.8, 0.0, 21.5), 180.0)
	plan.add_item("gallows_a_frame", Vector3(5.0, 0.0, 25.5), 0.0, {"height": 4.2, "spread": 4.6})
	plan.add_item("net_drum", Vector3(5.0, 0.0, 23.2), 90.0)
	## A `railing_run` runs along its own +X; yaw -90 turns +X onto +Z. Yaw +90
	## turns it onto -Z, which ran both rails off the bow — `PlanOutfit` refused
	## them and NOTHING WAS DRAWN, which is exactly the failure this whole wave is
	## about, reproduced in the capture rig. Hence `_report_refusals` below: a rig
	## that can silently photograph less than it was given is not evidence.
	plan.add_item("railing_run", Vector3(1.4, 0.0, 4.0), -90.0, {"length": 9.0})
	plan.add_item("railing_run", Vector3(8.6, 0.0, 4.0), -90.0, {"length": 9.0})
	return plan


func _report_refusals(plan: StructurePlan) -> void:
	var grid := HullRegistry.make_grid(HULL_ID)
	var off := PlanOutfit.off_hull_entities(StructureBaker.resolved(plan), grid)
	if off.is_empty():
		print("[fit] all %d plan entities are on the hull — the frame holds everything"
			% plan.entity_count())
		return
	for row_variant in off:
		var row := row_variant as Dictionary
		printerr("[fit] REFUSED %s %d — IT WILL BE IN NO FRAME"
			% [str(row["kind"]), int(row["id"])])


# ── Stage ────────────────────────────────────────────────────────────────────

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

	_camera = Camera3D.new()
	_camera.current = true
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.near = 0.05
	_camera.far = 900.0
	_world.add_child(_camera)


func _ground() -> Node3D:
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(300.0, 1.0, 60.0)
	slab.mesh = box
	slab.position = Vector3(30.0, -0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.47, 0.45)
	mat.roughness = 0.95
	slab.material_override = mat
	return slab


func _sea() -> Node3D:
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
	return sea


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
	for f in _figures:
		(f as Node3D).visible = false
	await CaptureClock.settle(get_tree(), 4)
	var without := _viewport.get_texture().get_image()
	for f in _figures:
		(f as Node3D).visible = true
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
	print("SHOT %-36s %-22s figure_px=%d %s" % [
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
