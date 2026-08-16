extends Node

## SCRATCH PROBE — leading underscore so the gate does not discover it.
##
## Does the subject of `hull_visual_capture` actually move while that rig is
## photographing it? The rig's frames can agree across eight back-to-back runs
## and still be taken of a moving hull, because every run samples the same
## transient at the same phase (STATE.md, 2026-08-16: "one clean pair closes
## nothing"). So this asks the SUBJECT, not the pixels.
##
## It reproduces `hull_visual_capture._capture_all` exactly — same SubViewport,
## same environment, same hull order, same `settle(3)` twice per view — and logs
## the boat's `global_transform.origin`, `linear_velocity`, `freeze` and
## `physics_quality` at every point the rig grabs an image.
##
##   HVC_PROBE_HOLD=1       apply `CaptureSubject.hold_still` (the fix)
##   HVC_PROBE_FORCE_LOD=1  call the LOD update by hand, once, right after
##                          `add_child` — what a run looks like when the 1.0 s
##                          timer crosses inside the capture window
##   neither                the rig as it stands (`boat.freeze = true` only)

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const BACKGROUND := Color(0.80, 0.84, 0.88)
const HULL_IDS := [
	"hull_15x5",
	"hull_28x10",
	"hull_45x16_cat",
	"hull_150x32",
	"hull_100x24",
	"hull_130x28",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var hold := OS.get_environment("HVC_PROBE_HOLD").strip_edges() == "1"
	var force_lod := OS.get_environment("HVC_PROBE_FORCE_LOD").strip_edges() == "1"
	print("=== HVC STILL PROBE: hold_still=%s force_lod=%s ===" % [hold, force_lod])
	CaptureClock.pin(get_tree())
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.70)
	env.ambient_light_energy = 0.85
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.light_energy = 1.4
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.55
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	world.add_child(camera)

	var worst_walk := 0.0
	var worst_hull := ""
	for hull_id in HULL_IDS:
		var boat := HullRegistry.build_hull(hull_id)
		if boat == null:
			continue
		boat.freeze = true
		world.add_child(boat)
		if hold:
			CaptureSubject.hold_still(boat)
		## The LOD's own body, called directly. `_physics_lod_timer` reaches only
		## 0.27–0.53 on a quiet box and 0.72–0.93 under saturating load, so on this
		## machine the rig usually stops short of the 1.0 s threshold. That is a
		## margin, not a guarantee: this mode asks what the frames look like on a
		## run where the timer DOES cross, which is the run the 2.5118% drift came
		## from. Meaningless with `hold` — `hold_still` stops the caller, and
		## calling the callee by hand would be testing a path the fix removes.
		if force_lod and not hold:
			boat.call("_update_automatic_physics_quality")
			print(
				"    %-16s LOD FORCED -> freeze=%s quality=%s"
				% [
					hull_id,
					str(boat.get("freeze")),
					boat.call("get_physics_quality_name"),
				]
			)
		var length := maxf(boat.length_m, 10.0)
		var beam := maxf(boat.beam_m, 5.0)
		var height := maxf(boat.depth_m, 3.0)
		var deck_y := (
			boat.hull_stations.deck_y if boat.hull_stations != null else height * 0.85
		)
		var figure := _make_scale_figure()
		figure.position = Vector3(beam * 0.18, deck_y, -length * 0.40)
		boat.add_child(figure)
		var first_y := 1e18
		var lo := 1e18
		var hi := -1e18
		for view in ["front", "side", "three_quarter"]:
			match view:
				"front":
					boat.rotation_degrees.y = 0.0
					camera.position = Vector3(
						0.0,
						height * 0.82,
						-length * 0.5 - maxf(beam * 1.15, height * 2.6)
					)
				"side":
					boat.rotation_degrees.y = 0.0
					camera.position = Vector3(
						beam * 0.5 + maxf(length * 0.76, height * 5.0),
						height * 0.68,
						0.0
					)
				_:
					boat.rotation_degrees.y = -18.0
					var distance := maxf(length * 0.64, beam * 1.45)
					camera.position = Vector3(distance * 0.55, height * 1.35, -distance)
			camera.look_at_from_position(
				camera.position, Vector3(0.0, height * 0.48, 0.0), Vector3.UP
			)
			figure.visible = false
			await CaptureClock.settle(get_tree(), 3)
			var a := _sample(boat, hull_id, view, "no-figure")
			figure.visible = true
			await CaptureClock.settle(get_tree(), 3)
			var b := _sample(boat, hull_id, view, "GRABBED")
			for y in [a, b]:
				if first_y > 1e17:
					first_y = y
				lo = minf(lo, y)
				hi = maxf(hi, y)
		var walk := hi - lo
		print(
			"  %-16s origin.y span across its six grabs = %.9f m (%.3f mm)"
			% [hull_id, walk, walk * 1000.0]
		)
		if walk > worst_walk:
			worst_walk = walk
			worst_hull = hull_id
		world.remove_child(boat)
		boat.free()

	print(
		"=== HVC STILL PROBE: hold_still=%s force_lod=%s  WORST origin.y walk = %.9f m (%.3f mm) on %s ==="
		% [hold, force_lod, worst_walk, worst_walk * 1000.0, worst_hull]
	)
	viewport.queue_free()
	get_tree().quit()


func _sample(boat: Node3D, hull_id: String, view: String, tag: String) -> float:
	var body := boat as RigidBody3D
	var origin := boat.global_transform.origin
	print(
		(
			"    %-16s %-14s %-10s origin=(%.9f, %.9f, %.9f) vy=%.9f freeze=%s"
			+ " quality=%s auto_lod=%s lod_timer=%.4f pframes=%d"
		)
		% [
			hull_id,
			view,
			tag,
			origin.x,
			origin.y,
			origin.z,
			body.linear_velocity.y if body != null else 0.0,
			str(boat.get("freeze")),
			boat.call("get_physics_quality_name") if boat.has_method("get_physics_quality_name") else "?",
			str(boat.get("automatic_physics_lod")),
			float(boat.get("_physics_lod_timer")),
			Engine.get_physics_frames(),
		]
	)
	return origin.y


func _make_scale_figure() -> Node3D:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	figure.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	figure.add_child(head)
	return figure
