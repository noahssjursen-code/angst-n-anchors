extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit, the gate must not
## discover it). Owner decision #1: the brick cell on land.
##
##   Q1_VARIANT=today xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_q1_cell_shot.tscn
##
## Renders the SAME building (`resources/data/buildings/warehouse.json`, the only
## blueprint the game has) through the SAME camera three times. The variant is
## named by the `Q1_VARIANT` environment variable and appears in the filename;
## the RIG does not change with it, because the owner is comparing images and any
## difference that is not the variable is noise (REALITY.md §8).
##
## Rig lifted from `_warehouse_shot.gd`, which lifted it from
## `vessel_render_capture.gd`: shadows explicitly ON, a PALE sky so the
## silhouette has a boundary, a 1.8 m figure IN THE SAME PLANE as the subject,
## and — for anything a size might be read off — an ORTHOGRAPHIC camera, because
## a perspective frame of this exact warehouse was misread by 2.4x.
##
## THE CAMERA IS HARDCODED, not fitted to the model's bounds. A fitted camera
## re-frames each variant to fill the frame and destroys the one comparison the
## owner is being asked to make, which is how big the thing is.

const OUT_DIR := "res://screenshots/decisions"

## Fixed for all three variants. Chosen off the TODAY bake (6.50 m tall, 20 m
## wide) with enough room above and around for the (a) variant to grow into.
const ELEV_ORTHO_SIZE := 14.0
const ELEV_CENTRE := Vector3(0.0, 3.6, 0.0)
const ELEV_DISTANCE := 80.0
const QUARTER_ORTHO_SIZE := 26.0

var _camera: Camera3D
var _figure: Node3D
var _variant := "today"


func _ready() -> void:
	_variant = OS.get_environment("Q1_VARIANT")
	if _variant.is_empty():
		_variant = "today"
	print("[q1] variant=%s  BuildingGrid.CELL_M=%.3f  BrickCatalog.size_m(block)=%s"
		% [_variant, BuildingGrid.CELL_M, str(BrickCatalog.size_m("block"))])

	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		printerr("[q1] warehouse blueprint did not load")
		get_tree().quit(1)
		return
	if OS.get_environment("Q1_REAUTHOR") == "1":
		layout = _reauthor_doubled(layout)
	var building := BuildingCache.instance(layout, false)
	add_child(building)

	## A SLAB, not a PlaneMesh. A plane is edge-on in an elevation and renders as
	## nothing, so the frame has no ground line and the reader cannot see that
	## the ground course floats. A 0.6 m slab with its top at y = 0 draws the
	## line the whole question turns on.
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(64.0, 0.6, 64.0)
	ground.mesh = slab
	ground.position = Vector3(0.0, -0.3, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.44, 0.45, 0.42)
	ground.material_override = ground_mat
	add_child(ground)

	_hide_autoload_ui()

	_light()

	var bounds := _bounds(building)
	print("[q1] %s: meshes %d  AABB pos %s size %s"
		% [_variant, _mesh_count(building), str(bounds.position), str(bounds.size)])
	print("[q1] %s: WIDTH %.2f m  HEIGHT %.2f m  DEPTH %.2f m  ground gap %.3f m"
		% [_variant, bounds.size.x, bounds.size.y, bounds.size.z, bounds.position.y])

	_report_courses(layout)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	## The figure stands against the FRONT face, in the same plane as the wall it
	## is measuring, not off a corner — the mistake that produced the 2.4x
	## misreading. -Z is the camera side.
	## Beside the left-hand cargo door (world x = -5), a metre clear of the front
	## wall, so the frame answers "does a 1.8 m player fit through that door"
	## without anyone typing a number.
	_figure = _make_figure()
	_figure.position = Vector3(-6.9, 0.0, -7.2)
	add_child(_figure)

	await _elevation()
	await _quarter()
	get_tree().quit(0)


