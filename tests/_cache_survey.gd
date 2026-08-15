extends SceneTree

## SCRATCH PROBE (leading underscore: the gate must not discover it).
## Surveys what `ModelCache` and `LandDecorCache` lose between producer and stamp,
## and re-measures the `duplicate()` claim in `model_cache.gd:97`.

const MODEL_PATHS := [
	"res://resources/data/models/buildings/foghorn_building.json",
	"res://resources/data/models/buildings/lighthouse_building.json",
	"res://resources/data/models/cargo/container_cube.json",
	"res://resources/data/meshes/docks/docking_bollard.json",
	"res://resources/data/meshes/props/fuel_station.json",
	"res://resources/data/models/dockyard/bulk_crane.json",
	"res://resources/data/models/dockyard/provision_crane.json",
	"res://resources/data/models/characters/npc_character_study.json",
]


func _initialize() -> void:
	print("=== A. ModelCache: producer vs stamp ===")
	for path in MODEL_PATHS:
		_survey_model(path)

	print("")
	print("=== B. LandDecorCache: prototype vs stamp ===")
	_survey_decor()

	print("")
	print("=== C. does duplicate() deep-copy Resources in 4.6? ===")
	_survey_duplicate()

	print("")
	print("=== D. the VESSEL side (STATE.md 1c's unverified half) ===")
	_survey_vessel_side()

	quit(0)


## STATE.md 1c: "Unverified there: whether `deck_text` and the ship-only light
## bricks lose their visuals on the vessel side too."
##
## `DeckFitout` uses NO prototype cache — `create_item_visual` and
## `create_cell_mounts` call `BrickCatalog.create_visual` and `add_child` the
## returned node itself, so nothing is flattened or stamped. The one lossy step
## on a hull is `VesselSkinBaker`, which merges static bricks into one mesh per
## material — and it is gated by `LIVE_TAGS`, which contains "text" and "light".
func _survey_vessel_side() -> void:
	var text_ids: Array[String] = []
	var light_ids: Array[String] = []
	var baked_anyway: Array[String] = []
	for brick_id in BrickCatalog.ids():
		var is_text := BrickCatalog.has_tag(brick_id, "text")
		var is_light := BrickCatalog.has_tag(brick_id, "light")
		if not (is_text or is_light):
			continue
		if is_text:
			text_ids.append(brick_id)
		if is_light:
			light_ids.append(brick_id)
		if VesselSkinBaker.is_baked_brick(brick_id):
			baked_anyway.append(brick_id)
	print("text bricks  (%d): %s" % [text_ids.size(), ", ".join(text_ids)])
	print("light bricks (%d): %s" % [light_ids.size(), ", ".join(light_ids)])
	print("swallowed by the skin bake: %d  %s"
		% [baked_anyway.size(), ", ".join(baked_anyway)])

	## What each of those bricks actually draws, and whether it survives the ONE
	## transformation the vessel path applies to a brick's visual.
	for brick_id in text_ids + light_ids:
		var visual := BrickCatalog.create_visual(brick_id, {"text": "TEST"})
		print("   %-18s draws %s   (skin-baked: %s)"
			% [brick_id, _fmt(_census(visual)), str(VesselSkinBaker.is_baked_brick(brick_id))])
		visual.free()

	## And the merge itself, on the shape the buildings defect dropped: does
	## `_merge_node_tree` recurse THROUGH a mesh?
	var st := SurfaceTool.new()
	st.create_from(BoxMesh.new(), 0)
	var mesh := st.commit()
	var outer := MeshInstance3D.new()
	outer.mesh = mesh
	outer.material_override = MeshBuilder.make_material(Color.RED)
	var inner := MeshInstance3D.new()
	inner.mesh = mesh
	inner.material_override = outer.material_override
	inner.transform.origin = Vector3(0.0, 4.0, 0.0)
	outer.add_child(inner)
	var buckets: Dictionary = {}
	VesselSkinBaker._merge_node_tree(outer, Transform3D.IDENTITY, buckets)
	var total := 0
	for key in buckets:
		var committed: ArrayMesh = ((buckets[key] as Dictionary)["st"] as SurfaceTool).commit()
		if committed != null and committed.get_surface_count() > 0:
			total += committed.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	print("skin merge of a mesh-under-a-mesh: %d vertices (one box = 24, two = 48)" % total)
	outer.free()


func _survey_model(path: String) -> void:
	if not FileAccess.file_exists(path):
		print("%s  MISSING" % path)
		return
	var assembler := ModelAssembler.new()
	assembler.build_part_colliders = false
	assembler.absolute_scale = 1.0
	assembler.model_data_path = path
	assembler.rebuild()

	var producer := _census(assembler)
	var nested := _nested_visuals(assembler)
	var depth := _max_visual_depth(assembler, 0)
	var all_nodes := _all_class_census(assembler)

	var stamped := ModelCache.instance(path, 1.0)
	var got := _census(stamped)

	print("%s" % path.get_file())
	print("   producer  %s   (all nodes: %s)" % [_fmt(producer), _fmt(all_nodes)])
	print("   stamped   %s" % _fmt(got))
	print("   visuals nested under a visual: %d   max visual nesting depth: %d" % [nested, depth])
	var lost := {}
	for cls in producer:
		var d := int(producer[cls]) - int(got.get(cls, 0))
		if d != 0:
			lost[cls] = d
	print("   LOST: %s" % ("nothing" if lost.is_empty() else _fmt(lost)))
	stamped.free()
	assembler.free()
	ModelCache.clear()


