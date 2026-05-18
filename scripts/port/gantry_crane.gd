@tool
class_name GantryCrane
extends Node3D

## Wharf gantry crane.
## Geometry comes from resources/data/models/dockyard/gantry_crane.json (loaded
## via ModelAssembler). Kinematic parts (trolley, hook) are looked up by role
## and animated by this script.
##
## Controls (active only while operator is seated):
##   A / D       — gantry rolls along quay (-X / +X within roll range)
##   W / S       — trolley travels along beam (toward water / toward land)
##   R / F       — hoist up / down (R raises hook, F lowers)
##   RMB drag    — orbit camera around hook
##   Scroll      — camera zoom
##   LMB         — click a glowing pallet corner socket to attach a chain
##   Space       — release pallet (drops on whatever is below: delivery zone, deck cell, or in place)
##   E           — board crane (when standing nearby) / exit crane (when seated, hands free)
##   Escape      — force exit

const MODEL_PATH := "res://resources/data/models/dockyard/gantry_crane.json"

signal player_boarded
signal player_exited

# ── Tunables ──────────────────────────────────────────────────────────────────

@export var gantry_roll_range_x: float = 4.0     # ±range from spawn X
@export var gantry_speed_m: float    = 3.0
@export var trolley_speed_m: float   = 4.0
@export var hoist_speed_m: float     = 3.5

## Trolley travel limits along Z. -Z = over water/ship berth, +Z = over apron.
@export var trolley_min_z: float = -28.0
@export var trolley_max_z: float = 20.0

## Hoist limits (hook position Y in trolley-local space — always negative).
@export var hoist_min_drop: float = 1.0    # hook just below trolley
@export var hoist_max_drop: float = 15.0   # hook close to ground

## How close (XZ) the hook must be to a pallet to highlight its sockets.
@export var pickup_range_m: float = 4.0
## Hook must be below this absolute world Y to enable pickup highlights.
@export var pickup_max_hook_height: float = 2.5

## Player must be within this range to board.
@export var board_range_m: float = 7.0

# ── Runtime state ─────────────────────────────────────────────────────────────

var _assembler: ModelAssembler
var _gantry_frame: Node3D      # holds the assembler; slides in X
var _trolley: Node3D
var _hook: Node3D
var _cable: MeshInstance3D
var _rigging: CraneRigging
var _camera: CraneCamera

var _spawn_x: float           # crane.position.x captured at _ready
var _gantry_x_offset: float = 0.0
var _trolley_z: float = 0.0
var _hoist_drop: float = 8.0

var _occupied: bool = false
var _player: CharacterBody3D = null
var _carried_pallet: Node3D = null      # PalletNode currently lifted
var _highlighted_pallet: Node3D = null  # PalletNode whose sockets glow

var _ui: CanvasLayer
var _prompt: Label
var _hud: Label


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_spawn_x = position.x
	_trolley_z = clampf(_trolley_z, trolley_min_z, trolley_max_z)
	_hoist_drop = clampf(_hoist_drop, hoist_min_drop, hoist_max_drop)
	if not Engine.is_editor_hint():
		_register_input_actions()
	_build()


func _exit_tree() -> void:
	if _rigging != null and is_instance_valid(_rigging):
		_rigging.detach_all()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_gantry_frame = Node3D.new()
	_gantry_frame.name = "GantryFrame"
	add_child(_gantry_frame)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_gantry_frame.owner = get_tree().edited_scene_root

	_assembler = ModelAssembler.new()
	_assembler.name = "CraneModel"
	_assembler.model_data_path = MODEL_PATH
	_gantry_frame.add_child(_assembler)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		_assembler.owner = get_tree().edited_scene_root

	_wire_kinematic_parts.call_deferred()

	if not Engine.is_editor_hint():
		_build_rigging.call_deferred()
		_build_camera.call_deferred()
		_build_ui()


