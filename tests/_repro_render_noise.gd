extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Lane B.
##
## Is the RENDERER bit-deterministic on this box, for a scene that provably does
## not move? Four static boxes, one shadow-casting sun, one fixed camera. The
## same frame is grabbed at four different settle depths inside ONE process and
## md5'd. Run the probe twice and compare the md5s across processes.
##
## Variants selected by `-- <variant>`:
##   main      — grab from the MAIN viewport (what hull/vessel captures use)
##   sub       — grab from a SubViewport with own_world_3d (what _starter_shot uses)
##   noshadow  — main viewport, shadows off
##   alpha     — main viewport, plus a big translucent slab (the _starter_shot sea)

var _mode := "main"
var _vp: Viewport
var _root3d: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_mode = str(arg)
	call_deferred("_run")


func _run() -> void:
	_root3d = Node3D.new()
	if _mode == "sub":
		var sub := SubViewport.new()
		sub.size = Vector2i(1280, 720)
		sub.own_world_3d = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		get_tree().root.add_child(sub)
		sub.add_child(_root3d)
		_vp = sub
	else:
		add_child(_root3d)
		_vp = get_viewport()

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.85, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.70, 0.78)
	env.ambient_light_energy = 0.85
	we.environment = env
	_root3d.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = _mode != "noshadow"
	_root3d.add_child(sun)

	for i in 4:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0 + float(i) * 0.37, 1.0 + float(i) * 0.61, 3.0)
		mi.mesh = box
		mi.position = Vector3(float(i) * 3.1 - 4.0, 0.5 + float(i) * 0.2, float(i) * 0.9)
		mi.rotation_degrees = Vector3(0.0, float(i) * 17.0, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3 + 0.15 * float(i), 0.4, 0.55 - 0.1 * float(i))
		mi.material_override = mat
		_root3d.add_child(mi)

	if _mode == "alpha":
		var sea := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(600.0, 40.0, 600.0)
		sea.mesh = slab
		sea.position = Vector3(0.0, -20.4, 0.0)
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.13, 0.32, 0.40, 0.62)
		wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wmat.roughness = 0.4
		wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sea.material_override = wmat
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root3d.add_child(sea)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 40.0
	_root3d.add_child(cam)
	cam.look_at_from_position(Vector3(-9.0, 6.0, 12.0), Vector3(0.0, 1.0, 0.0), Vector3.UP)

	for depth in [4, 8, 16, 32]:
		while Engine.get_process_frames() < depth:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(img.get_data())
		print("NOISE mode=%s depth=%d md5=%s size=%v" % [
			_mode, depth, ctx.finish().hex_encode(), img.get_size(),
		])
	get_tree().quit(0)
