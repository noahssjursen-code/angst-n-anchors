class_name ImportedDraftVessel
extends CatalogHullVessel

## Shared imported-model assembly for editor playtests, owned ships and replicas.
var draft: Dictionary
var part_roots: Array[Node3D] = []
var moving_colliders: Array[Dictionary] = []
var assembler := ImportedShipPartsEditor.new()
var engine_visual: Node3D
var engine_coupling: Node3D

func configure(snapshot: Dictionary) -> void:
	draft = snapshot.duplicate(true)
	name = "PlaytestBoat"
	mesh_data_path = ""
	model_data_path = ""
	automatic_physics_lod = false
	var hull_id := str(snapshot.get("hull", "trawler_hull_14m"))
	assert(ImportedHullCatalog.has(hull_id))
	_hull_id = hull_id
	var platform: Dictionary = ImportedHullCatalog.ENTRIES[hull_id]
	physics_profile = CatalogHullVessel.make_physics_profile(platform)
	MarineEngineCatalog.apply(physics_profile,hull_id,str(snapshot.get("engine_preset","")))
	physics_profile.roll_gyradius_fraction = .40
	physics_profile.pitch_gyradius_fraction = .32
	physics_profile.heave_damping_ratio = 1.0
	physics_profile.reverse_multiplier = 0.65
	physics_profile.harbour_drag_rate = 0.055
	physics_profile.astern_drag_multiplier = 3.0
	# Explicit hydrodynamics owns resistance. Godot's default 0.1/s plus the
	# inherited 0.05/s damping otherwise consumes ~134 kN on the 420 t coaster
	# at only 4.1 knots, despite its measured water drag being merely ~2.3 kN.
	linear_damp_coeff = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	# Game hull-form tuning: soft displacement-speed knees, never speed caps.
	physics_profile.wave_making_peak_coeff = {"trawler_hull_14m":.011,"hull_24x8":.007,"hull_32x10":.0065}[hull_id]
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
	_add_systems(physics_profile, hull_stations, length_m, depth_m, displacement_t)
	_add_mooring_fittings(hull_id, float(ImportedHullCatalog.outline(hull_id).deck_y))
	_assemble_parts()
	var doors := preload("res://scripts/ship/imported_door_interaction.gd").new()
	doors.name = "DoorInteraction"
	add_child(doors)
	(hull.get_node("DriveGear") as ShipDriveVisual).bind_local(self)
	_install_engine()
	var camera := get_node("BoatCamera") as BoatCamera
	camera.follow_distance = length_m * 1.36
	camera.follow_height = length_m * .64
	camera.min_distance = 4.0
	camera.look_height_offset = 3.5
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

func deck_grid() -> DeckGrid:
	return ImportedHullCatalog.make_grid(_hull_id)

func _install_engine() -> void:
	if is_instance_valid(engine_visual):
		remove_child(engine_visual)
		engine_visual.queue_free()
	var spec := MarineEngineCatalog.resolve(_hull_id,str(draft.get("engine_preset","")))
	engine_visual = MarineEngineCatalog.visual(_hull_id,str(spec.id))
	engine_visual.name = "InstalledEngine"
	for mesh in engine_visual.find_children("*","MeshInstance3D",true,false): mesh.set_meta("walk_detail_visual",true)
	engine_visual.position = MarineEngineCatalog.MOUNTS[_hull_id]
	add_child(engine_visual)
	engine_coupling = engine_visual.find_child("CouplingRotor",true,false)
	(get_node("HullVisual/DriveGear") as ShipDriveVisual).max_rpm = float(spec.shaft_rpm)

func _process(delta: float) -> void:
	if not is_instance_valid(engine_coupling): return
	var gear := get_node("HullVisual/DriveGear") as ShipDriveVisual
	engine_coupling.rotation.z = wrapf(engine_coupling.rotation.z+gear.signed_rpm*TAU/60.0*delta,-PI,PI)

func apply_brick_layout(layout: Dictionary) -> void:
	if not ImportedVesselLayout.valid(layout, _hull_id): return
	if draft == layout: return
	# Replica hydration replaces fit-out only; hull, physics and identity survive.
	if layout.get("engine_preset","") != draft.get("engine_preset",""):
		var base := CatalogHullVessel.make_physics_profile(ImportedHullCatalog.ENTRIES[_hull_id])
		MarineEngineCatalog.apply(base,_hull_id,str(layout.get("engine_preset","")))
		for field in ["design_displacement_t","engine_mass_kg","engine_position","shaft_power_kw","bollard_thrust_n","fuel_burn_l_per_sec_full","hull_center_of_mass"]:
			physics_profile.set(field,base.get(field))
		var prop := get_node("PropulsionComponent") as PropulsionComponent
		prop.shaft_power_kw = base.shaft_power_kw
		prop.max_thrust = base.bollard_thrust_n
		prop.fuel_burn_l_per_sec_full = base.fuel_burn_l_per_sec_full
		_refresh_mass()
	if is_instance_valid(_walk_deck):
		_walk_deck.collision_layer = 0
		_walk_deck.queue_free()
		_walk_deck = null
	for part in part_roots: part.free()
	part_roots.clear()
	moving_colliders.clear()
	assembler.records.clear()
	var posts := get_node_or_null("RailPosts")
	if posts != null: posts.free()
	draft = layout.duplicate(true)
	_install_engine()
	ModelPaint.apply(get_node("HullVisual"), draft.get("hull_colors", {}))
	_assemble_parts()
	if is_inside_tree(): call_deferred("_ensure_walk_deck")

