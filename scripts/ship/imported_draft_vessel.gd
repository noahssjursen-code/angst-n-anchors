class_name ImportedDraftVessel
extends CatalogHullVessel

## Draft-only assembly. Reuses the normal vessel physics/components; never commissions it.
var draft: Dictionary
var part_roots: Array[Node3D] = []
var moving_colliders: Array[Dictionary] = []
var assembler := ImportedShipPartsEditor.new()

func configure(snapshot: Dictionary) -> void:
	draft = snapshot.duplicate(true)
	name = "PlaytestBoat"
	mesh_data_path = ""
	model_data_path = ""
	automatic_physics_lod = false
	var hull_id := str(snapshot.get("hull", "trawler_hull_14m"))
	assert(ImportedHullCatalog.has(hull_id))
	var platform: Dictionary = ImportedHullCatalog.ENTRIES[hull_id]
	physics_profile = CatalogHullVessel.make_physics_profile(platform)
	physics_profile.roll_gyradius_fraction = .40
	physics_profile.pitch_gyradius_fraction = .32
	physics_profile.heave_damping_ratio = 1.0
	angular_damp_coeff = .9
	process_physics_priority = -10
	length_m = platform.loa_m
	beam_m = platform.beam_m
	depth_m = platform.depth_m
	draft_m = platform.draft_m
	displacement_t = platform.displacement_t
	hull_size = Vector3(beam_m, depth_m, length_m)
	hull_center = Vector3(0, depth_m / 2, 0)
	hull_stations = physics_profile.make_stations()
	fuel_capacity_l = platform.fuel_l
	fuel_l = fuel_capacity_l
	var hull := ImportedHullCatalog.instantiate(hull_id)
	hull.name = "HullVisual"
	ModelPaint.apply(hull, snapshot.get("hull_colors", {}))
	add_child(hull)
	for record: Dictionary in snapshot.get("parts", []):
		assembler.records[assembler.slot_key(record)] = record
	for record: Dictionary in assembler.records.values():
		var part := assembler.create_part(record)
		part.set_meta("asset_id", record["asset_id"])
		add_child(part)
		part_roots.append(part)
	_add_systems(physics_profile, hull_stations, length_m, depth_m, displacement_t)
	(hull.get_node("DriveGear") as ShipDriveVisual).bind_local(self)
	var camera := get_node("BoatCamera") as BoatCamera
	camera.follow_distance = length_m * 1.36
	camera.follow_height = length_m * .64
	camera.min_distance = 4.0
	camera.look_height_offset = 3.5
	for part in part_roots:
		var state := part.get_node_or_null("PartState") as ShipPartState
		if state != null and (not part.find_children("WheelPivot*", "Node3D", true, false).is_empty() or not part.find_children("ThrottlePivot*", "Node3D", true, false).is_empty()):
			state.bind_local_helm(get_node("BoatController"))
		_add_interactions(part, state)
	# Dynamic hull uses a convex shape; walking uses the actual imported triangles below.
	var hull_points := PackedVector3Array()
	for mesh: MeshInstance3D in hull.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("stern_gear_visual"): continue
		var transform := _relative_transform(mesh)
		for point in assembler._deformed_faces(mesh):
			hull_points.append(transform * point)
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull_points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

func _add_interactions(part: Node3D, state: ShipPartState) -> void:
	var style := str(BrickCatalog.get_entry(str(part.get_meta("asset_id", ""))).get("style", ""))
	if style == "winch":
		var fishing := FishingSystem.new()
		fishing.name = "FishingSystem"
		fishing.anchored_to_brick = true
		fishing.authored_winch = part
		part.add_child(fishing)
	elif style == "catch_tank":
		var hold := CatchHoldComponent.new()
		hold.name = "CatchHold"
		hold.configure("tank_%d" % part_roots.find(part), 600.0)
		hold.authored_visual = part
		part.add_child(hold)
	if not part.find_children("WheelPivot*", "Node3D", true, false).is_empty():
		var eye := Node3D.new()
		eye.name = "HelmEye"
		eye.position = Vector3(0, .75, .7)
		part.add_child(eye)
		var helm := BridgeInteractable.new()
		helm.name = "HelmInteraction"
		helm.exit_height_offset = -.7
		part.add_child(helm)
	for socket: Node3D in part.find_children("SeatSocket*", "Node3D", true, false):
		var mount := Node3D.new()
		mount.name = "SeatInteractionMount"
		part.add_child(mount)
		mount.transform = part.transform.affine_inverse() * _relative_transform(socket)
		var eye := Node3D.new()
		eye.name = "HelmEye"
		eye.position.y = .75
		mount.add_child(eye)
		var seat := ImportedSeatInteractable.new()
		seat.name = "SeatInteraction"
		seat.drives_ship = BrickCatalog.get_entry(str(part.get_meta("asset_id", ""))).get("style", "") == "helm_chair"
		seat.prompt_text = "Press F to helm" if seat.drives_ship else "Press F to sit"
		seat.interaction_volume_size = Vector3(.55, .6, .55)
		seat.exit_height_offset = -.51
		seat.exit_deck_offset = Vector2(.65, .45)
		seat.state_driver = state
		mount.add_child(seat)

func _apply_pending_or_default_fitout() -> void:
	pass # Imported drafts must never be converted back into the retired brick fit-out.

func _walk_deck_local_origin() -> Vector3:
	return Vector3.ZERO

func _ensure_walk_hull_collider() -> void:
	pass # No rectangular proxy beyond the pointed deck edge.

func _ensure_walk_deck() -> void:
	if is_instance_valid(_walk_deck):
		return
	_walk_deck = AnimatableBody3D.new()
	_walk_deck.name = "WalkDeck"
	_walk_deck.sync_to_physics = false
	_walk_deck.collision_layer = LAYER_BOAT_WALK
	_walk_deck.collision_mask = LAYER_PLAYER
	_walk_deck.set_meta("_boat_owner", self)
	_walk_deck.set_meta("align_player_capsule", true)
	get_parent().add_child(_walk_deck)
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		# Underwater moving hardware is presentation, not walkable deck triangles.
		if mesh.has_meta("stern_gear_visual"): continue
		# Small hinges/lever handles are visual hardware, not doorway obstacles.
		# Keep the complete moving leaf, frame and header collidable.
		if str(mesh.name).begins_with("Door hinge") or str(mesh.name).begins_with("Lever handle"):
			continue
		var faces := assembler._deformed_faces(mesh)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = _relative_transform(mesh)
		_walk_deck.add_child(collision)
		# Door leaf transforms follow their authored hinge, including the collision.
		var parent := mesh.get_parent()
		while parent != self:
			if str(parent.name).begins_with("DoorLeafPivot"):
				moving_colliders.append({"mesh":mesh, "collision":collision})
				break
			parent = parent.get_parent()
	_sync_walk_deck_transform()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for item in moving_colliders:
		item["collision"].transform = _relative_transform(item["mesh"])

func _relative_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != self:
		if parent is Node3D:
			result = parent.transform * result
		parent = parent.get_parent()
	return result

func _exit_tree() -> void:
	super._exit_tree()
	assembler.free()
