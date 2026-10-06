extends Node

## Shared runtime interaction for imported vessels, including editor sea trials.
var boat: ImportedDraftVessel
var prompt: Label
var bindings: Dictionary = {}
var binding_scan := 0.0

func _ready() -> void:
	boat = get_parent() as ImportedDraftVessel
	var layer := CanvasLayer.new()
	add_child(layer)
	prompt = Label.new()
	layer.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -180
	prompt.offset_right = 180
	prompt.offset_top = -92
	prompt.offset_bottom = -48
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)

func _process(delta: float) -> void:
	# Identity can arrive after assembly. Bind all doors for remote replay too.
	binding_scan -= delta
	if binding_scan <= 0.0 and not str(boat.get_meta("server_vessel_id", "")).is_empty():
		binding_scan = 0.5
		for key in bindings.keys():
			if not is_instance_valid(bindings[key]): bindings.erase(key)
		for part in boat.part_roots:
			if BrickCatalog.get_entry(str(part.get_meta("asset_id", ""))).get("style", "") == "door":
				ensure_binding(part.get_node("PartState"))
	var player := local_player()
	var door := looked_at_door(player)
	prompt.text = "" if door == null else ("Press F to close door" if door.state.door_open else "Press F to open door")

func local_player() -> CharacterBody3D:
	var view := get_viewport().get_camera_3d()
	for candidate in get_tree().get_nodes_in_group("player"):
		if candidate is CharacterBody3D and view != null and candidate.is_ancestor_of(view):
			return candidate
	return null

func looked_at_door(player: CharacterBody3D) -> ShipPartState:
	if not is_instance_valid(player) or get_tree().paused or GameMenu._screen != GameMenu.Screen.NONE:
		return null
	if player.has_method("is_vehicle_occupied") and player.is_vehicle_occupied(): return null
	var view := get_viewport().get_camera_3d()
	if view == null: return null
	# World and other ships must occlude the target; ignore our broad hull proxy
	# only because the imported walking mesh is the precise collision surface.
	var ray := PhysicsRayQueryParameters3D.create(view.global_position, view.global_position-view.global_basis.z*3.0, 1 | BoatBody.LAYER_BOAT_WALK)
	ray.exclude = [player.get_rid(), boat.get_rid()]
	var hit := boat.get_world_3d().direct_space_state.intersect_ray(ray)
	return state_for_hit(hit)

func state_for_hit(hit: Dictionary) -> ShipPartState:
	if hit.is_empty(): return null
	var body := hit.collider as CollisionObject3D
	if not is_instance_valid(body): return null
	var shape := body.shape_owner_get_owner(body.shape_find_owner(hit.shape))
	for item in boat.moving_colliders:
		if item.collision != shape: continue
		var node: Node = item.mesh
		while node != null and node != boat:
			var state := node.get_node_or_null("PartState") as ShipPartState
			if state != null: return state
			node = node.get_parent()
	return null

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo(): return
	var player := local_player()
	var state := looked_at_door(player)
	if state == null: return
	interact(state, player.global_position)
	get_viewport().set_input_as_handled()

func ensure_binding(state: ShipPartState) -> WorldStateBinding:
	var key_id := state.get_instance_id()
	if bindings.has(key_id): return bindings[key_id]
	var vessel_id := str(boat.get_meta("server_vessel_id", ""))
	if vessel_id.is_empty(): return null
	var part := state.visual
	var key := "%s:%s:%s" % [part.get_meta("asset_id", ""), part.position, part.rotation_degrees.y]
	var binding := WorldStateBinding.new()
	binding.entity_id = "door:%s:imported:%s" % [vessel_id, key.sha256_text()]
	binding.entity_kind = "door"
	binding.authoritative_state_changed.connect(func(snapshot: Dictionary, _action: String, _event: Dictionary) -> void:
		if is_instance_valid(state):
			state.apply_snapshot({"door_open":bool(snapshot.get("open", false)), "door_swing":float(snapshot.get("swing", 1.0))}, state.revision+1))
	# Parent with the part so rehydrating the fitout releases its subscription.
	state.add_child(binding)
	bindings[key_id] = binding
	return binding

func interact(state: ShipPartState, actor_position: Vector3) -> void:
	var binding := ensure_binding(state)
	if binding == null:
		state.request_door_from(actor_position)
		return
	# Registered ships follow authority echoes; disconnected sessions never
	# silently mutate a multiplayer door locally.
	if not WorldGateway.is_ready(): return
	var swing := float(state.state.door_swing)
	if not bool(state.state.door_open) and state.current_door <= .001:
		var pivots := state.visual.find_children("DoorLeafPivot*", "Node3D", true, false)
		if not pivots.is_empty(): swing = 1.0 if pivots[0].to_local(actor_position).x >= 0 else -1.0
	var opened := not bool(state.state.door_open)
	binding.request("open" if opened else "close", {"open":opened,"swing":swing})
