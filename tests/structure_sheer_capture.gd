extends Node

## Photographs the sheer band against its own control.
##
##   timeout 600 xvfb-run -a --server-args="-screen 0 1600x900x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/structure_sheer_capture.tscn
##
## SCENE lane, not `--script`. This one spawns the REAL hull, and BoatBody's
## dependency chain reaches autoload identifiers that `--script` cannot compile
## (CONVENTIONS §2). The gate assertions about the primitive live in
## `tests/structure_sheer_test.gd`, which runs in the SceneTree lane and names no
## vessel script; what is here is the picture plus the claims a picture needs to
## be trustworthy — that it is not blank, that the vessel in it is the vessel the
## fixture describes, and that drawing the bulwark did not cost a draw call.
##
## ── Why a second capture rig instead of vessel_render_capture ───────────────
## Because `StructureBaker` does not read `edges[]` yet — that seam lands in the
## same wave, in a file this one does not own — and a fixture whose bulwark
## renders as nothing would be a photograph of a bare hull. This rig resolves the
## fixture's edge through `StructureEdge.sheer_bulwark_spec` and bakes it through
## `StructureEdge.bake_boxes`, which is the same `_bucket_layer` the baker uses,
## so the merge and the draw-call count are the real ones. When the `edges[]`
## loop lands in `StructureBaker.bake()` this rig can be deleted and the two
## fixtures added to `vessel_render_capture.FIXTURES` instead; the pictures
## should not move.
##
## ── What to look at ─────────────────────────────────────────────────────────
## probe_sheer_bulwark__profile_port.png against
## probe_sheer_bulwark_flat__profile_port.png. Squint. The control is two
## parallel horizontal bars. The other one should be a boat.

const TestReport := preload("res://tests/support/test_report.gd")

const OUT_DIR := "res://screenshots/studio"
const SETTLE_FRAMES := 6

const FIXTURES: Array[String] = [
	"res://resources/data/structures/probe_sheer_bulwark.json",
	"res://resources/data/structures/probe_sheer_bulwark_flat.json",
]

## Same lens and the same four angles as `vessel_render_capture`, so a sheer
## capture is directly comparable with the vessels already in the folder. A long
## lens rather than a wide one: 35° keeps the perspective flat enough that a
## hull's sheer reads true, which is the entire point here.
const FOV_DEGREES := 35.0
const FRAME_MARGIN := 1.12
const VIEWS: Array[Dictionary] = [
	{"name": "profile_port", "azimuth": 270.0, "elevation": 3.0},
	{"name": "bow_quarter", "azimuth": 145.0, "elevation": 16.0},
	{"name": "stern_quarter", "azimuth": 35.0, "elevation": 16.0},
	{"name": "plan", "azimuth": 90.0, "elevation": 88.0},
]

## Where the 1.8 m figure stands, in ship-local metres. Amidships and inboard of
## the bulwark on the open deck: CONVENTIONS §3a's rule is that every vessel
## capture carries a figure AND that the figure is actually visible, and the
## documented failure was one placed inside a wheelhouse. With the bulwark
## 1.16 m high amidships, a 1.8 m figure standing here shows head and shoulders
## over it in the profile shot — which also makes the bulwark's height readable
## against a person rather than against the hull.
const FIGURE_AT := Vector3(-2.6, 0.0, 1.5)

