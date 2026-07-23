extends Node

var failures := PackedStringArray()


func _ready() -> void:
	var sweater_path := "res://resources/data/models/characters/wardrobe/tops/wool_sweater.json"
	var sweater_data := JsonUtil.load(sweater_path)
	_check(not sweater_data.is_empty(), "sweater model loads")
	_check(str(sweater_data.get("slot", "")) == "tops", "sweater declares tops slot")
	for raw_part in sweater_data.get("parts", []):
		if typeof(raw_part) != TYPE_DICTIONARY:
			continue
		var part := raw_part as Dictionary
		var mesh := part.get("mesh", {}) as Dictionary
		var vertex_count := int((mesh.get("vertices", []) as Array).size() / 3.0)
		_check((mesh.get("uvs", []) as Array).size() == vertex_count * 2, "%s has one UV per vertex" % str(part.get("name", "part")))
		var appearance := TextureMaterialCatalog.resolve(str(part.get("texture_profile", "")))
		_check(_asset_exists(str(appearance.get("texture", ""))), "%s texture exists" % str(part.get("name", "part")))
		_check(_asset_exists(str(appearance.get("texture_mask", ""))), "%s palette mask exists" % str(part.get("name", "part")))
	var actor := NpcBase.new()
	actor.wardrobe_enabled = false
	add_child(actor)
	await get_tree().process_frame
	var garment := CharacterGarment.new()
	actor.add_child(garment)
	_check(garment.attach(actor.visual, sweater_path), "garment attaches")
	for anchor_name in ["chest", "arm_left", "arm_right", "forearm_left", "forearm_right"]:
		var anchor := actor.get_part(anchor_name)
		_check(anchor != null, "anchor exists: %s" % anchor_name)
		if anchor != null:
			_check(not anchor.find_children("GarmentPart_*", "MeshTransformer", false, false).is_empty(), "garment part follows %s" % anchor_name)
	for state in [WalkAnimator.IDLE, WalkAnimator.WALK, WalkAnimator.WAVE]:
		actor.animator.set_preview_pose(state, PI * 0.5, 0.72)
		_check(actor.animator.current_state() == state, "garment survives %s pose" % String(state))
	if failures.is_empty():
		print("Character textured garment test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Character textured garment test: " + failure)
	get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _asset_exists(path: String) -> bool:
	return not path.is_empty() and (FileAccess.file_exists(path) or ResourceLoader.exists(path))
