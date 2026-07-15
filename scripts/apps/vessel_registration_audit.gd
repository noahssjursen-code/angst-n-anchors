class_name VesselRegistrationAudit
extends CanvasLayer

## Developer paperwork app: author legal code and audit every official vessel.
## Run res://scenes/apps/vessel_registration_audit.tscn with F6.

const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"

var _root: Control
var _tabs: TabContainer
var _legal_list: ItemList
var _legal_json: TextEdit
var _legal_status: Label
var _audit_list: ItemList
var _audit_detail: Label
var _audit_status: Label
var _audit_registration: OptionButton
var _audit_records: Array[Dictionary] = []


func _init() -> void:
	name = "VesselRegistrationAudit"
	layer = 14
	_build_ui()


func _ready() -> void:
	_reload_legal_code()
	_audit_all()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "RegistrationAuditRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = HudStyle.make_theme()
	add_child(_root)

	var background := ColorRect.new()
	background.color = Color(0.025, 0.032, 0.04)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	_root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	outer.add_child(UiBuilder.title_label("VESSEL REGISTRATION OFFICE", 24))
	var subtitle := UiBuilder.body_label(
		"Source-controlled legal code and official-vessel paperwork", 12
	)
	outer.add_child(subtitle)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	_build_legal_tab()
	_build_audit_tab()


func _build_legal_tab() -> void:
	var tab := HBoxContainer.new()
	tab.name = "Legal code"
	tab.add_theme_constant_override("separation", 12)
	_tabs.add_child(tab)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	tab.add_child(left)
	left.add_child(UiBuilder.section_header("REGISTRATIONS"))
	_legal_list = ItemList.new()
	_legal_list.name = "RegistrationList"
	_legal_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_legal_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(right)
	right.add_child(UiBuilder.section_header("CATALOG JSON"))
	_legal_json = TextEdit.new()
	_legal_json.name = "LegalCodeEditor"
	_legal_json.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_legal_json.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legal_json.custom_minimum_size.y = 460
	right.add_child(_legal_json)
	var buttons := HBoxContainer.new()
	var reload_btn := UiBuilder.compact_button("Reload")
	reload_btn.pressed.connect(_reload_legal_code)
	buttons.add_child(reload_btn)
	var validate_btn := UiBuilder.compact_button("Validate")
	validate_btn.pressed.connect(_validate_legal_code)
	buttons.add_child(validate_btn)
	var save_btn := UiBuilder.compact_button("Validate + save")
	save_btn.pressed.connect(_save_legal_code)
	buttons.add_child(save_btn)
	right.add_child(buttons)
	_legal_status = Label.new()
	_legal_status.name = "LegalStatus"
	_legal_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_legal_status)


func _build_audit_tab() -> void:
	var tab := HBoxContainer.new()
	tab.name = "Vessel paperwork"
	tab.add_theme_constant_override("separation", 12)
	_tabs.add_child(tab)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 360
	tab.add_child(left)
	var audit_btn := UiBuilder.button("Audit all official vessels")
	audit_btn.name = "AuditAllButton"
	audit_btn.pressed.connect(_audit_all)
	left.add_child(audit_btn)
	_audit_status = Label.new()
	_audit_status.name = "AuditStatus"
	left.add_child(_audit_status)
	left.add_child(UiBuilder.section_header("ASSIGN REGISTRATION"))
	_audit_registration = OptionButton.new()
	_audit_registration.name = "AuditRegistrationOption"
	for entry in VesselRegistrationCatalog.registrations():
		_audit_registration.add_item(str(entry.get("display", entry.get("id", ""))))
		_audit_registration.set_item_metadata(
			_audit_registration.item_count - 1, str(entry.get("id", ""))
		)
	left.add_child(_audit_registration)
	var assign_btn := UiBuilder.compact_button("Assign to selected prebuilt")
	assign_btn.name = "AssignRegistrationButton"
	assign_btn.pressed.connect(_assign_selected_registration)
	left.add_child(assign_btn)
	_audit_list = ItemList.new()
	_audit_list.name = "VesselAuditList"
	_audit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_audit_list.item_selected.connect(_show_audit)
	left.add_child(_audit_list)

	var detail_panel := UiBuilder.inner_panel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(detail_panel)
	_audit_detail = Label.new()
	_audit_detail.name = "AuditDetail"
	_audit_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_audit_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audit_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(_audit_detail)


func _reload_legal_code() -> void:
	VesselRegistrationCatalog.reload()
	var catalog := VesselRegistrationCatalog.raw_catalog()
	_legal_json.text = JSON.stringify(catalog, "\t")
	_legal_list.clear()
	for entry in VesselRegistrationCatalog.registrations():
		_legal_list.add_item("%s  ·  %s" % [
			str(entry.get("id", "")),
			str(entry.get("display", "")),
		])
	_legal_status.text = "Loaded legal code v%d" % VesselRegistrationCatalog.catalog_version()
	_legal_status.add_theme_color_override("font_color", HudStyle.C_LABEL)