var _t: RefCounted
var _stage: Node3D
var _camera: Camera3D
var _draw_calls := 0
var _primitives := 0
var _hull_only_calls := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("structure_sheer_capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_autoload_ui()
	for fixture in FIXTURES:
		await _capture(fixture, fixture.get_file().get_basename())
	_t.finish(get_tree())


func _capture(path: String, stem: String) -> void:
	print("[capture] %s" % stem)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _t.check("%s: parses as an object" % stem, raw is Dictionary):
		return
	var plan := raw as Dictionary
	var edges := plan.get("edges", []) as Array
	if not _t.check("%s: declares one edge run" % stem, edges.size() == 1):
		return
	var edge := edges[0] as Dictionary

	_stage = Node3D.new()
	add_child(_stage)
	_light_the_stage()

	## The REAL hull, bare: `HullRegistry.build_hull` rather than
	## `VesselSpawn.instantiate`, because instantiate applies a default brick
	## fit-out and the whole claim of this fixture is that there is nothing on
	## the hull but the bulwark.
	var boat: Node3D = HullRegistry.build_hull(str(plan.get("hull_id", "hull_28x10")))
	if not _t.check("%s: hull %s builds" % [stem, str(plan.get("hull_id", ""))], boat != null):
		return
	_stage.add_child(boat)
	if boat is PhysicsBody3D:
		(boat as PhysicsBody3D).freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED

	var stations: HullStations = boat.get("hull_stations") as HullStations
	if not _t.check("%s: the hull carries its stations" % stem, stations != null):
		return

	## The fixture restates hull_28x10's numbers so the SceneTree-lane gate test
	## can build HullStations without naming a vessel script. This is where that
	## restatement is held to the hull the game actually builds — a fixture that
	## quietly drifts from the hull would make every assertion in
	## structure_sheer_test true about a vessel that does not exist.
	var declared := plan.get("hull", {}) as Dictionary
	_t.near("%s: fixture LOA matches the built hull" % stem,
		float(declared.get("loa_m", 0.0)), stations.length_m, 1e-3)
	_t.near("%s: fixture beam matches" % stem,
		float(declared.get("beam_m", 0.0)), stations.beam_m, 1e-3)
	_t.near("%s: fixture depth matches deck_y" % stem,
		float(declared.get("depth_m", 0.0)), stations.deck_y, 1e-3)
	_t.check("%s: the hull's own sheer is non-zero (%.3f m forward, %.3f m aft)"
		% [stem, stations.sheer_forward_m, stations.sheer_aft_m],
		stations.sheer_forward_m > 0.0)

	_add_scale_figure(stations)

	## Draw calls with the bulwark and without, on the same frame budget.
	var bounds_hull := _world_bounds(_stage)
	_hull_only_calls = await _measure(bounds_hull)

	var spec := StructureEdge.sheer_bulwark_spec(stations, edge)
	var boxes := StructureEdge.sheer_band_boxes(spec)
	if not _t.check("%s: the bulwark emits geometry (%d boxes)" % [stem, boxes.size()],
		boxes.size() > 0):
		return
	var built := StructureEdge.bake_boxes(boxes)
	_stage.add_child(built)
	_t.equal("%s: the whole bulwark merged into one surface" % stem, built.get_child_count(), 1)

	var bounds := _world_bounds(_stage)
	_draw_calls = 0
	_primitives = 0
	for view in VIEWS:
		await _shoot(bounds, "%s__%s" % [stem, view["name"]], view)
	print("  [cost] %s  hull alone %d draw calls, hull + bulwark %d  (%d boxes, %d triangles)" % [
		stem, _hull_only_calls, _draw_calls, boxes.size(), StructureEdge.triangle_count(boxes),
	])
	## One material, so at most one more surface — and the shadow pass issues its
	## own call over it, hence the doubling. The claim is that a 70 m run of
	## bulwark in two colours is not a per-colour or a per-segment cost.
	_t.check(
		"%s: the bulwark cost %d draw calls over the bare hull (<= 2 with shadows)"
		% [stem, _draw_calls - _hull_only_calls],
		_draw_calls - _hull_only_calls <= 2,
	)

	_stage.queue_free()
	_stage = null
	await get_tree().process_frame


# ── Stage ───────────────────────────────────────────────────────────────────

func _hide_autoload_ui() -> void:
	for child in get_tree().root.get_children():
		if child != self:
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


## Same rig as vessel_render_capture, deliberately: the shadow is not a
## finishing touch on untextured geometry, it is most of what separates two grey
## surfaces meeting at an angle — and the cap rail's outboard overhang throws its
## shadow line straight along the sheer, which is a large part of why the curve
## reads at all.
func _light_the_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	_stage.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	_stage.add_child(fill)

	## A PALE sky, and this is the one place this rig deliberately departs from
	## vessel_render_capture's dark studio. The question being asked here is a
	## silhouette question — "squint at it, does that read as a boat" — and a
	## silhouette is the boundary between the subject and the ground. A near-black
	## hull on a near-black ground has no boundary to read: the first version of
	## this capture drew the sheer correctly and photographed it as a grey wire on
	## a grey field, which is a bad photograph of a good curve. Against a light
	## sky the vessel is a dark shape and its top edge is the only thing the eye
	## has to go on, which is exactly the test.
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.74, 0.80, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.70, 0.78)
	environment.ambient_light_energy = 0.60
	env.environment = environment
	_stage.add_child(env)

	_camera = Camera3D.new()
	_camera.current = true
	_stage.add_child(_camera)


