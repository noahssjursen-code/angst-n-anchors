@tool
class_name Crane
extends Node3D

## Port quay crane — slew, trolley, hoist, grab/release.
## PortDock._crane_general() positions and instantiates this at runtime.
## No .tscn required; entire geometry built procedurally in _build().
##
## Controls (active only while operator is seated):
##   A / D      — slew left / right
##   W / S      — trolley out (extend) / in (retract)
##   Space      — hoist up
##   Ctrl       — hoist down
##   E          — grab pallet / release pallet
##   Escape / E — exit crane (while not holding a pallet)

signal player_boarded
signal player_exited

const C_CRANE   := Color(0.85, 0.72, 0.20)
const C_TROLLEY := Color(0.60, 0.55, 0.15)
const C_CABLE   := Color(0.22, 0.22, 0.22)
const C_HOOK    := Color(0.25, 0.25, 0.28)

# ── Geometry ──────────────────────────────────────────────────────────────────

@export var tower_height:  float = 18.0
@export var boom_reach:    float = 20.0   # outboard from tower centre
@export var boom_tail:     float = 10.0   # inboard counterweight arm
@export var tower_w:       float = 2.5

# ── Kinematics ────────────────────────────────────────────────────────────────

@export var slew_speed_deg:  float = 45.0
@export var trolley_speed_m: float = 5.0
@export var hoist_speed_m:   float = 4.0

# ── Limits ────────────────────────────────────────────────────────────────────

@export var hoist_min_m:  float = 0.5
@export var hoist_max_m:  float = 0.0    # set to tower_height - 2 in _ready()
@export var trolley_min_m: float = 1.5
@export var trolley_max_m: float = 0.0   # set to boom_reach - 0.8 in _ready()

## How close the hook tip must be (XZ plane) to a PalletNode to grab it.
@export var grab_radius_m: float = 1.8
## Hook must be this close to the ground (local Y from crane base) to grab.
@export var grab_max_height_m: float = 3.2

## Interaction range — how close the player must be to board.
@export var board_range_m: float = 7.0

# ── Runtime state ─────────────────────────────────────────────────────────────

var _slew:  float  = 90.0    # degrees; +90 = boom toward water (dock -Z)
var _troll: float  = 8.0     # m from tower centre along boom
var _hoist: float  = 10.0    # m below boom (hook height = tower_height - hoist)

var _grabbed: PalletNode = null
var _occupied: bool       = false
var _player: CharacterBody3D = null

# ── Node references ───────────────────────────────────────────────────────────

var _slew_arm: Node3D
var _trolley:  Node3D
var _hook:     Node3D
var _cable:    MeshInstance3D
var _crane_cam: Camera3D
var _ui:    CanvasLayer
var _prompt: Label
var _hud:    Label   # in-operator HUD showing slew/troll/hoist


func _ready() -> void:
	hoist_max_m   = tower_height - 2.0
	trolley_max_m = boom_reach   - 0.8
	_troll = clampf(_troll, trolley_min_m, trolley_max_m)
	_hoist = clampf(_hoist, hoist_min_m,   hoist_max_m)
	if not Engine.is_editor_hint():
		_register_input_actions()
	_build()


# ── Main loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _occupied:
		_update_prompt()
		return
	_read_crane_input(delta)
	_apply_positions()
	if _grabbed != null:
		# Pallet rides the hook tip
		_grabbed.global_position = _hook.global_position + Vector3(0.0, 0.25, 0.0)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _occupied:
		if event.is_action_pressed("ui_cancel"):
			_exit_crane()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact"):
			if _grabbed != null:
				_try_release()
			else:
				_try_grab()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _nearest_boardable_player() != null:
			_enter_crane()
			get_viewport().set_input_as_handled()


# ── Crane input ───────────────────────────────────────────────────────────────

func _read_crane_input(delta: float) -> void:
	# Slew: A left, D right (negated so A swings boom toward operator's left)
	var slew_dir := Input.get_axis("crane_slew_left", "crane_slew_right")
	_slew -= slew_dir * slew_speed_deg * delta

	# Trolley: W extend outboard, S retract inboard
	var troll_dir := Input.get_axis("crane_trolley_in", "crane_trolley_out")
	_troll = clampf(_troll + troll_dir * trolley_speed_m * delta, trolley_min_m, trolley_max_m)

	# Hoist: Space up, Ctrl down
	var hoist_dir := 0.0
	if Input.is_action_pressed("crane_hoist_up"):
		hoist_dir = -1.0   # more hoist = hook descends
	if Input.is_action_pressed("crane_hoist_down"):
		hoist_dir = 1.0
	_hoist = clampf(_hoist + hoist_dir * hoist_speed_m * delta, hoist_min_m, hoist_max_m)


func _apply_positions() -> void:
	_slew_arm.rotation_degrees.y = _slew
	_trolley.position.x          = _troll
	_hook.position.y             = -_hoist

	# Cable scales from trolley down to hook
	_cable.scale.y    = _hoist
	_cable.position.y = -_hoist * 0.5


