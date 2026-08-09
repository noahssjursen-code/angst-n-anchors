extends Node

## Photographs a vessel built from a `structure_plan_v1` data object.
##
## This is the instrument the ship-parts work runs on: a plan goes in, a set of
## canonical-angle PNGs and a set of machine-checkable claims come out. No UI,
## no clicking, no display — the loop an agent can run and a human can review.
##
##   tools/capture.sh                       # every fixture
##   tools/capture.sh demo_workboat         # one, by stem
##
## Runs in the SCENE lane, not `--script`. `VesselSpawn` reaches BoatBody, which
## transitively names the WorldGateway autoload, and `--script` registers no
## autoloads — so this must boot as a main scene or it cannot compile.
##
## Views use the project's vessel orientation: bow -Z, stern +Z, port -X,
## starboard +X.

const TestReport := preload("res://tests/support/test_report.gd")

const OUT_DIR := "res://screenshots/studio"
const SETTLE_FRAMES := 6

## Fixture plans. A capture is only evidence if the same input always produces
## the same framing, so the angles are fixed and the names are stable —
## re-running overwrites rather than accumulating, which is what makes two runs
## diffable.
const FIXTURES: Array[String] = [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
	"res://resources/data/structures/probe_ferry_catamaran.json",
]

## A long lens rather than a wide one: 35° keeps the perspective flat enough
## that a hull's sheer and proportions read true, which is the whole point of a
## reference comparison. Framing is then solved from the lens, not guessed.
const FOV_DEGREES := 35.0
const FRAME_MARGIN := 1.12

## azimuth (deg, 0 = dead astern looking forward), elevation (deg).
const VIEWS: Array[Dictionary] = [
	# Port is -X, so a port profile needs the camera at -X: azimuth 270, not 90.
	# At 90 this shot was labelled "port" while showing the starboard side — a
	# reference photograph that lies about which side you are looking at is worse
	# than no photograph.
	{"name": "profile_port", "azimuth": 270.0, "elevation": 3.0},
	{"name": "bow_quarter", "azimuth": 145.0, "elevation": 16.0},
	{"name": "stern_quarter", "azimuth": 35.0, "elevation": 16.0},
	{"name": "plan", "azimuth": 90.0, "elevation": 88.0},
]

var _t: RefCounted
var _camera: Camera3D
var _stage: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("vessel_render_capture")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_autoload_ui()

	var wanted := _requested_stems()
	var ran := 0
	for fixture in FIXTURES:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		await _capture_plan(fixture, stem)
		ran += 1

	if ran == 0:
		_t.fail("no fixture matched %s" % [wanted])
	_t.finish(get_tree())


## The scene lane boots the real autoloads, and several of them (GameMenu,
## DebugHud, LoadingGate) draw a HUD over everything. That HUD landed in the
## first captures — a currency chip floating over the vessel. A reference
## comparison must contain the vessel and nothing else.
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


## `-- <stem> <stem>` selects a subset; no args means everything.
func _requested_stems() -> PackedStringArray:
	var stems := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if not text.begins_with("--"):
			stems.append(text)
	return stems


func _capture_plan(path: String, stem: String) -> void:
	print("[capture] %s" % stem)

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		_t.fail("%s: plan is not a JSON object" % stem)
		return
	var data := raw as Dictionary
	if not _t.check("%s: is a structure plan" % stem, StructurePlan.is_plan(data)):
		return

	var plan := StructurePlan.from_dict(data)
	_t.check("%s: plan has entities" % stem, plan.entity_count() > 0)

	_stage = Node3D.new()
	add_child(_stage)
	_light_the_stage()

	# The plan is authored in grid-corner space; the studio centres it on the
	# hull with this offset, and a capture that used a different one would be
	# photographing something the builder never sees.
	var offset := Vector3.ZERO
	var deck_y := 0.0
	if plan.context == "vessel" and plan.hull_id != "":
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid != null:
			offset = Vector3(-grid.half_beam, 0.0, -grid.half_loa)
			deck_y = grid.deck_y
			var boat: Node3D = VesselSpawn.instantiate(plan.hull_id, {}, "")
			if _t.check("%s: hull %s instantiates" % [stem, plan.hull_id], boat != null):
				_stage.add_child(boat)
				boat.position = Vector3(0.0, -deck_y, 0.0)
				if boat is PhysicsBody3D:
					(boat as PhysicsBody3D).freeze = true
				boat.process_mode = Node.PROCESS_MODE_DISABLED

	_add_scale_figure(offset)

	var built: Node3D = StructureBaker.bake(plan, offset)
	if not _t.check("%s: plan bakes to a node" % stem, built != null):
		return
	_stage.add_child(built)

	var meshes := _count_meshes(built)
	_t.check("%s: bake produced geometry (%d surfaces)" % [stem, meshes], meshes > 0)

	# Draw-call budget is the governing constraint — harbours are full of these.
	# A merged bake should stay in the tens, not the hundreds. If this trips,
	# something stopped merging.
	_t.check("%s: bake stays merged (%d mesh instances)" % [stem, meshes], meshes <= 64)

	var bounds := _world_bounds(_stage)
	_t.check("%s: vessel has a real extent" % stem, bounds.size.length() > 1.0)

	for view in VIEWS:
		await _shoot(bounds, "%s__%s" % [stem, view["name"]], view)

	_stage.queue_free()
	_stage = null
	await get_tree().process_frame


