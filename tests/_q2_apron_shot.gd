extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit). Owner decision #5:
## how densely a working apron should be dressed.
##
##   Q2_LABEL=step20 xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_q2_apron_shot.tscn
##
## The port is `port_trade_profile_test`'s own fixture — same definition, same
## seeds — so these frames are pictures of the exact apron whose "should sprinkle
## service props" check has been red, rather than of some other port that would
## be easier to shoot.
##
## `APRON_DECOR_STEP_M` is a const, so a variant is produced by editing that one
## line, rendering, and reverting; the label is passed in the environment and only
## ever reaches the FILENAME. The rig is identical across values, camera included:
## the owner is comparing images and a re-framed camera would be the loudest
## difference in the set (REALITY.md §8).

const OUT_DIR := "res://screenshots/decisions"

## Framing is DERIVED FROM THE DOCK FACE, not from the props. The foundation is
## generated before any apron decor exists and does not move with
## `APRON_DECOR_STEP_M`, so every value gets the identical camera — which is the
## whole point, and is stronger than hardcoding numbers off one run and hoping.
const WIDE_ORTHO := 260.0
const CLOSE_ORTHO := 60.0
## Where along the dock face the close-up looks, as a fraction of total arc.
const CLOSE_ARC_FRACTION := 0.255
const INLAND_LOOK_M := 26.0

var _camera: Camera3D
var _label := "step20"


func _ready() -> void:
	_label = OS.get_environment("Q2_LABEL")
	if _label.is_empty():
		_label = "step%d" % int(PortLandPlan.APRON_DECOR_STEP_M)

	var definition := PortDefinition.new()
	definition.port_id = "port-home"
	definition.display_name = "Haugsvik"
	definition.size = 2
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.site_seed = 991122
	PortDataCache.clear()
	var data := PortExpander.expand(definition, 424242)
	var graph := data.layout_graph

	var land: Dictionary = graph.initial_attributes.get("land_plan", {}) as Dictionary
	var apron: Dictionary = land.get("apron_decor", {}) as Dictionary
	var points: Array = apron.get("points", []) as Array
	print("[q2] label=%s  APRON_DECOR_STEP_M=%.1f  props=%d"
		% [_label, PortLandPlan.APRON_DECOR_STEP_M, points.size()])
	var kinds: Dictionary = {}
	var xs := PackedFloat64Array()
	for raw in points:
		var entry: Dictionary = raw
		var kind := str(entry.get("kind", "?"))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var local_arr: Array = entry.get("local", []) as Array
		if local_arr.size() >= 2:
			xs.append(float(local_arr[0]))
	if not xs.is_empty():
		var sorted_xs := xs
		sorted_xs.sort()
		var gaps := PackedFloat64Array()
		for i in range(1, sorted_xs.size()):
			gaps.append(sorted_xs[i] - sorted_xs[i - 1])
		gaps.sort()
		print("[q2] %s: along-face span %.1f .. %.1f m, neighbour gaps min %.1f median %.1f max %.1f"
			% [_label, sorted_xs[0], sorted_xs[sorted_xs.size() - 1],
				gaps[0] if not gaps.is_empty() else 0.0,
				gaps[gaps.size() / 2] if not gaps.is_empty() else 0.0,
				gaps[gaps.size() - 1] if not gaps.is_empty() else 0.0])
	print("[q2] %s: kinds %s" % [_label, str(kinds)])

	var visualizer := PortLayoutGraphVisualizer.new()
	visualizer.configure(graph)
	add_child(visualizer)

	## ⚠ `PortLayoutGraphVisualizer._stamp_apron_decor()` HAS NO CALLERS.
	## `_rebuild()` stamps foundation, berth terminals, apron pads, land
	## structures, modules and open slots, and carries the comment "Apron props
	## deferred — layout first via asphalt/apron gizmos, then decorate"; the
	## decorate step never landed. Grepped 2026-08-15: the only mentions of
	## `apron_decor` outside `PortLandPlan` are that one uncalled function, the
	## gate test, and two scratch probes (REALITY.md §3d).
	##
	## So this probe calls it EXPLICITLY when `Q2_STAMP=1`, and renders without
	## it otherwise. The un-stamped frame is what the game actually draws at
	## every value of the constant; the stamped frames are what the data would
	## look like if something drew it.
	if OS.get_environment("Q2_STAMP") == "1":
		visualizer._stamp_apron_decor()
		print("[q2] %s: apron decor stamped BY THIS PROBE (no game code calls it)" % _label)
	else:
		print("[q2] %s: apron decor NOT stamped — this is what the game draws" % _label)

	_light()
	_hide_autoload_ui()

	var foundation: Dictionary = graph.initial_attributes.get("foundation", {}) as Dictionary
	var face := PackedVector2Array()
	for raw in foundation.get("dock_face_polyline", []) as Array:
		var arr: Array = raw as Array
		if arr.size() >= 2:
			face.append(Vector2(float(arr[0]), float(arr[1])))
	if face.size() < 2:
		printerr("[q2] no dock face polyline")
		get_tree().quit(1)
		return
	var arcs := PortCoastTracer.path_arc_lengths(face)
	var total_arc := float(arcs[arcs.size() - 1])
	## The SAME crown the visualiser stamps props on — `_stamp_apron_decor` adds
	## the terrain clearance. Without it the scale figure sank into the pavement
	## and appeared in no frame, which is the one failure mode a scale reference
	## must not have (REALITY.md §8).
	var surface_y := float(foundation.get("surface_y_m", PortCoastTracer.FOUNDATION_SURFACE_Y_M)) \
		+ PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M
	var inland := PortCoastTracer.PORT_LOCAL_INLAND_DIR
	var mid: Vector2 = PortCoastTracer.point_at_arc_s(face, arcs, total_arc * 0.5).get(
		"position", Vector2.ZERO)
	var near: Vector2 = PortCoastTracer.point_at_arc_s(
		face, arcs, total_arc * CLOSE_ARC_FRACTION).get("position", Vector2.ZERO)
	var wide_centre := _to_world(mid + inland * INLAND_LOOK_M, surface_y)
	var close_centre := _to_world(near + inland * (INLAND_LOOK_M * 0.7), surface_y)
	print("[q2] %s: dock face arc %.2f m, wide centre %s, close centre %s"
		% [_label, total_arc, str(wide_centre), str(close_centre)])

	## Two 1.8 m figures on the apron crown, one per frame, both derived from the
	## same dock face and therefore in the same world spot for every value.
	add_child(_figure(wide_centre))
	add_child(_figure(close_centre))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _shoot("wide", WIDE_ORTHO, wide_centre, 52.0, 0.0)
	## Looked at from OFF THE END of the quay rather than from the water: at a
	## shallow angle straight in off the sea the inland village stands directly
	## behind the apron and hides it, which is the instrument obscuring the
	## subject. Down the face, the props string out and the village is off to one
	## side.
	await _shoot("close", CLOSE_ORTHO, close_centre, 16.0, 74.0)
	get_tree().quit(0)


