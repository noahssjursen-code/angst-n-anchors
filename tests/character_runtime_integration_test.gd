extends Node

var failures := PackedStringArray()


func _ready() -> void:
	var actor := NpcBase.new()
	actor.appearance = CharacterCatalog.appearance_preset("harbour_master")
	add_child(actor)
	await get_tree().process_frame
	_check(actor.visual != null, "NPC owns shared CharacterVisual")
	_check(actor.appearance.outerwear_id == "deck_jacket", "role preset reaches live NPC")
	_check(actor.get_part("arm_left") != null, "articulated left arm exists")
	_check(actor.animator != null, "shared character animator exists")
	actor.set_walk_distance(2.5)
	actor.set_idle()

	var replacement := CharacterCatalog.appearance_preset("trawler_deckhand")
	actor.apply_appearance(replacement)
	await get_tree().process_frame
	_check(actor.appearance.headwear_id == "souwester", "appearance rebuild keeps complete wardrobe")
	_check(actor.get_part("leg_right") != null, "animation rig refreshes after wardrobe rebuild")
	actor.set_walk_distance(5.0)
	actor.set_idle()

	for preset_id in ["islender_fisher", "harbour_master", "shipping_manager", "company_director", "harbour_mechanic", "dock_worker"]:
		var preset := CharacterCatalog.appearance_preset(preset_id)
		_check(preset != null and preset.body_id != "", "%s role appearance resolves" % preset_id)

	if failures.is_empty():
		print("Character runtime integration test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Character runtime integration test: " + failure)
	get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
