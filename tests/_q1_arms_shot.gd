extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit, the gate must not
## discover it). Owner decision #1: the brick cell on land.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_q1_arms_shot.tscn
##
## ── WHY THIS EXISTS WHEN `_q1_cell_shot.gd` ALREADY DID ────────────────────
##
## `_q1_cell_shot` shoots ONE arm per process, named by `Q1_VARIANT`, and the
## arm is selected by hand-editing `BrickCatalog` / `BuildingGrid` between runs.
## That is how the shipped `q1_brick_cell__*` set came to be three-quarters
## stale: a later wave could refresh only the `today` arm (the other two need
## constants it was fenced from touching), and a three-way comparison with one
## fresh arm is worse than one with none, because the reader sees a difference
## that is not the variable.
##
## This rig shoots EVERY arm in ONE process, so the camera, the lights, the sky,
## the ground, the clock and the driver are literally the same objects across all
## four arms. Nothing but the variable can differ.
##
## ── ⚠ IT DOES NOT RUN AGAINST THE SHIPPED TREE, BY DESIGN ─────────────────
##
## Varying a `const` inside one process is impossible, so the two constants have
## to be storage-class-changed first. That change is TEMPORARY — the tree ships
## with the `const`s, and this wave put them back and checked by content hash.
## The rig therefore sets them through the script object rather than by
## assignment (so this file still compiles against the shipped tree), READS THEM
## BACK, and refuses to shoot if the write did not take. **A rig that silently
## no-ops here would emit four identical frames labelled as three different
## options, which is a worse lie than shooting nothing.**
##
## To run it, apply exactly these two edits and revert them afterwards:
##
##   scripts/port/building_grid.gd
##     -  const CELL_M := 1.0
##     +  static var CELL_M := 1.0
##
##   scripts/ship/brick_catalog.gd
##     +  static var CELL_M_OVERRIDE := 0.0
##     +  static func _cell_m() -> float:
##     +      return CELL_M_OVERRIDE if CELL_M_OVERRIDE > 0.0 else DeckGrid.CELL_M
##     ... and in `size_m` and `create_visual`, `DeckGrid.CELL_M` -> `_cell_m()`.
##
## Rig lifted from `_q1_cell_shot.gd`, which lifted it from `_warehouse_shot.gd`,
## which lifted it from `vessel_render_capture.gd`: shadows explicitly ON, a PALE
## sky so the silhouette has a boundary, 1.8 m figures IN THE SAME PLANE as the
## subject, and an ORTHOGRAPHIC camera, because a perspective frame of this exact
## warehouse was misread by 2.4x.
##
## THE CAMERA IS HARDCODED, not fitted to the model's bounds. A fitted camera
## re-frames each arm to fill the frame and destroys the one comparison the owner
## is being asked to make, which is how big the thing is.
##
## ── THE TWO FIGURES, AND WHY IT IS TWO ─────────────────────────────────────
##
## ORANGE stands at a FIXED world position in every arm. It is the ruler: it
## never moves, so the building visibly grows and shrinks against it.
##
## BLUE stands 1.2 m in front of the building's own left-hand cargo door,
## derived per arm from the drawn door AABB by one rule that is the same in every
## arm. It has to move, because the door moves — that IS the variable — and a
## scale figure that is not beside the thing whose scale is in question answers
## nothing. Between them the frame carries both properties: "how big is the
## building" and "does a 1.8 m player fit through that door".

const CaptureClock := preload("res://tests/support/capture_clock.gd")

## `load()` into a plain `GDScript` var, NOT `const X := preload(...)`. A const
## preload is folded into the CLASS by the parser, and `BuildingGrid.set(...)` is
## then a parse error — "Cannot call non-static function set() on the class
## directly" — which fails the whole scene to load and leaves the process
## spinning with no `quit()` to reach. Measured, not guessed: that is exactly how
## the first cut of this indirection died.
var _building_grid_script: GDScript = load("res://scripts/port/building_grid.gd")
var _brick_catalog_script: GDScript = load("res://scripts/ship/brick_catalog.gd")

const OUT_DIR := "res://screenshots/decisions"
const PREFIX := "q1_cell_arms"

## Fixed for every arm. Chosen off the TODAY bake (6.50 m tall, 20 m wide) with
## room above and around for the grown arms.
const ELEV_ORTHO_SIZE := 14.0
const ELEV_CENTRE := Vector3(0.0, 3.6, 0.0)
const ELEV_DISTANCE := 80.0
const QUARTER_ORTHO_SIZE := 26.0
const QUARTER_DISTANCE := 80.0
const DOOR_ORTHO_SIZE := 6.5