func _assemble_parts() -> void:
	for record: Dictionary in draft.get("parts", []):
		assembler.records[ImportedShipPartsEditor.slot_key(record)] = record
	for record: Dictionary in assembler.records.values():
		var part := assembler.create_part(record)
		part.set_meta("asset_id", record["asset_id"])
		add_child(part)
		part_roots.append(part)
	var posts := Node3D.new()
	posts.name = "RailPosts"
	add_child(posts)
	for record in assembler.rail_joints(): posts.add_child(assembler.create_part(record))
	_configure_bulk_holds()
	_configure_cargo_pads()
	for part in part_roots:
		var state := part.get_node_or_null("PartState") as ShipPartState
		var controller := get_node_or_null("BoatController")
		if state != null and controller != null and (not part.find_children("WheelPivot*", "Node3D", true, false).is_empty() or not part.find_children("ThrottlePivot*", "Node3D", true, false).is_empty()):
			state.bind_local_helm(controller)
		_add_interactions(part, state)

func _configure_cargo_pads() -> void:
	if draft.get("hull") != "hull_24x8": return
	for part in part_roots:
		if part.get_meta("asset_id") in ["bulk_divider_5m", "hatch_cover_5x4"]: return
	for part in part_roots:
		var iso: bool = part.get_meta("asset_id") == "container_bed_20ft"
		if not iso and part.get_meta("asset_id") != "cargo_securing_bed_4m": continue
		if not part.basis.is_equal_approx(Basis.IDENTITY): continue
		if iso:
			if not (part.position.is_equal_approx(Vector3(-1.25,3.6,0)) or part.position.is_equal_approx(Vector3(1.25,3.6,0))): continue
			var supported := false
			for deck in part_roots:
				if deck.get_meta("asset_id") == "cargo_deck_5x8" and deck.position.is_equal_approx(Vector3(0,3.6,0)) and deck.basis.is_equal_approx(Basis.IDENTITY): supported = true
			if not supported: continue
		else:
			if not (part.position.is_equal_approx(Vector3(0,1.6,-2)) or part.position.is_equal_approx(Vector3(0,1.6,2))): continue
			var sealed := false
			for deck in part_roots:
				if deck.get_meta("asset_id") == "cargo_deck_5x8": sealed = true
			if sealed: continue
		# Mixing old and ISO beds would overlap inventory in the same hold.
		var mixed := false
		for other in part_roots:
			if other.get_meta("asset_id") == ("cargo_securing_bed_4m" if iso else "container_bed_20ft"): mixed = true
		if mixed: continue
		var socket := part.find_child("CargoDatum", true, false) as Node3D
		assert(socket != null)
		var pad := ImportedCargoPad.new()
		pad.name = "CargoPad"
		pad.deck_width_m = 2.5 if iso else 4.0
		pad.deck_length_m = 6.5 if iso else 4.0
		pad.cell_size_m = .5 if iso else 1.0
		pad.container_footprint = Vector2i(5,13) if iso else Vector2i(4,4)
		pad.transform = part.transform.affine_inverse() * _relative_transform(socket)
		part.add_child(pad)


func _add_mooring_fittings(hull_id: String, deck_y: float) -> void:
	# Explicit inboard positions: the former length/beam fractions put bow cleats
	# outside the tapered deck. These are regenerated utilities, not draft records.
	var root:=Node3D.new();root.name="MooringFittings";add_child(root)
	var config: Dictionary = ImportedHullCatalog.ENTRIES[hull_id]
	var inset_x: float = config.mooring_inset
	var stations: Array = config.mooring_stations
	for side in [-1,1]:
		for index in 2:
			var point:=MooringPoint.new()
			point.name=("Port" if side<0 else "Starboard")+("Bow" if index==0 else "Stern")
			point.side="port" if side<0 else "starboard"
			point.station="bow" if index==0 else "stern"
			point.position=Vector3(side*inset_x,deck_y,stations[index])
			point.bollard_scale=.85
			root.add_child(point)
			var guide: Node3D = (load("res://resources/models/parts/port_kit/deck_roller_fairlead.glb") as PackedScene).instantiate()
			guide.name=point.name+"Fairlead"
			SurfaceMaterialLibrary.apply(guide)
			guide.position=Vector3(side*float(config.mooring_guide),deck_y,stations[index])
			root.add_child(guide)
			point.rope_lead=guide.find_child("RopeLead",true,false) as Node3D
			assert(point.rope_lead != null)