func _wire_kinematic_parts() -> void:
	var trolley_part := _assembler.get_first_part_by_role("trolley")
	var hook_part := _assembler.get_first_part_by_role("hook")
	if trolley_part == null or hook_part == null:
		push_error("GantryCrane: trolley/hook role not found in model JSON")
		return

	_trolley = trolley_part
	_hook = hook_part

	# Reparent hook under trolley so trolley motion drags the hook with it.
	# Hoist then becomes a local Y on the hook.
	_hook.reparent(_trolley, false)
	_hook.position = Vector3(0.0, -_hoist_drop, 0.0)
	_hook.rotation = Vector3.ZERO

	_build_cable()
	_apply_kinematics()


func _build_cable() -> void:
	if _cable != null and is_instance_valid(_cable):
		_cable.queue_free()
	_cable = MeshInstance3D.new()
	_cable.name = "Cable"
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 1.0, 0.08)
	_cable.mesh = box
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.20, 0.22)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cable.material_override = mat
	_trolley.add_child(_cable)


func _build_rigging() -> void:
	if _hook == null:
		return
	_rigging = CraneRigging.new()
	_rigging.name = "Rigging"
	_rigging.hook = _hook
	add_child(_rigging)


func _build_camera() -> void:
	if _hook == null:
		return
	_camera = CraneCamera.new()
	_camera.name = "CraneCamera"
	_camera.target = _hook
	add_child(_camera)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "CraneUI"
	add_child(_ui)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "Press E to operate crane"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -240.0
	_prompt.offset_right = 240.0
	_prompt.offset_top = -96.0
	_prompt.offset_bottom = -48.0
	_ui.add_child(_prompt)

	_hud = Label.new()
	_hud.name = "Hud"
	_hud.visible = false
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.offset_left = 16.0
	_hud.offset_top = 16.0
	_hud.offset_right = 460.0
	_hud.offset_bottom = 160.0
	_ui.add_child(_hud)


# ── Main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _occupied:
		_update_prompt()
		return
	_read_kinematic_input(delta)
	_apply_kinematics()
	_update_carried_pallet()
	_update_pickup_highlight()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _occupied:
		if event.is_action_pressed("ui_cancel"):
			_exit_crane()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			if _carried_pallet == null:
				_exit_crane()
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed("crane_release"):
			_try_release()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _nearest_boardable_player() != null:
			_enter_crane()
			get_viewport().set_input_as_handled()


# ── Kinematics ────────────────────────────────────────────────────────────────

func _read_kinematic_input(delta: float) -> void:
	var gantry_dir := Input.get_axis("crane_gantry_left", "crane_gantry_right")
	_gantry_x_offset = clampf(
		_gantry_x_offset + gantry_dir * gantry_speed_m * delta,
		-gantry_roll_range_x, gantry_roll_range_x,
	)

	var trolley_dir := Input.get_axis("crane_trolley_land", "crane_trolley_water")
	# trolley_water = -Z, so we subtract.
	_trolley_z = clampf(
		_trolley_z - trolley_dir * trolley_speed_m * delta,
		trolley_min_z, trolley_max_z,
	)

	var hoist_dir := 0.0
	if Input.is_action_pressed("crane_hoist_up"):
		hoist_dir -= 1.0
	if Input.is_action_pressed("crane_hoist_down"):
		hoist_dir += 1.0
	_hoist_drop = clampf(
		_hoist_drop + hoist_dir * hoist_speed_m * delta,
		hoist_min_drop, hoist_max_drop,
	)


func _apply_kinematics() -> void:
	if _gantry_frame != null:
		_gantry_frame.position.x = _gantry_x_offset
	if _trolley != null:
		_trolley.position.z = _trolley_z
	if _hook != null:
		_hook.position = Vector3(0.0, -_hoist_drop, 0.0)
	if _cable != null and _hook != null:
		# Cable goes from trolley (Y=0) down to hook (Y=-hoist_drop).
		_cable.scale.y = _hoist_drop
		_cable.position = Vector3(0.0, -_hoist_drop * 0.5, 0.0)


