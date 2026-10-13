class_name FishingVisualReplication
extends RefCounted
## Presentation only. Never awards catches or runs the remote fishing simulation.
## Versioned, bounded binary payload fits alongside player/deck metadata in v5 UDP.
const PHASES := ["stowed", "charging", "casting", "fishing", "bite", "fighting", "landed"]
const ACTIONS := ["hold", "reel", "pay"]

static func encode(station: RodFishingStation, player: Node3D) -> String:
	if not station.working or not is_instance_valid(station._carried): return ""
	var fish: Array = station.session.catches if station.session is HarpeFishingSession else ([station.session.catch_data] if not station.session.catch_data.is_empty() else [])
	var bytes := PackedByteArray()
	bytes.resize(30 + mini(fish.size(), 6) * 4)
	bytes[0] = 1
	bytes[1] = 1 if station.equipment_id == "harpe" else 0
	bytes[2] = maxi(0, PHASES.find(station.session.phase))
	bytes[3] = clampi(roundi(station._bend * 255), 0, 255)
	bytes[4] = roundi(fposmod(station._crank.rotation.x, TAU) / TAU * 255) if is_instance_valid(station._crank) else 0
	bytes[5] = maxi(0, ACTIONS.find(station.session.line_action))
	# Player packets publish visible-body yaw, which can differ from the capsule
	# while looking around. Use that same frame for held gear and hook offsets.
	var yaw := player.global_rotation.y
	var controller := player.get_node_or_null("PlayerCamera") as PlayerCamera
	if controller != null: yaw = controller.get_replication_yaw()
	var frame := Transform3D(Basis(Vector3.UP,yaw),player.global_position)
	var pose := frame.affine_inverse() * station._carried.global_transform
	var angles := pose.basis.get_euler()
	var hook := frame.affine_inverse() * station.visual_hook
	for axis in 3:
		bytes.encode_s16(6 + axis * 2, clampi(roundi(pose.origin[axis] * 1000), -32768, 32767))
		bytes.encode_s16(12 + axis * 2, roundi(angles[axis] / PI * 32767))
		bytes.encode_float(18 + axis * 4, hook[axis])
	var species := FishCatalog.fish_ids()
	species.sort()
	for i in mini(fish.size(), 6):
		bytes[30 + i * 4] = maxi(0, species.find(str(fish[i].get("species_id", ""))))
		bytes[31 + i * 4] = clampi(int(fish[i].get("hook_index", 0)), 0, 5)
		bytes.encode_u16(32 + i * 4, clampi(roundi(float(fish[i].get("length_cm", 1)) * 10), 1, 6000))
	return Marshalls.raw_to_base64(bytes)

static func decode(text: String) -> Dictionary:
	if text.length() > 72 or text.is_empty(): return {}
	var bytes := Marshalls.base64_to_raw(text)
	if bytes.size() < 30 or bytes.size() > 54 or (bytes.size() - 30) % 4 != 0: return {}
	if bytes[0] != 1 or bytes[1] > 1 or bytes[2] >= PHASES.size() or bytes[5] >= ACTIONS.size(): return {}
	var position := Vector3.ZERO
	var angles := Vector3.ZERO
	var hook := Vector3.ZERO
	for axis in 3:
		position[axis] = bytes.decode_s16(6 + axis * 2) / 1000.0
		angles[axis] = bytes.decode_s16(12 + axis * 2) / 32767.0 * PI
		hook[axis] = bytes.decode_float(18 + axis * 4)
		if not is_finite(hook[axis]) or absf(hook[axis]) > 2000: return {}
	var species := FishCatalog.fish_ids()
	species.sort()
	var fish: Array[Dictionary] = []
	for i in (bytes.size() - 30) / 4:
		var index := int(bytes[30 + i * 4])
		if index >= species.size() or bytes[31 + i * 4] > 5: return {}
		fish.append({"species_id":species[index], "hook_index":int(bytes[31+i*4]), "length_cm":clampf(bytes.decode_u16(32+i*4)/10.0, .1, 600), "fish_id":"remote_hook_%d" % bytes[31+i*4]})
	return {"equipment":"harpe" if bytes[1] == 1 else "fishing_rod", "phase":PHASES[bytes[2]], "pose":Transform3D(Basis.from_euler(angles),position), "hook":hook, "bend":bytes[3]/255.0, "crank":bytes[4]/255.0*TAU, "action":ACTIONS[bytes[5]], "fish":fish}

static func apply(player: Node3D, text: String) -> void:
	var state := decode(text)
	var station := player.get_node_or_null("RemoteFishingVisual") as RodFishingStation
	if state.is_empty():
		if station != null:
			station._carry(false)
			player.remove_child(station)
			station.queue_free()
		return
	if station == null:
		station = RodFishingStation.new()
		station.name = "RemoteFishingVisual"
		station.remote_player = player
		station.authored_station = load("res://resources/models/fishing_items/spinning_rod.glb").instantiate()
		station.add_child(station.authored_station)
		player.add_child(station)
		station.set_physics_process(false)
		station.set_process_unhandled_input(false)
		station._interaction.collision_layer = 0
	if station.equipment_id != state.equipment:
		station._carry(false)
		station.working = false
		station.set_equipment(state.equipment)
	if not station.working:
		station.working = true
		station._carry(true)
	station.remote_pose = state.pose
	station.remote_hook = state.hook
	station._bend = state.bend
	station.session.phase = state.phase
	station.session.line_action = state.action
	station.session.tension = clampf((float(state.bend)-.09)/.16,0,1)
	station.session.catch_data = state.fish[0] if not state.fish.is_empty() else {}
	if station.session is HarpeFishingSession: station.session.catches.assign(state.fish)
	if is_instance_valid(station._crank): station._crank.rotation.x = state.crank
