extends Node3D

## SCRATCH CAPTURE (leading underscore — not a gate unit, the gate must not
## discover it). Owner decision 1b: the sign the cache was throwing away.
##
##   Q1B_VARIANT=after xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_q1b_sign_shot.tscn
##
## Renders `resources/data/buildings/warehouse.json` through the PRODUCTION
## path — `BuildingCache.instance(layout, …)`, the call
## `port_layout_graph_visualizer._stamp_apron_pads` makes — so the frame shows
## the tree the game shows and not `BuildingFitout`'s, which is one layer above
## the defect and has always drawn the sign correctly.
##
## Rig lifted verbatim from `_q1_cell_shot.gd`, and the reasons it gives hold
## here too: shadows explicitly ON, a PALE sky so the silhouette has a boundary,
## a 1.8 m figure IN THE SAME PLANE as the wall being measured, and an
## ORTHOGRAPHIC camera because a perspective frame of this exact warehouse was
## misread by 2.4x. The camera is HARDCODED, identical in both variants: the
## whole comparison is "is there lettering on that wall", and a camera that
## re-fits per variant answers a different question.
##
## `before` is shot with `BuildingCache` reverted to the mesh-only filter;
## `after` with the fix in. Nothing else differs between the two frames.

const OUT_DIR := "res://screenshots/decisions"

## Framed on the front (−Z) wall and the left-hand cargo door, close enough that
## 0.93 m letters are readable and wide enough that the 1.8 m figure beside the
## door still gives the frame an absolute scale.
const ELEV_ORTHO_SIZE := 11.0
const ELEV_CENTRE := Vector3(0.0, 4.0, 0.0)
const ELEV_DISTANCE := 80.0

var _camera: Camera3D
var _variant := "after"


func _ready() -> void:
	_variant = OS.get_environment("Q1B_VARIANT")
	if _variant.is_empty():
		_variant = "after"

	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		printerr("[q1b] warehouse blueprint did not load")
		get_tree().quit(1)
		return

	BuildingCache.clear()
	var building := BuildingCache.instance(layout, false)
	add_child(building)

	## The claim in words, printed beside the frame, so the picture is not the
	## only evidence and the two can disagree in public.
	var labels := _labels(building)
	printerr("[q1b] variant=%s  stamped meshes=%d  stamped Label3D=%d"
		% [_variant, _count_class(building, "MeshInstance3D"), labels.size()])
	for label in labels:
		printerr("[q1b]   sign text=%s  pos=%s  facing=%s  letters=%.3f m"
			% [label.text, str(label.global_position.snapped(Vector3.ONE * 0.001)),
				str(label.global_basis.z.snapped(Vector3.ONE * 0.001)),
				label.pixel_size * float(label.font_size)])

	## A slab, not a PlaneMesh: a plane is edge-on in an elevation and draws
	## nothing, leaving the frame with no ground line.
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

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	## Against the front face, a metre clear of the wall, on the −Z (camera) side,
	## and on PLAIN WALL rather than over a door — the first placement stood half
	## behind the right-hand door leaf, which is the "figure rendered perfectly
	## and appeared in no usable frame" failure in miniature (REALITY.md §8).
	## Directly under the sign, so letter height and body height are read off the
	## same column of pixels.
	var figure := _make_figure()
	figure.position = Vector3(-1.2, 0.0, -7.2)
	add_child(figure)

	await _elevation()
	get_tree().quit(0)


func _elevation() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ELEV_ORTHO_SIZE
	_camera.position = ELEV_CENTRE + Vector3(0.0, 0.0, -ELEV_DISTANCE)
	_camera.look_at(ELEV_CENTRE, Vector3.UP)
	var image := await _frame()
	var path := "%s/q1b_building_sign__%s__elevation.png" % [OUT_DIR, _variant]
	printerr("[q1b] %s (%d)" % [path, image.save_png(path)])


func _frame() -> Image:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


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


func _labels(node: Node) -> Array[Label3D]:
	var out: Array[Label3D] = []
	if node is Label3D:
		out.append(node as Label3D)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func _count_class(node: Node, cls: String) -> int:
	var count := 0
	for child in node.get_children():
		if child.is_class(cls):
			count += 1
		count += _count_class(child, cls)
	return count


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
