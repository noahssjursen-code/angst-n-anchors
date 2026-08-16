extends Node

## SCRATCH PROBE — leading underscore so the gate does not discover it.
##
## `hull_livery.gd:11` says a sheer-strake surface "was built and reverted for
## costing +2 draw calls a vessel". That is a QUOTED COST (REALITY §4f'), and it is
## the only argument on record against giving the strake its own paint. Measure it
## on the real thing: spawn every hull in the kit, count mesh surfaces on the shell
## and the frame's total draw calls with the hull in view.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const HULL_IDS := [
	"hull_15x5", "hull_28x10", "hull_45x16_cat",
	"hull_100x24", "hull_130x28", "hull_150x32",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CaptureClock.pin(get_tree())
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.85
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	world.add_child(camera)

	await CaptureClock.settle(get_tree(), 4)
	var empty_calls := RenderingServer.viewport_get_render_info(
		viewport.get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
	)
	print("empty scene draw calls: %d" % empty_calls)

	for hull_id in HULL_IDS:
		var boat := HullRegistry.build_hull(hull_id)
		boat.freeze = true
		world.add_child(boat)
		## `freeze` alone is revoked by BoatBody's automatic physics LOD — see
		## `tests/support/capture_subject.gd`. A drifting hull changes which surfaces
		## the camera can see, and this probe counts exactly that.
		CaptureSubject.hold_still(boat)
		var height := maxf(boat.depth_m, 3.0)
		var length := maxf(boat.length_m, 10.0)
		var beam := maxf(boat.beam_m, 5.0)
		camera.position = Vector3(
			beam * 0.5 + maxf(length * 0.76, height * 5.0), height * 0.68, 0.0
		)
		camera.look_at_from_position(
			camera.position, Vector3(0.0, height * 0.48, 0.0), Vector3.UP
		)
		await CaptureClock.settle(get_tree(), 4)
		var calls := RenderingServer.viewport_get_render_info(
			viewport.get_viewport_rid(),
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
		)
		var prims := RenderingServer.viewport_get_render_info(
			viewport.get_viewport_rid(),
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME,
		)
		var shell := boat.get_node_or_null("HullVisual/HullShell") as MeshInstance3D
		var surfaces := shell.mesh.get_surface_count() if shell != null and shell.mesh != null else -1
		var tris := 0
		for s in range(maxi(surfaces, 0)):
			tris += (shell.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("%-16s shell surfaces=%d  shell triangles=%d  frame draw_calls=%d  primitives=%d"
			% [hull_id, surfaces, tris, calls, prims])
		world.remove_child(boat)
		boat.free()
	get_tree().quit()
