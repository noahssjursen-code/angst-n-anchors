extends Control
## F6 review of everything under res://resources/audio.
## New wav files appear on their own. Add a matching entry to _notes() when you
## know what the clip is for; until then the row still plays and says so.

const ROOT := "res://resources/audio"
const EXCERPT_S := 12.0
const FONT := preload("res://resources/fonts/ui/Barlow-Regular.ttf")
const FONT_SEMI := preload("res://resources/fonts/ui/Barlow-SemiBold.ttf")
const FONT_COND := preload("res://resources/fonts/ui/BarlowCondensed-SemiBold.ttf")
const FONT_MONO := preload("res://resources/fonts/ui/JetBrainsMono.ttf")

const INK := Color(0.910, 0.941, 0.918)
const MUTED := Color(0.620, 0.690, 0.655)
const ACCENT := Color(0.855, 0.745, 0.545)
const PANEL := Color(0.110, 0.145, 0.150)
const BG := Color(0.075, 0.098, 0.102)
const LINE := Color(0.220, 0.275, 0.270)

var _entries: Array[Dictionary] = []
var _list: ItemList
var _title: Label
var _meta: Label
var _body: RichTextLabel
var _status: Label
var _bar: ColorRect
var _bar_fill: ColorRect
var _player: AudioStreamPlayer
var _index := -1
var _playlist := false
var _full := false
var _heard := 0.0
var _ignore_finish := false
var _filling := false
var _row_for_entry: Array[int] = []
@export var review_state_path := "user://audio_reviews/decisions.json"
var _review_store: AudioReviewStore
var _review_note: TextEdit
var _review_verdict: Label
var _review_summary: Label
var _review_message: Label
var _export_dialog: FileDialog
var _save_timer: Timer
var _syncing_note := false
var _approve_button: Button
var _deny_button: Button
var _review_dirty := false


func _ready() -> void:
	_review_store = AudioReviewStore.new(review_state_path)
	_build()
	_scan(ROOT)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _playback_rank(str(a.rel))
		var rb := _playback_rank(str(b.rel))
		if ra == rb:
			return str(a.rel) < str(b.rel)
		return ra < rb)
	_fill_list()
	_update_review_summary()
	if OS.get_cmdline_user_args().has("--audit"):
		_audit()
		get_tree().quit()
		return
	if not _entries.is_empty():
		_playlist = false
		if OS.get_cmdline_user_args().has("--review-unreviewed"):
			_next_unreviewed()
		else:
			_play(0, true)


func _process(delta: float) -> void:
	if _player == null or _index < 0:
		return
	if _player.playing:
		_heard += delta
		_refresh_status()
		if _playlist and not _full and bool(_entries[_index].loop) and _heard >= EXCERPT_S:
			_advance()
	else:
		_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if _review_note != null and _review_note.has_focus():
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_DOWN, KEY_J:
			_step(1, false)
		KEY_UP, KEY_K:
			_step(-1, false)
		KEY_ENTER, KEY_KP_ENTER:
			if _index >= 0:
				_playlist = false
				_play(_index, true)
		KEY_RIGHT, KEY_N:
			_step(1, _playlist)
		KEY_LEFT:
			_step(-1, _playlist)
		KEY_SPACE:
			_toggle_pause()
		KEY_P:
			_begin_playlist(0)
		KEY_ESCAPE:
			_playlist = false
			_ignore_finish = true
			_player.stop()
			_ignore_finish = false
			_refresh_status()
		_:
			return
	get_viewport().set_input_as_handled()


