class_name ContainerPaintMaterial
extends RefCounted

## Procedural painted-steel material for cubed cargo units (general + shipping).

const SHADER := preload("res://resources/shaders/container_paint.gdshader")

static var _prototype_cache: Dictionary = {}

const FREIGHT_PALETTE: Array[Color] = [
	Color(0.18, 0.48, 0.82), # maritime blue
	Color(0.78, 0.22, 0.16), # oxide red
	Color(0.18, 0.62, 0.34), # harbour green
	Color(0.92, 0.62, 0.12), # ochre
	Color(0.52, 0.30, 0.72), # violet
	Color(0.10, 0.68, 0.70), # teal
	Color(0.70, 0.36, 0.16), # umber
	Color(0.62, 0.64, 0.68), # weathered grey
]


static func build_for_commodity(commodity_id: String, seed: float = 0.0) -> ShaderMaterial:
	var key := commodity_id.strip_edges()
	if key.is_empty():
		key = ContainerUnit.DEFAULT_COMMODITY
	var mat := _prototype_for(key).duplicate() as ShaderMaterial
	mat.set_shader_parameter("seed", seed)
	return mat


static func apply_to_node(root: Node, commodity_id: String, seed: float = 0.0) -> void:
	if root == null:
		return
	var mat := build_for_commodity(commodity_id, seed)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).material_override = mat.duplicate()


static func apply_to_unit(root: Node, unit: ContainerUnit, seed: float = 0.0) -> void:
	if root == null or unit == null:
		return
	var variant := posmod(unit.paint_variant, FREIGHT_PALETTE.size())
	var base := FREIGHT_PALETTE[variant]
	var mat := _build_for_color(base, unit.commodity_id, seed)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).material_override = mat.duplicate()


static func seed_from_unit(unit: ContainerUnit) -> float:
	if unit == null or unit.id.is_empty():
		return 0.0
	return float(unit.id.hash() % 997) * 0.1


static func _prototype_for(commodity_id: String) -> ShaderMaterial:
	if _prototype_cache.has(commodity_id):
		return _prototype_cache[commodity_id] as ShaderMaterial
	var base := CommodityCatalog.commodity_color(commodity_id)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("paint_color", Vector3(base.r, base.g, base.b))
	mat.set_shader_parameter("paint_dark", Vector3(
		base.r * 0.52,
		base.g * 0.50,
		base.b * 0.58,
	))
	mat.set_shader_parameter("paint_highlight", Vector3(
		clampf(base.r * 1.22 + 0.04, 0.0, 1.0),
		clampf(base.g * 1.18 + 0.04, 0.0, 1.0),
		clampf(base.b * 1.12 + 0.04, 0.0, 1.0),
	))
	mat.set_shader_parameter("rust_color", Vector3(
		clampf(base.r * 0.85 + 0.18, 0.0, 1.0),
		clampf(base.g * 0.45 + 0.08, 0.0, 1.0),
		clampf(base.b * 0.25 + 0.05, 0.0, 1.0),
	))
	mat.set_shader_parameter("door_color", Vector3(
		base.r * 0.42,
		base.g * 0.40,
		base.b * 0.48,
	))
	_prototype_cache[commodity_id] = mat
	return mat


static func _build_for_color(base: Color, commodity_id: String, seed: float) -> ShaderMaterial:
	var key := "%s:%s" % [commodity_id, base.to_html(false)]
	if not _prototype_cache.has(key):
		var prototype := _prototype_for(commodity_id).duplicate() as ShaderMaterial
		prototype.set_shader_parameter("paint_color", Vector3(base.r, base.g, base.b))
		prototype.set_shader_parameter("paint_dark", Vector3(base.r * 0.48, base.g * 0.48, base.b * 0.52))
		prototype.set_shader_parameter("paint_highlight", Vector3(
			clampf(base.r * 1.2 + 0.04, 0.0, 1.0),
			clampf(base.g * 1.2 + 0.04, 0.0, 1.0),
			clampf(base.b * 1.2 + 0.04, 0.0, 1.0),
		))
		prototype.set_shader_parameter("door_color", Vector3(base.r * 0.38, base.g * 0.38, base.b * 0.42))
		_prototype_cache[key] = prototype
	var mat := (_prototype_cache[key] as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("seed", seed)
	return mat
