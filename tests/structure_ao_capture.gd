extends Node

## Photographs the AO rig fixture twice — the bake exactly as it ships today,
## and the same plan re-emitted through StructureAO — so the claim "this is why
## the vessels read as stacked cardboard" can be looked at instead of argued
## about. Lane B (scene), because it renders.
##
## The AO side of this file is also the WORKING DEMO of the call site described
## at the top of scripts/construction/structure_ao.gd: build one solver for the
## plan, emit every layer through `ao.append_box`, and set
## `vertex_color_use_as_albedo` on the bucket material. If that recipe is wrong,
## this capture comes out identical to the flat one and the test says so.
##
## A picture is not a test result (CONVENTIONS.md 3): the machine-checkable
## claims are that both bakes exist, that AO costs no extra surfaces, that the
## AO mesh actually carries a colour channel, that neither frame is blank, and
## that the AO frame is measurably darker in mean luminance than the flat one.
## The assertions that pin the SOLVER live in tests/structure_ao_test.gd.

const RIG := "res://resources/data/structures/probe_ao_junction.json"
const OUT_DIR := "res://screenshots/studio"
const VIEWS := {
	"three_quarter": {"eye": Vector3(24.0, 11.0, -10.0), "at": Vector3(7.0, 1.6, 7.0)},
	"junction": {"eye": Vector3(9.5, 3.4, -3.0), "at": Vector3(4.0, 1.0, 4.2)},
	"overhang": {"eye": Vector3(17.0, 1.5, 9.0), "at": Vector3(9.5, 2.8, 5.0)},
}

var _failures := 0
var _viewport: SubViewport


func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var plan := _load_plan()
	if plan == null:
		_check("AO rig fixture loads", false)
		_finish()
		return
	_check("AO rig fixture loads", true)

	var flat := StructureBaker.bake(plan)
	var ao := StructureAO.for_plan(plan)
	var baked := _bake_with_ao(plan, ao)
	_check("the flat bake produced surfaces", _surfaces(flat) > 0)
	_check("AO costs no extra surfaces (flat %d, AO %d)" % [_surfaces(flat), _surfaces(baked)],
		_surfaces(baked) == _surfaces(flat))
	print("  flat names: %s" % [_names(flat)])
	print("  AO names:   %s" % [_names(baked)])
	_check("the AO bake carries a vertex colour channel", _has_colors(baked))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(_viewport)
	var world := _stage()
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 52.0
	world.add_child(camera)
	## 1.8 m figure on deck — CONVENTIONS.md 3a. Without it nothing in the frame
	## has an absolute size and a wrongly-proportioned rig looks plausible.
	world.add_child(_mannequin(Vector3(9.5, 0.02, 9.5)))

	for variant in ["flat", "ao"]:
		var subject := flat if variant == "flat" else baked
		world.add_child(subject)
		for view in VIEWS.keys():
			var spec := VIEWS[view] as Dictionary
			camera.look_at_from_position(spec["eye"] as Vector3, spec["at"] as Vector3, Vector3.UP)
			for _frame in 3:
				await get_tree().process_frame
			var image := _viewport.get_texture().get_image()
			var luma := _mean_luminance(image)
			var path := "%s/structure_ao__%s_%s.png" % [OUT_DIR, view, variant]
			var error := image.save_png(path)
			_check("wrote %s (mean luma %.4f)" % [path.get_file(), luma], error == OK and luma > 0.01)
			_luma[view + "_" + variant] = luma
		world.remove_child(subject)

	for view in VIEWS.keys():
		var lit := float(_luma.get(view + "_flat", 0.0))
		var shaded := float(_luma.get(view + "_ao", 0.0))
		print("  %s: flat luma %.4f -> AO luma %.4f (%.1f%% darker)"
			% [view, lit, shaded, (1.0 - shaded / maxf(lit, 1e-6)) * 100.0])
		_check("%s: the AO frame is visibly darker than the flat one" % view, shaded < lit * 0.97)
	flat.free()
	baked.free()
	_finish()


var _luma := {}