func _configure_bulk_holds() -> void:
	if draft.get("hull") == "hull_32x10":
		_configure_coaster_hold()
		return
	if draft.get("hull") != "hull_24x8": return
	# The load deck closes the former hold opening; it cannot also expose
	# accessible bulk storage underneath its solid structural plate.
	for cover in part_roots:
		if cover.get_meta("asset_id") == "cargo_deck_5x8": return
	for part in part_roots:
		if part.get_meta("asset_id") != "bulk_divider_5m": continue
		# The divider must be at its authored seat; arbitrary imported records cannot
		# create cargo capacity elsewhere or place inventory above a solid deck.
		if not part.position.is_equal_approx(Vector3(0,3.6,0)) or not is_zero_approx(part.rotation.y): continue
		for station in [-2.05,2.05]:
			var socket := part.find_child("HoldForward" if station<0 else "HoldAft",true,false) as Node3D
			assert(socket != null, "Bulk divider requires authored hold sockets")
			var hold := ImportedBulkHold.new()
			hold.name = "ForwardBulkHold" if station<0 else "AftBulkHold"
			hold.boat = self
			hold.configure("bulk_forward" if station<0 else "bulk_aft",5.0,3.9,2.7,40)
			hold.transform = part.transform.affine_inverse() * _relative_transform(socket)
			for cover in part_roots:
				if cover.get_meta("asset_id") == "hatch_cover_5x4" and absf(cover.position.z-station)<.1 and absf(cover.position.x)<.1 and absf(cover.position.y-4.34)<.1:
					hold.cargo_accessible = false
			part.add_child(hold)

func _configure_coaster_hold() -> void:
	# One continuous space: four covers do not manufacture four compartments.
	# Its floor and lip come from the Blender sockets, not a second visual pit.
	for part in part_roots:
		if part.get_meta("asset_id") != "hold_coaming_6x12": continue
		if not part.position.is_equal_approx(Vector3(0,4.5,0)) or not part.basis.is_equal_approx(Basis.IDENTITY): continue
		var floor_socket := get_node("HullVisual").find_child("HoldCentre",true,false) as Node3D
		assert(floor_socket != null)
		var floor_y := _relative_transform(floor_socket).origin.y
		var lip := Vector3.ZERO
		for index in 4:
			var seat := part.find_child("CoverSeat%d" % index,true,false) as Node3D
			assert(seat != null)
			lip += _relative_transform(seat).origin * .25
		var hold := ImportedBulkHold.new()
		hold.name = "MainBulkHold"
		hold.boat = self
		# Provisional game load limit; geometric volume is not safe deadweight.
		hold.design_capacity_t = 120.0
		hold.configure("bulk_main",6.0,12.0,lip.y-floor_y,hold.design_capacity_t)
		hold.position = part.transform.affine_inverse() * lip
		for cover in part_roots:
			var entry := BrickCatalog.get_entry(str(cover.get_meta("asset_id")))
			if entry.get("style","") != "cargo_hatch": continue
			# Conservatively close this undivided hold while any lift-off cover
			# overlaps its opening, including a shifted/rotated authoring record.
			var bounds := cover.transform * BrickCatalog.visual_bounds(cover)
			if bounds.intersects(AABB(Vector3(-3,lip.y-.25,-6),Vector3(6,.75,12))):
				hold.cargo_accessible = false
		part.add_child(hold)
		return # Duplicate authoring records cannot duplicate hull capacity.

func _add_interactions(part: Node3D, state: ShipPartState) -> void:
	var style := str(BrickCatalog.get_entry(str(part.get_meta("asset_id", ""))).get("style", ""))
	if style == "winch":
		var fishing := FishingSystem.new()
		fishing.name = "FishingSystem"
		fishing.anchored_to_brick = true
		fishing.authored_winch = part
		var nearest:=INF
		for candidate in part_roots:
			if candidate.get_meta("asset_id","")!="trawl_gantry_4m":continue
			if candidate.has_meta("trawl_rig_owner"):continue
			var distance:=part.position.distance_to(candidate.position)
			if distance<nearest and distance<8:
				nearest=distance;fishing.authored_gantry=candidate
		if fishing.authored_gantry!=null:fishing.authored_gantry.set_meta("trawl_rig_owner",part)
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
		if mesh.has_meta("bulk_fill_visual"): continue
		if mesh.has_meta("fishing_rig_visual"): continue
		# Authored tread pans carry the player; millimetre grip ribs are surface detail.
		if mesh.has_meta("walk_detail_visual"): continue
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
		if mesh.has_meta("fishing_stow_visual"):
			collision.disabled=not mesh.get_meta("fishing_stowed",false)
			moving_colliders.append({"mesh":mesh,"collision":collision,"fishing_stow":true})
			continue
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
	_sync_moving_part_colliders()

func _sync_moving_part_colliders() -> void:
	for item in moving_colliders:
		if item.get("fishing_stow",false):
			item["collision"].disabled=not item["mesh"].get_meta("fishing_stowed",false)
			if item["collision"].disabled:continue
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
