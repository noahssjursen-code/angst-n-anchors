extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B: it names
## WaveSurface / VesselSpawn / BoatBody, all of which reach autoloads.
##
## Measures the small hull the way the brief demands — in the world, not in a
## dictionary:
##   1. settle it on flat water and read the ACTUAL waterline against the draft
##      it declares;
##   2. the buoyancy volume below that waterline against the declared tonnage;
##   3. a 1.8 m player capsule against the real PhysicsServer3D body that
##      VesselSpawn -> apply_plan -> _ensure_walk_deck actually built;
##   4. rudder + thrust from rest, reporting speed, heel and pitch.
##
## HULL_ID is read from the command line so the same probe can be pointed at the
## 28 m hull as a control: `-- hull_28x10`.

const SETTLE_FRAMES := 600
const DRIVE_FRAMES := 420
## scenes/shared/player.tscn: CapsuleShape3D radius 0.35, height 1.8.
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.8

var _hull_id := "hull_15x5"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("hull_"):
			_hull_id = str(arg)
	print("=== PROBE hull_id=%s ===" % _hull_id)
	WaveSurface.fft_system = null
	WaveSurface.clear_sample_cache()
	await _measure_float()
	await _measure_stand()
	await _measure_drive()
	print("=== PROBE DONE ===")
	get_tree().quit(0)


func _entry() -> Dictionary:
	return HullRegistry.get_by_id(_hull_id)


# ── 1 + 2 · floats at the draft it declares, at the tonnage it declares ──────

func _measure_float() -> void:
	var entry := _entry()
	var boat := HullRegistry.build_hull(_hull_id)
	if boat == null:
		print("FLOAT: build_hull returned null")
		return
	boat.name = "FloatSubject"
	boat.automatic_physics_lod = false
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	var stations: HullStations = boat.hull_stations
	var declared_draft := boat.draft_m
	var declared_disp := boat.displacement_t

	print("DECL : loa=%.2f beam=%.2f depth=%.2f draft=%.3f disp=%.2f t class=%s power=%.1f kW" % [
		boat.length_m, boat.beam_m, boat.depth_m, declared_draft, declared_disp,
		ShipClass.display_name(int(entry.get("ship_class", 1)) as ShipClass.Type),
		float(entry.get("default_shaft_power_kw", 0.0)),
	])
	print("PROF : validate()=%s  stations keel_y=%.3f deck_y=%.3f fullness=%.4f sheer f/a=%.3f/%.3f" % [
		"CLEAN" if boat.physics_profile.validate().is_empty() else str(boat.physics_profile.validate()),
		stations.keel_y, stations.deck_y, stations.section_fullness_exponent,
		stations.sheer_forward_m, stations.sheer_aft_m,
	])
	print("MASS : rigid body mass=%.1f kg (=%.3f t) vs declared %.3f t" % [
		boat.mass, boat.mass / 1000.0, declared_disp,
	])

	var buoy := boat.get_node_or_null("StripBuoyancyComponent") as StripBuoyancyComponent
	var settled_y := 0.0
	for frame in range(SETTLE_FRAMES):
		await get_tree().physics_frame
		if frame == SETTLE_FRAMES - 1:
			settled_y = boat.global_position.y
	var actual_draft := WaveSurface.WATER_LEVEL - (settled_y + stations.keel_y)
	print("FLOAT: settled y=%.4f  actual draft=%.4f m  declared %.4f m  delta=%+.4f m (%.2f%%)" % [
		settled_y, actual_draft, declared_draft, actual_draft - declared_draft,
		(actual_draft - declared_draft) / declared_draft * 100.0,
	])
	print("TRIM : pitch=%.4f deg  heel=%.4f deg  |v|=%.4f m/s  sleeping=%s" % [
		rad_to_deg(boat.rotation.x), rad_to_deg(boat.rotation.z),
		boat.linear_velocity.length(), str(boat.sleeping),
	])

	var vol_at_actual := stations.volume_below(actual_draft)
	var vol_at_design := stations.volume_below(declared_draft)
	var rho := boat.physics_profile.water_density
	print("DISP : volume_below(actual)=%.3f m3 -> %.3f t   volume_below(design)=%.3f m3 -> %.3f t   declared %.3f t" % [
		vol_at_actual, vol_at_actual * rho / 1000.0,
		vol_at_design, vol_at_design * rho / 1000.0,
		declared_disp,
	])
	print("DISP : design-volume error %.4f%%   live buoyancy submerged=%.3f m3 lift=%.1f N (weight %.1f N)" % [
		absf(vol_at_design * rho / 1000.0 - declared_disp) / declared_disp * 100.0,
		buoy.submerged_volume_m3 if buoy != null else -1.0,
		buoy.total_lift_n if buoy != null else -1.0,
		boat.mass * 9.81,
	])
	var envelope_t := boat.length_m * boat.beam_m * declared_draft * rho / 1000.0
	print("FORM : Cb=%.4f (envelope %.2f t)  freeboard=%.3f m  L/B=%.3f" % [
		declared_disp / envelope_t, envelope_t,
		boat.depth_m - declared_draft, boat.length_m / boat.beam_m,
	])
	boat.free()
	await get_tree().process_frame


