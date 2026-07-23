extends Node

const CATALOG := preload("res://scripts/character/character_catalog.gd")
const VISUAL_SLOTS := [
	&"hair", &"facial_hair", &"tops", &"outerwear",
	&"trousers", &"footwear", &"headwear", &"eyewear",
	&"face_accessories", &"neckwear", &"handwear", &"utility_accessories",
]
const VALID_ANCHORS := [
	"pelvis", "chest", "neck", "head",
	"arm_left", "arm_right", "forearm_left", "forearm_right",
	"hand_left", "hand_right", "leg_left", "leg_right",
	"shin_left", "shin_right", "foot_left", "foot_right",
]

var failures := PackedStringArray()


func _ready() -> void:
	_validate_models()
	_validate_presets()
	_validate_cosmetic_keys()
	await _validate_material_tint_isolation()
	if failures.is_empty():
		print("Character wardrobe test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Character wardrobe test: " + failure)
	get_tree().quit(1)


func _validate_models() -> void:
	var model_count := 0
	for slot in VISUAL_SLOTS:
		for option in CATALOG.options(slot):
			var id := str(option.get("id", ""))
			var declared_parts: Array = option.get("parts", [])
			var path := CATALOG.wardrobe_model_path(slot, id)
			if declared_parts.is_empty():
				_check(path.is_empty(), "%s/%s should not load a model" % [slot, id])
				continue
			model_count += 1
			_check(FileAccess.file_exists(path), "%s/%s model exists" % [slot, id])
			var model := JsonUtil.load(path)
			_check(str(model.get("slot", "")) == String(slot), "%s/%s declares its catalog slot" % [slot, id])
			var parts: Array = model.get("parts", [])
			_check(not parts.is_empty(), "%s/%s contains model parts" % [slot, id])
			var names := PackedStringArray()
			for part in parts:
				var part_name := str(part.get("name", ""))
				_check(not part_name.is_empty(), "%s/%s part is named" % [slot, id])
				_check(not part_name in names, "%s/%s part names are unique" % [slot, id])
				names.append(part_name)
				_check(str(part.get("anchor", "")) in VALID_ANCHORS, "%s/%s part uses an articulated anchor" % [slot, id])
				var mesh: Dictionary = part.get("mesh", {})
				var vertices := mesh.get("vertices", []) as Array
				var indices := mesh.get("indices", []) as Array
				_check(vertices.size() >= 9 and vertices.size() % 3 == 0, "%s/%s has valid JSON vertices" % [slot, id])
				_check(indices.size() >= 3 and indices.size() % 3 == 0, "%s/%s has triangle indices" % [slot, id])
				var uvs := mesh.get("uvs", []) as Array
				_check(uvs.is_empty() or uvs.size() == (vertices.size() / 3) * 2, "%s/%s has one UV per textured vertex" % [slot, id])
				var texture_profile := str(part.get("texture_profile", ""))
				if not texture_profile.is_empty():
					var profile := TextureMaterialCatalog.resolve(texture_profile)
					_check(not profile.is_empty(), "%s/%s texture profile resolves" % [slot, id])
					_check(_asset_exists(str(profile.get("texture", ""))), "%s/%s texture exists" % [slot, id])
					var mask_path := str(profile.get("texture_mask", ""))
					_check(mask_path.is_empty() or _asset_exists(mask_path), "%s/%s texture mask exists" % [slot, id])
			for declared_name in declared_parts:
				_check(str(declared_name) in names, "%s/%s catalog part `%s` exists" % [slot, id, declared_name])
	_check(model_count >= 30, "curated wardrobe contains at least thirty fitted models")


