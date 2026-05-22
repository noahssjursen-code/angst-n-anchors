extends RefCounted

## Stateless binary encoder and decoder for the v3 multiplayer protocol.
## All functions are pure and have zero side-effects.

const UDP_PROTOCOL_VERSION := 3

const UDP_MSG_TYPE_POSITION := 1
const UDP_MSG_TYPE_SNAPSHOT := 2
const UDP_MSG_TYPE_SHIP_SPAWN := 3
const UDP_MSG_TYPE_SHIP_BOARD := 4
const UDP_MSG_TYPE_SHIP_TRANSFORM := 5
const UDP_MSG_TYPE_CARGO_SPAWN := 6
const UDP_MSG_TYPE_CARGO_MOVE := 7
const UDP_MSG_TYPE_CARGO_DESPAWN := 8
const UDP_MSG_TYPE_CRANE_OPERATE := 9
const UDP_MSG_TYPE_CRANE_STATE := 10

const UDP_MAX_PLAYER_ID_LEN := 64
const UDP_MAX_SHIP_ID_LEN := 64
const UDP_MAX_HULL_ID_LEN := 64
const UDP_MAX_CARGO_ID_LEN := 64
const UDP_MAX_COMMODITY_LEN := 32
const UDP_MAX_CRANE_ID_LEN := 64

const UDP_POSITION_HEADER_SIZE := 7
const UDP_POSITION_FLOATS_SIZE := 16
const UDP_SNAPSHOT_HEADER_SIZE := 11
const UDP_SNAPSHOT_PLAYER_FLOATS_SIZE := 16
const UDP_SNAPSHOT_SHIP_FLOATS_SIZE := 16


# ── Outbound Encoders (Client -> Server) ──────────────────────────────────────

static func encode_player_position(seq: int, player_id: String, pos: Vector3, yaw: float) -> PackedByteArray:
	var id_bytes := player_id.to_utf8_buffer()
	var id_len := id_bytes.size()
	if id_len > UDP_MAX_PLAYER_ID_LEN:
		id_len = UDP_MAX_PLAYER_ID_LEN
		id_bytes = id_bytes.slice(0, id_len)
	
	var packet := PackedByteArray()
	packet.resize(UDP_POSITION_HEADER_SIZE)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_POSITION)
	packet.encode_u32(2, seq)
	packet.encode_u8(6, id_len)
	packet.append_array(id_bytes)
	
	var floats := PackedByteArray()
	floats.resize(UDP_POSITION_FLOATS_SIZE)
	floats.encode_float(0, pos.x)
	floats.encode_float(4, pos.y)
	floats.encode_float(8, pos.z)
	floats.encode_float(12, yaw)
	packet.append_array(floats)
	
	return packet


static func encode_ship_spawn(seq: int, ship_id: String, hull_id: String, owner_id: String, pos: Vector3, yaw: float) -> PackedByteArray:
	var s_bytes := ship_id.to_utf8_buffer()
	var h_bytes := hull_id.to_utf8_buffer()
	var o_bytes := owner_id.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_SHIP_SPAWN)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(s_bytes.size(), 0, UDP_MAX_SHIP_ID_LEN))
	packet.append_array(s_bytes.slice(0, clampi(s_bytes.size(), 0, UDP_MAX_SHIP_ID_LEN)))
	packet.append(clampi(h_bytes.size(), 0, UDP_MAX_HULL_ID_LEN))
	packet.append_array(h_bytes.slice(0, clampi(h_bytes.size(), 0, UDP_MAX_HULL_ID_LEN)))
	packet.append(clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN))
	packet.append_array(o_bytes.slice(0, clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN)))
	
	var floats := PackedByteArray()
	floats.resize(16)
	floats.encode_float(0, pos.x)
	floats.encode_float(4, pos.y)
	floats.encode_float(8, pos.z)
	floats.encode_float(12, yaw)
	packet.append_array(floats)
	
	return packet