# ── Grab / release ────────────────────────────────────────────────────────────

func _try_grab() -> void:
	if _hoist < (hoist_max_m - grab_max_height_m):
		return  # hook too high
	var hook_pos := _hook.global_position
	var best: PalletNode = null
	var best_d2  := grab_radius_m * grab_radius_m

	for node in get_tree().get_nodes_in_group(PalletNode.GROUP):
		var pn := node as PalletNode
		if pn == null or pn.pallet == null:
			continue
		var dx := hook_pos.x - pn.global_position.x
		var dz := hook_pos.z - pn.global_position.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best    = pn

	if best == null:
		return

	# If the pallet was on a deck, tell the deck to release it
	_detach_from_deck(best.pallet)
	best.grabbed.emit(best)
	_grabbed = best


func _try_release() -> void:
	if _grabbed == null:
		return
	var hook_pos := _hook.global_position

	# 1. Delivery zone — check all nodes in cargo_delivery_zone group
	for node in get_tree().get_nodes_in_group("cargo_delivery_zone"):
		if not node.has_method("accepts_pallet"):
			continue
		if not bool(node.call("accepts_pallet", _grabbed.pallet)):
			continue
		# Close enough (XZ distance ≤ 3 m)?
		var n3 := node as Node3D
		if n3 == null:
			continue
		var dx := hook_pos.x - n3.global_position.x
		var dz := hook_pos.z - n3.global_position.z
		if dx * dx + dz * dz > 9.0:   # 3 m radius
			continue
		node.call("deliver_pallet", _grabbed.pallet)
		_grabbed.queue_free()
		_grabbed = null
		return

	# 2. Ship deck cell
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null or deck.is_full():
			continue
		if not deck.contains_world_point(hook_pos):
			continue
		var cell := deck.add_pallet(_grabbed.pallet, hook_pos)
		if cell >= 0:
			_grabbed.queue_free()
			_grabbed = null
			return

	# 3. No valid target — drop the pallet in place
	_drop_in_place()


func _drop_in_place() -> void:
	if _grabbed == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root != null and _grabbed.get_parent() != scene_root:
		_grabbed.reparent(scene_root)
	_grabbed.global_position = _hook.global_position
	_grabbed.released.emit(_grabbed)
	_grabbed = null


func _detach_from_deck(pallet: Pallet) -> void:
	for node in get_tree().get_nodes_in_group(CargoDeckComponent.DECK_GROUP):
		var deck := node as CargoDeckComponent
		if deck == null:
			continue
		if deck.remove_pallet_by_resource(pallet) != null:
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
	_crane_cam.current = true
	if _prompt != null:
		_prompt.visible = false
	if _hud != null:
		_hud.visible = true
	player_boarded.emit()


func _exit_crane() -> void:
	_occupied = false
	if _grabbed != null:
		_drop_in_place()
	if _player != null:
		var pcam := _player.get_node_or_null("Camera3D") as Camera3D
		if pcam != null:
			pcam.current = true
		_player.global_position = to_global(Vector3(tower_w * 2.0 + 1.5, 0.0, 3.0))
		_player.velocity = Vector3.ZERO
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
		_player = null
	_crane_cam.current = false
	if _hud != null:
		_hud.visible = false
	player_exited.emit()


# ── Prompt / HUD ──────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if _prompt == null:
		return
	_prompt.visible = _nearest_boardable_player() != null


func _update_hud() -> void:
	if _hud == null:
		return
	var action := ""
	if _grabbed != null:
		action = "E: release pallet"
	elif _hoist >= (hoist_max_m - grab_max_height_m):
		action = "E: grab pallet"
	_hud.text = "Slew %.0f°  Trolley %.1f m  Hook %.1f m\n%s\nEsc: exit" % [
		_slew, _troll, tower_height - _hoist, action
	]


# ── Build geometry ────────────────────────────────────────────────────────────

func _build() -> void:
	_build_tower()
	_build_slew_arm()
	if not Engine.is_editor_hint():
		_build_camera()
		_build_ui()


func _build_tower() -> void:
	var body             := StaticBody3D.new()
	body.name            = "TowerBody"
	body.position        = Vector3(0.0, tower_height * 0.5, 0.0)
	var mi               := MeshInstance3D.new()
	var mesh             := BoxMesh.new()
	mesh.size            = Vector3(tower_w, tower_height, tower_w)
	mi.mesh              = mesh
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = C_CRANE
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	body.add_child(mi)
	var col  := CollisionShape3D.new()
	var box  := BoxShape3D.new()
	box.size = Vector3(tower_w, tower_height, tower_w)
	col.shape = box
	body.add_child(col)
	add_child(body)

	# Cab platform on the +Z face of tower, for player to stand near
	_vis_box(Vector3(tower_w + 1.2, 0.25, 2.0),
		Vector3(0.0, 2.5, tower_w * 0.5 + 1.0), C_CRANE.darkened(0.2), "CabPlatform")