func _scan(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for file_name in access.get_files():
		if file_name.ends_with(".wav"):
			_add_file(dir.path_join(file_name))
	for folder_name in access.get_directories():
		if not folder_name.begins_with("."):
			_scan(dir.path_join(folder_name))


func _add_file(path: String) -> void:
	var rel := path.trim_prefix(ROOT + "/")
	var stem := _stem(rel)
	var note: Dictionary = _notes().get(stem, _world_note(stem))
	var spec: Dictionary = AudioLibrary.entries().get(path, {})
	if not spec.is_empty():
		note = {"title": _title_from_file(rel), "loop": spec.loop, "kind": "Loop" if spec.loop else "One-shot", "text": str(spec.description), "where": str(spec.trigger)}
		if str(spec.status).begins_with("planned"):
			note.where += "\nRecorded for a future sound connection; not yet used during play."
	var loop := bool(note.get("loop", _infer_loop(rel)))
	var entry := {
		"path": path,
		"rel": rel,
		"stem": stem,
		"title": str(note.get("title", _title_from_file(rel))),
		"kind": str(note.get("kind", "Continuous bed" if loop else "One-shot")),
		"text": str(note.get("text", "New file in the library. It plays here. An explanation has not been written for it yet.")),
		"where": str(note.get("where", "")),
		"loop": loop,
		"known": not note.is_empty(),
		"sha256": FileAccess.get_sha256(path),
		"duration_seconds": float(spec.get("actual_seconds", 0.0)),
	}
	_entries.append(entry)


func _fill_list() -> void:
	_filling = true
	_list.clear()
	_row_for_entry.clear()
	_row_for_entry.resize(_entries.size())
	var last_group := ""
	for i in _entries.size():
		var group := _group_label(str(_entries[i].rel))
		if group != last_group:
			var header := _list.add_item(group.to_upper())
			_list.set_item_metadata(header, -1)
			_list.set_item_custom_fg_color(header, ACCENT)
			_list.set_item_disabled(header, true)
			last_group = group
		var take := _take_number(str(_entries[i].rel))
		var label := str(_entries[i].title)
		if take > 0:
			label += "  ·  %d" % take
		var row := _list.add_item(label)
		_list.set_item_metadata(row, i)
		_row_for_entry[i] = row
		_update_review_row(i)
	_filling = false


func _play(index: int, full: bool) -> void:
	if index < 0 or index >= _entries.size():
		_playlist = false
		return
	_index = index
	_full = full
	_heard = 0.0
	var entry: Dictionary = _entries[index]
	var stream := AudioLibrary.stream(str(entry.path), bool(entry.loop))
	if stream == null:
		push_warning("Audio showcase could not load %s" % entry.path)
		if _playlist:
			_advance()
		return
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if bool(entry.loop) else AudioStreamWAV.LOOP_DISABLED
	_ignore_finish = true
	_player.stop()
	_ignore_finish = false
	_player.stream = stream
	_player.stream_paused = false
	_player.volume_db = 0.0
	_player.play()
	_show_entry(entry)
	_filling = true
	_list.select(_row_for_entry[index])
	_list.ensure_current_is_visible()
	_filling = false


func _advance() -> void:
	if not _playlist:
		return
	var next := _index + 1
	if next >= _entries.size():
		_playlist = false
		_ignore_finish = true
		_player.stop()
		_ignore_finish = false
		_status.text = "End of library."
		return
	_play(next, false)


func _begin_playlist(index: int) -> void:
	_playlist = true
	_play(index, false)


func _step(direction: int, keep_playlist: bool) -> void:
	if _entries.is_empty():
		return
	var start := _index if _index >= 0 else 0
	var next := posmod(start + direction, _entries.size())
	_playlist = keep_playlist
	_play(next, not keep_playlist)


func _toggle_pause() -> void:
	if _player.stream == null:
		return
	if _player.playing:
		_player.stream_paused = not _player.stream_paused
	else:
		_player.play()
	_refresh_status()


func _on_item_selected(row: int) -> void:
	if _filling:
		return
	var index := int(_list.get_item_metadata(row))
	if index < 0:
		return
	_playlist = false
	_play(index, true)


func _on_finished() -> void:
	if _ignore_finish:
		return
	if _playlist:
		_advance()
	else:
		_refresh_status()


func _show_entry(entry: Dictionary) -> void:
	_title.text = str(entry.title)
	var length := 0.0
	if _player.stream != null:
		length = _player.stream.get_length()
	var kind := str(entry.kind)
	var length_text := _clock(length)
	if bool(entry.loop):
		length_text += " loop"
	_meta.text = "%s    %s" % [kind, length_text]
	var where := str(entry.where)
	var body := str(entry.text)
	if not where.is_empty():
		body = where + "\n\n" + body
	if _playlist and bool(entry.loop):
		body += "\n\nPlay all listens to the first %d seconds, then moves on. Enter hears the whole loop." % int(EXCERPT_S)
	_body.text = body
	_syncing_note = true
	var vote := _review_store.decision(entry)
	_review_note.text = str(vote.note)
	_syncing_note = false
	_update_review_controls()
	_refresh_status()


func _refresh_status() -> void:
	if _index < 0 or _index >= _entries.size():
		_status.text = ""
		_bar_fill.anchor_right = 0.0
		return
	var entry: Dictionary = _entries[_index]
	var length := _player.stream.get_length() if _player.stream != null else 0.0
	var shown := _heard
	if _player.playing and _player.stream != null:
		shown = _player.get_playback_position()
	var mode := "Play all" if _playlist else "This clip"
	if _player.stream_paused:
		mode = "Paused"
	elif not _player.playing:
		mode = "Stopped"
	_status.text = "%s    %s    %s / %s" % [mode, entry.rel, _clock(shown), _clock(length)]
	var span := length
	if _playlist and not _full and bool(entry.loop):
		span = minf(length, EXCERPT_S)
	var fraction := 0.0 if span <= 0.0 else clampf(shown / span, 0.0, 1.0)
	_bar_fill.offset_right = _bar.size.x * fraction


func _audit() -> void:
	assert(ShipyardPlaytestMode.active(), "Audio review must not open captain saves")
	var missing: PackedStringArray = []
	for entry in _entries:
		if not bool(entry.known):
			missing.append(str(entry.rel))
	print("AUDIO LIBRARY %d files, %d without an explanation" % [_entries.size(), missing.size()])
	for rel in missing:
		print("  missing  ", rel)
	if missing.is_empty():
		print("AUDIO LIBRARY PASS")


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var heading := Label.new()
	heading.text = "SOUND LIBRARY"
	_style(heading, FONT_COND, 28, ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(_button("Play", _on_play_pressed))
	header.add_child(_button("Play all", _on_play_all_pressed))
	header.add_child(_button("Stop", _on_stop_pressed))
	header.add_child(_button("Export report", _choose_report_path))

	var hint := Label.new()
	hint.text = "Up and down move. Enter plays the whole clip. P plays the library. Space pauses. Esc stops."
	_style(hint, FONT, 15, MUTED)
	column.add_child(hint)
	_review_summary = Label.new()
	_style(_review_summary, FONT, 16, INK)
	column.add_child(_review_summary)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -150
	column.add_child(split)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.focus_mode = Control.FOCUS_NONE
	_style(_list, FONT, 16, INK)
	_list.add_theme_color_override("font_hovered_color", INK)
	_list.add_theme_color_override("font_selected_color", INK)
	_list.add_theme_color_override("guide_color", LINE)
	_list.add_theme_stylebox_override("panel", _panel())
	_list.add_theme_stylebox_override("selected", _selected_style())
	_list.add_theme_stylebox_override("hovered", _selected_style(true))
	_list.item_selected.connect(_on_item_selected)
	split.add_child(_list)

	var detail := PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_stylebox_override("panel", _panel())
	split.add_child(detail)
	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 22)
	detail_margin.add_theme_constant_override("margin_top", 18)
	detail_margin.add_theme_constant_override("margin_right", 22)
	detail_margin.add_theme_constant_override("margin_bottom", 18)
	detail.add_child(detail_margin)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 10)
	detail_margin.add_child(detail_box)

	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style(_title, FONT_SEMI, 26, INK)
	detail_box.add_child(_title)
	_meta = Label.new()
	_style(_meta, FONT_COND, 16, ACCENT)
	detail_box.add_child(_meta)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.selection_enabled = true
	_body.add_theme_font_override("normal_font", FONT)
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_color_override("default_color", INK)
	detail_box.add_child(_body)
	var review_controls := HBoxContainer.new()
	review_controls.add_theme_constant_override("separation", 8)
	detail_box.add_child(review_controls)
	_approve_button = _button("Approve", func(): _set_verdict("approved"))
	_approve_button.name = "ApproveAudio"
	review_controls.add_child(_approve_button)
	_deny_button = _button("Deny", func(): _set_verdict("denied"))
	_deny_button.name = "DenyAudio"
	review_controls.add_child(_deny_button)
	review_controls.add_child(_button("Reset", func(): _set_verdict("unreviewed")))
	_review_verdict = Label.new()
	_style(_review_verdict, FONT_SEMI, 16, ACCENT)
	detail_box.add_child(_review_verdict)
	_review_note = TextEdit.new()
	_review_note.name = "ReviewNotes"
	_review_note.custom_minimum_size = Vector2(0, 110)
	_review_note.placeholder_text = "Your notes: too synthetic, wrong engine, clicks at the loop, too much reverb…"
	_review_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style(_review_note, FONT, 16, INK)
	_review_note.add_theme_stylebox_override("normal", _panel())
	_review_note.text_changed.connect(_on_review_note_changed)
	detail_box.add_child(_review_note)
	detail_box.add_child(_button("Next unreviewed", _next_unreviewed))
	_review_message = Label.new()
	_review_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style(_review_message, FONT, 14, MUTED)
	_review_message.text = "Decisions save automatically. Export a report when you want to send feedback."
	detail_box.add_child(_review_message)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save_review)
	add_child(_save_timer)
	_export_dialog = FileDialog.new()
	_export_dialog.title = "Save audio review report"
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.use_native_dialog = true
	_export_dialog.filters = PackedStringArray(["*.json ; Audio review report"])
	_export_dialog.file_selected.connect(_export_report)
	add_child(_export_dialog)

	_bar = ColorRect.new()
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.color = LINE
	column.add_child(_bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = ACCENT
	_bar_fill.anchor_right = 0.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_right = 0.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_fill)

	_status = Label.new()
	_style(_status, FONT_MONO, 14, MUTED)
	column.add_child(_status)

	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	_player.finished.connect(_on_finished)
	add_child(_player)


