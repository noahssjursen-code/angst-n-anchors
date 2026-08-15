class_name HoldHatch
extends Node3D

## Interactable hatch on a `CatchHoldComponent`. Look at the hatch + F to work it.
##
## Deliberately the SAME MECHANISM as `BrickDoor`, not a second one (the project
## already had exactly one openable-thing pattern and this is it): a camera-ray
## onto an `Area3D` decides whether you are looking at the thing, a `CanvasLayer`
## prompt says which way it will go, and the intent is routed through
## `WorldStateBinding` when the vessel has a server identity so every client and
## every late joiner sees the same boards. Without an identity or a session it
## stays a plain local hatch — single-player, the shipyard preview, the showcase.
##
## What differs from a door, and why: a door DISABLES its leaf collider when it
## opens, because an open doorway is a hole a player walks through. This hatch
## moves its boards instead and every one of them keeps its collider, because an
## open hatch is not a hole a player goes through — see the argument in
## `catch_hold_component.gd`. Nothing here may disable a collision shape.

const GROUP := "hold_hatch"
const LAYER_WORLD := 1

@export var interact_range: float = 3.5
@export var prompt_open: String = "Press F — open hatch"
@export var prompt_close: String = "Press F — close hatch"

var _hold: CatchHoldComponent
var _boat: BoatBody
var _interact_area: Area3D
var _prompt_layer: CanvasLayer
var _prompt_label: Label
var _binding: WorldStateBinding


func configure(hold: CatchHoldComponent, boat: BoatBody) -> void:
	_hold = hold
	_boat = boat


func _ready() -> void:
	add_to_group(GROUP)
	if _hold == null:
		_hold = get_parent() as CatchHoldComponent
	if _hold == null:
		push_warning("HoldHatch: no CatchHoldComponent to work")
		return
	_ensure_prompt_ui()
	_ensure_interact_area()
	_ensure_network_binding()


func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not _can_interact():
		return
	toggle()
	get_viewport().set_input_as_handled()


func toggle() -> void:
	if _hold == null:
		return
	if _binding == null:
		_ensure_network_binding()
	if _binding != null and WorldGateway.is_ready():
		_binding.request("close" if _hold.is_hatch_open() else "open", {
			"open": not _hold.is_hatch_open(),
		})
		return
	_hold.set_hatch_open(not _hold.is_hatch_open())


func is_open() -> bool:
	return _hold != null and _hold.is_hatch_open()


## Deterministic shared identity — identical on every client that fits out this
## vessel. Durable server vessel id + the hold's own id, which `DeckFitout`
## already makes unique per hold for the mass ledger's sake.
func _hatch_entity_id() -> String:
	if _hold == null:
		return ""
	if _boat == null or not is_instance_valid(_boat):
		return ""
	var vid := str(_boat.get_meta("server_vessel_id", "")).strip_edges()
	if vid.is_empty():
		return "" ## unregistered vessel — stays local-only
	return "hatch:%s:%s" % [vid, _hold.get_state().hold_id]


func _ensure_network_binding() -> void:
	if _binding != null:
		return
	var entity_id := _hatch_entity_id()
	if entity_id.is_empty():
		return
	_binding = WorldStateBinding.new()
	_binding.name = "HatchStateBinding"
	_binding.entity_id = entity_id
	_binding.entity_kind = "hold_hatch"
	add_child(_binding)
	_binding.authoritative_state_changed.connect(_on_authoritative_hatch_state)


func _on_authoritative_hatch_state(
	state: Dictionary, _action: String, _event: Dictionary
) -> void:
	if _hold == null:
		return
	_hold.set_hatch_open(bool(state.get("open", false)))


func _can_interact() -> bool:
	if _hold == null or _interact_area == null or not is_inside_tree():
		return false
	var player := _nearest_player_in_range()
	if player == null:
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * interact_range
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	if (hit.get("collider") as Area3D) != _interact_area:
		return false
	## …and nothing SOLID stands in front of it. Same second query `BrickDoor`
	## makes, and for the same reason: the area alone would let a player work the
	## hatch through the deckhouse wall. The hold's own boards do not count as in
	## the way — they are what the area is wrapped around — so a body hit inside
	## the hatch's own footprint is treated as this hatch, exactly as a door
	## treats its own closed leaf.
	var body_q := PhysicsRayQueryParameters3D.create(from, to)
	body_q.exclude = [player.get_rid()]
	body_q.collide_with_areas = false
	body_q.collide_with_bodies = true
	var body_hit := space.intersect_ray(body_q)
	if body_hit.is_empty():
		return true
	var area_dist := from.distance_to(hit.position as Vector3)
	var body_dist := from.distance_to(body_hit.position as Vector3)
	if body_dist + 0.05 >= area_dist:
		return true
	return _is_over_the_hatch(body_hit.position as Vector3)


func _is_over_the_hatch(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	var rect := _hold.hatch_aperture_m().grow(CatchHoldComponent.COAMING_TO_LINER_M)
	return rect.has_point(Vector2(local.x, local.z))


func _nearest_player_in_range() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body == null:
			continue
		if global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null


## A flat volume standing just above the boards, the size of the coaming's clear
## opening. Above them on purpose: the boards are solid in BOTH states, so an
## area buried among them would lose the ray to whichever board is nearest, and
## the prompt would flicker with where the player's crosshair fell.
func _ensure_interact_area() -> void:
	var opening := _hold.hatch_aperture_m()
	_interact_area = Area3D.new()
	_interact_area.name = "HatchInteractArea"
	_interact_area.collision_layer = LAYER_WORLD
	_interact_area.collision_mask = 0
	_interact_area.monitoring = false
	_interact_area.monitorable = true
	_interact_area.position = Vector3(
		0.0, CatchHoldComponent.COAMING_HEIGHT_M + 0.25, 0.0
	)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(opening.size.x, 0.4), 0.5, maxf(opening.size.y, 0.4))
	col.shape = box
	_interact_area.add_child(col)
	add_child(_interact_area)


func _ensure_prompt_ui() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "HatchPromptLayer"
	_prompt_layer.layer = 20
	add_child(_prompt_layer)
	_prompt_label = Label.new()
	_prompt_label.visible = false
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -220.0
	_prompt_label.offset_right = 220.0
	_prompt_label.offset_top = -148.0
	_prompt_label.offset_bottom = -108.0
	_prompt_label.add_theme_color_override("font_color", BrandTokens.BRASS)
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	_prompt_label.add_theme_constant_override("shadow_as_outline", 1)
	_prompt_layer.add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	var show := _can_interact()
	_prompt_label.visible = show
	if show:
		_prompt_label.text = prompt_close if is_open() else prompt_open
