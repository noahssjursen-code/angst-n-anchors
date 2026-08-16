extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit, the gate must not
## discover it).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_roof_eave_shot.tscn
##
## THE QUESTION: does the eave close? The warehouse's roof hung 0.820 m clear of
## its walls with daylight right round, in EVERY brick-cell arm, and this shoots
## the same building before and after the fix from the same camera in the same
## process.
##
## ── ⚠ IT DOES NOT RUN AGAINST THE SHIPPED TREE, BY DESIGN ─────────────────
##
## Same constraint and same discipline as `_q1_arms_shot.gd`, from which the rig
## is lifted: a `const` cannot be varied inside one process, so three things
## must be storage-class-changed first, TEMPORARILY, and put back and verified
## by CONTENT HASH afterwards:
##
##   scripts/port/building_grid.gd   const CELL_M -> static var CELL_M
##   scripts/ship/brick_catalog.gd   static var CELL_M_OVERRIDE + _cell_m()
##   scripts/ship/brick_catalog.gd   static var PLATE_ON_CEILING, consulted by
##                                   `roof_plate_offset_y`
##
## The rig writes them through the script object and READS THEM BACK, and
## REFUSES TO SHOOT if a write did not take — four frames labelled before/after
## that were all the same frame would be a worse lie than shooting nothing.
##
## ── FOUR FRAMES, TWO VARIABLES ─────────────────────────────────────────────
##
## arm    = which brick cell the owner is still deciding between
##          `shipped` (brick 0.5 m on a 1.0 m lattice) and `brick-1.0m`.
## state  = `before` (plate pinned to the cell ceiling — the shipped bug) and
##          `after` (plate seated on the cell floor).
##
## The camera, lights, sky, ground, clock and driver are literally the same
## objects across all four. Nothing but the two variables can differ.
##
## ── THE TWO VIEWS ──────────────────────────────────────────────────────────
##
## `elevation` — the whole building, orthographic, FIXED lens across all four
## frames, with a 1.8 m figure standing on the ground beside the door.
## `eave` — a 3.2 m orthographic crop of the top-left wall/roof junction, which
## is where the daylight is. It carries a SECOND 1.8 m figure standing ON the
## drawn roof at the eave, placed per frame from the measured roof top by one
## rule that is the same in every frame, so the detail has absolute scale too
## and the reader can see whether that roof is at a height a person could be on.

const CaptureClock := preload("res://tests/support/capture_clock.gd")

var _building_grid_script: GDScript = load("res://scripts/port/building_grid.gd")
var _brick_catalog_script: GDScript = load("res://scripts/ship/brick_catalog.gd")

const OUT_DIR := "res://screenshots/decisions"
const PREFIX := "q1d_roof_eave"

const ELEV_ORTHO_SIZE := 14.0
const ELEV_CENTRE := Vector3(0.0, 3.6, 0.0)
const ELEV_DISTANCE := 80.0
const EAVE_ORTHO_SIZE := 3.2

const FRAMES: Array[Dictionary] = [
	{"arm": "shipped", "brick_cell": 0.0, "state": "before", "ceiling": true},
	{"arm": "shipped", "brick_cell": 0.0, "state": "after", "ceiling": false},
	{"arm": "brick-1.0m", "brick_cell": 1.0, "state": "before", "ceiling": true},
	{"arm": "brick-1.0m", "brick_cell": 1.0, "state": "after", "ceiling": false},
]

var _camera: Camera3D
var _ground_figure: Node3D
var _roof_figure: Node3D
var _source: Dictionary = {}


func _ready() -> void:
	if not _overrides_are_settable():
		printerr("[eave] REFUSING TO SHOOT. The three constants are still `const`, "
			+ "so every frame would render the shipped state and four frames "
			+ "would be identical under four names. Apply the TEMPORARY edits "
			+ "named in this file's header, shoot, then revert and verify by "
			+ "content hash.")
		get_tree().quit(1)
		return

	var pinned := CaptureClock.pin(get_tree())
	print("[eave] clock pinned to %.3f" % pinned)

	var src := BuildingBlueprintCatalog.by_id("warehouse")
	if src == null:
		printerr("[eave] warehouse blueprint did not load")
		get_tree().quit(1)
		return
	_source = src.to_dict()

	_hide_autoload_ui()
	_light()
	_ground()
	_ground_figure = _make_figure(Color(0.95, 0.30, 0.06))
	add_child(_ground_figure)
	_roof_figure = _make_figure(Color(0.10, 0.32, 0.85))
	add_child(_roof_figure)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for frame in FRAMES:
		await _shoot(frame)

	_set_overrides(0.0, false)
	print("[eave] restored in-process: size_m(block)=%s  plate_on_ceiling=%s"
		% [str(BrickCatalog.size_m("block")), str(BrickCatalog.PLATE_ON_CEILING)])
	get_tree().quit(0)


func _set_overrides(brick_cell: float, ceiling: bool) -> void:
	_brick_catalog_script.set("CELL_M_OVERRIDE", brick_cell)
	_brick_catalog_script.set("PLATE_ON_CEILING", ceiling)


