extends RefCounted

## Stateless binary encoder and decoder for the v4 generic state-replication protocol.
## All functions are pure and have zero side-effects.

const UDP_PROTOCOL_VERSION := 4

const UDP_MSG_TYPE_CLIENT_UPDATE := 1
const UDP_MSG_TYPE_SNAPSHOT := 2
const UDP_MSG_TYPE_LOGOUT := 3

const MAX_STRING_LEN := 128


# ── Outbound Encoder (Client -> Server) ──────────────────────────────────────

## Encodes a generic ClientUpdate package containing observer pos and local entity updates.
## - `entities` array contains dictionaries with:
##   - "id": String
##   - "type": String
##   - "format": int (2, 3, 4, or 6)
##   - "payload": Array of floats (representing the vector)
##   - "meta": String
static func encode_client_update(seq: int, player_id: String, observer_pos: Vector3, entities: Array) -> PackedByteArray:
	var packet := PackedByteArray()
	
	# Header: version (1B), type (1B), seq (4B), player_id_len (1B) = 7B
	packet.resize(7)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_CLIENT_UPDATE)
	packet.encode_u32(2, seq)
	
	var id_bytes := player_id.to_utf8_buffer()
	var id_len := id_bytes.size()
	if id_len > MAX_STRING_LEN:
		id_len = MAX_STRING_LEN
		id_bytes = id_bytes.slice(0, MAX_STRING_LEN)
	packet.encode_u8(6, id_len)
	packet.append_array(id_bytes)
	
	# Observer pos (3 floats = 12 bytes)
	var obs_bytes := PackedByteArray()
	obs_bytes.resize(12)
	obs_bytes.encode_float(0, observer_pos.x)
	obs_bytes.encode_float(4, observer_pos.y)
	obs_bytes.encode_float(8, observer_pos.z)
	packet.append_array(obs_bytes)
	
	# Entity count
	var ent_count := clampi(entities.size(), 0, 255)
	packet.append(ent_count)
	
	# For each entity
	for i in ent_count:
		var ent: Dictionary = entities[i]
		
		# Entity ID
		var ent_id_bytes := String(ent.get("id", "")).to_utf8_buffer()
		var ent_id_len := clampi(ent_id_bytes.size(), 0, MAX_STRING_LEN)
		packet.append(ent_id_len)
		if ent_id_len > 0:
			packet.append_array(ent_id_bytes.slice(0, ent_id_len))
		
		# Entity Type
		var type_bytes := String(ent.get("type", "")).to_utf8_buffer()
		var type_len := clampi(type_bytes.size(), 0, MAX_STRING_LEN)
		packet.append(type_len)
		if type_len > 0:
			packet.append_array(type_bytes.slice(0, type_len))
		
		# Format (Payload float count: 2, 3, 4, 6)
		var format: int = clampi(int(ent.get("format", 0)), 2, 6)
		packet.append(format)
		
		# Payload (format floats)
		var payload: Array = ent.get("payload", [])
		var pay_bytes := PackedByteArray()
		pay_bytes.resize(format * 4)
		for j in format:
			var val: float = 0.0
			if j < payload.size():
				val = float(payload[j])
			pay_bytes.encode_float(j * 4, val)
		packet.append_array(pay_bytes)
		
		# Metadata string
		var meta_bytes := String(ent.get("meta", "")).to_utf8_buffer()
		var meta_len := clampi(meta_bytes.size(), 0, 255)
		packet.append(meta_len)
		if meta_len > 0:
			packet.append_array(meta_bytes.slice(0, meta_len))
			
	return packet


## Encodes an explicit logout/disconnect packet containing the local player_id.
static func encode_logout(player_id: String) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(3)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_LOGOUT)
	
	var id_bytes := player_id.to_utf8_buffer()
	var id_len := id_bytes.size()
	if id_len > MAX_STRING_LEN:
		id_len = MAX_STRING_LEN
		id_bytes = id_bytes.slice(0, MAX_STRING_LEN)
	packet.encode_u8(2, id_len)
	packet.append_array(id_bytes)
	return packet


# ── Inbound Decoder (Server -> Client) ────────────────────────────────────────

## Parses the multi-entity snapshot from the server (v4).
## Returns a Dictionary with "next_update_ms", "nearest_distance", and "entities".
## Returns an empty dictionary if parsing fails due to version mismatch or packet truncation.
static func decode_snapshot(packet: PackedByteArray) -> Dictionary:
	# Snapshot Header: version (1B), type (1B), next_update_ms (4B), nearest_dist (4B), entity_count (1B) = 11B
	if packet.size() < 11:
		return {}
	if packet.decode_u8(0) != UDP_PROTOCOL_VERSION:
		return {}
	if packet.decode_u8(1) != UDP_MSG_TYPE_SNAPSHOT:
		return {}
	
	var next_update_ms := packet.decode_u32(2)
	var nearest_dist := packet.decode_float(6)
	var entity_count := packet.decode_u8(10)
	
	var off := 11
	var entities: Array[Dictionary] = []
	
	for i in entity_count:
		# 1. Decode Entity ID
		if off + 1 > packet.size():
			return {}
		var id_len := packet.decode_u8(off)
		off += 1
		if off + id_len > packet.size():
			return {}
		var entity_id := packet.slice(off, off + id_len).get_string_from_utf8()
		off += id_len
		
		# 2. Decode Entity Type
		if off + 1 > packet.size():
			return {}
		var type_len := packet.decode_u8(off)
		off += 1
		if off + type_len > packet.size():
			return {}
		var entity_type := packet.slice(off, off + type_len).get_string_from_utf8()
		off += type_len
		
		# 3. Decode Owner ID
		if off + 1 > packet.size():
			return {}
		var owner_len := packet.decode_u8(off)
		off += 1
		if off + owner_len > packet.size():
			return {}
		var owner_id := packet.slice(off, off + owner_len).get_string_from_utf8()
		off += owner_len
		
		# 4. Decode Format & Payload
		if off + 1 > packet.size():
			return {}
		var format := packet.decode_u8(off)
		off += 1
		
		if off + (format * 4) > packet.size():
			return {}
		var payload: Array[float] = []
		for j in format:
			payload.append(packet.decode_float(off))
			off += 4
			
		# 5. Decode Metadata string
		if off + 1 > packet.size():
			return {}
		var meta_len := packet.decode_u8(off)
		off += 1
		if off + meta_len > packet.size():
			return {}
		var meta := packet.slice(off, off + meta_len).get_string_from_utf8()
		off += meta_len
		
		# Extrapolate Vector3 global coordinate from the format payload
		var pos := Vector3.ZERO
		if format == 2:
			# Format 2 = XY (on water flat plane we map Y=0, X=f[0], Z=f[1])
			pos = Vector3(payload[0], 0.0, payload[1])
		elif format >= 3:
			pos = Vector3(payload[0], payload[1], payload[2])
		
		entities.append({
			"id": entity_id,
			"type": entity_type,
			"owner_id": owner_id,
			"pos": pos,
			"format": format,
			"payload": payload,
			"meta": meta
		})
		
	return {
		"next_update_ms": next_update_ms,
		"nearest_distance": nearest_dist,
		"entities": entities
	}