## brick_cell: 0.0 means "leave BrickCatalog alone" (= DeckGrid.CELL_M = 0.5).
const ARMS: Array[Dictionary] = [
	{"name": "a-today", "brick_cell": 0.0, "grid_cell": 1.0, "reauthor": false},
	{"name": "b-brick-1.0m", "brick_cell": 1.0, "grid_cell": 1.0, "reauthor": false},
	{"name": "c-grid-0.5m", "brick_cell": 0.0, "grid_cell": 0.5, "reauthor": false},
	{"name": "c-grid-0.5m-reauthored", "brick_cell": 0.0, "grid_cell": 0.5, "reauthor": true},
]

var _camera: Camera3D
var _ruler: Node3D
var _door_figure: Node3D
var _subject: Node3D
var _source: Dictionary = {}


func _ready() -> void:
	if not _constants_are_settable():
		printerr("[q1arms] REFUSING TO SHOOT. `BuildingGrid.CELL_M` and/or the brick "
			+ "cell are still `const`, so every arm would render the shipped state "
			+ "and the four frames would be identical under three different names. "
			+ "Apply the two TEMPORARY edits named in this file's header, shoot, "
			+ "then revert them and verify by content hash.")
		get_tree().quit(1)
		return

	var pinned := CaptureClock.pin(get_tree())
	print("[q1arms] clock pinned to %.3f (‑1 == no clock in this lane)" % pinned)

	## Read the blueprint document ONCE and rebuild a fresh `BuildingLayout` for
	## every arm. The catalog hands back a shared object and the re-authoring arm
	## mutates one, so re-parsing is the only way an arm cannot contaminate the
	## next.
	var src := BuildingBlueprintCatalog.by_id("warehouse")
	if src == null:
		printerr("[q1arms] warehouse blueprint did not load")
		get_tree().quit(1)
		return
	_source = src.to_dict()
	print("[q1arms] subject: %s  role=%s  grid=%s  cells=%d"
		% [src.blueprint_id, src.role, str(src.grid_size), src.cells.size()])

	_hide_autoload_ui()
	_light()
	_ground()
	_ruler = _make_figure(Color(0.95, 0.30, 0.06))
	add_child(_ruler)
	_door_figure = _make_figure(Color(0.10, 0.32, 0.85))
	add_child(_door_figure)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	for arm in ARMS:
		await _shoot_arm(arm)

	_restore_defaults()
	print("[q1arms] restored in-process: BuildingGrid.CELL_M=%.3f  size_m(block)=%s"
		% [BuildingGrid.CELL_M, str(BrickCatalog.size_m("block"))])
	get_tree().quit(0)


## Write through the script object, never by `BuildingGrid.CELL_M = x`. The
## assignment form does not compile once the constants are back, and this file
## has to survive the revert or the frames it produced have no rig.
func _set_constants(brick_cell: float, grid_cell: float) -> void:
	_brick_catalog_script.set("CELL_M_OVERRIDE", brick_cell)
	_building_grid_script.set("CELL_M", grid_cell)


## Setting a `const` through `set()` is a silent no-op, so prove the write took
## by reading the DRAWN size back out — not the variable, the thing it feeds.
func _constants_are_settable() -> bool:
	var grid_before: Variant = _building_grid_script.get("CELL_M")
	var brick_before := BrickCatalog.size_m("block").x
	_set_constants(1.0, 0.5)
	var moved := (
		absf(float(_building_grid_script.get("CELL_M")) - 0.5) < 0.0001
		and absf(BrickCatalog.size_m("block").x - 1.0) < 0.0001)
	_set_constants(0.0, float(grid_before) if grid_before != null else 1.0)
	if not moved:
		printerr("[q1arms] probe: grid %s (wanted 0.5), brick %.3f (wanted 1.000), "
			% [str(_building_grid_script.get("CELL_M")), BrickCatalog.size_m("block").x]
			+ "shipped brick was %.3f" % brick_before)
	return moved


func _restore_defaults() -> void:
	_set_constants(0.0, 1.0)


