extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B.
##
## Photographs the new small hull so a person can judge it. Rules from
## CONVENTIONS §3a / REALITY §8 are baked in rather than hoped for:
##   • a 1.8 m figure stands on the deck of EVERY vessel in EVERY frame, and each
##     frame is shot twice (figure hidden / shown) so "visible" is MEASURED, not
##     assumed — the figure-pixel count is printed and a 0 is a broken capture;
##   • the size views are ORTHOGRAPHIC with `keep_aspect = KEEP_WIDTH`, so the
##     camera's `size` is metres across the frame and nothing about the scale is
##     left to a lens. A 15 m boat is exactly where a perspective lens lies;
##   • pale sky, so the silhouette has a boundary against its ground;
##   • the sea is a TRANSLUCENT slab whose top is exactly
##     `WaveSurface.WATER_LEVEL`, and each hull is placed by its own declared
##     draft — so the waterline in the picture is the waterline in the physics,
##     and the underwater body is still readable through it;
##   • shadows are ON. `DirectionalLight3D.shadow_enabled` defaults to false and
##     cost this project a full day of "the art looks flat".
##
## hull_28x10 is shot through the SAME rig at the SAME metres-per-pixel, because
## "does the small hull read as a shrunken trawler" is a comparison and cannot be
## answered from one picture.

const OUT_DIR := "res://screenshots/vessels"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5 ## WaveSurface.WATER_LEVEL, named here so the rig is standalone

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()

	## ── the small hull, alone, tight ────────────────────────────────────────
	var small := _place("hull_15x5", Vector3.ZERO)
	await _ortho("hull_15x5__profile_ortho", Vector3(60.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 19.0)
	await _ortho("hull_15x5__bow_on_ortho", Vector3(0.0, WL + 0.6, -60.0), Vector3(0.0, WL + 0.6, 0.0), 9.0)
	## Straight down. `look_at` with UP parallel to the view direction is degenerate,
	## and 8 m across on a 15 m boat cropped to a patch of bare deck — the old call did
	## both and the frame it produced showed no boat at all (REALITY §8).
	await _ortho_plan("hull_15x5__plan_ortho", 30.0)
	await _persp("hull_15x5__bow_quarter", Vector3(-11.0, 4.2, -13.0), Vector3(0.0, WL + 0.8, -1.0))
	await _persp("hull_15x5__stern_quarter", Vector3(10.0, 3.8, 13.0), Vector3(0.0, WL + 0.8, 1.0))
	small.free()
	await get_tree().process_frame

	## ── the 28 m hull, alone, through the SAME rig at the SAME m/px ─────────
	var big := _place("hull_28x10", Vector3.ZERO)
	await _ortho("hull_28x10__profile_ortho_control", Vector3(90.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 35.5)
	big.free()
	await get_tree().process_frame

	## ── both, one camera, one scale ─────────────────────────────────────────
	var a := _place("hull_15x5", Vector3(0.0, 0.0, -17.0))
	var b := _place("hull_28x10", Vector3(0.0, 0.0, 7.0))
	await _ortho(
		"hull_15x5_beside_hull_28x10__ortho",
		Vector3(90.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 60.0
	)
	a.free()
	b.free()

	print("SHOT DONE")
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

	## Translucent slab, top face exactly at WL and 40 m deep, so it fills the
	## lower half of every frame and a hull that floated too low would visibly
	## sink into it rather than run off the bottom of the water.
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
	## Placed by the hull's OWN declared draft, so the picture and the physics
	## agree about where the waterline is.
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
	for _frame in range(4):
		await get_tree().process_frame
	var without := _viewport.get_texture().get_image()
	for f in figures:
		f.visible = true
	for _frame in range(4):
		await get_tree().process_frame
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, case]))
	var moved := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := without.get_pixel(x, y)
			var b := image.get_pixel(x, y)
			if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
				moved += 1
	print("SHOT %-46s %-20s figure_px=%d %s" % [
		case, lens, moved, "<<< FIGURE IN NO FRAME" if moved == 0 else "",
	])


func _make_figure() -> Node3D:
	## 1.8 m overall: a 1.5 m capsule with a 0.28 m head, matching
	## `hull_visual_capture` and the studio mannequin.
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