func _survey_decor() -> void:
	LandDecorCache.clear()
	for variant in range(LandDecorCache.VARIANT_COUNT):
		var proto: Node3D = LandDecorCache._bake_house(variant)
		var producer := _census(proto)
		var all_nodes := _all_class_census(proto)
		var nested := _nested_visuals(proto)
		var depth := _max_visual_depth(proto, 0)
		var stamped := LandDecorCache.house_instance(variant, 0.0, 0.0)
		var got := _census(stamped)
		var lost := {}
		for cls in producer:
			var d := int(producer[cls]) - int(got.get(cls, 0))
			if d != 0:
				lost[cls] = d
		print("variant %d  producer %s (all: %s)  stamped %s  nested-under-visual %d depth %d  LOST %s"
			% [variant, _fmt(producer), _fmt(all_nodes), _fmt(got), nested, depth,
				("nothing" if lost.is_empty() else _fmt(lost))])
		## Field-level: does the stamp keep what the prototype set?
		if producer.size() > 0:
			var p_mi := proto.get_child(0) as MeshInstance3D
			var s_mi := stamped.get_child(0) as MeshInstance3D
			print("        gi_mode proto=%d stamp=%d | name proto=%s stamp=%s | mesh shared=%s | mat shared=%s"
				% [p_mi.gi_mode, s_mi.gi_mode, p_mi.name, s_mi.name,
					str(p_mi.mesh == s_mi.mesh), str(p_mi.material_override == s_mi.material_override)])
		stamped.free()
		proto.free()
	LandDecorCache.clear()


func _survey_duplicate() -> void:
	var box := BoxMesh.new()
	var st := SurfaceTool.new()
	st.create_from(box, 0)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_meta("building_lens_base_emission", 3.5)
	mi.layers = 5
	var mi2 := mi.duplicate() as MeshInstance3D
	print("MeshInstance3D.duplicate(): mesh SHARED=%s  material SHARED=%s  meta carried=%s  layers=%d  gi=%d"
		% [str(mi2.mesh == mesh), str(mi2.material_override == mat),
			str(mi2.has_meta("building_lens_base_emission")), mi2.layers, mi2.gi_mode])

	var label := Label3D.new()
	label.text = "WAREHOUSE"
	var font := SystemFont.new()
	label.font = font
	label.set_meta("k", 1)
	var label2 := label.duplicate() as Label3D
	print("Label3D.duplicate():        font SHARED=%s  text=%s  meta carried=%s"
		% [str(label2.font == font), label2.text, str(label2.has_meta("k"))])

	var light := OmniLight3D.new()
	light.set_meta("building_light_base_energy", 2.0)
	var light2 := light.duplicate() as OmniLight3D
	print("OmniLight3D.duplicate():    meta carried=%s" % str(light2.has_meta("building_light_base_energy")))

	## Does duplicate() carry children?
	var parent := MeshInstance3D.new()
	parent.mesh = mesh
	var kid := MeshInstance3D.new()
	kid.mesh = mesh
	parent.add_child(kid)
	var parent2 := parent.duplicate() as MeshInstance3D
	print("duplicate() child count: src=%d copy=%d" % [parent.get_child_count(), parent2.get_child_count()])

	mi.free(); mi2.free(); label.free(); label2.free(); light.free(); light2.free()
	parent.free(); parent2.free()


func _census(node: Node, out: Dictionary = {}) -> Dictionary:
	for child in node.get_children():
		if child is VisualInstance3D:
			var cls := child.get_class()
			out[cls] = int(out.get(cls, 0)) + 1
		_census(child, out)
	return out


func _all_class_census(node: Node, out: Dictionary = {}) -> Dictionary:
	for child in node.get_children():
		var cls := child.get_class()
		out[cls] = int(out.get(cls, 0)) + 1
		_all_class_census(child, out)
	return out


## Visuals that have a VisualInstance3D ancestor — the meshes the buildings
## defect dropped.
func _nested_visuals(root: Node, under_visual: bool = false, count: int = 0) -> int:
	for child in root.get_children():
		var is_vis := child is VisualInstance3D
		if is_vis and under_visual:
			count += 1
		count = _nested_visuals(child, under_visual or is_vis, count)
	return count


func _max_visual_depth(root: Node, depth: int) -> int:
	var best := depth
	for child in root.get_children():
		var d := depth + (1 if child is VisualInstance3D else 0)
		best = maxi(best, _max_visual_depth(child, d))
	return best


func _fmt(kinds: Dictionary) -> String:
	var keys := kinds.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(kinds[k])])
	return "none" if parts.is_empty() else ", ".join(parts)
