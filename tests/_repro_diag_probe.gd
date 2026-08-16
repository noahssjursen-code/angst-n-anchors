extends Node

## SCRATCH DIAGNOSTIC PROBE (leading underscore — the gate must not score it).
## Lane B (scene): res://tests/_repro_diag_probe.tscn
##
## Asks one question the repro harness cannot: **does the image change WITHIN a
## single process, with nothing in the scene moving?**
##
## `tools/repro.sh` compares two processes, so every cross-process difference
## looks the same whatever caused it. This probe stands the `_small_hull_shot`
## stage up once and grabs the SAME camera N times in a row, comparing each grab
## to the first. If the frames drift inside one process, the cause is per-frame
## and no amount of pinning process-level state will close it; if they are
## identical inside a process and differ between processes, the cause is
## per-process (a seed, a mesh build, a start hour).
##
## It then repeats the sweep with the sun's shadow disabled, because the
## difference masks from `_small_hull_shot` put almost every moved pixel on a
## SHADOW boundary rather than on a silhouette edge.
##
## Finally it hashes the hull mesh surfaces and the body transform so a second
## process can be compared against the first on the geometry rather than on the
## pixels.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_repro_diag_probe.tscn

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const WL := -1.5
const SKY := Color(0.80, 0.85, 0.90)
const WATER := Color(0.13, 0.32, 0.40, 0.62)
const GRABS := 8

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _boat: BoatBody
var _run_tag := "a"
var _fix := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--tag="):
			_run_tag = str(arg).substr(6)
		if str(arg) == "--fix":
			_fix = true
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f" % CaptureClock.pin(get_tree()))
	_build_stage()
	_boat = HullRegistry.build_hull("hull_15x5")
	_boat.freeze = true
	_world.add_child(_boat)
	## THE FIX UNDER TEST. `freeze = true` alone does not hold: one second after
	## the hull enters the tree `BoatBody._physics_process` runs
	## `_update_automatic_physics_quality()`, finds no PlayerVessel in the group,
	## takes the `nearest_distance == INF` branch to `PhysicsQuality.FULL`, and
	## `set_physics_quality` writes `freeze = false` and re-enables
	## `StripBuoyancyComponent`. The hull then bobs to its buoyancy equilibrium.
	if _fix:
		_boat.automatic_physics_lod = false
		_boat.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
	_boat.position = Vector3(0.0, WL - _boat.draft_m - _boat.hull_stations.keel_y, 0.0)
	var figure := _make_figure()
	figure.position = Vector3(
		_boat.beam_m * 0.20, _boat.hull_stations.deck_y + 0.12, _boat.length_m * 0.18
	)
	_boat.add_child(figure)

	_geometry_hashes()

	## The bow-on ortho — the worst frame in the rig's own numbers.
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 9.0
	_camera.look_at_from_position(
		Vector3(0.0, WL + 0.6, -60.0), Vector3(0.0, WL + 0.6, 0.0), Vector3.UP
	)

	await _sweep("shadowON", true, 60, 1)
	await _sweep("shadowOFF", false, 20, 1)
	## ON again, LAST, so "it converged because the renderer warmed up" and "it
	## converged because the shadow settled" are told apart: if the divergence
	## comes back after twenty stable shadow-off frames, it is the shadow.
	await _sweep("shadowON2", true, 20, 1)

	print("DIAG DONE")
	get_tree().quit(0)


## N grabs of an unchanging scene from an unchanging camera. Each grab is
## written out and hashed; the pixel comparison is done in Python afterwards,
## because a 1600x900 double loop in GDScript costs minutes per pair.
func _sweep(label: String, shadow: bool, count: int = GRABS, per: int = 4) -> void:
	var slug := label.strip_edges().replace(" ", "_")
	var out := "res://.probe/diag/%s" % _run_tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_sun.shadow_enabled = shadow
	for i in range(count):
		await CaptureClock.settle(get_tree(), per)
		var img: Image = _viewport.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s_g%02d.png" % [out, slug, i]))
		print("DIAG %s grab %d frame=%d msec=%d boat=%s cam=%s lin=%s ang=%s"
			% [
				label, i, Engine.get_frames_drawn(), Time.get_ticks_msec(),
				_bits(_boat.global_transform), _bits(_camera.global_transform),
				_bits3(_boat.linear_velocity), _bits3(_boat.angular_velocity),
			])


## Cross-process comparison on the SUBJECT rather than the pixels: if these
## agree between two runs, the geometry did not move and the difference is in
## the render.
func _geometry_hashes() -> void:
	var t := _boat.global_transform
	var words := PackedFloat32Array([
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	])
	print("DIAG transform bits=%s" % [words.to_byte_array().hex_encode()])
	var surfaces := 0
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for node in _walk(_boat):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			surfaces += 1
			var arrays := mi.mesh.surface_get_arrays(s)
			for entry in arrays:
				if entry != null:
					ctx.update(var_to_bytes(entry))
	print("DIAG mesh surfaces=%d sha256=%s" % [surfaces, ctx.finish().hex_encode()])


## Exact bits, not a rounded print — a transform that moves by an ULP moves a
## silhouette edge by a pixel and prints as the same number at %.6f.
func _bits(t: Transform3D) -> String:
	return PackedFloat32Array([
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]).to_byte_array().hex_encode()


func _bits3(v: Vector3) -> String:
	return PackedFloat32Array([v.x, v.y, v.z]).to_byte_array().hex_encode()


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


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

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	_sun.light_energy = 1.45
	_sun.shadow_enabled = true
	_world.add_child(_sun)
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