func _to_world(local: Vector2, y: float) -> Vector3:
	return Vector3(local.x, y, local.y)


## Orthographic throughout. A perspective frame of a 300 m apron makes the far
## props smaller than the near ones, and "are there enough of them" is exactly
## the judgement that ruins.
func _shoot(
		view: String, ortho: float, centre: Vector3,
		elevation_deg: float, yaw_deg: float,
) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ortho
	var elevation := deg_to_rad(elevation_deg)
	var yaw := deg_to_rad(yaw_deg)
	var dir := Vector3(
		-sin(yaw) * cos(elevation), sin(elevation), -cos(yaw) * cos(elevation))
	_camera.position = centre + dir * 400.0
	_camera.look_at(centre, Vector3.UP)
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/q2_apron__%s__%s.png" % [OUT_DIR, _label, view]
	print("[q2] %s (%d)" % [path, get_viewport().get_texture().get_image().save_png(path)])


func _figure(at: Vector3) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.28
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.28, 0.05)
	body.material_override = mat
	root.add_child(body)
	root.position = at
	return root


func _hide_autoload_ui() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas_items(child)


func _hide_canvas_items(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas_items(child)


func _light() -> void:
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, 34.0, 0.0)
	sun.light_energy = 1.20
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 500.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.4
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -130.0, 0.0)
	fill.light_energy = 0.32
	add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.74, 0.80, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.72, 0.80)
	environment.ambient_light_energy = 0.62
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