static func encode_ship_board(seq: int, ship_id: String, pilot_id: String) -> PackedByteArray:
	var s_bytes := ship_id.to_utf8_buffer()
	var p_bytes := pilot_id.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_SHIP_BOARD)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(s_bytes.size(), 0, UDP_MAX_SHIP_ID_LEN))
	packet.append_array(s_bytes.slice(0, clampi(s_bytes.size(), 0, UDP_MAX_SHIP_ID_LEN)))
	packet.append(clampi(p_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN))
	if p_bytes.size() > 0:
		packet.append_array(p_bytes.slice(0, clampi(p_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN)))
		
	return packet


static func encode_ship_transform(seq: int, ship_id: String, pos: Vector3, yaw: float) -> PackedByteArray:
	var s_bytes := ship_id.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_SHIP_TRANSFORM)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(s_bytes.size(), 0, UDP_MAX_SHIP_ID_LEN))
	packet.append_array(s_bytes.slice(0, clampi(s_bytes.size(), 0, UDP_MAX_SHIP_ID_LEN)))
	
	var floats := PackedByteArray()
	floats.resize(16)
	floats.encode_float(0, pos.x)
	floats.encode_float(4, pos.y)
	floats.encode_float(8, pos.z)
	floats.encode_float(12, yaw)
	packet.append_array(floats)
	
	return packet


static func encode_cargo_spawn(seq: int, cargo_id: String, owner_id: String, commodity: String, units: int, fp_x: int, fp_z: int, pos: Vector3, yaw: float) -> PackedByteArray:
	var c_bytes := cargo_id.to_utf8_buffer()
	var o_bytes := owner_id.to_utf8_buffer()
	var m_bytes := commodity.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_CARGO_SPAWN)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(c_bytes.size(), 0, UDP_MAX_CARGO_ID_LEN))
	packet.append_array(c_bytes.slice(0, clampi(c_bytes.size(), 0, UDP_MAX_CARGO_ID_LEN)))
	packet.append(clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN))
	packet.append_array(o_bytes.slice(0, clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN)))
	packet.append(clampi(m_bytes.size(), 0, UDP_MAX_COMMODITY_LEN))
	packet.append_array(m_bytes.slice(0, clampi(m_bytes.size(), 0, UDP_MAX_COMMODITY_LEN)))
	
	# units (u16), footprint x/z (u8 each)
	var detail := PackedByteArray()
	detail.resize(4)
	detail.encode_u16(0, clampi(units, 0, 65535))
	detail.encode_u8(2, clampi(fp_x, 1, 255))
	detail.encode_u8(3, clampi(fp_z, 1, 255))
	packet.append_array(detail)
	
	var floats := PackedByteArray()
	floats.resize(16)
	floats.encode_float(0, pos.x)
	floats.encode_float(4, pos.y)
	floats.encode_float(8, pos.z)
	floats.encode_float(12, yaw)
	packet.append_array(floats)
	
	return packet


static func encode_cargo_move(seq: int, cargo_id: String, pos: Vector3, yaw: float, carried_by: String) -> PackedByteArray:
	var c_bytes := cargo_id.to_utf8_buffer()
	var o_bytes := carried_by.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_CARGO_MOVE)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(c_bytes.size(), 0, UDP_MAX_CARGO_ID_LEN))
	packet.append_array(c_bytes.slice(0, clampi(c_bytes.size(), 0, UDP_MAX_CARGO_ID_LEN)))
	
	var floats := PackedByteArray()
	floats.resize(16)
	floats.encode_float(0, pos.x)
	floats.encode_float(4, pos.y)
	floats.encode_float(8, pos.z)
	floats.encode_float(12, yaw)
	packet.append_array(floats)
	
	packet.append(clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN))
	if o_bytes.size() > 0:
		packet.append_array(o_bytes.slice(0, clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN)))
		
	return packet


