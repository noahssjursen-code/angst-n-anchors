class_name DistantForestCache
extends RefCounted
## Disposable presentation data, never a world/captain save. One latest-world
## file per mode bounds disk use; failed reads/writes simply regenerate trees.
const VERSION := 2 # Coastal vegetation follows the same setback as nearby trees.
const MAX_BYTES := 64 * 1024 * 1024

static func default_path() -> String:
	var mode := "playtest" if ShipyardPlaytestMode.active() else "game"
	return OS.get_cache_dir().path_join("angst-n-anchors-visuals").path_join("forest-" + mode + ".bin")

static func digest(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()

static func identity(checksum: String, seed: int, size_m: float, coverage: PackedByteArray, zones: Array, step: float, sink: float) -> String:
	return digest(var_to_bytes([VERSION,checksum,seed,size_m,coverage,zones,step,sink]))

static func read(path: String, key: String) -> Dictionary:
	if path.is_empty() or key.is_empty() or not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() < 130 or file.get_length() > MAX_BYTES: return {}
	if file.get_line() != key: return {}
	var expected := file.get_line()
	var bytes := file.get_buffer(file.get_length()-file.get_position())
	if digest(bytes) != expected: return {}
	# No object decoding, scripts or resources can be loaded from this cache.
	var decoded: Variant = bytes_to_var(bytes)
	if not valid(decoded): return {}
	return decoded

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty() or value.size()>4096: return false
	for key in value:
		if not key is Vector2i: return false
		var groups: Variant = value[key]
		if not groups is Array or groups.size()!=4: return false
		for group in groups:
			if not group is PackedFloat32Array or group.size()%4!=0 or group.size()>200000: return false
	return true

static func write(path: String, key: String, batches: Dictionary) -> bool:
	if path.is_empty() or key.is_empty() or not valid(batches): return false
	var bytes := var_to_bytes(batches)
	if bytes.size()+130 > MAX_BYTES: return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return false
	var temporary := path + ".%d-%d.tmp" % [OS.get_process_id(),Time.get_ticks_usec()]
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return false
	file.store_line(key)
	file.store_line(digest(bytes))
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	if error == OK: error=DirAccess.rename_absolute(temporary,path)
	if error != OK: DirAccess.remove_absolute(temporary)
	return error == OK