## A 1.8 m figure on deck, in every frame.
##
## Without one, a capture has no absolute scale and a superstructure can be
## proportioned entirely wrong while looking plausible — which is exactly what
## happened. `scenes/shared/player.tscn` is a 1.8-tall capsule with its eye at
## 1.6, so world units are real metres FOR A HUMAN. Hull geometry is not on that
## scale: the catalog calls `hull_28x10` "14.0 × 5.0 m" but draws it 28 units
## long, so next to a 1.8 m player it reads as a 28 m vessel. Anything built on a
## hull must be sized against the figure, not against the catalog's display name.
##
## Matches the studio's own `_build_scale_mannequin` so a plan looks the same
## height in a capture as it does while you are drawing it.
func _add_scale_figure(offset: Vector3) -> void:
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

	# Stand it on the open forward working deck. The first attempt put it at
	# z = 18, which is inside the wheelhouse on the trawler fixtures — the figure
	# rendered and was invisible in every frame, which is the one failure mode a
	# scale reference must not have. This spot is clear of the bow bulwark run,
	# the hatch coaming and the deckhouse on all three fixtures; a plan that
	# builds over it will need the figure placed from the plan rather than fixed.
	#
	# The deck plane is y = 0 in stage space: this rig bakes the plan at the
	# origin and lowers the HULL by deck_y to meet it, rather than raising the
	# plan the way `DeckFitout.apply_plan` does. Adding deck_y here left the
	# figure hanging in the air above the mast.
	figure.position = offset + Vector3(2.5, 0.0, 7.0)
	_stage.add_child(figure)


func _light_the_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	_stage.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	_stage.add_child(fill)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.13, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.70)
	environment.ambient_light_energy = 0.45
	env.environment = environment
	_stage.add_child(env)

	_camera = Camera3D.new()
	_camera.current = true
	_stage.add_child(_camera)


func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	var centre := bounds.get_center()
	var azimuth := deg_to_rad(float(view["azimuth"]))
	var elevation := deg_to_rad(float(view["elevation"]))

	var dir := Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		cos(elevation) * cos(azimuth),
	)
	# Straight down would make `look_at` degenerate against UP.
	var up_hint := Vector3.UP if float(view["elevation"]) < 85.0 else Vector3.FORWARD
	var right := dir.cross(up_hint).normalized()
	var up := right.cross(dir).normalized()

	# Fitting the bounding SPHERE to the vertical FOV wastes most of a 16:9 frame
	# on a hull that is three times longer than it is tall. Project the eight
	# corners onto the camera's own right/up axes, then solve each axis against
	# its own field of view and take whichever needs more room.
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

	var image := get_viewport().get_texture().get_image()
	var out := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(out)
	_t.check("%s: capture written" % name, err == OK)

	# A capture that is a flat field of one colour is a failed render that looks
	# exactly like a successful one in a file listing. Refuse it.
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


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _world_bounds(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, boxes)
	if boxes.is_empty():
		return AABB()
	var out := boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


## Lights and the environment are VisualInstance3Ds with their own AABBs; letting
## them into the merge blows the bounds up and pushes every camera miles back.
func _collect_bounds(node: Node, into: Array[AABB]) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.visible:
			into.append(gi.global_transform * gi.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, into)