func _finish() -> void:
	print("---")
	print("structure_ao_capture: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


# ── The call site, exactly as StructureBaker should adopt it ─────────────────

func _bake_with_ao(plan: StructurePlan, ao: StructureAO) -> Node3D:
	var root := Node3D.new()
	root.name = "StructureBakeAO"
	var buckets := {}
	var expanded := StructureBaker.expand(plan)
	var wall_default := StructureBaker._palette_color(plan, "wall", StructureBaker.DEFAULT_WALL_COLOR)
	var deck_default := StructureBaker._palette_color(plan, "deck", StructureBaker.DEFAULT_DECK_COLOR)
	for wall_variant in expanded["walls"] as Array:
		for layer in StructureBaker._wall_layers(wall_variant as Dictionary, wall_default):
			_bucket(buckets, layer as Dictionary, ao)
	for deck_variant in expanded["decks"] as Array:
		for layer in StructureBaker._plate_layers(deck_variant as Dictionary, wall_default, deck_default):
			_bucket(buckets, layer as Dictionary, ao)
	for stair_variant in expanded["stairs"] as Array:
		for layer in StructureBaker._stair_layers(stair_variant as Dictionary, deck_default):
			_bucket(buckets, layer as Dictionary, ao)
	for key in buckets.keys():
		var bucket := buckets[key] as Dictionary
		var st := bucket["st"] as SurfaceTool
		var material := StandardMaterial3D.new()
		## Exactly what StructureBaker.bake() builds today: white albedo, colour
		## carried per vertex. AO changes the vertex colour, not the material.
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		var response: Dictionary = StructureBaker.MATERIALS.get(
			str(bucket["material"]), StructureBaker.MATERIALS["painted"]
		)
		material.roughness = float(response["roughness"])
		material.metallic = float(response["metallic"])
		st.set_material(material)
		var mesh := st.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			var instance := MeshInstance3D.new()
			instance.name = "StructureAO_%s" % str(key)
			instance.mesh = mesh
			root.add_child(instance)
	return root


func _bucket(buckets: Dictionary, layer: Dictionary, ao: StructureAO) -> void:
	var color := layer["color"] as Color
	var material := str(layer["material"])
	## Same bucket key the baker uses now: material only. Colour rides on the
	## vertices, so two colours in one material still cost one draw call.
	var key := material
	if not buckets.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		buckets[key] = {"color": color, "material": material, "st": st}
	ao.append_box(
		(buckets[key] as Dictionary)["st"] as SurfaceTool,
		layer["center"] as Vector3,
		layer["size"] as Vector3,
		layer.get("basis", Basis.IDENTITY) as Basis,
		color,
	)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _load_plan() -> StructurePlan:
	if not FileAccess.file_exists(RIG):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG))
	if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
		return null
	return StructurePlan.from_dict(parsed as Dictionary)


func _names(root: Node3D) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is MeshInstance3D:
			out.append(child.name)
	return out


func _surfaces(root: Node3D) -> int:
	var count := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			count += 1
	return count


func _has_colors(root: Node3D) -> bool:
	for child in root.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var arrays: Array = (instance.mesh as ArrayMesh).surface_get_arrays(0)
		if arrays[Mesh.ARRAY_COLOR] == null:
			return false
	return true


## Deliberately flat, sky-dominated lighting: one soft sun and a strong ambient.
## This is the condition under which untouched boxes read as cardboard, so it is
## the condition the AO has to fix. A raking key light would flatter both sides.
func _stage() -> Node3D:
	var world := Node3D.new()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.76)
	env.ambient_light_energy = 1.05
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 0.85
	world.add_child(sun)
	return world


func _mannequin(at: Vector3) -> Node3D:
	var node := MeshInstance3D.new()
	node.name = "ScaleFigure_1m8"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 1.8, 0.28)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.32, 0.18)
	material.roughness = 0.9
	node.material_override = material
	node.position = at + Vector3(0, 0.9, 0)
	return node


func _mean_luminance(image: Image) -> float:
	var total := 0.0
	var samples := 0
	var step := 4
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var c := image.get_pixel(x, y)
			total += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			samples += 1
	return total / float(maxi(samples, 1))