func _on_play_pressed() -> void:
	var index := _index if _index >= 0 else 0
	_playlist = false
	_play(index, true)


func _on_play_all_pressed() -> void:
	_begin_playlist(0)


func _on_stop_pressed() -> void:
	_playlist = false
	_ignore_finish = true
	_player.stop()
	_ignore_finish = false
	_refresh_status()


func _set_verdict(verdict: String) -> void:
	if _index < 0:
		return
	_playlist = false
	_review_store.set_decision(_entries[_index], verdict, _review_note.text)
	_review_dirty = true
	_save_review()
	_update_review_row(_index)
	_update_review_controls()
	_update_review_summary()


func _on_review_note_changed() -> void:
	if _syncing_note or _index < 0:
		return
	_playlist = false
	var entry: Dictionary = _entries[_index]
	_review_store.set_decision(entry, str(_review_store.decision(entry).verdict), _review_note.text)
	_review_dirty = true
	_save_timer.start()


func _save_review() -> void:
	if not _review_dirty:
		return
	if _review_store.save():
		_review_dirty = false
		_review_message.text = "Review saved. Export a report when you are ready."
	else:
		_review_message.text = _review_store.last_error


func _exit_tree() -> void:
	if _review_dirty and _review_store != null:
		_review_store.save()


func _update_review_row(index: int) -> void:
	var entry: Dictionary = _entries[index]
	var verdict := str(_review_store.decision(entry).verdict)
	var marker := {"approved": "[OK]", "denied": "[NO]", "unreviewed": "[  ]"}
	var take := _take_number(str(entry.rel))
	var label := "%s  %s" % [marker[verdict], entry.title]
	if take > 0:
		label += "  ·  %d" % take
	_list.set_item_text(_row_for_entry[index], label)
	var color := Color(0.55, 0.82, 0.66) if verdict == "approved" else Color(0.95, 0.60, 0.51) if verdict == "denied" else INK
	_list.set_item_custom_fg_color(_row_for_entry[index], color)


