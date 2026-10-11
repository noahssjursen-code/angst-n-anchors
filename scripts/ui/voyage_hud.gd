class_name VoyageHud
extends Control

var _helm: MarineHelmConsole
var _prompt: Label
var _shortcuts: Label
var _objective: Label
var _notice: Label
var _notice_time := 0.0
var modal := false
var _timer := 0.0
var preview_mode := false

func _ready() -> void:
	theme = VoyageStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_helm = MarineHelmConsole.new()
	_helm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_helm.offset_left=28
	_helm.offset_right=28 + MarineHelmConsole.WIDTH
	_helm.offset_top=-28 - MarineHelmConsole.HEIGHT
	_helm.offset_bottom=-28
	add_child(_helm)
	_prompt=_banner(Vector2(-230,-104),Vector2(230,-62),Control.PRESET_CENTER_BOTTOM)
	_prompt.add_theme_font_size_override("font_size",18)
	_prompt.add_theme_stylebox_override("normal",VoyageStyle.box(Color("1a2124"),8))
	_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible=false
	_shortcuts=VoyageStyle.label("[J] Tablet     [M] Chart",18,VoyageStyle.LIGHT)
	_shortcuts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_shortcuts.offset_left=-300
	_shortcuts.offset_right=-28
	_shortcuts.offset_top=-48
	_shortcuts.offset_bottom=-22
	_shortcuts.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_shortcuts.add_theme_color_override("font_outline_color",Color(0,0,0,.85))
	_shortcuts.add_theme_constant_override("outline_size",4)
	add_child(_shortcuts)
	_objective=_banner(Vector2(28,24),Vector2(810,95),Control.PRESET_TOP_LEFT)
	_notice=_banner(Vector2(28,110),Vector2(850,190),Control.PRESET_TOP_LEFT)
	_notice.visible=false
	if not preview_mode:
		LocalPlayerView.voyage_changed.connect(present)
		present(LocalPlayerView.get_voyage_snapshot())

func _banner(from: Vector2,to: Vector2,preset: Control.LayoutPreset) -> Label:
	var label := VoyageStyle.label("",21,VoyageStyle.LIGHT)
	label.set_anchors_and_offsets_preset(preset)
	label.offset_left=from.x
	label.offset_top=from.y
	label.offset_right=to.x
	label.offset_bottom=to.y
	label.add_theme_stylebox_override("normal",VoyageStyle.box(VoyageStyle.DARK,12))
	add_child(label)
	return label

func present(state: Dictionary) -> void:
	_helm.visible=bool(state.helming) and not modal
	_objective.visible=not bool(state.helming) and not modal
	_objective.text=str(state.get("objective",""))
	_shortcuts.visible=not modal
	# Keep keys at the bottom edge; reserve the minimap corner while helming.
	_shortcuts.offset_left=-620 if bool(state.helming) else -300
	_shortcuts.offset_right=-344 if bool(state.helming) else -28
	if bool(state.helming):
		_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_prompt.offset_left=28
		_prompt.offset_right=235
		_prompt.offset_top=-28-MarineHelmConsole.HEIGHT-56
		_prompt.offset_bottom=-28-MarineHelmConsole.HEIGHT-12
	else:
		_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_prompt.offset_left=-230
		_prompt.offset_right=230
		_prompt.offset_top=-104
		_prompt.offset_bottom=-62
	_prompt.visible=not modal and not _prompt.text.is_empty()
	if not _helm.visible: return
	_helm.present(state)

func _physics_process(delta: float) -> void:
	if not is_visible_in_tree() or preview_mode: return
	_timer-=delta
	if _timer<=0:
		_timer=.15
		present_interaction(LocalPlayerView.get_interaction_hint() if not modal else "")
	_notice_time-=delta
	_notice.visible=_notice_time>0 and not modal

func notify(text: String) -> void:
	_notice.text=text
	_notice_time=9.0

func present_interaction(text: String) -> void:
	_prompt.text=text
	_prompt.visible=not modal and not text.is_empty()
