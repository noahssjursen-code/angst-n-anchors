extends Node3D

## SCRATCH CAPTURE (leading underscore — the gate must not discover it).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_roof_zfight_probe.tscn
##
## WHY THIS EXISTS. `tests/_prebuilt_gen.gd:340` records a MEASURED prior
## failure: a roof whose underside lands exactly on the wall top plane
## Z-FIGHTS — *"a jagged white sawtooth the full length of the house"*,
## `screenshots/vessels/iter_house/v9__house_profile_ortho.png` against
## `v6__house_profile_ortho.png` — and the note says `roof_flat` "never had that
## problem because it draws a 0.18 m slab at the TOP of its cell".
##
## Seating the plate on the cell FLOOR puts a `roof_flat*` underside exactly on
## the wall top plane on every vessel, which is the configuration that note says
## fights. Whether it actually does is a question about a rasteriser, so it is
## LOOKED AT, not reasoned about (REALITY.md §6).
##
## Shoots the 28 m coaster's deckhouse in profile and in three-quarter, at the
## shipped constants, with a 1.8 m figure standing on the deck beside it.
## No constants are set: this runs against the tree as it ships.

const CaptureClock := preload("res://tests/support/capture_clock.gd")

const OUT_DIR := "res://screenshots/decisions"
const PREFIX := "q1d_roof_eave__vessel-after"
const STEM := "28_10_m"

var _camera: Camera3D


func _ready() -> void:
	var pinned := CaptureClock.pin(get_tree())
	print("[zfight] clock pinned to %.3f" % pinned)

	var path := "res://resources/data/vessels/prebuilt/%s.json" % STEM
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var doc := parsed as Dictionary
	var layout := BrickLayout.from_dict(doc.get("brick_layout", {}) as Dictionary)
	var grid := HullRegistry.make_grid(str(doc.get("hull_id", "")))

	_hide_autoload_ui()
	_light()

	## The deckhouse only — every brick from the roof course down four, so the
	## wall/roof junction fills the frame instead of being three pixels on a
	## 28 m hull.
	var root := Node3D.new()
	add_child(root)
	var lo := INF
	var hi := -INF
	var n := 0
	var centre := Vector3.ZERO
	for item_v in layout.iter_primary_cells():
		var item := item_v as Dictionary
		var cell: Vector3i = item.get("cell", Vector3i.ZERO)
		if cell.y < 1 or cell.y > 6:
			continue
		var visual := DeckFitout.create_item_visual(root, grid, item)
		if visual == null:
			continue
		var aabb := _bounds(visual)
		if aabb.size == Vector3.ZERO:
			continue
		if BrickCatalog.is_flat_roof(str(item.get("brick_id", ""))):
			lo = minf(lo, aabb.position.y)
		if str(item.get("brick_id", "")) == "block":
			hi = maxf(hi, aabb.position.y + aabb.size.y)
		centre += aabb.position + aabb.size * 0.5
		n += 1
	if n > 0:
		centre /= float(n)
	print("[zfight] %d bricks; wall head %.4f, roof underside %.4f, joint %.4f m"
		% [n, hi, lo, lo - hi])
	print("[zfight] house centre %s" % str(centre))

	var figure := _make_figure(Color(0.95, 0.30, 0.06))
	figure.position = Vector3(centre.x + 4.2, hi - 2.5, centre.z)
	add_child(figure)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	## PROFILE: the camera looks along +X at the house side, so the wall/roof
	## junction is seen EDGE ON — which is exactly the view the v9 sawtooth
	## showed up in, and the worst case for two coplanar faces.
	var eye := Vector3(centre.x, hi + 0.05, centre.z)
	await _shot("profile", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 4.5
		_camera.position = eye + Vector3(-26.0, 0.0, 0.0)
		_camera.look_at(eye, Vector3.UP))

	var q := Vector3(centre.x, hi - 0.6, centre.z)
	await _shot("quarter", func() -> void:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 7.0
		var dir := Vector3(
			sin(deg_to_rad(145.0)) * cos(deg_to_rad(10.0)),
			sin(deg_to_rad(10.0)),
			cos(deg_to_rad(145.0)) * cos(deg_to_rad(10.0)))
		_camera.position = q + dir * 40.0
		_camera.look_at(q, Vector3.UP))

	get_tree().quit(0)


func _shot(view: String, pose: Callable) -> void:
	pose.call()
	await CaptureClock.settle(get_tree(), 6)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s__%s.png" % [OUT_DIR, PREFIX, view]
	print("[zfight] %s (%d)" % [path, image.save_png(path)])


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
