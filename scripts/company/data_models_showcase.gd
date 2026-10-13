extends Control

## Isolated F6 inspector. All examples are scratch data, never captain saves.
const FIXTURES := "res://resources/data/showcases/company_entities.json"
const MANIFEST_PROPOSALS := "res://resources/data/showcases/manifest_proposals.json"
var records: Array = []
var selected: Dictionary = {}
var entity_tree: Tree
var json_view: CodeEdit
var title_label: Label
var description: Label
var scope_label: Label
var status_label: Label
var search: LineEdit
var links: HFlowContainer
var export_dialog: FileDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES))
	records = fixture.records
	var manifest_proposals: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PROPOSALS))
	records.append_array(manifest_proposals.records)
	# Use the exact exported bytes as the content address. Float formatting differs
	# across serializers; clients verify received bytes instead of reserializing.
	var construction_path := "res://resources/data/showcases/ship_construction.json"
	var content_hash := FileAccess.get_sha256(construction_path)
	for record: Dictionary in records:
		if record.id == "construction":
			record.json = JSON.parse_string(FileAccess.get_file_as_string(construction_path))
		elif record.json.get("construction", {}).has("sha256"):
			record.json.construction.sha256 = content_hash
	_add_current_records()
	_build_ui()
	_populate_tree()
	_select_record("manifest-freight")
	_populate_tree()
	if OS.get_cmdline_user_args().has("--verify-entity-inspector"):
		call_deferred("_verify")
	elif OS.get_cmdline_user_args().has("--capture-entity-inspector"):
		call_deferred("_capture")


func _add_current_records() -> void:
	var player := PlayerData.new()
	player.account_id = "showcase-account"
	player.captain_id = "showcase-captain"
	player.display_name = "Showcase captain"
	player.company = CompanyContracts.new_company("showcase-company", player.account_id,
		player.captain_id, "Showcase Maritime", "port-demo", Color("387c83"), 0)
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/vessels/prebuilt/fishing_hook_line.json"))
	var vessel := PlayerData.ledger_vessel_record({"uid": "showcase-vessel",
		"name": "Nordlys", "display": "Nordlys", "hull_id": stock.hull_id,
		"brick_layout": stock.brick_layout, "shaft_power_kw": stock.shaft_power_kw})
	player.upsert_owned_vessel(vessel)
	for entry in [
		["actual-player", "PlayerData · actual serializer", player.to_dict()],
		["actual-company", "Company · actual constructor", player.company],
		["actual-vessel", "Vessel · actual ledger record", player.owned_vessels[0]],
	]:
		records.append({"id": entry[0], "group": "currentGame", "name": entry[1],
			"scope": "Current game schema · isolated sample",
			"note": "Produced by the existing game data code with a scratch captain and stock ship. Compare with the proposed records above. No live player or multiplayer session is loaded.",
			"json": entry[2], "links": []})


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("111922")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var heading := Label.new()
	heading.text = "Data models"
	heading.add_theme_font_size_override("font_size", 26)
	root.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "Select an entity to inspect its JSON. Proposed contracts and actual game records are labelled separately."
	subtitle.add_theme_color_override("font_color", Color("a5b8c8"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)
	var lab_button := Button.new()
	lab_button.text = "Open live data lab · simulate freight with the authority"
	lab_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/showcases/gameplay_data_lab.tscn"))
	root.add_child(lab_button)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 340
	root.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	split.add_child(left)
	search = LineEdit.new()
	search.placeholder_text = "Find an entity…"
	search.text_changed.connect(func(_value: String): _populate_tree())
	left.add_child(search)
	entity_tree = Tree.new()
	entity_tree.hide_root = true
	entity_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entity_tree.add_theme_constant_override("v_separation", 8)
	entity_tree.item_selected.connect(_on_tree_selected)
	left.add_child(entity_tree)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 420
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 23)
	right.add_child(title_label)
	scope_label = Label.new()
	scope_label.add_theme_color_override("font_color", Color("80d9b8"))
	right.add_child(scope_label)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("bac9d6"))
	right.add_child(description)
	links = HFlowContainer.new()
	right.add_child(links)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	var copy := Button.new()
	copy.text = "Copy JSON"
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(json_view.text)
		status_label.text = "Copied JSON")
	actions.add_child(copy)
	var save := Button.new()
	save.text = "Export JSON…"
	save.pressed.connect(func():
		export_dialog.current_file = str(selected.get("id", "entity")) + ".json"
		export_dialog.popup_centered_ratio(0.65))
	actions.add_child(save)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(status_label)
	json_view = CodeEdit.new()
	json_view.editable = false
	json_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	json_view.gutters_draw_line_numbers = true
	json_view.add_theme_font_size_override("font_size", 20)
	var syntax := CodeHighlighter.new()
	syntax.number_color = Color("ecc18f")
	syntax.symbol_color = Color("b8c6d4")
	syntax.add_color_region('"', '"', Color("9fdbc2"))
	for keyword in ["true", "false", "null"]:
		syntax.add_keyword_color(keyword, Color("c4a9e8"))
	json_view.syntax_highlighter = syntax
	right.add_child(json_view)
	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.json ; JSON record"])
	export_dialog.file_selected.connect(_export_json)
	add_child(export_dialog)


