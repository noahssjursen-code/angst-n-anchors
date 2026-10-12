class_name WorldGenerationCache
extends RefCounted

## Disposable derived data, never captain state. Object deserialization disabled.
const DIRECTORY := "user://world_generation_cache/"
## Allows isolated cold-generation measurements without deleting user caches.
static var enabled := true

static func digest(value: Variant) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()

static func read(key: String) -> Dictionary:
	if not enabled: return {}
	var path := DIRECTORY+key.sha256_text()+".bin"
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>32000000: return {}
	var record = file.get_var(false)
	if not record is Dictionary or record.get("key","")!=key: return {}
	var data: Dictionary = record.get("data",{}) if record.get("data",{}) is Dictionary else {}
	return data if record.get("digest","")==digest(data) else {}

static func write(key: String, data: Dictionary) -> void:
	if not enabled: return
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var path := DIRECTORY+key.sha256_text()+".bin"
	var temporary := path+".%d.%d.tmp" % [OS.get_process_id(),Time.get_ticks_usec()]
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return
	file.store_var({"key":key,"data":data,"digest":digest(data)},false)
	file.close()
	if DirAccess.rename_absolute(temporary,path)!=OK: DirAccess.remove_absolute(temporary)
