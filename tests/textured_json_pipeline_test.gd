extends Node

var failures := PackedStringArray()


func _ready() -> void:
	MeshBuilder.clear_geometry_cache()
	MeshBuilder.clear_material_cache()
	var vertices: Array = [-0.5, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 1.0, 0.0]
	var indices: Array = [0, 1, 2]
	var uvs: Array = [0.0, 1.0, 1.0, 1.0, 0.5, 0.0]
	var profile := TextureMaterialCatalog.resolve("icelander_knit")
	_check(not profile.is_empty(), "texture profile resolves")
	_check(MeshUv.valid_for(vertices, uvs), "UV validator accepts one UV per vertex")
	var second_profile := TextureMaterialCatalog.resolve("icelander_knit")
	second_profile["primary_color"] = "#ffffff"
	_check(str(profile.get("primary_color", "")) != "#ffffff", "resolved profiles are safe independent copies")
	var first := _build(vertices, indices, uvs, profile, Color("18364e"), Color("e0dcc7"), "test:triangle")
	var duplicate := _build(vertices, indices, uvs, profile, Color("18364e"), Color("e0dcc7"), "test:triangle")
	var variant := _build(vertices, indices, uvs, profile, Color("b44828"), Color("172a3a"), "test:triangle")
	_check(first.mesh == duplicate.mesh, "identical JSON geometry shares one ArrayMesh")
	_check(first.mesh == variant.mesh, "palette variants still share geometry")
	_check(first.material_override == duplicate.material_override, "identical palette shares one material")
	_check(first.material_override != variant.material_override, "different palette selects a different cached material")
	_check(MeshBuilder.geometry_cache_size() == 1, "one geometry cache entry serves three instances")
	_check(MeshBuilder.material_cache_size() == 2, "two liveries create two materials")
	_check(MeshBuilder.texture_cache_size() == 2, "base texture and mask load once")
	add_child(first)
	add_child(duplicate)
	add_child(variant)

	var assembler_a := ModelAssembler.new()
	assembler_a.model_data_path = AssetPaths.ICELANDER_SWEATER_PROOF_MODEL
	add_child(assembler_a)
	var assembler_b := ModelAssembler.new()
	assembler_b.model_data_path = AssetPaths.ICELANDER_SWEATER_PROOF_MODEL
	add_child(assembler_b)
	await get_tree().process_frame
	var torso_a := assembler_a.get_part("torso") as MeshTransformer
	var torso_b := assembler_b.get_part("torso") as MeshTransformer
	_check(torso_a != null and torso_b != null, "ModelAssembler resolves textured profile parts")
	if torso_a != null and torso_b != null:
		_check(torso_a.mesh_texture_path == str(profile.get("texture", "")), "ModelAssembler applies profile texture")
		_check(torso_a.mesh_texture_mask_path == str(profile.get("texture_mask", "")), "ModelAssembler applies profile mask")
		var torso_mesh_a := _generated_mesh(torso_a)
		var torso_mesh_b := _generated_mesh(torso_b)
		_check(torso_mesh_a != null and torso_mesh_b != null, "assembled textured meshes exist")
		if torso_mesh_a != null and torso_mesh_b != null:
			_check(torso_mesh_a.mesh == torso_mesh_b.mesh, "stable model-part id bypasses repeated geometry builds")
			_check(torso_mesh_a.material_override == torso_mesh_b.material_override, "assembled copies share cached material")
	first.queue_free()
	duplicate.queue_free()
	variant.queue_free()
	assembler_a.queue_free()
	assembler_b.queue_free()
	await get_tree().process_frame
	MeshBuilder.clear_geometry_cache()
	MeshBuilder.clear_material_cache()
	await get_tree().process_frame
	if failures.is_empty():
		print("Textured JSON pipeline test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Textured JSON pipeline test: " + failure)
	get_tree().quit(1)


func _build(
		vertices: Array,
		indices: Array,
		uvs: Array,
		profile: Dictionary,
		primary: Color,
		secondary: Color,
		geometry_cache_id: String,
) -> MeshInstance3D:
	return MeshBuilder.from_data(
		vertices,
		indices,
		Color.WHITE,
		float(profile.get("roughness", 0.9)),
		float(profile.get("metallic", 0.0)),
		uvs,
		str(profile.get("texture", "")),
		str(profile.get("texture_mask", "")),
		primary,
		secondary,
		geometry_cache_id,
	)


func _generated_mesh(transformer: MeshTransformer) -> MeshInstance3D:
	for child in transformer.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