func _build_slew_arm() -> void:
	_slew_arm          = Node3D.new()
	_slew_arm.name     = "SlewArm"
	_slew_arm.position = Vector3(0.0, tower_height, 0.0)
	add_child(_slew_arm)

	# Boom: extends +X (outboard) and -X (counterweight)
	var boom_len := boom_reach + boom_tail
	var boom_cx  := (boom_reach - boom_tail) * 0.5
	_vis_box_in(_slew_arm, Vector3(boom_len, 1.6, 1.6), Vector3(boom_cx, 0.0, 0.0), C_CRANE, "Boom")
	# Counterweight block
	_vis_box_in(_slew_arm, Vector3(2.8, 2.8, 2.8), Vector3(-boom_tail + 1.4, -0.9, 0.0),
		Color(0.50, 0.50, 0.52), "Counterweight")

	# King post (connects tower top to boom)
	_vis_box_in(_slew_arm, Vector3(0.5, 2.0, 0.5), Vector3(0.0, 1.0, 0.0), C_CRANE.lightened(0.1), "KingPost")

	# Trolley
	_trolley          = Node3D.new()
	_trolley.name     = "Trolley"
	_trolley.position = Vector3(_troll, 0.0, 0.0)
	_slew_arm.add_child(_trolley)

	_vis_box_in(_trolley, Vector3(1.1, 0.7, 1.1), Vector3.ZERO, C_TROLLEY, "TrolleyMesh")

	# Cable (scaled in _apply_positions)
	var cable_mesh       := BoxMesh.new()
	cable_mesh.size      = Vector3(0.07, 1.0, 0.07)
	_cable               = MeshInstance3D.new()
	_cable.name          = "Cable"
	_cable.mesh          = cable_mesh
	_cable.cast_shadow   = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat             := StandardMaterial3D.new()
	cmat.albedo_color    = C_CABLE
	cmat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cable.material_override = cmat
	_trolley.add_child(_cable)

	# Hook block
	_hook          = Node3D.new()
	_hook.name     = "Hook"
	_hook.position = Vector3(0.0, -_hoist, 0.0)
	_trolley.add_child(_hook)
	_vis_box_in(_hook, Vector3(0.55, 0.4, 0.55), Vector3.ZERO, C_HOOK, "HookMesh")

	_apply_positions()


func _build_camera() -> void:
	# Camera is a child of SlewArm so it rotates with slew and always looks
	# along the boom direction. Positioned just above the pivot, looking
	# outboard (+X in SlewArm space) and steeply down — gives a clear
	# top-down-ish view of the hook and the landing zone below it.
	_crane_cam                  = Camera3D.new()
	_crane_cam.name             = "CraneCam"
	_crane_cam.position         = Vector3(boom_reach * 0.25, 4.0, 0.0)
	_crane_cam.rotation_degrees = Vector3(-55.0, -90.0, 0.0)
	_crane_cam.current          = false
	_slew_arm.add_child(_crane_cam)


func _build_ui() -> void:
	_ui      = CanvasLayer.new()
	_ui.name = "CraneUI"
	add_child(_ui)

	_prompt                        = Label.new()
	_prompt.name                   = "CranePrompt"
	_prompt.text                   = "Press E to operate crane"
	_prompt.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible                = false
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left   = -220.0
	_prompt.offset_right  =  220.0
	_prompt.offset_top    =  -92.0
	_prompt.offset_bottom =  -48.0
	_ui.add_child(_prompt)

	_hud                       = Label.new()
	_hud.name                  = "CraneHud"
	_hud.visible               = false
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.offset_left  = 16.0
	_hud.offset_top   = 16.0
	_hud.offset_right = 420.0
	_hud.offset_bottom = 100.0
	_ui.add_child(_hud)


# ── Input action registration ─────────────────────────────────────────────────

func _register_input_actions() -> void:
	var bindings: Dictionary = {
		"crane_slew_left":    KEY_A,
		"crane_slew_right":   KEY_D,
		"crane_trolley_in":   KEY_S,
		"crane_trolley_out":  KEY_W,
		"crane_hoist_up":     KEY_SPACE,
		"crane_hoist_down":   KEY_CTRL,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev                  := InputEventKey.new()
		ev.physical_keycode     = int(bindings[action])
		InputMap.action_add_event(action, ev)


# ── Mesh helpers ──────────────────────────────────────────────────────────────

func _vis_box(size: Vector3, pos: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	return _vis_box_in(self, size, pos, color, node_name)


func _vis_box_in(parent: Node3D, size: Vector3, pos: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	var mi               := MeshInstance3D.new()
	mi.name              = node_name
	var mesh             := BoxMesh.new()
	mesh.size            = size
	mi.mesh              = mesh
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat              := StandardMaterial3D.new()
	mat.albedo_color     = color
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position          = pos
	parent.add_child(mi)
	return mi