## Setting a `const` through `set()` is a silent no-op, so prove the writes took
## by reading the DRAWN numbers back out — not the variables, the things they
## feed.
func _overrides_are_settable() -> bool:
	_set_overrides(1.0, true)
	var brick_moved := absf(BrickCatalog.size_m("block").x - 1.0) < 0.0001
	var ceiling_top := BrickCatalog.roof_plate_offset_y("roof_flat_4x4")
	_set_overrides(1.0, false)
	var floor_seat := BrickCatalog.roof_plate_offset_y("roof_flat_4x4")
	_set_overrides(0.0, false)
	var seat_moved := absf(ceiling_top - floor_seat) > 0.0001
	if not (brick_moved and seat_moved):
		printerr("[eave] probe: brick %.3f (wanted 1.000), seat ceiling %.4f vs "
			% [BrickCatalog.size_m("block").x, ceiling_top]
			+ "floor %.4f (wanted different)" % floor_seat)
	return brick_moved and seat_moved


func _shoot(frame: Dictionary) -> void:
	var arm := str(frame["arm"])
	var state := str(frame["state"])
	_set_overrides(float(frame["brick_cell"]), bool(frame["ceiling"]))
	BuildingCache.clear()

	var layout := BuildingLayout.from_dict(_source.duplicate(true))
	var fitout := BuildingFitout.build(layout, false)
	add_child(fitout)

	## Drawn extents, per family, off the nodes in the live tree.
	var wall_top := -INF
	var roof_bottom := INF
	var roof_top := -INF
	var roof_min_x := INF
	var front_z := INF
	for child in fitout.get_children():
		if not (child is Node3D):
			continue
		var raw := str(child.name)
		var cut := raw.rfind("_")
		var brick_id := raw.substr(0, cut) if cut > 0 else raw
		var aabb := _bounds(child)
		if aabb.size == Vector3.ZERO:
			continue
		if brick_id == "block":
			wall_top = maxf(wall_top, aabb.position.y + aabb.size.y)
			front_z = minf(front_z, aabb.position.z)
		elif BrickCatalog.is_flat_roof(brick_id):
			roof_bottom = minf(roof_bottom, aabb.position.y)
			roof_top = maxf(roof_top, aabb.position.y + aabb.size.y)
			roof_min_x = minf(roof_min_x, aabb.position.x)

	var name := "%s-%s" % [arm, state]
	print("")
	print("[eave] ===== %s =====" % name)
	print("[eave] %s: brick %.3f m on a %.3f m lattice"
		% [name, BrickCatalog.size_m("block").x, BuildingGrid.CELL_M])
	print("[eave] %s: wall head %.4f  roof underside %.4f  roof top %.4f"
		% [name, wall_top, roof_bottom, roof_top])
	print("[eave] %s: DAYLIGHT UNDER THE EAVE = %.4f m" % [name, roof_bottom - wall_top])

	## Ground figure: fixed world position in every frame — it is the ruler.
	_ground_figure.position = Vector3(-11.4, 0.0, -9.0)
	## Roof figure: derived per frame from the measured roof top at the left
	## eave, by one rule. It has to move, because the roof is what moved.
	_roof_figure.position = Vector3(roof_min_x + 1.2, roof_top, front_z - 0.9)

	await _frame(name, "elevation", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = ELEV_ORTHO_SIZE
		_camera.position = ELEV_CENTRE + Vector3(0.0, 0.0, -ELEV_DISTANCE)
		_camera.look_at(ELEV_CENTRE, Vector3.UP))

	## The eave crop is centred on the LATTICE junction, not on the drawn roof —
	## if it tracked the roof the roof would be in the middle of every frame and
	## the reader could not see it move.
	var eave_centre := Vector3(roof_min_x + 1.1, BuildingGrid.CELL_M * 6.0, 0.0)
	await _frame(name, "eave", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = EAVE_ORTHO_SIZE
		_camera.position = eave_centre + Vector3(0.0, 0.0, -ELEV_DISTANCE)
		_camera.look_at(eave_centre, Vector3.UP))

	remove_child(fitout)
	fitout.free()


func _frame(name: String, view: String, pose: Callable) -> void:
	pose.call()
	await CaptureClock.settle(get_tree(), 6)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s__%s__%s.png" % [OUT_DIR, PREFIX, name, view]
	print("[eave] %s (%d)" % [path, image.save_png(path)])


## ── RIG (lifted from `_q1_arms_shot.gd`) ───────────────────────────────────


func _ground() -> void:
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(64.0, 0.6, 64.0)
	ground.mesh = slab
	ground.position = Vector3(0.0, -0.3, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.44, 0.45, 0.42)
	ground.material_override = ground_mat
	add_child(ground)


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


func _make_figure(color: Color) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.28
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	body.material_override = mat
	root.add_child(body)
	return root


func _light() -> void:
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.74, 0.80, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.70, 0.78)
	environment.ambient_light_energy = 0.60
	env.environment = environment
	add_child(env)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
