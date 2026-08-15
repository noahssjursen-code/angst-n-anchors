extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Photographs THE BOAT A NEW CAPTAIN IS ACTUALLY GIVEN, so a person can answer
## the only question a gate cannot: does this read as a boat someone would want
## to own? It is the first thing a player ever sees.
##
## The subject is not a hull id and not a JSON file — it is
## `CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)`
## spawned through `VesselSpawn.instantiate_from_record`, i.e. the same two calls
## onboarding makes. If the grant ever stops resolving, this rig photographs
## nothing rather than photographing a stand-in that looks fine.
##
## Rig rules are inherited from `tests/_small_hull_shot.gd` (CONVENTIONS §3a /
## REALITY §8) and are baked in rather than hoped for:
##   • a 1.8 m figure stands on deck in EVERY frame, and each frame is shot twice
##     (figure hidden / shown) so "visible" is MEASURED — a figure_px of 0 means
##     the scale reference appeared in no frame;
##   • the size views are ORTHOGRAPHIC with `keep_aspect = KEEP_WIDTH`, so the
##     camera's `size` is metres across the frame and no lens is inflating a
##     15 m boat;
##   • the profile is shot from −X, which is PORT. `profile_port` used to shoot
##     from +X and label starboard as port;
##   • pale sky so the silhouette has a boundary, translucent sea whose top is
##     exactly the waterline each hull is placed at by its own declared draft;
##   • shadows ON.
##
## The 28 m cargo starter is shot through the SAME rig at the SAME metres per
## pixel, because "is this the right boat for a beginner" is a comparison.

const OUT_DIR := "res://screenshots/vessels/starter"
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

	var granted := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if granted.is_empty():
		print("SHOT ABORTED — onboarding grants nothing for '%s'" % CompanyContracts.DEFAULT_STARTER)
		get_tree().quit(1)
		return
	print("SUBJECT  career=%s  hull=%s  name=%s  reg=%s" % [
		CompanyContracts.DEFAULT_STARTER,
		str(granted.get("hull_id", "")), str(granted.get("name", "")),
		str(granted.get("registration_id", "")),
	])

	var boat := _place(granted, Vector3.ZERO)
	if boat == null:
		print("SHOT ABORTED — the granted record would not spawn")
		get_tree().quit(1)
		return
	await _ortho("starter__profile_port_ortho", Vector3(-60.0, WL + 2.6, 0.0), Vector3(0.0, WL + 2.6, 0.0), 21.0)
	await _ortho("starter__bow_on_ortho", Vector3(0.0, WL + 2.4, -60.0), Vector3(0.0, WL + 2.4, 0.0), 11.0)
	await _ortho("starter__stern_on_ortho", Vector3(0.0, WL + 2.4, 60.0), Vector3(0.0, WL + 2.4, 0.0), 11.0)
	## KEEP_WIDTH: the frame is 16:9, so a plan view of a 15 m boat needs
	## 15 x 16/9 = 26.7 m ACROSS to fit its LENGTH. At 17 m it cropped both ends.
	await _ortho_plan("starter__plan_ortho", 28.0)
	await _persp("starter__bow_quarter", Vector3(-16.0, 6.6, -19.0), Vector3(0.0, WL + 1.4, -1.0))
	await _persp("starter__stern_quarter", Vector3(15.0, 6.0, 19.0), Vector3(0.0, WL + 1.4, 1.0))
	## Deck-level: what the captain sees standing on their own boat.
	await _persp("starter__on_deck", Vector3(1.6, WL + 3.4, 7.4), Vector3(0.0, WL + 2.0, -2.0))
	boat.free()
	await get_tree().process_frame

	## The boat a beginner used to be handed, same camera, same metres per pixel.
	var control := CompanyService.build_starter_vessel_record("general_cargo")
	var a := _place(granted, Vector3(0.0, 0.0, -14.0))
	var b := _place(control, Vector3(0.0, 0.0, 10.0))
	if a != null and b != null:
		await _ortho(
			"starter_beside_28m_cargo__ortho",
			Vector3(-90.0, WL + 0.6, 0.0), Vector3(0.0, WL + 0.6, 0.0), 56.0
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


func _place(record: Dictionary, at: Vector3) -> BoatBody:
	if record.is_empty():
		return null
	var boat := VesselSpawn.instantiate_from_record(record)
	if boat == null:
		return null
	boat.freeze = true
	boat.automatic_physics_lod = false
	_world.add_child(boat)
	boat.position = Vector3(at.x, WL - boat.draft_m - boat.hull_stations.keel_y, at.z)
	## TWO figures — one on the working deck abaft the house, one on the foredeck.
	## One aft figure alone is INVISIBLE from ahead: the deckhouse occludes it, and
	## the bow-on ortho (the frame whose whole job is beam) came back
	## `figure_px=0`, which is REALITY §8's "rendered perfectly, appeared in no
	## frame" in its third variant. Both are counted, every frame.
	var figures: Array[Node3D] = []
	var aft := _make_figure()
	aft.position = Vector3(
		boat.beam_m * 0.20, boat.hull_stations.deck_y + 0.12, boat.length_m * 0.18
	)
	boat.add_child(aft)
	figures.append(aft)
	var fwd := _make_figure()
	fwd.position = Vector3(
		-boat.beam_m * 0.18, boat.hull_stations.deck_y + 0.12, -boat.length_m * 0.28
	)
	boat.add_child(fwd)
	figures.append(fwd)
	boat.set_meta("scale_figures", figures)
	return boat


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


func _ortho_plan(case: String, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	## UP parallel to the view direction is a degenerate `look_at`; FORWARD is the
	## up-vector that gives a plan view with the bow up the frame (REALITY §8).
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
	print("SHOT %-40s %-22s figure_px=%d %s" % [
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
