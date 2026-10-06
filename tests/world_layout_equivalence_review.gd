extends SceneTree

## Capture a baseline before changing generation internals, then compare complete
## fields/checksums. Reference files live in task scratch, never captain saves.
func _initialize() -> void:
	var record_path := ""
	var reference_path := "res://tests/fixtures/world_layout_v8_baseline.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--record="): record_path = arg.trim_prefix("--record=")
		if arg.begins_with("--reference="): reference_path = arg.trim_prefix("--reference=")
	var reference: Dictionary = {}
	if not reference_path.is_empty():
		reference = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	var results := {}
	for seed_value in [424242, 42, 8675309]:
		for size in [10000.0, 40000.0, 120000.0]:
			WorldLayoutGenerator.clear_cache()
			var start := Time.get_ticks_usec()
			var layout := WorldLayoutGenerator.generate(seed_value, WorldLayoutGenerator.DEFAULT_CONFIG_PATH, size)
			var elapsed := (Time.get_ticks_usec()-start)/1000.0
			var key := "%d:%d" % [seed_value, size]
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(layout._signed_distance.to_byte_array())
			hash.update(layout._regions)
			var data := {"checksum":layout.layout_checksum,"field_hash":hash.finish().hex_encode(),"elapsed_ms":elapsed}
			results[key] = data
			if not reference.is_empty():
				assert(reference.has(key))
				assert(data.checksum == reference[key].checksum, "World/checksum compatibility changed for " + key)
				assert(data.field_hash == reference[key].field_hash, "Field bytes changed for " + key)
			print("LAYOUT REVIEW ", key, " ", JSON.stringify(data))
	if not record_path.is_empty():
		var file := FileAccess.open(record_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
	print("LAYOUT EQUIVALENCE ", "BASELINE" if reference.is_empty() else "PASS")
	quit()
