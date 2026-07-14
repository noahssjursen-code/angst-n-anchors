class_name HullLivery
extends RefCounted

## Runtime-safe hull colors. Geometry owns stable material slots:
## surface 0 = topsides, surface 1 = anti-fouling keel, separate Deck mesh.
## A future paint/livery editor can persist this dictionary on vessel records.

const DEFAULT_TOPSIDES := Color(0.14, 0.16, 0.18)
const DEFAULT_KEEL := Color(0.34, 0.055, 0.04)
const DEFAULT_DECK := Color(0.38, 0.34, 0.28)
const DEFAULT_ACCENT := Color(0.82, 0.78, 0.62)


static func normalize(raw: Dictionary = {}) -> Dictionary:
	return {
		"topsides_color": _read_color(raw.get("topsides_color"), DEFAULT_TOPSIDES),
		"keel_color": _read_color(raw.get("keel_color"), DEFAULT_KEEL),
		"deck_color": _read_color(raw.get("deck_color"), DEFAULT_DECK),
		"accent_color": _read_color(raw.get("accent_color"), DEFAULT_ACCENT),
	}


static func to_dict(raw: Dictionary = {}) -> Dictionary:
	var livery := normalize(raw)
	return {
		"topsides_color": _color_array(livery["topsides_color"] as Color),
		"keel_color": _color_array(livery["keel_color"] as Color),
		"deck_color": _color_array(livery["deck_color"] as Color),
		"accent_color": _color_array(livery["accent_color"] as Color),
	}


static func apply_to_boat(boat: Node, raw: Dictionary = {}) -> void:
	if boat == null:
		return
	var livery := normalize(raw)
	var visual := boat.get_node_or_null("HullVisual")
	if visual != null:
		for child in visual.get_children():
			if not child is MeshInstance3D:
				continue
			var mesh_instance := child as MeshInstance3D
			if str(mesh_instance.name).begins_with("Hull"):
				_apply_hull_materials(mesh_instance, livery)
			elif mesh_instance.name == "Deck":
				mesh_instance.material_override = MeshBuilder.make_material(
					livery["deck_color"] as Color, 0.95, 0.0
				)
	boat.set_meta("hull_livery", to_dict(livery))


static func _apply_hull_materials(mesh_instance: MeshInstance3D, livery: Dictionary) -> void:
	if mesh_instance.mesh == null:
		return
	if mesh_instance.mesh.get_surface_count() >= 1:
		mesh_instance.set_surface_override_material(
			0,
			MeshBuilder.make_material(livery["topsides_color"] as Color, 0.9, 0.05)
		)
	if mesh_instance.mesh.get_surface_count() >= 2:
		mesh_instance.set_surface_override_material(
			1,
			MeshBuilder.make_material(livery["keel_color"] as Color, 0.96, 0.0)
		)


static func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is Array and (value as Array).size() >= 3:
		var values := value as Array
		return Color(
			float(values[0]),
			float(values[1]),
			float(values[2]),
			float(values[3]) if values.size() >= 4 else 1.0
		)
	if value is String and not (value as String).is_empty():
		return Color.from_string(value as String, fallback)
	return fallback


static func _color_array(color: Color) -> Array[float]:
	return [color.r, color.g, color.b, color.a]