## ── RE-AUTHORING THE BLUEPRINT FOR (b) ─────────────────────────────────────
##
## (b)'s stated cost is that every blueprint has to be re-authored. Rendering
## (b) against the un-migrated `warehouse.json` therefore photographs
## (b)-minus-the-work, and "the door is shorter than the player" is then a fact
## about an un-migrated file, not an argument about the option. This builds the
## migrated blueprint IN MEMORY — nothing is written to the tree — so (b) can be
## judged on the building it is actually proposing.
##
## THE RULE, and it is the only one that preserves metres. A brick with
## footprint F covers F cells. On the 1 m lattice that is F metres; on a 0.5 m
## lattice it is F/2 metres. So each primary placement becomes EIGHT placements,
## two per axis, stepped by F cells at doubled coordinates: 2F cells = F metres,
## the authored size, restored.
##
## Floor underlays take the bottom layer only (four placements, 2x2 in plan):
## the underlay is one thin plate at the foot of a one-metre course, and two
## stacked copies would be two floors half a metre apart. This is a judgement
## the doubling rule does not make for you, which is itself part of the answer
## to "what does migration cost".
##
## Content is placed before surfaces because `_place_content` refuses a cell
## that already holds content while `_place_surface` attaches to one — the same
## order the editor would produce.
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
	var footprints: Dictionary = {}
	for job in content:
		var cell := job["cell"] as Vector3i
		var entry := job["entry"] as Dictionary
		var brick_id := str(entry.get("brick_id", ""))
		var yaw := int(entry.get("yaw", 0))
		var step := _footprint_steps(brick_id, yaw)
		footprints[brick_id] = step
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
		footprints[brick_id] = step
		var color: Variant = entry.get("color", null)
		for i in 2:
			for k in 2:
				var origin := Vector3i(
					cell.x * 2 + i * step.x, cell.y * 2, cell.z * 2 + k * step.z)
				if out.place_footprint(origin, brick_id, yaw, null, color):
					surfaced += 1
				else:
					surface_refused += 1

	print("[q1] REAUTHOR: %d content primaries -> %d placements (%d refused); "
		% [content.size(), placed, refused]
		+ "%d surfaces -> %d placements (%d refused)"
			% [surfaces.size(), surfaced, surface_refused])
	print("[q1] REAUTHOR: grid %s -> %s, cells %d -> %d"
		% [str(src.grid_size), str(out.grid_size), src.cells.size(), out.cells.size()])
	## A brick wider than one cell is drawn ONCE per placement, so eight copies of
	## it are eight of the thing, not one of it at twice the size. That tiles for
	## a plain slab and does not for anything with internal structure.
	var ids := footprints.keys()
	ids.sort()
	for id_variant in ids:
		var id := str(id_variant)
		var fp := footprints[id] as Vector3i
		var multi := fp.x > 1 or fp.y > 1 or fp.z > 1
		print("[q1] REAUTHOR: %-18s footprint %s  %s"
			% [id, str(fp), "MULTI-CELL — 8 copies, not one" if multi else "tiles"])
	return out


func _count_non_mesh(node: Node) -> Dictionary:
	var count := 0
	var kinds: Dictionary = {}
	for child in node.get_children():
		if child is MeshInstance3D:
			continue
		if child is VisualInstance3D or child is Light3D:
			count += 1
			var kind := child.get_class()
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			continue
		var sub := _count_non_mesh(child)
		count += int(sub["count"])
		for key in (sub["kinds"] as Dictionary):
			kinds[key] = int(kinds.get(key, 0)) + int((sub["kinds"] as Dictionary)[key])
	return {"count": count, "kinds": kinds}


func _footprint_steps(brick_id: String, yaw: int) -> Vector3i:
	var fp := BrickCatalog.footprint_of(brick_id)
	var steps := int(round(float(yaw) / 90.0)) % 4
	if steps % 2 != 0:
		return Vector3i(fp.z, fp.y, fp.x)
	return fp


