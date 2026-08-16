extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Lane B.
##
## `tests/_starter_shot.gd` reproduced verbatim EXCEPT that every frame is md5'd
## instead of written, and the parts suspected of costing reproducibility can be
## switched off one at a time. Run it twice per variant and compare the md5 list.
##
##   -- full      everything the shot rig does (figures, hide/show, pixel loop)
##   -- nocount   drop the 1.44 M-sample GDScript pixel loop
##   -- nofigure  drop the two scale figures entirely
##   -- postdraw  keep everything, but await RenderingServer.frame_post_draw
##   -- onlyfirst shoot the first view and stop

const WL := -1.5

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _mode := "full"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		_mode = str(a)
	call_deferred("_run")


func _run() -> void:
	_build_stage()
	var granted := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	var boat := _place(granted, Vector3.ZERO)
	await _ortho("profile_port_ortho", Vector3(-60.0, WL + 2.6, 0.0), Vector3(0.0, WL + 2.6, 0.0), 21.0)
	if _mode != "onlyfirst":
		await _ortho("bow_on_ortho", Vector3(0.0, WL + 2.4, -60.0), Vector3(0.0, WL + 2.4, 0.0), 11.0)
		await _ortho("stern_on_ortho", Vector3(0.0, WL + 2.4, 60.0), Vector3(0.0, WL + 2.4, 0.0), 11.0)
		await _ortho_plan("plan_ortho", 28.0)
		await _persp("bow_quarter", Vector3(-16.0, 6.6, -19.0), Vector3(0.0, WL + 1.4, -1.0))
		await _persp("stern_quarter", Vector3(15.0, 6.0, 19.0), Vector3(0.0, WL + 1.4, 1.0))
		await _persp("on_deck", Vector3(1.6, WL + 3.4, 7.4), Vector3(0.0, WL + 2.0, -2.0))
	boat.free()
	await get_tree().process_frame
	print("BISECT DONE mode=%s frames=%d" % [_mode, Engine.get_process_frames()])
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
	env.background_color = Color(0.80, 0.85, 0.90)
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
	mat.albedo_color = Color(0.13, 0.32, 0.40, 0.62)
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
	var boat := VesselSpawn.instantiate_from_record(record)
	boat.freeze = true
	boat.automatic_physics_lod = false
	_world.add_child(boat)
	boat.position = Vector3(at.x, WL - boat.draft_m - boat.hull_stations.keel_y, at.z)
	if _mode == "nofigure":
		boat.set_meta("scale_figures", [] as Array[Node3D])
		return boat
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
	await _save(case)


func _ortho_plan(case: String, width_m: float) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = width_m
	_camera.look_at_from_position(Vector3(0.0, 60.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	await _save(case)


func _persp(case: String, from: Vector3, look_at: Vector3) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 40.0
	_camera.look_at_from_position(from, look_at, Vector3.UP)
	await _save(case)


func _save(case: String) -> void:
	var figures := _figures()
	for f in figures:
		f.visible = false
	for _frame in range(4):
		await get_tree().process_frame
	if _mode == "postdraw":
		await RenderingServer.frame_post_draw
	var without := _viewport.get_texture().get_image()
	for f in figures:
		f.visible = true
	for _frame in range(4):
		await get_tree().process_frame
	if _mode == "postdraw":
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(image.get_data())
	var moved := -1
	if _mode != "nocount":
		moved = 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var a := without.get_pixel(x, y)
				var b := image.get_pixel(x, y)
				if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
					moved += 1
	print("BISECT %-24s mode=%-9s md5=%s figure_px=%d at_frame=%d" % [
		case, _mode, ctx.finish().hex_encode(), moved, Engine.get_process_frames(),
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
