class_name HarbourNetMeta
extends Object

## MP helpers: encode/decode plug edges as UDP metadata fragments.
## Peers apply through HarbourController so SP and MP share one path.


static func ship_berth_fragment(berth_id: String) -> String:
	var bid := berth_id.strip_edges()
	if bid.is_empty():
		return ""
	return "berth=%s" % bid


static func parse_berth_id(meta: String) -> String:
	return _parse_key(meta, "berth")


static func equipment_job_fragment(ship_id: String, mode: String) -> String:
	var sid := ship_id.strip_edges()
	var m := mode.strip_edges().to_lower()
	if sid.is_empty() and m.is_empty():
		return ""
	var parts: PackedStringArray = []
	if not sid.is_empty():
		parts.append("ship=%s" % sid)
	if not m.is_empty():
		parts.append("job=%s" % m)
	return ";".join(parts)


static func parse_equipment_ship_id(meta: String) -> String:
	return _parse_key(meta, "ship")


static func parse_equipment_job(meta: String) -> String:
	return _parse_key(meta, "job")


static func apply_ship_berth_meta(
		harbour: HarbourController,
		ship: BoatBody,
		meta: String,
) -> bool:
	if harbour == null or ship == null:
		return false
	var berth_id := parse_berth_id(meta)
	return harbour.apply_remote_ship_berth(ship, berth_id)


static func merge_meta(existing: String, fragment: String) -> String:
	var frag := fragment.strip_edges()
	if frag.is_empty():
		return existing.strip_edges()
	var base := existing.strip_edges()
	if base.is_empty():
		return frag
	var keys: Dictionary = {}
	for part in base.split(";", false):
		var kv := part.split("=", false, 1)
		if kv.size() == 2:
			keys[str(kv[0])] = str(kv[1])
	for part in frag.split(";", false):
		var kv2 := part.split("=", false, 1)
		if kv2.size() == 2:
			keys[str(kv2[0])] = str(kv2[1])
	var out := PackedStringArray()
	for k in keys.keys():
		out.append("%s=%s" % [str(k), str(keys[k])])
	out.sort()
	return ";".join(out)


static func _parse_key(meta: String, key: String) -> String:
	for part in meta.split(";", false):
		var kv := part.split("=", false, 1)
		if kv.size() == 2 and str(kv[0]) == key:
			return str(kv[1]).strip_edges()
	return ""
