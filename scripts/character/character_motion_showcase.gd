extends Node3D

## Runnable motion review: same imported rig and clips as gameplay.
var actors: Array[CharacterVisual] = []
var clips := [&"idle", &"walk", &"run"]
var _rig_lines: Array[MeshInstance3D] = []
var _show_joints := false

func _ready() -> void:
	GameMenu.set_gameplay_hud_visible(false)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.045,.065,.078)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.7,.8,.88)
	env.environment.ambient_light_energy = .6
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-35,0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20,20)
	floor.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.07,.10,.12)
	floor.material_override = mat
	add_child(floor)
	for i in range(3):
		var actor := CharacterVisual.new()
		actor.position.x = (i-1)*1.35
		actor.rotation.y = PI-.48
		add_child(actor)
		var look := CharacterCatalog.appearance_preset("dock_worker" if OS.get_cmdline_user_args().has("--heavy") else "sailor")
		if OS.get_cmdline_user_args().has("--heavy"):
			look.build = 1.0
			look.belly = 1.0
			look.frame = 1.0
			look.age = 80
		actor.apply_appearance(look)
		actor.play_motion(clips[i])
		actors.append(actor)
		var rig_lines := MeshInstance3D.new()
		rig_lines.mesh = ImmediateMesh.new()
		var rig_material := StandardMaterial3D.new()
		rig_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rig_material.albedo_color = Color(.2,1,.65)
		rig_material.no_depth_test = true
		rig_lines.material_override = rig_material
		actor.add_child(rig_lines)
		_rig_lines.append(rig_lines)
		var label := Label3D.new()
		label.text = str(clips[i]).to_upper()
		label.position = Vector3((i-1)*1.35,2.03,0)
		label.font_size = 44
		label.pixel_size = .0025
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0,1.8,5.9)
	camera.look_at(Vector3(0,1,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.65
	var args := OS.get_cmdline_user_args()
	_show_joints = args.has("--joints")
	if args.has("--still"):
		for i in range(3):
			actors[i].animation_player.play(clips[i],0.0)
			actors[i].animation_player.speed_scale = 0.0
			actors[i].animation_player.seek(.2,true)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[args.find("--still")+1])
		get_tree().quit()
	if args.has("--frames"):
		await _capture(args[args.find("--frames")+1])

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		_show_joints = not _show_joints

func _process(_delta: float) -> void:
	for i in range(actors.size()):
		_rig_lines[i].visible = _show_joints
		if not _show_joints: continue
		var mesh := _rig_lines[i].mesh as ImmediateMesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var rig := actors[i].skeleton
		for bone in range(rig.get_bone_count()):
			var parent := rig.get_bone_parent(bone)
			if parent < 0: continue
			for index in [parent,bone]:
				mesh.surface_add_vertex(actors[i].to_local(rig.to_global(rig.get_bone_global_pose(index).origin)))
		mesh.surface_end()

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	for actor in actors:
		actor.animation_player.stop()
	for i in range(3):
		actors[i].animation_player.play(clips[i],0)
		actors[i].animation_player.speed_scale = 0
	for frame in range(120):
		for i in range(3):
			var player := actors[i].animation_player
			player.seek(fposmod(frame/30.0,player.get_animation(clips[i]).length),true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("%04d.png" % frame))
	print("MOTION CAPTURE PASS: 120 frames at 30fps, shared Godot character rig")
	get_tree().quit()