func _populate_tree() -> void:
	entity_tree.clear()
	var root := entity_tree.create_item()
	for group in ["manifests", "manifestRecords", "contractsProposal", "players", "companies", "vessels", "placedEntities", "currentGame"]:
		var category: TreeItem = null
		for record: Dictionary in records:
			if record.group != group:
				continue
			if not search.text.is_empty() and not (str(record.name) + " " + group).to_lower().contains(search.text.to_lower()):
				continue
			if category == null:
				category = entity_tree.create_item(root)
				category.set_text(0, {"manifests": "Cargo manifests · proposed", "manifestRecords": "Goods & equipment · proposed", "contractsProposal": "Contracts & demand · proposed"}.get(group, group))
				category.set_selectable(0, false)
				category.set_custom_color(0, Color("91bfe3"))
			var item := entity_tree.create_item(category)
			item.set_text(0, record.name)
			item.set_metadata(0, record.id)
			item.set_tooltip_text(0, record.scope)
			if record.id == selected.get("id", ""):
				item.select(0)
	if root.get_child_count() == 0:
		var empty := entity_tree.create_item(root)
		empty.set_text(0, "No matching entities")
		empty.set_selectable(0, false)


func _on_tree_selected() -> void:
	var item := entity_tree.get_selected()
	if item != null and item.get_metadata(0) != null:
		_select_record(str(item.get_metadata(0)))


func _select_record(id: String) -> void:
	for record: Dictionary in records:
		if record.id != id:
			continue
		selected = record
		title_label.text = record.name
		scope_label.text = record.scope
		description.text = record.note
		json_view.text = JSON.stringify(record.json, "\t", false)
		json_view.scroll_vertical = 0
		status_label.text = "%s.json · %d bytes" % [id, json_view.text.to_utf8_buffer().size()]
		for child in links.get_children():
			links.remove_child(child)
			child.queue_free()
		for related_id: String in record.links:
			var button := Button.new()
			button.text = "→ " + _record_name(related_id)
			button.pressed.connect(func():
				_select_record(related_id)
				_populate_tree())
			links.add_child(button)
		return


func _record_name(id: String) -> String:
	for record: Dictionary in records:
		if record.id == id:
			return record.name
	return id


func _export_json(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_label.text = "Could not save: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(json_view.text + "\n")
	status_label.text = "Exported " + path.get_file()


func _verify() -> void:
	assert(ShipyardPlaytestMode.active(), "F6 must be isolated before autoloads start")
	assert(not PlayerSession._persistent_io_enabled)
	assert(records.size() == 32)
	var seen_ids := {}
	for record: Dictionary in records:
		assert(not seen_ids.has(record.id), "Inspector record IDs must be unique")
		seen_ids[record.id] = true
		_select_record(record.id)
		assert(PlayerData.json_equivalent(JSON.parse_string(json_view.text), record.json))
		for related_id: String in record.links:
			assert(_record_name(related_id) != related_id)
	search.text = "buoy"
	_populate_tree()
	assert(entity_tree.get_root().get_child_count() == 1)
	search.text = "no-such-entity"
	_populate_tree()
	assert(entity_tree.get_root().get_first_child().get_text(0) == "No matching entities")
	search.text = ""
	_populate_tree()
	# Select via the production Tree signal, rather than only calling the renderer.
	entity_tree.get_root().get_first_child().get_first_child().select(0)
	_on_tree_selected()
	assert(selected.id == "manifest-freight")
	_select_record("company-own")
	var export_path := OS.get_cache_dir().path_join("ana-data-model-test-%d.json" % OS.get_process_id())
	_export_json(export_path)
	assert(PlayerData.json_equivalent(JSON.parse_string(FileAccess.get_file_as_string(export_path)), selected.json))
	DirAccess.remove_absolute(export_path)
	_select_record("construction")
	assert(selected.json.layout.parts.size() == 70)
	_select_record("vessel-own")
	assert(selected.json.construction.sha256 == FileAccess.get_sha256("res://resources/data/showcases/ship_construction.json"))
	for id in ["player-other", "company-other", "vessel-other", "trap-public"]:
		_select_record(id)
		for private_field in ["balance_minor", "purchased_items", "company_memberships", "recovery_claim", "catch_inventory_id"]:
			assert(not json_view.text.contains('"' + private_field + '"'))
	print("data_models_showcase: PASS — 32 records, JSON round trips, export, construction hash, public projections, links, search, selection and save isolation")
	get_tree().quit()


func _capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var path := archive.path_join("godot-data-models-%d.png" % int(Time.get_unix_time_from_system()))
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("data_models_showcase capture: ", path, " result=", result)
	get_tree().quit()