func _validate_presets() -> void:
	_check(CATALOG.outfit_presets().size() >= 12, "wardrobe has at least twelve complete working looks")
	for preset in CATALOG.outfit_presets():
		var label := str(preset.get("id", "preset"))
		for mapping in [
			[&"body_presets", "body_id"],
			[&"hair", "hair_id"], [&"facial_hair", "facial_hair_id"],
			[&"tops", "top_id"], [&"outerwear", "outerwear_id"],
			[&"trousers", "trousers_id"], [&"footwear", "footwear_id"],
			[&"headwear", "headwear_id"], [&"eyewear", "eyewear_id"],
			[&"face_accessories", "face_accessory_id"], [&"neckwear", "neckwear_id"],
			[&"handwear", "handwear_id"], [&"utility_accessories", "utility_id"],
			[&"uniform_templates", "uniform_id"],
			[&"face_surfaces", "face_texture_profile_id"],
		]:
			_check(CATALOG.is_valid(mapping[0], str(preset.get(mapping[1], "none"))), "%s has valid %s" % [label, mapping[1]])
		for color_property in [
			"skin_color", "hair_color", "top_color", "clothing_color",
			"trousers_color", "footwear_color", "headwear_color", "accent_color",
			"accessory_color", "company_primary_color", "company_secondary_color",
		]:
			if not preset.has(color_property) and label in ["harbour_captain", "trawler_deckhand", "orange_oilskin", "dock_worker", "harbour_master", "shipping_manager", "marine_engineer"]:
				continue
			_check(Color.from_string(str(preset.get(color_property, "")), Color.TRANSPARENT) != Color.TRANSPARENT,
				"%s has valid %s" % [label, color_property])


func _validate_cosmetic_keys() -> void:
	var keys := PackedStringArray()
	for slot in VISUAL_SLOTS:
		for option in CATALOG.options(slot):
			var id := str(option.get("id", ""))
			if id == "none" or (option.get("parts", []) as Array).is_empty():
				continue
			var metadata := CATALOG.cosmetic_metadata(slot, id)
			var key := str(metadata.get("inventory_key", ""))
			_check(not key.is_empty(), "%s/%s has a stable inventory key" % [slot, id])
			_check(not key in keys, "%s/%s inventory key is unique" % [slot, id])
			keys.append(key)
			_check(str(metadata.get("trade_policy", "")) in ["game_owned", "platform_inventory"], "%s/%s has a supported trade policy" % [slot, id])


func _validate_material_tint_isolation() -> void:
	# Character uniforms share cached meshes and materials. Recolouring one
	# character must select another cached material instead of mutating every
	# character already wearing that colour.
	var base_model := JsonUtil.load(AssetPaths.NPC_CHARACTER_STUDY_MODEL)
	var base_parts: Array = base_model.get("parts", [])
	var fixture_mesh: Dictionary = (base_parts[0] as Dictionary).get("mesh", {}) if not base_parts.is_empty() else {}
	var first := MeshTransformer.new()
	first.create_collision = false
	first.mesh_data = fixture_mesh
	first.mesh_color = Color("a34b32")
	add_child(first)
	var second := MeshTransformer.new()
	second.create_collision = false
	second.mesh_data = fixture_mesh
	second.mesh_color = first.mesh_color
	add_child(second)
	await get_tree().process_frame
	first._apply_appearance()
	second._apply_appearance()
	var first_mesh := first._generated_mesh_instance()
	_check(first_mesh != null, "material tint fixture builds")
	var initial_material := first_mesh.material_override as StandardMaterial3D if first_mesh != null else null
	var initial_color := initial_material.albedo_color if initial_material != null else Color.TRANSPARENT
	second.mesh_color = Color("315a7a")
	var first_material := first_mesh.material_override as StandardMaterial3D if first_mesh != null else null
	_check(first_material != null and first_material.albedo_color.is_equal_approx(initial_color),
		"recolouring one character does not recolour another")
	first.queue_free()
	second.queue_free()


func _asset_exists(path: String) -> bool:
	return not path.is_empty() and (FileAccess.file_exists(path) or ResourceLoader.exists(path))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