func _shoot_arm(arm: Dictionary) -> void:
	var name := str(arm["name"])
	_set_constants(float(arm["brick_cell"]), float(arm["grid_cell"]))
	## Prototypes are baked at the constants that were live when they were baked.
	BuildingCache.clear()

	var layout := BuildingLayout.from_dict(_source.duplicate(true))
	if bool(arm["reauthor"]):
		layout = _reauthor_doubled(layout)

	print("")
	print("[q1arms] ===== ARM %s =====" % name)
	print("[q1arms] %s: BuildingGrid.CELL_M=%.3f  BrickCatalog.size_m(block)=%s"
		% [name, BuildingGrid.CELL_M, str(BrickCatalog.size_m("block"))])

	var door_aabb := _measure_fitout(name, layout)

	_subject = BuildingCache.instance(layout, false)
	add_child(_subject)

	var bounds := _bounds(_subject)
	print("[q1arms] %s: STAMPED meshes %d  AABB pos %s size %s"
		% [name, _mesh_count(_subject), str(bounds.position), str(bounds.size)])
	print("[q1arms] %s: WIDTH %.2f m  HEIGHT %.2f m  DEPTH %.2f m  ground gap %.3f m"
		% [name, bounds.size.x, bounds.size.y, bounds.size.z, bounds.position.y])

	## ── figure placement ───────────────────────────────────────────────────
	## Fixed ruler: outside every arm's footprint on the left, in the frame in
	## both poses. Same six numbers in all four arms.
	var front_z := bounds.position.z
	var back_z := bounds.position.z + bounds.size.z
	var door_x := door_aabb.position.x + door_aabb.size.x * 0.5
	if door_aabb.size == Vector3.ZERO:
		door_x = bounds.position.x + bounds.size.x * 0.25
	print("[q1arms] %s: door figure at x %.2f (door AABB pos %s size %s)"
		% [name, door_x, str(door_aabb.position), str(door_aabb.size)])

	## ELEVATION: camera sits at −Z and looks at +Z, so −Z is the near face.
	_ruler.position = Vector3(-11.4, 0.0, -9.0)
	_door_figure.position = Vector3(door_x, 0.0, front_z - 1.2)
	await _shot(name, "elevation", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = ELEV_ORTHO_SIZE
		_camera.position = ELEV_CENTRE + Vector3(0.0, 0.0, -ELEV_DISTANCE)
		_camera.look_at(ELEV_CENTRE, Vector3.UP))

	## QUARTER: camera swings to +X/−Z, so the near faces are the RIGHT and the
	## DOOR FACE. Azimuth is 145° and not 35° for exactly that reason — swung the
	## other way the near faces are the blank back and the blank left end, and
	## the first cut of this rig photographed a warehouse with no doors in it.
	_ruler.position = Vector3(11.6, 0.0, -11.0)
	_door_figure.position = Vector3(door_x, 0.0, front_z - 1.2)
	await _shot(name, "quarter", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = QUARTER_ORTHO_SIZE
		var dir := Vector3(
			sin(deg_to_rad(145.0)) * cos(deg_to_rad(16.0)),
			sin(deg_to_rad(16.0)),
			cos(deg_to_rad(145.0)) * cos(deg_to_rad(16.0)))
		_camera.position = ELEV_CENTRE + dir * QUARTER_DISTANCE
		_camera.look_at(ELEV_CENTRE, Vector3.UP))

	## DOOR DETAIL. THIS IS THE ONE VIEW WHOSE CENTRE MOVES, and it is stated
	## rather than hidden: it centres on the arm's OWN left-hand cargo door,
	## because the door is what moved and a detail of empty wall answers nothing.
	## The LENS does not change — same orthographic projection, same fixed size
	## in every arm — so a metre is the same number of pixels in all four frames
	## and the doors remain directly comparable to each other and to the figure.
	var door_centre := Vector3(door_x, DOOR_ORTHO_SIZE * 0.42, 0.0)
	await _shot(name, "door", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = DOOR_ORTHO_SIZE
		_camera.position = door_centre + Vector3(0.0, 0.0, -ELEV_DISTANCE)
		_camera.look_at(door_centre, Vector3.UP))

	remove_child(_subject)
	_subject.free()
	_subject = null


func _shot(arm: String, view: String, pose: Callable) -> void:
	pose.call()
	await CaptureClock.settle(get_tree(), 6)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s__%s__%s.png" % [OUT_DIR, PREFIX, arm, view]
	print("[q1arms] %s (%d)" % [path, image.save_png(path)])


