extends Node3D

## SCRATCH PROBE — leading underscore, so the gate skips it in both lanes.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_cat_stem_sea_shot.tscn
##
## WHAT IS UNDER A PIECE PLACED ON THE CELLS THE LOFT CALLS WATER?
##
## `_cat_stem_place_drive` proved a player can put one there through the app.
## This stands the same vessel at its DESIGN WATERLINE over a sea plane and
## photographs the bow, so the answer is looked at rather than inferred.
##
## The plan is applied through `DeckFitout.apply_any` — the path a SPAWNED
## vessel takes, not a bake the studio alone can reach.
##
## `CaptureSubject.hold_still` is called on the hull: a BoatBody's physics LOD
## revokes `freeze` one second after it enters the tree.

const CaptureSubject := preload("res://tests/support/capture_subject.gd")
const CaptureClock := preload("res://tests/support/capture_clock.gd")
const OUT_DIR := "res://screenshots/studio"

## Three corner facets on the forward corners, exactly the cells
## `_cat_stem_place_drive` placed by clicking.
const PLAN := {
	"format": "structure_plan_v1",
	"context": "vessel",
	"hull_id": "hull_45x16_cat",
	"pieces": [
		{"piece": "corner_45", "cell": [0, 0, 0], "facing": 0, "params": {"span": 1, "height": 5, "chain": "corner"}},
		{"piece": "corner_45", "cell": [31, 0, 0], "facing": 0, "params": {"span": 1, "height": 5, "chain": "corner"}},
		{"piece": "corner_45", "cell": [0, 0, 1], "facing": 0, "params": {"span": 1, "height": 5, "chain": "corner"}},
	],
	"walls": [],
	"decks": [],
	"stairs": [],
	"edges": [],
	"items": [],
}

var _camera: Camera3D
var _stage: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	CaptureClock.pin(get_tree())
	_hide_hud()

	_stage = Node3D.new()
	add_child(_stage)
	_light()

	var boat: Node3D = VesselSpawn.instantiate("hull_45x16_cat", {}, "")
	_stage.add_child(boat)
	CaptureSubject.hold_still(boat)
	var stations: HullStations = boat.get("hull_stations")
	var draft: float = boat.get("draft_m")
	## Float it: the design waterline sits at world y = 0.
	boat.position = Vector3(0.0, -(stations.keel_y + draft), 0.0)
	boat.process_mode = Node.PROCESS_MODE_DISABLED

	var grid := HullRegistry.make_grid("hull_45x16_cat")
	DeckFitout.apply_any(boat, PLAN.duplicate(true), grid)
	for i in range(6):
		await get_tree().process_frame

	print("  deck_y %.3f, keel_y %.3f, draft %.3f -> deck stands %.3f m above the sea"
		% [stations.deck_y, stations.keel_y, draft, stations.deck_y - (stations.keel_y + draft)])
	_report_pieces(boat)

	_sea()

	_camera = Camera3D.new()
	_camera.fov = 32.0
	_stage.add_child(_camera)

	await _shoot("cat_stem_piece__bow_low", Vector3(-17.0, 2.6, -40.0), Vector3(-6.0, 3.5, -21.0))
	await _shoot("cat_stem_piece__bow_on", Vector3(0.0, 3.2, -46.0), Vector3(0.0, 4.2, -22.0))
	await _shoot("cat_stem_piece__under_the_bow", Vector3(-13.0, -1.2, -34.0), Vector3(-6.0, 4.0, -21.5))
	print("SEA SHOT DONE")
	get_tree().quit(0)


func _report_pieces(boat: Node) -> void:
	var count := 0
	var bounds := AABB()
	var have := false
	for node in _descendants(boat):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not str(mi.name).to_lower().contains("piece") \
				and not str(mi.get_parent().name).to_lower().contains("fitout"):
			continue
		count += 1
		var a := mi.global_transform * mi.mesh.get_aabb()
		if have:
			bounds = bounds.merge(a)
		else:
			bounds = a
			have = true
	print("  fitout drew %d mesh instances; bounds pos %v size %v"
		% [count, bounds.position.snappedf(0.001), bounds.size.snappedf(0.001)])


func _sea() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	sea.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.26, 0.34)
	mat.roughness = 0.25
	sea.material_override = mat
	sea.position = Vector3.ZERO
	_stage.add_child(sea)


func _light() -> void:
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
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.85)
	env.ambient_light_energy = 0.85
	we.environment = env
	_stage.add_child(we)


func _shoot(stem: String, eye: Vector3, look: Vector3) -> void:
	_camera.position = eye
	_camera.look_at(look, Vector3.UP)
	_camera.current = true
	await CaptureClock.settle(get_tree(), 6)
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, stem]))
	print("  wrote %s/%s.png" % [OUT_DIR, stem])


func _hide_hud() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas(child)


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas(child)


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out
