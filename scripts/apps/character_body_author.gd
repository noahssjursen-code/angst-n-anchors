extends SceneTree

## Source-controlled authoring recipe for the neutral articulated character body.
##
## This file deliberately contains no wardrobe pieces. It produces the jointed
## JSON body used by both NPCs and players. Every visible part is an authored
## cuboid mesh so the character speaks the same visual language as vessels,
## cranes, and harbour buildings.

const OUTPUT_PATH := "res://resources/data/models/characters/npc_character_study.json"
const BOX_INDICES := [
	0, 2, 1, 0, 3, 2,
	4, 5, 6, 4, 6, 7,
	0, 1, 5, 0, 5, 4,
	1, 2, 6, 1, 6, 5,
	2, 3, 7, 2, 7, 6,
	3, 0, 4, 3, 4, 7,
]


func _init() -> void:
	var model := {
		"name": "npc_character_body_v2",
		"_doc": "Neutral articulated body. Wardrobe-free. Bow/face points toward -Z.",
		"parts": _parts(),
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("CharacterBodyAuthor: cannot write %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(model, "  "))
	file.close()
	print("CharacterBodyAuthor: wrote %d parts to %s" % [model.parts.size(), OUTPUT_PATH])
	quit()


func _parts() -> Array:
	var parts: Array = []
	# A compact 1.65 m worker built from the same rectangular language as the
	# original port characters. Pelvis is the locomotion root and chest is one
	# uninterrupted torso mass: no armour-like stack, taper, or trapezoid.
	parts.append(_part("pelvis", "body_lower", "", Vector3(0.0, 0.90, 0.0), Vector3(0.28, 0.18, 0.19), Vector3.ZERO, Color("344653")))
	parts.append(_part("chest", "body_upper", "pelvis", Vector3(0.0, 0.06, 0.0), Vector3(0.33, 0.42, 0.20), Vector3(0.0, 0.18, 0.0), Color("344653")))
	parts.append(_part("neck", "skin_shadow", "chest", Vector3(0.0, 0.39, 0.0), Vector3(0.068, 0.07, 0.074), Vector3(0.0, 0.025, 0.0), Color("a87557"), 0.80))
	parts.append(_part("head", "skin", "neck", Vector3(0.0, 0.07, 0.0), Vector3(0.195, 0.225, 0.185), Vector3(0.0, 0.108, 0.0), Color("b98260"), 0.80))
	parts.append(_part("ear_left", "skin_shadow", "head", Vector3(-0.104, 0.108, 0.0), Vector3(0.022, 0.058, 0.050), Vector3.ZERO, Color("a87557"), 0.82))
	parts.append(_part("ear_right", "skin_shadow", "head", Vector3(0.104, 0.108, 0.0), Vector3(0.022, 0.058, 0.050), Vector3.ZERO, Color("a87557"), 0.82))

	# Legs: hip -> knee -> ankle -> foot. Meshes deliberately overrun each pivot
	# by 30-35 mm so bends remain solid instead of opening mannequin gaps.
	for side in ["left", "right"]:
		var x := -0.073 if side == "left" else 0.073
		parts.append(_part("leg_%s" % side, "body_lower", "pelvis", Vector3(x, -0.02, 0.0), Vector3(0.128, 0.43, 0.16), Vector3(0.0, -0.19, 0.0), Color("344653")))
		parts.append(_part("shin_%s" % side, "body_lower", "leg_%s" % side, Vector3(0.0, -0.39, 0.0), Vector3(0.116, 0.41, 0.145), Vector3(0.0, -0.18, 0.0), Color("344653")))
		parts.append(_part("foot_%s" % side, "footwear", "shin_%s" % side, Vector3(0.0, -0.37, 0.0), Vector3(0.132, 0.105, 0.205), Vector3(0.0, -0.052, -0.045), Color("18232a"), 0.86))

	# Arms use the same overlap contract. Shoulder pivots sit inside the torso
	# edge, so the neutral silhouette reads as one body rather than attached rods.
	for side in ["left", "right"]:
		var x := -0.155 if side == "left" else 0.155
		parts.append(_part("arm_%s" % side, "body_upper", "chest", Vector3(x, 0.32, 0.0), Vector3(0.108, 0.35, 0.125), Vector3(0.0, -0.145, 0.0), Color("344653")))
		parts.append(_part("forearm_%s" % side, "body_upper", "arm_%s" % side, Vector3(0.0, -0.29, 0.0), Vector3(0.100, 0.31, 0.116), Vector3(0.0, -0.13, 0.0), Color("344653")))
		parts.append(_part("hand_%s" % side, "skin", "forearm_%s" % side, Vector3(0.0, -0.26, 0.0), Vector3(0.090, 0.12, 0.104), Vector3(0.0, -0.055, -0.004), Color("b98260"), 0.80))

	# A deliberately restrained face: readable at gameplay distance, with no
	# hair, beard, hat, or other wardrobe baked into the body.
	parts.append(_part("eye_left", "face_ink", "head", Vector3(-0.038, 0.127, -0.0985), Vector3(0.020, 0.014, 0.012), Vector3.ZERO, Color("14191c"), 0.94))
	parts.append(_part("eye_right", "face_ink", "head", Vector3(0.038, 0.127, -0.0985), Vector3(0.020, 0.014, 0.012), Vector3.ZERO, Color("14191c"), 0.94))
	parts.append(_part("nose", "nose", "head", Vector3(0.0, 0.087, -0.103), Vector3(0.020, 0.030, 0.022), Vector3.ZERO, Color("a87557"), 0.80))
	parts.append(_part("mouth", "mouth", "head", Vector3(0.0, 0.050, -0.0985), Vector3(0.044, 0.009, 0.012), Vector3.ZERO, Color("493338"), 0.94))
	return parts


func _part(part_name: String, role: String, parent_name: String, position: Vector3,
		size: Vector3, mesh_center: Vector3, color: Color, roughness := 0.88) -> Dictionary:
	var result := {
		"name": part_name,
		"role": role,
		"position": _v3(position),
		"mesh": _box_mesh(size, mesh_center),
		"color": [color.r, color.g, color.b, color.a],
		"roughness": roughness,
		"metallic": 0.0,
		"collision": "none",
	}
	if not parent_name.is_empty():
		result["parent"] = parent_name
	return result


func _box_mesh(size: Vector3, center: Vector3) -> Dictionary:
	var h := size * 0.5
	var corners := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var vertices: Array = []
	for point in corners:
		vertices.append_array(_v3(point))
	return {"vertices": vertices, "indices": BOX_INDICES.duplicate()}


func _v3(value: Vector3) -> Array:
	return [snappedf(value.x, 0.000001), snappedf(value.y, 0.000001), snappedf(value.z, 0.000001)]
