class_name CrewSlotTile
extends PanelContainer

## One crew slot — empty (+) or filled with a miniature NPC preview.

signal slot_pressed(slot_index: int)

const TILE_SIZE := 76.0

var _slot_index: int = 0
var _employee: Dictionary = {}
var _viewport_host: SubViewportContainer
var _viewport: SubViewport
var _npc: NpcBase
var _plus_label: Label
var _role_label: Label
var _btn: Button


func _init() -> void:
	custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudStyle.C_BG_INNER * 1.1
	sb.border_color = HudStyle.C_BRASS * 0.65
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func() -> void: slot_pressed.emit(_slot_index))
	_btn = btn
	add_child(btn)

	var stack := Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(stack)

	_plus_label = Label.new()
	_plus_label.text = "+"
	_plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plus_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plus_label.add_theme_font_size_override("font_size", 28)
	_plus_label.add_theme_color_override("font_color", HudStyle.C_LABEL)
	stack.add_child(_plus_label)

	_viewport_host = SubViewportContainer.new()
	_viewport_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_host.offset_left = 4.0
	_viewport_host.offset_top = 4.0
	_viewport_host.offset_right = -4.0
	_viewport_host.offset_bottom = -18.0
	_viewport_host.stretch = true
	_viewport_host.visible = false
	stack.add_child(_viewport_host)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(96, 96)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.transparent_bg = true
	_viewport_host.add_child(_viewport)

	var world := Node3D.new()
	_viewport.add_child(world)

	_npc = NpcBase.new()
	world.add_child(_npc)

	var cam := Camera3D.new()
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, 2.15)).looking_at(
		Vector3(0.0, 0.85, 0.0), Vector3.UP
	)
	cam.fov = 32.0
	cam.current = true
	world.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	light.light_energy = 1.1
	world.add_child(light)

	_role_label = Label.new()
	_role_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_role_label.offset_top = -16.0
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.add_theme_font_size_override("font_size", 10)
	_role_label.add_theme_color_override("font_color", HudStyle.C_TEXT)
	_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_role_label)


func setup(slot_index: int) -> void:
	_slot_index = slot_index


func set_employee(employee: Dictionary) -> void:
	_employee = employee.duplicate() if not employee.is_empty() else {}
	var filled := not _employee.is_empty()
	_plus_label.visible = not filled
	_viewport_host.visible = filled
	_role_label.visible = filled
	if filled:
		_role_label.text = str(_employee.get("role", ""))
		_btn.tooltip_text = "%s — %s/day" % [
			str(_employee.get("name", "Crew")),
			PlayerData.format_money(int(_employee.get("wage_per_day", 0))),
		]
		_apply_npc_appearance()
	else:
		_role_label.text = ""
		_btn.tooltip_text = "Assign crew"


func _apply_npc_appearance() -> void:
	if _employee.is_empty():
		return
	var colors := VesselCrew.colors_from_employee(_employee)
	var apply := func() -> void:
		_npc.set_colors(colors["skin"], colors["coat"], colors["pants"])
		_npc.rotation.y = float(_slot_index) * 0.7
	if _npc.is_node_ready():
		apply.call()
	else:
		_npc.ready.connect(apply, CONNECT_ONE_SHOT)