# ── 3 · a player can stand on it, through PhysicsServer3D ───────────────────

func _measure_stand() -> void:
	var boat: BoatBody = VesselSpawn.instantiate(_hull_id, {}, "")
	if boat == null:
		print("STAND: VesselSpawn.instantiate returned null")
		return
	boat.name = "StandSubject"
	boat.automatic_physics_lod = false
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk == null:
		print("STAND: no WalkDeck body")
		boat.free()
		return
	var shape_count := PhysicsServer3D.body_get_shape_count(walk.get_rid())
	print("STAND: WalkDeck rid shapes=%d layer=%d" % [shape_count, walk.collision_layer])

	var space := walk.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT

	var grid := HullRegistry.make_grid(_hull_id)
	var deck_y_world := boat.to_global(Vector3(0.0, grid.deck_y, 0.0)).y
	print("STAND: deck grid %dx%d cells, deck_y local=%.3f world=%.3f" % [
		grid.width, grid.length, grid.deck_y, deck_y_world,
	])

	## Sample points spread over the FULL cells of the deck, in boat-local x/z.
	var samples: Array[Vector3] = []
	for iz in [2, grid.length / 4, grid.length / 2, (grid.length * 3) / 4, grid.length - 3]:
		for ix in [1, grid.width / 2, grid.width - 2]:
			if grid.cell_shape(int(ix), int(iz)) != DeckGrid.CellShape.FULL:
				continue
			var c := grid.cell_center_local(Vector3i(int(ix), 0, int(iz)))
			samples.append(Vector3(c.x, 0.0, c.z))

	var landed := 0
	var started_inside := 0
	var fell_through := 0
	var drops := PackedFloat64Array()
	for s in samples:
		## Start the capsule's CENTRE 3 m above the deck — clear air, so
		## cast_motion cannot be answering "began inside something".
		var start := boat.to_global(Vector3(s.x, grid.deck_y + 3.0 + PLAYER_HEIGHT * 0.5, s.z))
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = capsule
		params.transform = Transform3D(Basis.IDENTITY, start)
		params.collision_mask = BoatBody.LAYER_BOAT_WALK
		params.collide_with_bodies = true
		params.collide_with_areas = false
		if not space.intersect_shape(params, 1).is_empty():
			started_inside += 1
			continue
		params.motion = Vector3(0.0, -6.0, 0.0)
		var hit := space.cast_motion(params)
		var travel := hit[0] * 6.0
		if hit[0] >= 0.999:
			fell_through += 1
			continue
		landed += 1
		var foot_y := start.y - travel - PLAYER_HEIGHT * 0.5
		drops.append(foot_y - deck_y_world)
	var mean := 0.0
	for d in drops:
		mean += d
	if drops.size() > 0:
		mean /= float(drops.size())
	print("STAND: %d samples · landed=%d fell_through=%d started_inside=%d · mean foot-above-deck_y=%+.4f m" % [
		samples.size(), landed, fell_through, started_inside, mean,
	])

	## Control that the query can say NO: the same drop 40 m off the port beam
	## must fall through, or the filter is answering about something else.
	var off := boat.to_global(Vector3(-40.0, grid.deck_y + 3.0 + PLAYER_HEIGHT * 0.5, 0.0))
	var op := PhysicsShapeQueryParameters3D.new()
	op.shape = capsule
	op.transform = Transform3D(Basis.IDENTITY, off)
	op.collision_mask = BoatBody.LAYER_BOAT_WALK
	op.motion = Vector3(0.0, -6.0, 0.0)
	print("STAND: open-water control fraction=%.3f (1.000 == nothing there, as it must be)" % space.cast_motion(op)[0])

	## And a standing pose on the surface the capsule actually LANDED on must NOT
	## be embedded in anything. `mean` is measured, not assumed: the walk slab's
	## top is above `grid.deck_y`, so a pose derived from the grid value alone
	## reports an overlap that is the instrument, not the hull (REALITY §8).
	var stand := boat.to_global(
		Vector3(0.0, grid.deck_y + mean + PLAYER_HEIGHT * 0.5 + 0.02, 0.0)
	)
	var sp := PhysicsShapeQueryParameters3D.new()
	sp.shape = capsule
	sp.transform = Transform3D(Basis.IDENTITY, stand)
	sp.collision_mask = BoatBody.LAYER_BOAT_WALK
	print("STAND: standing pose overlaps=%d (0 == the player fits above the deck)" % space.intersect_shape(sp, 4).size())

	boat.free()
	await get_tree().process_frame