## ── MEASUREMENT ────────────────────────────────────────────────────────────
##
## Built from `BuildingFitout.build` rather than `BuildingCache.instance`,
## because the cache flattens the tree and throws the per-brick node names away,
## and every number below is per brick id. Parented into the live tree for the
## measurement and removed again before a frame is drawn: `global_transform` is
## the LOCAL transform for a node outside the tree, which silently reported every
## course centred on y = 0 the first time this shape ran.
##
## Returns the drawn AABB of the LEFT-HAND (most −X) cargo door, which is where
## the blue figure stands.
func _measure_fitout(arm: String, layout: BuildingLayout) -> AABB:
	var fitout := BuildingFitout.build(layout, true)
	add_child(fitout)

	var lo: Dictionary = {}
	var hi: Dictionary = {}
	var per_id_count: Dictionary = {}
	var doors: Array[AABB] = []
	for child in fitout.get_children():
		if not (child is Node3D):
			continue
		## Node names are "<brick_id>_<x,y,z>" for content bricks and
		## "<x,y,z>_surface" / "<x,y,z>_floor" for the underlays; a brick id may
		## itself contain underscores, so cut at the LAST one.
		var raw := str(child.name)
		var cut := raw.rfind("_")
		var brick_id := raw.substr(0, cut) if cut > 0 else raw
		if brick_id.contains(","):
			brick_id = "floor/surface"
		var aabb := _bounds(child)
		if brick_id == "block_door_double" and aabb.size != Vector3.ZERO:
			doors.append(aabb)
		per_id_count[brick_id] = int(per_id_count.get(brick_id, 0)) + 1
		if brick_id.begins_with("roof"):
			brick_id = "roof"
		if aabb.size == Vector3.ZERO:
			continue
		if not lo.has(brick_id):
			lo[brick_id] = aabb.position.y
			hi[brick_id] = aabb.position.y + aabb.size.y
		else:
			lo[brick_id] = minf(float(lo[brick_id]), aabb.position.y)
			hi[brick_id] = maxf(float(hi[brick_id]), aabb.position.y + aabb.size.y)

	var kinds := _visual_census(fitout)
	print("[q1arms] %s: FITOUT nodes %s" % [arm, str(per_id_count)])
	print("[q1arms] %s: FITOUT visuals by class %s" % [arm, str(kinds)])
	print("[q1arms] %s: FITOUT colliders %d" % [arm, _collider_count(fitout)])

	var ids := lo.keys()
	ids.sort()
	for id_variant in ids:
		var id := str(id_variant)
		print("[q1arms] %s: drawn y %6.3f .. %6.3f  %s" % [arm, lo[id], hi[id], id])
	if lo.has("roof") and hi.has("block"):
		print("[q1arms] %s: DAYLIGHT under the roof = %.3f m (roof bottom %.3f, wall top %.3f)"
			% [arm, float(lo["roof"]) - float(hi["block"]),
				float(lo["roof"]), float(hi["block"])])

	var left := AABB()
	if not doors.is_empty():
		doors.sort_custom(func(a: AABB, b: AABB) -> bool: return a.position.x < b.position.x)
		left = doors[0]
		var merged := doors[0]
		for d in doors:
			merged = merged.merge(d)
		print("[q1arms] %s: %d door leaves drawn; leftmost drawn %.3f w x %.3f h, sill y %.3f, head y %.3f"
			% [arm, doors.size(), left.size.x, left.size.y,
				left.position.y, left.position.y + left.size.y])
		print("[q1arms] %s: a 1.8 m player %s the drawn door head (%.3f m)"
			% [arm, "CLEARS" if left.position.y + left.size.y >= 1.8 else "DOES NOT CLEAR",
				left.position.y + left.size.y])

	remove_child(fitout)
	fitout.free()
	return left


func _visual_census(node: Node) -> Dictionary:
	var kinds: Dictionary = {}
	_census_into(node, kinds)
	return kinds


func _census_into(node: Node, kinds: Dictionary) -> void:
	if node is VisualInstance3D:
		var kind := node.get_class()
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	for child in node.get_children():
		_census_into(child, kinds)


func _collider_count(node: Node) -> int:
	var n := 0
	if node is CollisionShape3D:
		n += 1
	for child in node.get_children():
		n += _collider_count(child)
	return n


