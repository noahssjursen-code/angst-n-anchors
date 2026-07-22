extends Node

var failures := PackedStringArray()


func _ready() -> void:
	var model := JsonUtil.load(AssetPaths.NPC_CHARACTER_STUDY_MODEL)
	var head_spec: Dictionary = {}
	for raw_part in model.get("parts", []):
		if typeof(raw_part) == TYPE_DICTIONARY and str(raw_part.get("name", "")) == "head":
			head_spec = raw_part
			break
	var mesh := head_spec.get("mesh", {}) as Dictionary
	_check(not mesh.is_empty(), "head mesh exists")
	_check(MeshUv.valid_for(mesh.get("vertices", []), mesh.get("uvs", [])), "head owns one UV per vertex")
	_check((mesh.get("vertices", []) as Array).size() == 72, "head uses 24 seam-safe atlas vertices")

	var visual := CharacterVisual.new()
	add_child(visual)
	var appearance := CharacterAppearance.default_appearance()
	appearance.face_texture_profile_id = "face_surface_base"
	visual.apply_appearance(appearance)
	await get_tree().process_frame
	var textured_head := visual.get_part("head") as MeshTransformer
	var profile := TextureMaterialCatalog.resolve("face_surface_base")
	_check(textured_head != null, "default appearance exposes the textured head")
	if textured_head != null:
		_check(textured_head.mesh_texture_path == str(profile.get("texture", "")), "face profile supplies atlas")
		_check(textured_head.mesh_texture_mask_path == str(profile.get("texture_mask", "")), "face profile supplies palette mask")
		_check(textured_head.mesh_primary_color.is_equal_approx(appearance.skin_color), "skin colour drives face palette")
		_check(textured_head.mesh_color.is_equal_approx(Color.WHITE), "face atlas is not multiplied by skin colour twice")
		var generated := _generated_mesh(textured_head)
		_check(generated != null, "textured head has generated mesh")
		if generated != null:
			_check(generated.material_override is ShaderMaterial, "face profile uses shared palette-mask shader")
			_check(_all_normals_face_outward(generated), "all seam-safe head faces keep outward winding")

	appearance.face_texture_profile_id = "face_surface_freckled"
	visual.apply_appearance(appearance)
	await get_tree().process_frame
	var alternate_head := visual.get_part("head") as MeshTransformer
	var alternate_profile := TextureMaterialCatalog.resolve("face_surface_freckled")
	_check(alternate_head != null, "alternate face surface rebuilds the head")
	if alternate_head != null:
		_check(alternate_head.mesh_texture_path == str(alternate_profile.get("texture", "")), "face surface id selects a different reusable atlas")

	visual.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("Character face surface test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Character face surface test: " + failure)
	get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _generated_mesh(transformer: MeshTransformer) -> MeshInstance3D:
	for child in transformer.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _all_normals_face_outward(mesh_instance: MeshInstance3D) -> bool:
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	if vertices.is_empty() or vertices.size() != normals.size():
		return false
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	var center := bounds.get_center()
	for i in vertices.size():
		if normals[i].dot(vertices[i] - center) <= 0.0001:
			return false
	return true
