extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Photographs THE FISH HOLD on the boat a new captain is granted, close enough
## to answer "what does a person standing here see, and what are their feet on".
##
## Rig rules inherited from `tests/_starter_shot.gd` (CONVENTIONS §3a / REALITY §8):
##   • a 1.8 m figure in EVERY frame, shot twice (hidden / shown) so `figure_px`
##     MEASURES visibility rather than asserting placement;
##   • the on-hatch figure's feet are placed at the height PhysicsServer3D says a
##     capsule would rest at, so the picture and the physics cannot disagree —
##     if the deck spans the hatch the figure stands on the deck, and if a hatch
##     cover carries it the figure stands on the cover;
##   • the size views are ORTHOGRAPHIC with KEEP_WIDTH, so `size` is metres
##     across the frame;
##   • plan view uses Vector3.FORWARD as the up-vector — UP is degenerate there;
##   • pale sky, shadows on.
##
## One frame is a CUTAWAY: the hull's own `Deck` plate mesh is hidden. That plate
## is an opaque slab spanning the whole deck, including the hatch, so everything
## the hold draws below the deck plane — liner, pit floor, chilled water, fish —
## is behind it in every normal view. The cutaway is the only way to see what is
## actually drawn down there.

const OUT_DIR := "res://screenshots/vessels/hold"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _tag := "before"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_tag = str(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()

	var granted := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if granted.is_empty():
		print("SHOT ABORTED — onboarding grants nothing")
		get_tree().quit(1)
		return
	var boat := VesselSpawn.instantiate_from_record(granted)
	if boat == null:
		print("SHOT ABORTED — the granted record would not spawn")
		get_tree().quit(1)
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	_world.add_child(boat)
	boat.position = Vector3(0.0, WL - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var holds := CatchHoldComponent.get_all_for_ship(boat)
	if holds.is_empty():
		print("SHOT ABORTED — the granted boat has no catch hold")
		get_tree().quit(1)
		return
	var hold: CatchHoldComponent = holds[0]
	var hl := boat.to_local(hold.global_position)
	print("HOLD boat-local %v footprint %v" % [hl, hold.footprint_m])

	## Where physics says a person's feet land over the middle of the hatch.
	var stand_y := _support_y(boat, Vector3(hl.x, hl.y + 3.0, hl.z))
	print("SUPPORT over the hatch centre: boat-local y=%.3f (hold deck plane y=%.3f)"
		% [stand_y, hl.y])
	var on_hatch := _make_figure()
	on_hatch.position = Vector3(hl.x, stand_y, hl.z)
	boat.add_child(on_hatch)
	var beside_y := _support_y(boat, Vector3(hl.x, hl.y + 3.0, hl.z + hold.footprint_m.z * 0.5 + 0.7))
	var beside := _make_figure()
	beside.position = Vector3(hl.x, beside_y, hl.z + hold.footprint_m.z * 0.5 + 0.7)
	boat.add_child(beside)
	var figures: Array[Node3D] = [on_hatch, beside]
	boat.set_meta("scale_figures", figures)

	var world_centre := boat.to_global(Vector3(hl.x, hl.y, hl.z))
	## EMPTY first — that is the state a working boat is in most of the time, and
	## the fill visual hides what the aperture itself looks like.
	await _persp("hold__%s__empty_quarter" % _tag,
		world_centre + Vector3(4.6, 3.4, 4.6), world_centre + Vector3(0.0, 0.4, 0.0))
	await _ortho_plan("hold__%s__empty_plan_ortho" % _tag, world_centre, 6.0)
	## Then filled: the chilled water and the fish scatter are drawn only when
	## there is catch aboard.
	hold.accept_lot(CatchLot.create({"lot_id": "shot", "mass_kg": 3900.0}))
	await _persp("hold__%s__quarter" % _tag,
		world_centre + Vector3(4.6, 3.4, 4.6), world_centre + Vector3(0.0, 0.4, 0.0))
	await _persp("hold__%s__eye_level" % _tag,
		world_centre + Vector3(0.9, 1.7, 4.2), world_centre + Vector3(0.0, 0.3, 0.0))
	## From ASTERN. The deckhouse stands forward of the hold on this boat, so a
	## bow-on ortho photographs the back of the house and puts both figures
	## behind glazing — measured, figure_px 1408 (REALITY §8: check the camera).
	await _ortho("hold__%s__section_ortho" % _tag,
		world_centre + Vector3(0.0, 0.9, 40.0), world_centre + Vector3(0.0, 0.9, 0.0), 6.0)
	await _ortho_plan("hold__%s__plan_ortho" % _tag, world_centre, 6.0)

	## Cutaway: hide the hull's opaque deck plate and shoot the same quarter.
	var deck_plate := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if deck_plate != null:
		deck_plate.visible = false
		await _persp("hold__%s__cutaway_no_deck_plate" % _tag,
			world_centre + Vector3(4.6, 3.4, 4.6), world_centre + Vector3(0.0, -0.3, 0.0))
		deck_plate.visible = true
	else:
		print("NO DECK PLATE NODE — cutaway skipped")

	print("SHOT DONE")
	get_tree().quit(0)


func _support_y(boat: BoatBody, from_local: Vector3) -> float:
	var space := boat.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		boat.to_global(from_local),
		boat.to_global(from_local - Vector3(0.0, 8.0, 0.0)),
		BoatBody.LAYER_BOAT_WALK,
	)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return from_local.y
	return boat.to_local(hit["position"] as Vector3).y


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


func _ortho_plan(case: String, centre: Vector3, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(
		centre + Vector3(0.0, 40.0, 0.0), centre, Vector3.FORWARD
	)
	await _save(case, "plan ortho %.1f m across" % width_m)


func _persp(case: String, from: Vector3, look_at: Vector3) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 42.0
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case, "persp 42 deg")


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
	print("SHOT %-42s %-22s figure_px=%d %s" % [
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