## A 1.8 m figure on deck, in every frame — CONVENTIONS §3a. Without one a
## capture has no absolute scale and a wrongly-proportioned build looks entirely
## plausible.
func _add_scale_figure(stations: HullStations) -> void:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.95, 0.55, 0.1)
	body.material_override = suit
	figure.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.70, 0.55)
	head.material_override = skin
	figure.add_child(head)

	## The build plane, 0.12 above the shell top — where StructurePlan geometry
	## stands, so the figure and the bulwark share a floor.
	figure.position = FIGURE_AT + Vector3(0.0, stations.deck_y + 0.12, 0.0)
	_stage.add_child(figure)


# ── Shooting ────────────────────────────────────────────────────────────────

func _measure(bounds: AABB) -> int:
	await _shoot(bounds, "", VIEWS[0])
	return _draw_calls


func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	var centre := bounds.get_center()
	var azimuth := deg_to_rad(float(view["azimuth"]))
	var elevation := deg_to_rad(float(view["elevation"]))
	var dir := Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		cos(elevation) * cos(azimuth),
	)
	var up_hint := Vector3.UP if float(view["elevation"]) < 85.0 else Vector3.FORWARD
	var right := dir.cross(up_hint).normalized()
	var up := right.cross(dir).normalized()

	var half_v := deg_to_rad(FOV_DEGREES) * 0.5
	var aspect := float(get_viewport().size.x) / maxf(1.0, float(get_viewport().size.y))
	var tan_v := tan(half_v)
	var tan_h := tan_v * aspect
	var half_w := 0.0
	var half_h := 0.0
	var half_d := 0.0
	for i in 8:
		var corner := bounds.position + Vector3(
			bounds.size.x * float(i & 1),
			bounds.size.y * float((i >> 1) & 1),
			bounds.size.z * float((i >> 2) & 1),
		)
		var local := corner - centre
		half_w = maxf(half_w, absf(local.dot(right)))
		half_h = maxf(half_h, absf(local.dot(up)))
		half_d = maxf(half_d, absf(local.dot(dir)))
	var distance := maxf(half_h / tan_v, half_w / tan_h) * FRAME_MARGIN + half_d

	_camera.fov = FOV_DEGREES
	_camera.near = maxf(0.05, distance * 0.005)
	_camera.far = distance * 4.0
	_camera.position = centre + dir * distance
	_camera.look_at(centre, up_hint)

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	_draw_calls = maxi(_draw_calls, int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)))
	_primitives = maxi(_primitives, int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	)))
	if name.is_empty():
		return

	var image := get_viewport().get_texture().get_image()
	var out := "%s/%s.png" % [OUT_DIR, name]
	_t.check("%s: capture written" % name, image.save_png(out) == OK)
	## A flat field of one colour is a failed render that looks exactly like a
	## successful one in a file listing. Refuse it.
	_t.check("%s: capture is not blank" % name, _distinct_colours(image) >= 8)
	print("  %s  %dx%d" % [out, image.get_width(), image.get_height()])


func _distinct_colours(image: Image) -> int:
	var seen := {}
	var step := maxi(1, image.get_width() / 96)
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			seen[image.get_pixel(x, y).to_rgba32()] = true
			if seen.size() >= 64:
				return seen.size()
	return seen.size()


func _world_bounds(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, boxes)
	if boxes.is_empty():
		return AABB()
	var out := boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


## Lights and the environment carry their own enormous AABBs; letting them into
## the merge pushes every camera miles back.
func _collect_bounds(node: Node, into: Array[AABB]) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.visible:
			into.append(gi.global_transform * gi.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, into)
