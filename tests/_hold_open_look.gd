extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## ONE QUESTION: if the hatch boards were simply taken away, would a player see
## the catch — or does the hull's own deck plate stand in the way?
##
## `tests/_hold_shot.gd`'s header asserts the plate "is an opaque slab spanning
## the whole deck, including the hatch, so everything the hold draws below the
## deck plane … is behind it in every normal view", and `bd548bc`'s message
## asserts the opposite — "the chilled water and fish read as a pool at deck
## level from any angle". Two claims about the same mesh, so one of them is
## wrong (REALITY §4a: the disagreement is the finding). This shoots it.
##
## Frames, all the same camera, filled to 3900 kg:
##   boards            what ships today
##   open_naive        every hatch-board MESH hidden, nothing else touched
##   open_no_plate     the same, plus HullVisual/Deck hidden — the control that
##                     separates "the plate hides it" from "nothing is drawn"

const OUT_DIR := "res://screenshots/vessels/hold"
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const WL := -1.5

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_stage()
	var granted := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	var boat := VesselSpawn.instantiate_from_record(granted)
	if boat == null:
		print("ABORT: no spawn")
		get_tree().quit(1)
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	_world.add_child(boat)
	boat.position = Vector3(0.0, WL - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	for _i in range(3):
		await get_tree().physics_frame

	var hold := CatchHoldComponent.first_for_ship(boat)
	if hold == null:
		print("ABORT: no hold")
		get_tree().quit(1)
		return
	## THE BOARDS ARE A PRECONDITION ON EVERY PATH THAT MOVES CATCH — 2026-08-16.
	## Without this the fills below are refused and every frame photographs an
	## empty hold while the print-out still claims a mass.
	hold.set_hatch_open(true)
	hold.accept_lot(CatchLot.create({"lot_id": "look", "mass_kg": 3900.0}))
	var hl := boat.to_local(hold.global_position)

	## The three planes this whole decision turns on, printed rather than recalled.
	var plate := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if plate != null:
		var pb := (boat.global_transform.affine_inverse() * plate.global_transform) * plate.get_aabb()
		print("DECK PLATE mesh y %.3f..%.3f  x %.3f..%.3f  z %.3f..%.3f  surfaces=%d"
			% [pb.position.y, pb.end.y, pb.position.x, pb.end.x, pb.position.z, pb.end.z,
				plate.mesh.get_surface_count()])
		var mat := plate.material_override as StandardMaterial3D
		print("DECK PLATE material transparency=%s cull=%s"
			% [str(mat.transparency) if mat != null else "?",
				str(mat.cull_mode) if mat != null else "?"])
	var water := hold.get_node_or_null("FishAndChilledWater")
	if water != null:
		for node in water.get_children():
			var mi := node as MeshInstance3D
			if mi == null:
				continue
			var wb := (boat.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			print("WATER SURFACE mesh y %.3f..%.3f" % [wb.position.y, wb.end.y])
			break
	print("HOLD deck plane y=%.3f  footprint=%v" % [hl.y, hold.footprint_m])

	var centre := boat.to_global(hl)
	await _persp("hold__probe__boards", centre + Vector3(4.6, 3.4, 4.6), centre + Vector3(0, 0.4, 0))
	await _ortho_plan("hold__probe__boards_plan", centre, 4.4)

	var boards: Array[MeshInstance3D] = []
	var solid := hold.get_node_or_null("OpenRswFishHold")
	for node in solid.get_children():
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var b := (boat.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		## The boards are the only meshes that span the clear opening above the
		## deck plane; identified by that property, not by child index.
		if b.position.y > hl.y + 0.05 and b.size.x > hold.footprint_m.x * 0.4:
			boards.append(mi)
	print("HATCH BOARD meshes found: %d" % boards.size())
	for mi in boards:
		mi.visible = false
	await _persp("hold__probe__open_naive", centre + Vector3(4.6, 3.4, 4.6), centre + Vector3(0, 0.4, 0))
	await _ortho_plan("hold__probe__open_naive_plan", centre, 4.4)

	if plate != null:
		plate.visible = false
		await _persp("hold__probe__open_no_plate",
			centre + Vector3(4.6, 3.4, 4.6), centre + Vector3(0, 0.4, 0))
		await _ortho_plan("hold__probe__open_no_plate_plan", centre, 4.4)
		plate.visible = true

	## HOW FAR DOWN CAN YOU SEE? The plate is a solid slab spanning the hatch, so
	## a fill stage whose surface is below the plate is hidden whatever the boards
	## do. Shot at four fills, boards still hidden, plate back.
	for pct in [0.05, 0.25, 0.50, 0.97]:
		hold.withdraw_oldest(hold.get_state().total_mass_kg())
		hold.accept_lot(CatchLot.create({
			"lot_id": "fill%d" % int(pct * 100.0), "mass_kg": 4000.0 * pct,
		}))
		var surface := -1000.0
		for node in hold.get_node("FishAndChilledWater").get_children():
			var mi := node as MeshInstance3D
			if mi == null:
				continue
			surface = ((boat.global_transform.affine_inverse() * mi.global_transform)
				* mi.get_aabb()).end.y
			break
		print("FILL %3d%%  water surface y=%.3f  (plate slab %.3f..%.3f)"
			% [int(pct * 100.0), surface, 2.600, 2.700])
		await _persp("hold__probe__fill%02d" % int(pct * 100.0),
			centre + Vector3(4.6, 3.4, 4.6), centre + Vector3(0, 0.4, 0))
	print("LOOK DONE")
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


func _persp(case: String, from: Vector3, look_at: Vector3) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 42.0
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case)


func _ortho_plan(case: String, centre: Vector3, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(centre + Vector3(0.0, 40.0, 0.0), centre, Vector3.FORWARD)
	await _save(case)


func _save(case: String) -> void:
	for _frame in range(4):
		await get_tree().process_frame
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, case]))
	print("SHOT %s" % case)
