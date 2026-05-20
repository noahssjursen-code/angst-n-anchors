extends Control

## Title flow: continue voyage, create captain, or quit.

const WORLD_SCENE := "res://scenes/world.tscn"

enum Page { TITLE, CREATOR }

var _page: Page = Page.TITLE
var _title_root: Control
var _creator: CharacterCreatorPanel
var _continue_btn: Button
var _new_game_warns: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	_build_title_page()
	_creator = CharacterCreatorPanel.new()
	_creator.name = "CharacterCreator"
	_creator.visible = false
	_creator.confirmed.connect(_on_creator_confirmed)
	_creator.cancelled.connect(_on_creator_cancelled)
	add_child(_creator)
	_show_title()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.09)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.02, 0.03, 0.06, 0.35)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_title_page() -> void:
	_title_root = CenterContainer.new()
	_title_root.name = "TitlePage"
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_root)

	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.custom_minimum_size = Vector2(420, 0)
	_title_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ANGST 'N ANCHORS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(title)

	var tag := Label.new()
	tag.text = "Maritime trade on a cold coast"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", HudStyle.C_LABEL)
	vbox.add_child(tag)

	vbox.add_child(HSeparator.new())

	_continue_btn = Button.new()
	_continue_btn.text = "Continue voyage"
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)

	var new_btn := Button.new()
	new_btn.text = "New captain"
	new_btn.pressed.connect(_on_new_captain)
	vbox.add_child(new_btn)

	var edit_btn := Button.new()
	edit_btn.text = "Edit captain"
	edit_btn.pressed.connect(_on_edit_captain)
	vbox.add_child(edit_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	_refresh_continue_state()


func _refresh_continue_state() -> void:
	var session: Node = get_node_or_null("/root/PlayerSession")
	var has_save: bool = false
	if session != null:
		has_save = session.has_local_save()
	_continue_btn.disabled = not has_save
	if has_save and session != null:
		var pdata: PlayerData = session.get("data") as PlayerData
		if pdata != null:
			_continue_btn.text = "Continue as %s" % pdata.display_name
	else:
		_continue_btn.text = "Continue voyage"


func _show_title() -> void:
	_page = Page.TITLE
	_title_root.visible = true
	_creator.visible = false
	_refresh_continue_state()


func _show_creator(new_voyage: bool) -> void:
	_page = Page.CREATOR
	_new_game_warns = new_voyage
	_title_root.visible = false
	_creator.visible = true
	var session := get_node_or_null("/root/PlayerSession")
	if new_voyage:
		_creator.open_with_existing(null)
	else:
		_creator.open_with_existing(session.data if session != null else null)


func _on_continue() -> void:
	_go_to_world()


func _on_new_captain() -> void:
	_show_creator(true)


func _on_edit_captain() -> void:
	_show_creator(false)


func _on_creator_cancelled() -> void:
	_show_title()


func _on_creator_confirmed(display_name: String, appearance: CharacterAppearance) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		_go_to_world()
		return
	if _new_game_warns:
		session.begin_new_captain(display_name, appearance)
	else:
		session.set_display_name(display_name)
		session.set_appearance(appearance)
	_go_to_world()


func _go_to_world() -> void:
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.has_method("set_gameplay_hud_visible"):
		menu.set_gameplay_hud_visible(true)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.save_now()
	get_tree().quit()