# ── 4 · drivable: rudder and thrust without capsizing ───────────────────────

func _measure_drive() -> void:
	WaveSurface.clear_sample_cache()
	var boat := HullRegistry.build_hull(_hull_id)
	if boat == null:
		print("DRIVE: build_hull returned null")
		return
	boat.name = "DriveSubject"
	boat.automatic_physics_lod = false
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	var prop := boat.get_node_or_null("PropulsionComponent") as PropulsionComponent
	var rudder := boat.get_node_or_null("RudderComponent") as RudderComponent
	if prop == null or rudder == null:
		print("DRIVE: missing propulsion/rudder")
		boat.free()
		return
	var max_heel := 0.0
	var max_pitch := 0.0
	var straight_speed := 0.0
	var start_yaw := boat.rotation.y
	var helm := 0.0
	for frame in range(DRIVE_FRAMES):
		prop.throttle = -1.0 ## bow is −Z; this is full ahead
		rudder.rudder_input = helm
		await get_tree().physics_frame
		if frame == DRIVE_FRAMES / 2:
			straight_speed = absf(boat.linear_velocity.dot(-boat.global_transform.basis.z))
			helm = 1.0
			start_yaw = boat.rotation.y
		max_heel = maxf(max_heel, absf(rad_to_deg(boat.rotation.z)))
		max_pitch = maxf(max_pitch, absf(rad_to_deg(boat.rotation.x)))
	var end_speed := absf(boat.linear_velocity.dot(-boat.global_transform.basis.z))
	var yaw_delta := rad_to_deg(wrapf(boat.rotation.y - start_yaw, -PI, PI))
	print("DRIVE: straight speed after %.1f s = %.3f m/s (%.2f kn)" % [
		float(DRIVE_FRAMES / 2) / 60.0, straight_speed, straight_speed * 1.94384,
	])
	print("DRIVE: hard-over %.1f s -> yaw %+.2f deg, speed %.3f m/s (%.2f kn)" % [
		float(DRIVE_FRAMES / 2) / 60.0, yaw_delta, end_speed, end_speed * 1.94384,
	])
	print("DRIVE: max |heel| %.3f deg, max |pitch| %.3f deg, still upright=%s" % [
		max_heel, max_pitch, str(boat.global_transform.basis.y.y > 0.7),
	])
	var stations: HullStations = boat.hull_stations
	var draft_now := WaveSurface.WATER_LEVEL - (boat.global_position.y + stations.keel_y)
	print("DRIVE: draft while manoeuvring = %.4f m (design %.4f m)" % [draft_now, boat.draft_m])
	boat.free()
	await get_tree().process_frame