static func encode_cargo_despawn(seq: int, cargo_id: String) -> PackedByteArray:
	var c_bytes := cargo_id.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_CARGO_DESPAWN)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(c_bytes.size(), 0, UDP_MAX_CARGO_ID_LEN))
	packet.append_array(c_bytes.slice(0, clampi(c_bytes.size(), 0, UDP_MAX_CARGO_ID_LEN)))
	
	return packet


static func encode_crane_operate(seq: int, crane_id: String, operator_id: String) -> PackedByteArray:
	var c_bytes := crane_id.to_utf8_buffer()
	var o_bytes := operator_id.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_CRANE_OPERATE)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(c_bytes.size(), 0, UDP_MAX_CRANE_ID_LEN))
	packet.append_array(c_bytes.slice(0, clampi(c_bytes.size(), 0, UDP_MAX_CRANE_ID_LEN)))
	
	packet.append(clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN))
	if o_bytes.size() > 0:
		packet.append_array(o_bytes.slice(0, clampi(o_bytes.size(), 0, UDP_MAX_PLAYER_ID_LEN)))
		
	return packet


static func encode_crane_state(seq: int, crane_id: String, joints: Dictionary) -> PackedByteArray:
	var c_bytes := crane_id.to_utf8_buffer()
	
	var packet := PackedByteArray()
	packet.resize(6)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_CRANE_STATE)
	packet.encode_u32(2, seq)
	
	packet.append(clampi(c_bytes.size(), 0, UDP_MAX_CRANE_ID_LEN))
	packet.append_array(c_bytes.slice(0, clampi(c_bytes.size(), 0, UDP_MAX_CRANE_ID_LEN)))
	
	var floats := PackedByteArray()
	floats.resize(32)
	floats.encode_float(0, float(joints.get("gantry_x", 0.0)))
	floats.encode_float(4, float(joints.get("trolley_z", 0.0)))
	floats.encode_float(8, float(joints.get("hook_drop", 0.0)))
	floats.encode_float(12, float(joints.get("hook_yaw", 0.0)))
	floats.encode_float(16, float(joints.get("base_x", 0.0)))
	floats.encode_float(20, float(joints.get("base_y", 0.0)))
	floats.encode_float(24, float(joints.get("base_z", 0.0)))
	floats.encode_float(28, float(joints.get("base_yaw", 0.0)))
	packet.append_array(floats)
	
	return packet


# ── Inbound Decoder (Server -> Client) ────────────────────────────────────────