# ── Carried pallet ────────────────────────────────────────────────────────────

func _update_carried_pallet() -> void:
	if _carried_pallet == null or _rigging == null:
		return
	# Fully attached: pallet rides under the hook.
	if _rigging.attached_count() >= CraneRigging.MAX_CHAINS:
		var hp := _hook.global_position
		_carried_pallet.global_position = Vector3(hp.x, hp.y - 1.4, hp.z)


# ── Pickup highlight ──────────────────────────────────────────────────────────

func _update_pickup_highlight() -> void:
	if _carried_pallet != null or _rigging == null or _hook == null:
		_clear_highlight()
		return
	if _hook.global_position.y > pickup_max_hook_height:
		_clear_highlight()
		return

	var nearest := _find_nearest_pallet()
	if nearest == _highlighted_pallet:
		return
	_clear_highlight()
	if nearest != null:
		_highlighted_pallet = nearest
		_set_pallet_highlight(_highlighted_pallet, true)


func _find_nearest_pallet() -> Node3D:
	var hp := _hook.global_position
	var best: Node3D = null
	var best_d2 := pickup_range_m * pickup_range_m
	for n in get_tree().get_nodes_in_group(PalletNode.GROUP):
		var pn := n as Node3D
		if pn == null:
			continue
		var dx := hp.x - pn.global_position.x
		var dz := hp.z - pn.global_position.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = pn
	return best


func _clear_highlight() -> void:
	if _highlighted_pallet != null and is_instance_valid(_highlighted_pallet):
		_set_pallet_highlight(_highlighted_pallet, false)
	_highlighted_pallet = null


func _set_pallet_highlight(pallet_node: Node3D, on: bool) -> void:
	for socket in _sockets_of(pallet_node):
		if socket.has_method("set_highlighted"):
			socket.set_highlighted(on)
		if on:
			if not socket.clicked.is_connected(_on_socket_clicked):
				socket.clicked.connect(_on_socket_clicked)
		else:
			if socket.clicked.is_connected(_on_socket_clicked):
				socket.clicked.disconnect(_on_socket_clicked)


func _sockets_of(pallet_node: Node3D) -> Array:
	var out := []
	if pallet_node == null:
		return out
	for c in pallet_node.get_children():
		if c is PalletAttachPoint:
			out.append(c)
	return out


func _on_socket_clicked(socket: Node) -> void:
	if _carried_pallet != null or _rigging == null or _highlighted_pallet == null:
		return
	if not _rigging.attach(socket as Node3D):
		return
	# When all four attached → start carrying.
	if _rigging.attached_count() >= CraneRigging.MAX_CHAINS:
		_begin_carry(_highlighted_pallet)


func _begin_carry(pallet_node: Node3D) -> void:
	_carried_pallet = pallet_node
	# Stop highlighting (sockets stay green via set_attached).
	if _highlighted_pallet != null:
		_set_pallet_highlight(_highlighted_pallet, false)
		_highlighted_pallet = null
	# Detach pallet from any cargo deck it sat on.
	if pallet_node.has_method("get") and pallet_node.get("pallet") != null:
		_detach_from_deck(pallet_node.get("pallet"))
	# Re-mark sockets attached so they stay green while carried.
	for socket in _sockets_of(pallet_node):
		if socket.has_method("set_attached"):
			socket.set_attached(true)


# ── Release ───────────────────────────────────────────────────────────────────

func _try_release() -> void:
	if _carried_pallet == null:
		return
	var hook_pos := _hook.global_position
	var pallet_res = _carried_pallet.get("pallet")

	# 1) Delivery zone match
	if pallet_res != null:
		for node in get_tree().get_nodes_in_group("cargo_delivery_zone"):
			if not node.has_method("accepts_pallet"):
				continue
			if not bool(node.call("accepts_pallet", pallet_res)):
				continue
			var n3 := node as Node3D
			if n3 == null:
				continue
			var dx := hook_pos.x - n3.global_position.x
			var dz := hook_pos.z - n3.global_position.z
			if dx * dx + dz * dz > 9.0:
				continue
			node.call("deliver_pallet", pallet_res)
			_consume_pallet()
			return

	# 2) Ship deck cell
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null or deck.is_full():
			continue
		if not deck.contains_world_point(hook_pos):
			continue
		if pallet_res != null:
			var cell := deck.add_pallet(pallet_res, hook_pos)
			if cell >= 0:
				_consume_pallet()
				return

	# 3) Drop in place
	_drop_in_place()


