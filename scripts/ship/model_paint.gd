class_name ModelPaint
extends RefCounted
## Stable material-name contract. Each mesh instance owns its overrides.
const SLOTS := {"upholstery":"Paint_Upholstery","surface": "Paint_Surface", "fascia": "Paint_Fascia", "underside": "Paint_Underside","wall": "Warm white painted steel", "upper": "Paint_HullUpper", "lower": "Paint_HullLower", "deck": "Paint_Deck"}
const DEFAULTS := {"upholstery":Color(.065,.11,.14),"surface": Color(.48,.55,.55), "fascia": Color(.74,.78,.75), "underside": Color(.74,.78,.75),"wall": Color(0.74, 0.78, 0.75), "upper": Color(0.075, 0.25, 0.29), "lower": Color(0.36, 0.075, 0.043), "deck": Color.WHITE}

static func apply(root: Node, colors: Dictionary) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		for child in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh := node as MeshInstance3D
		for i in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if original == null:
				continue
			for slot in colors:
				if not SLOTS.has(slot) or not original.resource_name.begins_with(SLOTS[slot]):
					continue
				var raw: Variant = colors[slot]
				var colour: Color = raw if raw is Color else Color(float(raw[0]), float(raw[1]), float(raw[2]), 1)
				var active := mesh.get_active_material(i)
				if active != null and active.has_meta("marine_profile"):
					mesh.set_surface_override_material(i, SurfaceMaterialLibrary.material(active.get_meta("marine_profile"), colour, original.resource_name))
				else:
					var copy := original.duplicate() as StandardMaterial3D
					copy.albedo_color = colour
					mesh.set_surface_override_material(i, copy)

static func encode(color: Color) -> Array:
	return [color.r, color.g, color.b]