func _parse_legal_editor() -> Dictionary:
	var parsed: Variant = JSON.parse_string(_legal_json.text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _validate_legal_code() -> void:
	var catalog := _parse_legal_editor()
	if catalog.is_empty():
		_set_legal_status("Invalid JSON document", true)
		return
	var errors := VesselRegistrationCatalog.validate_catalog(catalog)
	_set_legal_status(
		"Legal code valid" if errors.is_empty() else " · ".join(errors),
		not errors.is_empty(),
	)


func _save_legal_code() -> void:
	var catalog := _parse_legal_editor()
	if catalog.is_empty():
		_set_legal_status("Invalid JSON document", true)
		return
	var err := VesselRegistrationCatalog.save_catalog(catalog)
	if err != OK:
		_set_legal_status("Save failed (error %d)" % err, true)
		return
	_set_legal_status("Saved legal code v%d" % int(catalog.get("version", 0)), false)
	_reload_legal_code()
	_audit_all()


func _set_legal_status(message: String, failed: bool) -> void:
	_legal_status.text = message
	_legal_status.add_theme_color_override(
		"font_color", HudStyle.C_RED if failed else HudStyle.C_GREEN
	)


func _audit_all() -> void:
	_audit_records.clear()
	_audit_list.clear()
	var passed := 0
	var files := _prebuilt_files()
	for path in files:
		var audit := _audit_file(path)
		_audit_records.append(audit)
		var ok := bool(audit.get("ok", false))
		if ok:
			passed += 1
		_audit_list.add_item("%s  %s" % ["PASS" if ok else "FAIL", str(audit.get("name", path))])
		_audit_list.set_item_custom_fg_color(
			_audit_list.item_count - 1,
			HudStyle.C_GREEN if ok else HudStyle.C_RED,
		)
	_audit_status.text = "Legal code v%d · %d/%d official vessels certified" % [
		VesselRegistrationCatalog.catalog_version(), passed, files.size(),
	]
	if not _audit_records.is_empty():
		_audit_list.select(0)
		_show_audit(0)


func _prebuilt_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PREBUILT_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.to_lower().ends_with(".json"):
			out.append("%s/%s" % [PREBUILT_DIR, filename])
		filename = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _audit_file(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "name": path.get_file(), "errors": ["Invalid JSON"], "path": path}
	var preset := parsed as Dictionary
	var hull_id := str(preset.get("hull_id", ""))
	var registration_id := str(preset.get("registration_id", ""))
	var layout_raw: Variant = preset.get("brick_layout", {})
	if not layout_raw is Dictionary:
		return {
			"ok": false, "name": str(preset.get("name", path.get_file())),
			"errors": ["Missing brick layout"], "path": path,
		}
	var report := VesselCompliance.validate(
		BrickLayout.from_dict(layout_raw as Dictionary),
		hull_id,
		registration_id,
		HullRegistry.make_grid(hull_id),
	)
	report["name"] = str(preset.get("name", path.get_file()))
	report["path"] = path
	report["hull_id"] = hull_id
	return report


func _show_audit(index: int) -> void:
	if index < 0 or index >= _audit_records.size():
		return
	var report := _audit_records[index]
	for i in range(_audit_registration.item_count):
		if str(_audit_registration.get_item_metadata(i)) == str(report.get("registration_id", "")):
			_audit_registration.select(i)
			break
	var lines := PackedStringArray([
		str(report.get("name", "Vessel")),
		str(report.get("path", "")),
		"Hull: %s" % str(report.get("hull_id", "")),
		"Registration: %s" % str(report.get("registration_id", "missing")),
		"Result: %s" % ("CERTIFIED" if bool(report.get("ok", false)) else "REJECTED"),
		"",
	])
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		lines.append("%s  %s — %s (current: %s)" % [
			"PASS" if bool(item.get("ok", false)) else "FAIL",
			str(item.get("label", "")),
			str(item.get("requirement", "")),
			str(item.get("current", "")),
		])
	var errors: PackedStringArray = report.get("errors", PackedStringArray())
	if not errors.is_empty():
		lines.append("")
		lines.append("Findings:")
		for error in errors:
			lines.append("• " + error)
	_audit_detail.text = "\n".join(lines)


func _assign_selected_registration() -> void:
	var selected := _audit_list.get_selected_items()
	if selected.is_empty() or _audit_registration.selected < 0:
		return
	var index := int(selected[0])
	if index < 0 or index >= _audit_records.size():
		return
	var path := str(_audit_records[index].get("path", ""))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_audit_status.text = "Cannot assign registration: invalid prebuilt JSON"
		return
	var preset := (parsed as Dictionary).duplicate(true)
	preset["format_version"] = PrebuiltVesselCatalog.FORMAT_VERSION
	preset["registration_id"] = str(
		_audit_registration.get_item_metadata(_audit_registration.selected)
	)
	var absolute := ProjectSettings.globalize_path(path)
	var temp := absolute + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		_audit_status.text = "Cannot write " + path
		return
	file.store_string(JSON.stringify(preset, "\t") + "\n")
	file.close()
	if FileAccess.file_exists(absolute):
		var remove_err := DirAccess.remove_absolute(absolute)
		if remove_err != OK:
			DirAccess.remove_absolute(temp)
			_audit_status.text = "Existing prebuilt is locked"
			return
	var err := DirAccess.rename_absolute(temp, absolute)
	if err != OK:
		_audit_status.text = "Could not install updated paperwork"
		return
	_audit_all()