func _update_review_controls() -> void:
	if _index < 0:
		return
	var verdict := str(_review_store.decision(_entries[_index]).verdict)
	_review_verdict.text = "This clip: " + verdict.capitalize()
	_approve_button.text = "Approved" if verdict == "approved" else "Approve"
	_deny_button.text = "Denied" if verdict == "denied" else "Deny"


func _update_review_summary() -> void:
	var counts: Dictionary = _review_store.report(_entries).summary
	_review_summary.text = "%d clips    •    %d approved    •    %d denied    •    %d unreviewed" % [_entries.size(), counts.approved, counts.denied, counts.unreviewed]


func _next_unreviewed() -> void:
	for offset in range(1, _entries.size() + 1):
		var next := posmod(_index + offset, _entries.size())
		if _review_store.decision(_entries[next]).verdict == "unreviewed":
			_playlist = false
			_play(next, true)
			return
	_review_message.text = "Every clip has a decision. Export your report."


func _choose_report_path() -> void:
	_playlist = false
	_save_review()
	_export_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_export_dialog.current_file = "Angst-n-Anchors-audio-review-%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	_export_dialog.popup_centered_ratio(0.65)


func _export_report(path: String, copy_path := true) -> void:
	_save_review()
	if not path.to_lower().ends_with(".json"):
		path += ".json"
	if _review_store.export_report(path, _entries):
		_review_message.text = "Report saved: " + path
		if copy_path:
			DisplayServer.clipboard_set(path)
			_review_message.text += "\nFile path copied. Send the file or paste its path in chat."
	else:
		_review_message.text = _review_store.last_error


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 40
	_style(button, FONT_SEMI, 16, INK)
	button.add_theme_stylebox_override("normal", _panel())
	button.add_theme_stylebox_override("hover", _selected_style(true))
	button.add_theme_stylebox_override("pressed", _selected_style())
	button.pressed.connect(handler)
	return button