## Per-brick-id drawn extents, so the roof/wall daylight in the frames is a
## measured number and not something I eyeballed off a picture. Built from
## `BuildingFitout.build` rather than `BuildingCache.instance` because the cache
## flattens the tree and throws the per-brick node names away.
func _report_courses(layout: BuildingLayout) -> void:
	## Parented into the live tree for the measurement and removed again before a
	## single frame is drawn: `Node3D.global_transform` is the LOCAL transform
	## for a node outside the tree, which silently reported every course centred
	## on y = 0 the first time this ran.
	var fitout := BuildingFitout.build(layout, false)
	add_child(fitout)
	var lo: Dictionary = {}
	var hi: Dictionary = {}
	for child in fitout.get_children():
		if not (child is Node3D):
			continue
		## Node names are "<brick_id>_<x,y,z>" for content bricks and
		## "<x,y,z>_surface" / "<x,y,z>_floor" for the underlays; a brick id may
		## itself contain underscores, so cut at the LAST one and bucket
		## anything that still smells of a cell key as floor.
		var raw := str(child.name)
		var cut := raw.rfind("_")
		var brick_id := raw.substr(0, cut) if cut > 0 else raw
		if brick_id.contains(","):
			brick_id = "floor/surface"
		if brick_id.begins_with("roof"):
			brick_id = "roof"
		var aabb := _bounds(child)
		if aabb.size == Vector3.ZERO:
			continue
		if not lo.has(brick_id):
			lo[brick_id] = aabb.position.y
			hi[brick_id] = aabb.position.y + aabb.size.y
		else:
			lo[brick_id] = minf(float(lo[brick_id]), aabb.position.y)
			hi[brick_id] = maxf(float(hi[brick_id]), aabb.position.y + aabb.size.y)
	## `BuildingCache._flatten_visuals` rebuilds MeshInstance3D and ONLY
	## MeshInstance3D; anything else is recursed into and, having no mesh
	## children, dropped. Count what the fitout draws that is not a mesh, so the
	## claim is a measurement and not a code read.
	var non_mesh := _count_non_mesh(fitout)
	print("[q1] %s: BuildingFitout draws %d non-MeshInstance3D visuals (%s)"
		% [_variant, int(non_mesh["count"]), str(non_mesh["kinds"])])

	var ids := lo.keys()
	ids.sort()
	for id_variant in ids:
		var id := str(id_variant)
		print("[q1] %s: drawn y %6.3f .. %6.3f  %s" % [_variant, lo[id], hi[id], id])
	if lo.has("roof") and hi.has("block"):
		print("[q1] %s: DAYLIGHT under the roof = %.3f m (roof bottom %.3f, wall top %.3f)"
			% [_variant, float(lo["roof"]) - float(hi["block"]),
				float(lo["roof"]), float(hi["block"])])
	remove_child(fitout)
	fitout.free()


## Orthographic front elevation. Pixel height is proportional to world height at
## any depth, so a reader may take a size off this frame and be right.
func _elevation() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ELEV_ORTHO_SIZE
	_camera.position = ELEV_CENTRE + Vector3(0.0, 0.0, -ELEV_DISTANCE)
	_camera.look_at(ELEV_CENTRE, Vector3.UP)
	var image := await _frame()
	var path := "%s/q1_brick_cell__%s__elevation.png" % [OUT_DIR, _variant]
	print("[q1] %s (%d)" % [path, image.save_png(path)])


## Same orthographic lens, swung round for a solidity read — gaps in a wall are
## easier to see raking than square on.
func _quarter() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = QUARTER_ORTHO_SIZE
	## Moved to the NEAR wall for this view only — behind the building in the
	## elevation pose it is occluded. Same position in all three variants, which
	## is the property that matters, and the lens is orthographic so its pixel
	## height is still proportional to its world height wherever it stands.
	_figure.position = Vector3(-9.0, 0.0, 7.4)
	var dir := Vector3(sin(deg_to_rad(-35.0)) * cos(deg_to_rad(16.0)),
		sin(deg_to_rad(16.0)), cos(deg_to_rad(-35.0)) * cos(deg_to_rad(16.0)))
	_camera.position = ELEV_CENTRE + dir * 80.0
	_camera.look_at(ELEV_CENTRE, Vector3.UP)
	var image := await _frame()
	var path := "%s/q1_brick_cell__%s__quarter.png" % [OUT_DIR, _variant]
	print("[q1] %s (%d)" % [path, image.save_png(path)])


func _frame() -> Image:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


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


func _make_figure() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.28
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.30, 0.06)
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