## ── RE-AUTHORING THE BLUEPRINT FOR THE grid-0.5 ARM ────────────────────────
##
## Lifted verbatim from `_q1_cell_shot.gd` so the two passes are the same
## migration. Shrinking the lattice halves the building unless the blueprint is
## re-authored, and re-authoring every blueprint IS that option's stated cost —
## so the arm is shot both ways and the owner sees the option and its bill.
##
## THE RULE, and it is the only one that preserves metres. A brick with footprint
## F covers F cells. On the 1 m lattice that is F metres; on a 0.5 m lattice it is
## F/2 metres. So each primary placement becomes EIGHT placements, two per axis,
## stepped by F cells at doubled coordinates: 2F cells = F metres, restored.
##
## Floor underlays take the bottom layer only (four placements, 2x2 in plan): the
## underlay is one thin plate at the foot of a one-metre course, and two stacked
## copies would be two floors half a metre apart. That is a judgement the doubling
## rule does not make for you, which is itself part of what migration costs.
func _reauthor_doubled(src: BuildingLayout) -> BuildingLayout:
	var out := BuildingLayout.new()
	out.blueprint_id = src.blueprint_id
	out.display_name = src.display_name
	out.role = src.role
	out.pad_template_id = src.pad_template_id
	out.grid_size = src.grid_size * 2

	var content: Array[Dictionary] = []
	var surfaces: Array[Dictionary] = []
	for entry in src.iter_primary_cells():
		var cell := entry["cell"] as Vector3i
		if BuildingLayout.entry_is_surface_only(entry):
			surfaces.append({"cell": cell, "entry": entry})
			continue
		content.append({"cell": cell, "entry": entry})
		if entry.has("surface"):
			surfaces.append({"cell": cell, "entry": entry["surface"] as Dictionary})

	var placed := 0
	var refused := 0
	for job in content:
		var cell := job["cell"] as Vector3i
		var entry := job["entry"] as Dictionary
		var brick_id := str(entry.get("brick_id", ""))
		var yaw := int(entry.get("yaw", 0))
		var step := _footprint_steps(brick_id, yaw)
		var color: Variant = entry.get("color", null)
		var props: Dictionary = {}
		if entry.has("text"):
			props["text"] = str(entry["text"])
		for i in 2:
			for j in 2:
				for k in 2:
					var origin := Vector3i(
						cell.x * 2 + i * step.x,
						cell.y * 2 + j * step.y,
						cell.z * 2 + k * step.z)
					if out.place_footprint(origin, brick_id, yaw, null, color, props):
						placed += 1
					else:
						refused += 1

	var surfaced := 0
	var surface_refused := 0
	for job in surfaces:
		var cell := job["cell"] as Vector3i
		var entry := job["entry"] as Dictionary
		var brick_id := str(entry.get("brick_id", "floor"))
		var yaw := int(entry.get("yaw", 0))
		var step := _footprint_steps(brick_id, yaw)
		var color: Variant = entry.get("color", null)
		for i in 2:
			for k in 2:
				var origin := Vector3i(
					cell.x * 2 + i * step.x, cell.y * 2, cell.z * 2 + k * step.z)
				if out.place_footprint(origin, brick_id, yaw, null, color):
					surfaced += 1
				else:
					surface_refused += 1

	print("[q1arms] REAUTHOR: %d content primaries -> %d placements (%d refused); "
		% [content.size(), placed, refused]
		+ "%d surfaces -> %d placements (%d refused)"
			% [surfaces.size(), surfaced, surface_refused])
	print("[q1arms] REAUTHOR: grid %s -> %s, cells %d -> %d"
		% [str(src.grid_size), str(out.grid_size), src.cells.size(), out.cells.size()])
	return out


func _footprint_steps(brick_id: String, yaw: int) -> Vector3i:
	var fp := BrickCatalog.footprint_of(brick_id)
	var steps := int(round(float(yaw) / 90.0)) % 4
	if steps % 2 != 0:
		return Vector3i(fp.z, fp.y, fp.x)
	return fp


## ── RIG ────────────────────────────────────────────────────────────────────


## A SLAB, not a PlaneMesh. A plane is edge-on in an elevation and renders as
## nothing, so the frame has no ground line and the reader cannot see that the
## ground course floats. A 0.6 m slab with its top at y = 0 draws the line the
## whole question turns on.
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


## The scene lane boots the real autoloads and several of them draw a HUD over
## everything; it landed in the first frame of this rig too.
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
	## llvmpipe rasterises the shadow map in software; the 4096 default never
	## finished a frame on a 645-mesh building. This is the rig, not the subject.
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


func _mesh_count(node: Node) -> int:
	return _meshes(node).size()
