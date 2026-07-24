class_name StructureMaterialLibrary
extends RefCounted

## Global construction surface library shared by StructureBaker, Structure Studio,
## and any runtime consumer of structure_plan_v1 materials.
##
## Plans store material *ids* (painted, wood, …) plus optional RGB tints.
## This catalog resolves id → PBR response + albedo texture. Character/garment
## textures live in TextureMaterialCatalog — keep those worlds separate.

const DATA_PATH := "res://resources/data/materials/structure_materials.json"
const FALLBACK_ID := "painted"

static var _cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _material_cache: Dictionary = {}


static func reload() -> void:
	_cache.clear()
	clear_runtime_caches()
	_ensure_loaded()


## Drop texture/material instance caches (keeps JSON definitions). Useful for
## headless probes and editor hot-reload.
static func clear_runtime_caches() -> void:
	_texture_cache.clear()
	_material_cache.clear()


static func _ensure_loaded() -> void:
	if not _cache.is_empty():
		return
	var data := _load_json(DATA_PATH)
	_cache = {
		"materials": (data.get("materials", {}) as Dictionary).duplicate(true),
		"swatches": (data.get("swatches", []) as Array).duplicate(true),
	}
	if (_cache["materials"] as Dictionary).is_empty():
		## Hard fallback so a missing JSON never blanks the baker.
		_cache["materials"] = {
			FALLBACK_ID: {
				"label": "Painted",
				"roughness": 0.80,
				"metallic": 0.0,
				"uv_metres": 2.5,
				"tintable": true,
				"default_color": [0.82, 0.84, 0.86],
			}
		}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("StructureMaterialLibrary: missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


static func ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for key in (_cache["materials"] as Dictionary).keys():
		out.append(str(key))
	out.sort()
	return out


static func has_id(material_id: String) -> bool:
	_ensure_loaded()
	return (_cache["materials"] as Dictionary).has(material_id.strip_edges())


static func normalize_id(material_id: String) -> String:
	var trimmed := material_id.strip_edges()
	if trimmed.is_empty():
		return FALLBACK_ID
	return trimmed if has_id(trimmed) else FALLBACK_ID


static func definition(material_id: String) -> Dictionary:
	_ensure_loaded()
	var id := normalize_id(material_id)
	var materials := _cache["materials"] as Dictionary
	return (materials[id] as Dictionary).duplicate(true)


static func label_of(material_id: String) -> String:
	var def := definition(material_id)
	return str(def.get("label", normalize_id(material_id).capitalize()))


static func category_of(material_id: String) -> String:
	return str(definition(material_id).get("category", "misc"))


## Distinct category ids present in the catalog, sorted.
static func categories() -> Array[String]:
	_ensure_loaded()
	var seen: Dictionary = {}
	for material_id in ids():
		seen[category_of(material_id)] = true
	var out: Array[String] = []
	for key in seen.keys():
		out.append(str(key))
	out.sort()
	return out


static func ids_in_category(category: String) -> Array[String]:
	var wanted := category.strip_edges().to_lower()
	if wanted.is_empty() or wanted == "all":
		return studio_material_ids()
	var out: Array[String] = []
	for material_id in studio_material_ids():
		if category_of(material_id) == wanted:
			out.append(material_id)
	return out


static func roughness_of(material_id: String) -> float:
	return float(definition(material_id).get("roughness", 0.8))


static func metallic_of(material_id: String) -> float:
	return float(definition(material_id).get("metallic", 0.0))


static func uv_metres_of(material_id: String) -> float:
	return maxf(float(definition(material_id).get("uv_metres", 2.0)), 0.25)


static func swatches() -> Array:
	_ensure_loaded()
	return (_cache["swatches"] as Array).duplicate(true)


static func default_color(material_id: String) -> Color:
	var raw: Variant = definition(material_id).get("default_color", [0.82, 0.84, 0.86])
	return color_of(raw, Color(0.82, 0.84, 0.86))


static func color_of(value: Variant, fallback := Color.WHITE) -> Color:
	if value is Color:
		return value
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Color(
			float(list[0]),
			float(list[1]),
			float(list[2]),
			float(list[3]) if list.size() > 3 else 1.0,
		)
	if value is String and not str(value).is_empty():
		return Color.from_string(str(value), fallback)
	return fallback


static func load_albedo(material_id: String) -> Texture2D:
	var id := normalize_id(material_id)
	if _texture_cache.has(id):
		return _texture_cache[id] as Texture2D
	var path := str(definition(id).get("texture", ""))
	var texture: Texture2D = null
	if not path.is_empty():
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		if texture == null and FileAccess.file_exists(path):
			var image := Image.new()
			if image.load(path) == OK:
				texture = ImageTexture.create_from_image(image)
	_texture_cache[id] = texture
	return texture


## Build (or reuse) a StandardMaterial3D for a material id + tint colour.
## Ghost bakes pass `ghost=true` for translucent x-ray presentation.
static func make_material(material_id: String, tint: Color, ghost := false) -> StandardMaterial3D:
	var id := normalize_id(material_id)
	var key := "%s_%02x%02x%02x_%s" % [
		id,
		int(tint.r * 255.0),
		int(tint.g * 255.0),
		int(tint.b * 255.0),
		"g" if ghost else "s",
	]
	if _material_cache.has(key):
		return (_material_cache[key] as StandardMaterial3D).duplicate() as StandardMaterial3D
	var material := StandardMaterial3D.new()
	var def := definition(id)
	material.roughness = float(def.get("roughness", 0.8))
	material.metallic = float(def.get("metallic", 0.0))
	var albedo := load_albedo(id)
	if albedo != null:
		material.albedo_texture = albedo
		## Tint multiplies the texture so swatches recolour without unique maps.
		material.albedo_color = tint
	else:
		material.albedo_color = tint
	if ghost:
		material.albedo_color = Color(material.albedo_color, 0.13)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = material
	return material.duplicate() as StandardMaterial3D


## Convenience for Studio UI — ordered ids suitable for button rows.
## Grouped roughly: finishes → timber → metals → marine → masonry → ground → misc.
static func studio_material_ids() -> Array[String]:
	var preferred: Array[String] = [
		"painted", "whitewash", "plaster", "tile", "plastic", "glass",
		"wood", "teak", "plywood", "clapboard",
		"metal", "steel", "galvanized", "aluminum", "corrugated", "rust",
		"brass", "bronze", "copper",
		"fiberglass", "antislip", "rubber", "rope", "netting", "canvas",
		"concrete", "brick", "stone", "roof_tile", "shingle",
		"asphalt", "tar", "cobble", "gravel", "sand", "dirt",
	]
	var out: Array[String] = []
	for id in preferred:
		if has_id(id):
			out.append(id)
	for id in ids():
		if id not in out:
			out.append(id)
	return out