func _style(node: Control, font: Font, size: int, color: Color) -> void:
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("default_color", color)
	node.add_theme_color_override("font_selected_color", color)


func _panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.set_corner_radius_all(2)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.border_color = LINE
	box.set_border_width_all(1)
	return box


func _selected_style(hover := false) -> StyleBoxFlat:
	var box := _panel()
	box.bg_color = Color(0.23, 0.29, 0.26) if not hover else Color(0.180, 0.220, 0.215)
	box.border_color = ACCENT if not hover else LINE
	return box


func _playback_rank(rel: String) -> int:
	const ORDER: Array[String] = [
		"looped/ocean/",
		"looped/wind/",
		"looped/rain/",
		"looped/atmosphere/",
		"looped/foghorns/",
		"normal/thunder/",
		"world/",
		"ship/engines/",
		"ship/thruster/",
		"ship/hull/",
		"ship/controls/",
	]
	for i in ORDER.size():
		if rel.begins_with(ORDER[i]):
			return i
	return ORDER.size()


func _group_label(rel: String) -> String:
	var parts := rel.split("/")
	if rel.begins_with("looped/ocean/"):
		return "Waves"
	if rel.begins_with("looped/wind/"):
		return "Wind"
	if rel.begins_with("looped/rain/"):
		return "Rain"
	if rel.begins_with("looped/atmosphere/"):
		return "Air"
	if rel.begins_with("looped/foghorns/"):
		return "Harbour horn"
	if rel.begins_with("normal/thunder/"):
		return "Thunder"
	if parts.size() >= 3 and parts[0] == "ship" and parts[1] == "engines":
		return "Engine  ·  " + parts[2].replace("_", " ")
	if parts.size() >= 2 and parts[0] == "world":
		return parts[1].replace("_", " ").capitalize()
	if parts.size() >= 2:
		return parts[1].replace("_", " ").capitalize()
	return parts[0]


func _stem(rel: String) -> String:
	var no_ext := rel.trim_suffix(".wav")
	var slash := no_ext.rfind("/")
	var folder := ""
	var file := no_ext
	if slash >= 0:
		folder = no_ext.substr(0, slash + 1)
		file = no_ext.substr(slash + 1)
	var digits := RegEx.new()
	digits.compile("_\\d+$")
	return folder + digits.sub(file, "")


func _take_number(rel: String) -> int:
	var file := rel.get_file().trim_suffix(".wav")
	var digits := RegEx.new()
	digits.compile("_(\\d+)$")
	var found := digits.search(file)
	if found == null:
		return 0
	return int(found.get_string(1))


func _title_from_file(rel: String) -> String:
	var file := rel.get_file().trim_suffix(".wav")
	var digits := RegEx.new()
	digits.compile("_\\d+$")
	return digits.sub(file, "").replace("_", " ").capitalize()


func _infer_loop(rel: String) -> bool:
	if rel.begins_with("normal/"):
		return false
	var file := rel.get_file()
	for token in ["start", "stop", "click", "thunder", "engage", "release", "hook", "board", "exit"]:
		if token in file:
			return false
	return true


