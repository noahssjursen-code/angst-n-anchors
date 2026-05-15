class_name ContractNpc
extends StaticBody3D

## Placeholder NPC at the origin port. Opens a contract board when the player interacts.
## Reads from ContractRegistry — no knowledge of warehouses, cargo, or ships.

@export var port_id: String = ""
@export var interact_range: float = 4.0
@export var npc_color: Color = Color(0.22, 0.38, 0.60)

var _panel: Panel
var _list: VBoxContainer
var _prompt_layer: CanvasLayer
var _prompt: Label
var _open: bool = false

const LAYER_WORLD := 1


func _ready() -> void:
	_build_body()
	if not Engine.is_editor_hint():
		_build_ui()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("ui_cancel") and _open:
		_close_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and _player_can_interact():
		var player := _nearest_player()
		var carry  := player.get_node_or_null("PlayerCarryComponent") as PlayerCarryComponent
		if carry != null and carry.is_carrying():
			return
		_open_panel()
		get_viewport().set_input_as_handled()


# ── Panel ─────────────────────────────────────────────────────────────────────

func _open_panel() -> void:
	_refresh_list()
	_panel.visible    = true
	_open             = true
	Input.mouse_mode  = Input.MOUSE_MODE_VISIBLE


func _close_panel() -> void:
	_panel.visible    = false
	_open             = false
	Input.mouse_mode  = Input.MOUSE_MODE_CAPTURED


func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var registry := _registry()
	if registry == null:
		_list.add_child(_plain_label("ContractRegistry autoload not found."))
		return

	var contracts: Array[Contract] = registry.get_contracts_from_port(port_id)
	if contracts.is_empty():
		_list.add_child(_plain_label("No contracts available."))
		return

	for contract in contracts:
		_list.add_child(_make_row(contract, registry))


func _make_row(contract: Contract, registry: Node) -> Control:
	var dest: String = registry.get_destination_name(contract)

	var info           := Label.new()
	info.text          = "%s  →  %s\n%d × %s   %d gold" % [
		registry.get_port_display_name(contract.origin_port_id),
		dest,
		contract.quantity,
		contract.display_name,
		contract.reward_gold,
	]
	info.autowrap_mode            = TextServer.AUTOWRAP_WORD
	info.size_flags_horizontal    = Control.SIZE_EXPAND_FILL

	var btn := Button.new()
	match contract.state:
		Contract.State.AVAILABLE:
			btn.text = "Accept"
			btn.pressed.connect(_on_accept.bind(contract.id))
		Contract.State.ACCEPTED:
			btn.text     = "Active"
			btn.disabled = true
		Contract.State.COMPLETED:
			btn.text     = "Done"
			btn.disabled = true

	var row                    := HBoxContainer.new()
	row.size_flags_horizontal  = Control.SIZE_FILL
	row.add_child(info)
	row.add_child(btn)

	var sep     := HSeparator.new()
	var wrapper := VBoxContainer.new()
	wrapper.add_child(row)
	wrapper.add_child(sep)
	return wrapper


func _on_accept(contract_id: String) -> void:
	var registry := _registry()
	if registry != null:
		registry.accept_contract(contract_id)
	_refresh_list()


# ── Prompt ────────────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if _prompt == null:
		return
	_prompt.visible = _player_can_interact() and not _open


# ── Interaction check ─────────────────────────────────────────────────────────

func _player_can_interact() -> bool:
	var player := _nearest_player()
	if player == null:
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false
	var from  := camera.global_position
	var to    := from - camera.global_transform.basis.z * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude             = [player.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas  = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	return collider == self or (collider != null and is_ancestor_of(collider))


func _nearest_player() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_body() -> void:
	collision_layer = LAYER_WORLD
	collision_mask  = 0

	var shape          := BoxShape3D.new()
	shape.size         = Vector3(0.7, 1.8, 0.7)
	var col            := CollisionShape3D.new()
	col.name           = "Body"
	col.shape          = shape
	col.position       = Vector3.UP * 0.9
	add_child(col)

	var body := MeshBuilder.box(shape.size, npc_color, 0.6, 0.0)
	body.name     = "NpcVisual"
	body.position = Vector3.UP * 0.9
	add_child(body)

	var hat := MeshBuilder.box(Vector3(0.75, 0.12, 0.75), npc_color.lightened(0.15), 0.5, 0.0)
	hat.name     = "NpcHat"
	hat.position = Vector3.UP * 1.86
	add_child(hat)


func _build_ui() -> void:
	var ui_layer      := CanvasLayer.new()
	ui_layer.name     = "ContractNpcLayer"
	add_child(ui_layer)

	_panel            = Panel.new()
	_panel.name       = "ContractBoard"
	_panel.visible    = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -320.0
	_panel.offset_right  =  320.0
	_panel.offset_top    = -280.0
	_panel.offset_bottom =  280.0
	ui_layer.add_child(_panel)

	var title                      := Label.new()
	title.text                     = "Contract Board"
	title.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 10.0
	title.offset_bottom = 40.0
	_panel.add_child(title)

	var scroll                    := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 48.0
	scroll.offset_bottom = -44.0
	_panel.add_child(scroll)

	_list                    = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close_btn              := Button.new()
	close_btn.text             = "Close"
	close_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	close_btn.offset_top       = -38.0
	close_btn.offset_bottom    = -6.0
	close_btn.offset_left      = 8.0
	close_btn.offset_right     = -8.0
	close_btn.pressed.connect(_close_panel)
	_panel.add_child(close_btn)

	_prompt_layer      = CanvasLayer.new()
	_prompt_layer.name = "ContractNpcPromptLayer"
	add_child(_prompt_layer)

	_prompt                    = Label.new()
	_prompt.text               = "Press E to view contracts"
	_prompt.visible            = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left        = -220.0
	_prompt.offset_right       =  220.0
	_prompt.offset_top         = -148.0
	_prompt.offset_bottom      = -108.0
	_prompt_layer.add_child(_prompt)


func _plain_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")