func _consume_pallet() -> void:
	if _rigging != null:
		_rigging.detach_all()
	if _carried_pallet != null and is_instance_valid(_carried_pallet):
		_carried_pallet.queue_free()
	_carried_pallet = null


func _drop_in_place() -> void:
	if _carried_pallet == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root != null and _carried_pallet.get_parent() != scene_root:
		_carried_pallet.reparent(scene_root)
	var hp := _hook.global_position
	_carried_pallet.global_position = Vector3(hp.x, 0.0, hp.z)
	if _carried_pallet.has_signal("released"):
		_carried_pallet.emit_signal("released", _carried_pallet)
	if _rigging != null:
		_rigging.detach_all()
	_carried_pallet = null


func _detach_from_deck(pallet_res) -> void:
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null:
			continue
		if deck.remove_pallet_by_resource(pallet_res) != null:
			return


# ── Board / exit ──────────────────────────────────────────────────────────────

func _nearest_boardable_player() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= board_range_m:
			return body
	return null


func _enter_crane() -> void:
	_player = _nearest_boardable_player()
	if _player == null:
		return
	_occupied = true
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO
	if _camera != null:
		_camera.set_enabled(true)
	get_viewport().physics_object_picking = true
	if _prompt != null:
		_prompt.visible = false
	if _hud != null:
		_hud.visible = true
	player_boarded.emit()


func _exit_crane() -> void:
	_occupied = false
	if _carried_pallet != null:
		_drop_in_place()
	_clear_highlight()
	if _camera != null:
		_camera.set_enabled(false)
	if _player != null:
		var pcam := _player.get_node_or_null("Camera3D") as Camera3D
		if pcam != null:
			pcam.current = true
		_player.global_position = to_global(Vector3(_gantry_x_offset + 4.0, 0.0, 4.0))
		_player.velocity = Vector3.ZERO
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
		_player = null
	if _hud != null:
		_hud.visible = false
	player_exited.emit()


# ── UI ────────────────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if _prompt == null:
		return
	_prompt.visible = _nearest_boardable_player() != null


func _update_hud() -> void:
	if _hud == null:
		return
	var hint := ""
	if _carried_pallet != null:
		hint = "[Space] release pallet"
	else:
		var attached := 0 if _rigging == null else _rigging.attached_count()
		if attached > 0:
			hint = "Chains attached: %d / 4 — click remaining corners" % attached
		elif _highlighted_pallet != null:
			hint = "Click glowing pallet corners to attach chains"
		else:
			hint = "Lower hook (F) near a pallet to begin"
	_hud.text = "Gantry %+5.1f m   Trolley %+5.1f m   Hook drop %4.1f m\n%s\n[A/D] roll  [W/S] trolley  [R/F] hoist  [RMB] orbit  [scroll] zoom  [E/Esc] exit" % [
		_gantry_x_offset, _trolley_z, _hoist_drop, hint,
	]


# ── Input registration ────────────────────────────────────────────────────────

func _register_input_actions() -> void:
	var bindings := {
		"crane_gantry_left":  KEY_A,
		"crane_gantry_right": KEY_D,
		"crane_trolley_land": KEY_S,   # +Z = toward land
		"crane_trolley_water": KEY_W,  # -Z = toward water
		"crane_hoist_up":     KEY_R,
		"crane_hoist_down":   KEY_F,
		"crane_release":      KEY_SPACE,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(bindings[action])
		InputMap.action_add_event(action, ev)