func _clock(seconds: float) -> String:
	var whole := maxi(int(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


func _world_note(stem: String) -> Dictionary:
	const BLURBS := {
		"world/footsteps/step_steel": ["Steel deck step", "One-shot", "A boot on the ship you are standing on."],
		"world/footsteps/step_concrete": ["Quay step", "One-shot", "A boot on harbour concrete, when you are not aboard."],
		"world/footsteps/step_wood": ["Wood step", "One-shot", "A boot on timber. Kept for wooden decks and piers."],
		"world/footsteps/step_grating": ["Grating step", "One-shot", "A boot on steel grating."],
		"world/body/jump": ["Jump", "One-shot", "Leaving the deck or the quay."],
		"world/body/land_steel": ["Land on steel", "One-shot", "Coming down on a deck."],
		"world/body/land_concrete": ["Land on concrete", "One-shot", "Coming down on the quay."],
		"world/water/splash_enter": ["Enter the water", "One-shot", "You left the deck or the quay and went in."],
		"world/water/wade": ["Wading", "Water bed", "While you are in the water, before the rescue puts you back."],
		"world/water/quay_lap": ["Quay water", "Water bed", "Small harbour waves on a quay. Separate from the open-sea bed."],
		"world/water/bow_wash": ["Bow wash", "Water bed", "Water along the hull while the ship is moving. Separate from the weather sea."],
		"world/doors/door_open": ["Door open", "One-shot", "A steel door on the ship."],
		"world/doors/door_close": ["Door close", "One-shot", "The same door shutting."],
		"world/doors/door_latch": ["Latch", "One-shot", "The latch itself."],
		"world/mooring/line_on": ["Line on", "One-shot", "A mooring line made fast on a bollard."],
		"world/mooring/line_off": ["Line off", "One-shot", "A mooring line let go."],
		"world/mooring/line_creak": ["Working lines", "Ship bed", "The ropes when a moored ship is still moving."],
		"world/mooring/fender_rub": ["Fender", "Ship bed", "The hull working against the quay."],
		"world/crane/slew": ["Crane slew", "Crane bed", "The crane turning. Heard at the crane."],
		"world/crane/trolley": ["Crane travel", "Crane bed", "Trolley on a provision crane, boom on a bulk crane."],
		"world/crane/hoist": ["Crane hoist", "Crane bed", "The winch while the hook is moving."],
		"world/crane/grab_open": ["Grab open", "One-shot", "The bulk grab jaws opening."],
		"world/crane/grab_close": ["Grab close", "One-shot", "The bulk grab jaws closing."],
		"world/crane/hook_stop": ["Hook stop", "One-shot", "The hoist reaching a stop."],
		"world/fishing/winch": ["Trawl winch", "Ship bed", "While the trawl is set."],
		"world/fishing/net_splash": ["Net in the water", "One-shot", "The gear entering the sea."],
		"world/fishing/gear_out": ["Set the trawl", "One-shot", "Shooting the gear."],
		"world/fishing/gear_in": ["Haul the trawl", "One-shot", "Recovering the gear."],
		"world/ladder/ladder_step": ["Ladder", "One-shot", "Climbing between the quay and the deck."],
		"world/gangway/gangway_step": ["Gangway step", "One-shot", "A boot on the gangway, instead of a deck step."],
		"world/gangway/gangway_lower": ["Gangway down", "One-shot", "The ramp swinging onto the quay when both lines are fast."],
		"world/gangway/gangway_raise": ["Gangway up", "One-shot", "The ramp lifting when the lines are let go."],
		"world/ramp/ramp_hydraulic": ["Bow ramp hydraulics", "Ship bed", "The ferry ramp cylinders while the leaf is moving."],
		"world/ramp/ramp_land": ["Bow ramp lands", "One-shot", "The ramp toe meeting the passenger pier."],
		"world/helm/seat_sit": ["Take the chair", "One-shot", "Sitting at the helm or in a passenger seat."],
		"world/helm/seat_stand": ["Leave the chair", "One-shot", "Standing up from that seat."],
		"world/helm/breaker_click": ["Light breaker", "One-shot", "The bridge breaker when the light preset changes."],
		"world/helm/autopilot_click": ["Autopilot relay", "One-shot", "The relay when passage autopilot is engaged or given up."],
		"world/cargo/container_lift": ["Container lift", "One-shot", "The chains taking the weight of a box off its bed."],
		"world/cargo/container_land": ["Container land", "One-shot", "The box set down on a free bed."],
		"world/cargo/bulk_pour": ["Bulk pour", "One-shot", "Ore or gravel leaving the grab."],
		"world/water/stern_wash": ["Stern wash", "Water bed", "Propeller wash at the stern while the ship is moving. Heard on the hull, not as a headphone bed."],
		"world/water/hull_slap": ["Hull slap", "One-shot", "A wave hitting the side of a moving hull."],
	}
	if not BLURBS.has(stem):
		return {}
	var row: Array = BLURBS[stem]
	var loop := str(row[1]).ends_with("bed")
	return {"title": row[0], "kind": row[1], "loop": loop, "text": row[2], "where": "Played in the world, at the thing that made it."}


func _notes() -> Dictionary:
	var helm := "Heard by you, at the helm, as a 2D bed. It is not placed on the engine in the world."
	return {
		"looped/ocean/calm_seas": _bed("Calm sea", "Light water against the hull in a low sea.", "Weather bed. Blends in as the wave intensity rises from calm toward chop."),
		"looped/ocean/choppy_seas": _bed("Choppy sea", "Short steep sea, more slap than the calm take.", "Weather bed between calm and rough."),
		"looped/ocean/rough_seas": _bed("Rough sea", "Heavier sea, longer wash and more impact.", "Weather bed between chop and storm."),
		"looped/ocean/stormy_seas": _bed("Storm sea", "The top of the ocean bed. Large water, no thunder mixed in.", "Weather bed at the high end of wave intensity."),
		"looped/wind/wind_light": _bed("Light wind", "Air over the mic in a moderate breeze.", "Weather bed. Crossfades toward gale as the wind rises."),
		"looped/wind/wind_gale": _bed("Gale", "Hard wind, still only wind. Rain and sea are separate beds.", "Weather bed for strong wind."),
		"looped/rain/rain_drizzle": _bed("Drizzle", "Fine rain, the first wet layer.", "Weather bed. Starts as rain becomes audible."),
		"looped/rain/rain_moderate": _bed("Moderate rain", "Steady rain on the listener.", "Weather bed between drizzle and heavy rain."),
		"looped/rain/rain_heavy": _bed("Heavy rain", "Hard rain, the top of the rain bed. No thunder mixed in.", "Weather bed at high rain amount."),
		"looped/rain/rain_on_roof": _bed("Rain on the roof", "Rain on steel, heard from inside a cabin or under a cover.", "Replaces most of the open-air rain while you are standing under a roof. The sea stays quieter, not silent."),
		"looped/atmosphere/atm_calm_clear": _bed("Clear air", "The dry, quiet coastal bed under fair weather.", "Atmosphere bed when rain and wind are both low."),
		"looped/atmosphere/atm_grey_drizzle": _bed("Grey drizzle", "Wet air without a gale.", "Atmosphere bed for rain in lighter wind."),
		"looped/atmosphere/atm_dry_squall": _bed("Dry squall", "Wind-driven air with little rain in it.", "Atmosphere bed for a gale that stays mostly dry."),
		"looped/atmosphere/atm_full_storm": _bed("Full storm", "Rain and gale together. Thunder is a separate one-shot.", "Atmosphere bed when rain and wind are both high."),
		"looped/foghorns/fog_horn": _note("Harbour fog horn", "Positional", true, "Placed on a foghorn building and heard in the world, out to a long distance.", "One blast, then quiet, in a thirty-second loop. It sounds while local fog is thick and holds through small dips so it does not restart on every wisp."),
		"normal/thunder/thunder": _note("Thunder", "One-shot", false, "Weather one-shot on the listener, after a lightning strike.", "Delay follows the distance of the bolt. Louder when the strike is close. One of the numbered takes is chosen each time."),
		"ship/controls/throttle_click": _note("Throttle step", "One-shot", false, helm, "A click when the throttle lever moves to a new step."),
		"ship/hull/hull_creak": _note("Hull creak", "Ship bed", true, helm + " Rises with wave intensity and with how hard the hull is rolling.", "Occasional working of a steel hull in a seaway."),
		"ship/thruster/bow_thruster": _note("Bow thruster", "Ship bed", true, helm + " Fades in once the thruster is actually commanded.", "Tunnel thruster while the lateral control is held."),
		"ship/engines/compact_i6/engine_idle": _engine("Compact inline-six idle", "14 m trawler. Compact diesel, 300 kW at 240 shaft rpm. The 450 kW package uses this recording and is pitched up to 275 rpm. A hull with no engine preset uses this bank."),
		"ship/engines/compact_i6/engine_load": _engine("Compact inline-six under way", "Same trawler engine, held under load. Crossfades with idle as the throttle rises."),
		"ship/engines/compact_i6/engine_start": _engine_shot("Compact inline-six start", "Starter, catch, then idle. Plays when you take the helm on the trawler."),
		"ship/engines/compact_i6/engine_stop": _engine_shot("Compact inline-six stop", "Ignition off and rundown. Plays when you leave the trawler helm."),
		"ship/engines/coastal_i6/engine_idle": _engine("Coastal inline-six idle", "24 m harbour cargo and coastal bulk. 700 kW at 210 shaft rpm. The 950 kW package is pitched up to 240 rpm."),
		"ship/engines/coastal_i6/engine_load": _engine("Coastal inline-six under way", "Same workboat engine under load. Heavier and slower than the trawler."),
		"ship/engines/coastal_i6/engine_start": _engine_shot("Coastal inline-six start", "Start for the 24 m cargo and bulk boats."),
		"ship/engines/coastal_i6/engine_stop": _engine_shot("Coastal inline-six stop", "Shutdown for the 24 m cargo and bulk boats."),
		"ship/engines/freighter_v12/engine_idle": _engine("Freighter V12 idle", "32 m coastal freighter. Medium-speed V12, 1100 kW at 180 shaft rpm. The 1600 kW package is pitched up to 210 rpm."),
		"ship/engines/freighter_v12/engine_load": _engine("Freighter V12 under way", "Same coaster engine under load. This is not the fast catamaran, even though that ferry reuses the freighter's visual model."),
		"ship/engines/freighter_v12/engine_start": _engine_shot("Freighter V12 start", "Start for the 32 m freighter."),
		"ship/engines/freighter_v12/engine_stop": _engine_shot("Freighter V12 stop", "Shutdown for the 32 m freighter."),
		"ship/engines/catamaran_twin/engine_idle": _engine("Ferry twins idle", "Coastal Express. Two diesels, 3600 kW combined, 420 shaft rpm. A separate bank from the slow freighter."),
		"ship/engines/catamaran_twin/engine_load": _engine("Ferry twins under way", "Both ferry diesels held at working rpm, with the beat between them."),
		"ship/engines/catamaran_twin/engine_start": _engine_shot("Ferry twins start", "Start for the Coastal Express."),
		"ship/engines/catamaran_twin/engine_stop": _engine_shot("Ferry twins stop", "Shutdown for the Coastal Express."),
		"ship/engines/feeder_v12/engine_idle": _engine("Feeder V12 idle", "88 m feeder, the 2100 kW package, 185 shaft rpm. Deeper than the 32 m freighter."),
		"ship/engines/feeder_v12/engine_load": _engine("Feeder V12 under way", "The 2100 kW feeder engine under load."),
		"ship/engines/feeder_v12/engine_start": _engine_shot("Feeder V12 start", "Start for the 2100 kW feeder package."),
		"ship/engines/feeder_v12/engine_stop": _engine_shot("Feeder V12 stop", "Shutdown for the 2100 kW feeder package."),
		"ship/engines/feeder_high_v12/engine_idle": _engine("High-output feeder idle", "88 m Northline default. 5600 kW medium-speed V12 at 220 shaft rpm."),
		"ship/engines/feeder_high_v12/engine_load": _engine("High-output feeder under way", "The 5600 kW engine held under load. Larger than the 2100 kW feeder bank."),
		"ship/engines/feeder_high_v12/engine_start": _engine_shot("High-output feeder start", "Start for the 5600 kW feeder."),
		"ship/engines/feeder_high_v12/engine_stop": _engine_shot("High-output feeder stop", "Shutdown for the 5600 kW feeder."),
	}


func _bed(title: String, text: String, where: String) -> Dictionary:
	return {"title": title, "kind": "Ambient bed", "loop": true, "text": text, "where": where}


func _engine(title: String, text: String) -> Dictionary:
	return {"title": title, "kind": "Engine bed", "loop": true, "text": text, "where": "Close mix while you are at the helm. The same loop also sits on the stern, so the ship is heard from the deck and the quay. That stern copy ducks while you are in the chair."}


func _engine_shot(title: String, text: String) -> Dictionary:
	return {"title": title, "kind": "One-shot", "loop": false, "text": text, "where": "Heard by you when the helm is taken or given up. It does not loop."}


func _note(title: String, kind: String, loop: bool, where: String, text: String) -> Dictionary:
	return {"title": title, "kind": kind, "loop": loop, "text": text, "where": where}