## Parses the multi-entity snapshot from server (v3).
## Returns a Dictionary with "players", "ships", "cargos", "cranes", and network stats.
## Returns an empty dictionary if parsing fails due to version mismatch or packet truncation.
static func decode_snapshot(packet: PackedByteArray) -> Dictionary:
	if packet.size() < UDP_SNAPSHOT_HEADER_SIZE:
		return {}
	if packet.decode_u8(0) != UDP_PROTOCOL_VERSION:
		return {}
	if packet.decode_u8(1) != UDP_MSG_TYPE_SNAPSHOT:
		return {}
	
	var next_update_ms := packet.decode_u32(2)
	var nearest_dist := packet.decode_float(6)
	var player_count := packet.decode_u8(10)
	
	var off := UDP_SNAPSHOT_HEADER_SIZE
	
	# 1. Parse Players
	var players: Array[Dictionary] = []
	for i in player_count:
		if off + 1 > packet.size():
			return {}
		var name_len := packet.decode_u8(off)
		off += 1
		if name_len == 0 or name_len > UDP_MAX_PLAYER_ID_LEN:
			return {}
		if off + name_len + UDP_SNAPSHOT_PLAYER_FLOATS_SIZE > packet.size():
			return {}
		var player_id := packet.slice(off, off + name_len).get_string_from_utf8()
		off += name_len
		var px := packet.decode_float(off)
		off += 4
		var py := packet.decode_float(off)
		off += 4
		var pz := packet.decode_float(off)
		off += 4
		var pyaw := packet.decode_float(off)
		off += 4
		players.append({
			"player_id": player_id,
			"x": px, "y": py, "z": pz, "yaw": pyaw,
		})
	
	if off >= packet.size():
		return {
			"next_update_ms": next_update_ms,
			"nearest_distance": nearest_dist,
			"players": players,
			"ships": [], "cargos": [], "cranes": []
		}
		
	# 2. Parse Ships
	var ship_count := packet.decode_u8(off)
	off += 1
	var ships: Array[Dictionary] = []
	for i in ship_count:
		# ship_id
		if off + 1 > packet.size():
			return {}
		var sid_len := packet.decode_u8(off)
		off += 1
		if sid_len == 0 or sid_len > UDP_MAX_SHIP_ID_LEN:
			return {}
		if off + sid_len > packet.size():
			return {}
		var ship_id := packet.slice(off, off + sid_len).get_string_from_utf8()
		off += sid_len
		
		# hull_id
		if off + 1 > packet.size():
			return {}
		var hid_len := packet.decode_u8(off)
		off += 1
		if hid_len == 0 or hid_len > UDP_MAX_HULL_ID_LEN:
			return {}
		if off + hid_len > packet.size():
			return {}
		var hull_id := packet.slice(off, off + hid_len).get_string_from_utf8()
		off += hid_len
		
		# owner_id
		if off + 1 > packet.size():
			return {}
		var oid_len := packet.decode_u8(off)
		off += 1
		if oid_len == 0 or oid_len > UDP_MAX_PLAYER_ID_LEN:
			return {}
		if off + oid_len > packet.size():
			return {}
		var owner_id := packet.slice(off, off + oid_len).get_string_from_utf8()
		off += oid_len
		
		# pilot_id (optional)
		if off + 1 > packet.size():
			return {}
		var pid_len := packet.decode_u8(off)
		off += 1
		if pid_len > UDP_MAX_PLAYER_ID_LEN:
			return {}
		var pilot_id := ""
		if pid_len > 0:
			if off + pid_len > packet.size():
				return {}
			pilot_id = packet.slice(off, off + pid_len).get_string_from_utf8()
			off += pid_len
			
		# Pose
		if off + UDP_SNAPSHOT_SHIP_FLOATS_SIZE > packet.size():
			return {}
		var sx := packet.decode_float(off)
		off += 4
		var sy := packet.decode_float(off)
		off += 4
		var sz := packet.decode_float(off)
		off += 4
		var syaw := packet.decode_float(off)
		off += 4
		
		ships.append({
			"ship_id": ship_id,
			"hull_id": hull_id,
			"owner_id": owner_id,
			"pilot_id": pilot_id,
			"x": sx, "y": sy, "z": sz, "yaw": syaw,
		})
		
	if off >= packet.size():
		return {
			"next_update_ms": next_update_ms,
			"nearest_distance": nearest_dist,
			"players": players,
			"ships": ships,
			"cargos": [], "cranes": []
		}
		
	# 3. Parse Cargos (v3)
	var cargo_count := packet.decode_u8(off)
	off += 1
	var cargos: Array[Dictionary] = []
	for i in cargo_count:
		# cargo_id
		if off + 1 > packet.size():
			return {}
		var cid_len := packet.decode_u8(off)
		off += 1
		if cid_len == 0 or cid_len > UDP_MAX_CARGO_ID_LEN:
			return {}
		if off + cid_len > packet.size():
			return {}
		var cargo_id := packet.slice(off, off + cid_len).get_string_from_utf8()
		off += cid_len
		
		# commodity
		if off + 1 > packet.size():
			return {}
		var com_len := packet.decode_u8(off)
		off += 1
		if com_len > UDP_MAX_COMMODITY_LEN:
			return {}
		var commodity := ""
		if com_len > 0:
			if off + com_len > packet.size():
				return {}
			commodity = packet.slice(off, off + com_len).get_string_from_utf8()
			off += com_len
			
		# units (u16), footprint x/z (u8 each)
		if off + 4 > packet.size():
			return {}
		var units := packet.decode_u16(off)
		off += 2
		var fp_x := packet.decode_u8(off)
		off += 1
		var fp_z := packet.decode_u8(off)
		off += 1
		
		# Pose
		if off + 16 > packet.size():
			return {}
		var cx := packet.decode_float(off)
		off += 4
		var cy := packet.decode_float(off)
		off += 4
		var cz := packet.decode_float(off)
		off += 4
		var cyaw := packet.decode_float(off)
		off += 4
		
		# carried_by (optional)
		if off + 1 > packet.size():
			return {}
		var carried_len := packet.decode_u8(off)
		off += 1
		if carried_len > UDP_MAX_PLAYER_ID_LEN:
			return {}
		var carried_by := ""
		if carried_len > 0:
			if off + carried_len > packet.size():
				return {}
			carried_by = packet.slice(off, off + carried_len).get_string_from_utf8()
			off += carried_len
			
		cargos.append({
			"cargo_id": cargo_id,
			"commodity": commodity,
			"units": units,
			"footprint_x": fp_x,
			"footprint_z": fp_z,
			"x": cx, "y": cy, "z": cz, "yaw": cyaw,
			"carried_by": carried_by,
		})
		
	if off >= packet.size():
		return {
			"next_update_ms": next_update_ms,
			"nearest_distance": nearest_dist,
			"players": players,
			"ships": ships,
			"cargos": cargos,
			"cranes": []
		}
		
	# 4. Parse Cranes (v3)
	var crane_count := packet.decode_u8(off)
	off += 1
	var cranes: Array[Dictionary] = []
	for i in crane_count:
		# crane_id
		if off + 1 > packet.size():
			return {}
		var cr_len := packet.decode_u8(off)
		off += 1
		if cr_len == 0 or cr_len > UDP_MAX_CRANE_ID_LEN:
			return {}
		if off + cr_len > packet.size():
			return {}
		var crane_id := packet.slice(off, off + cr_len).get_string_from_utf8()
		off += cr_len
		
		# operator_id (optional)
		if off + 1 > packet.size():
			return {}
		var op_len := packet.decode_u8(off)
		off += 1
		if op_len > UDP_MAX_PLAYER_ID_LEN:
			return {}
		var operator_id := ""
		if op_len > 0:
			if off + op_len > packet.size():
				return {}
			operator_id = packet.slice(off, off + op_len).get_string_from_utf8()
			off += op_len
			
		# Joints & Base (8 floats = 32 bytes)
		if off + 32 > packet.size():
			return {}
		var gantry_x := packet.decode_float(off)
		off += 4
		var trolley_z := packet.decode_float(off)
		off += 4
		var hook_drop := packet.decode_float(off)
		off += 4
		var hook_yaw := packet.decode_float(off)
		off += 4
		var base_x := packet.decode_float(off)
		off += 4
		var base_y := packet.decode_float(off)
		off += 4
		var base_z := packet.decode_float(off)
		off += 4
		var base_yaw := packet.decode_float(off)
		off += 4
		
		cranes.append({
			"crane_id": crane_id,
			"operator_id": operator_id,
			"gantry_x": gantry_x,
			"trolley_z": trolley_z,
			"hook_drop": hook_drop,
			"hook_yaw": hook_yaw,
			"base_x": base_x,
			"base_y": base_y,
			"base_z": base_z,
			"base_yaw": base_yaw,
		})
		
	return {
		"next_update_ms": next_update_ms,
		"nearest_distance": nearest_dist,
		"players": players,
		"ships": ships,
		"cargos": cargos,
		"cranes": cranes,
	}
