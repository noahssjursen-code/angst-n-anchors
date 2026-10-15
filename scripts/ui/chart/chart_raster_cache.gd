class_name ChartRasterCache
extends RefCounted

## Disposable, client-only geography images. Neither ownership nor live port
## construction belongs here. World + chart versions make an old bake inert.
const VERSION := 2
const DIRECTORY := "user://chart_raster_cache/"
const MAX_FILES := 80
const MAX_FILE_BYTES := 6000000
static var directory := DIRECTORY
static var enabled := true


static func world_key(layout: WorldLayout) -> String:
	var checksum := layout.layout_checksum
	if checksum.is_empty():
		# Unidentified test layouts may share RAM by instance, never disk.
		checksum = "instance-%d" % layout.get_instance_id()
	return "chart%d:gen%d:bed%d:seed%d:%.3f:%s" % [
		VERSION, WorldLayoutGenerator.GENERATION_VERSION,
		WorldLayout.SEABED_VERSION, layout.seed, layout.world_size_m, checksum,
	]


static func read(key: String, resolution: int) -> Image:
	if not enabled or key.contains("instance-"):
		return null
	var path := _path(key)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	if image.get_width() != resolution or image.get_height() != resolution:
		return null
	image.generate_mipmaps()
	return image


static func write(key: String, image: Image) -> void:
	if not enabled or key.contains("instance-") or image == null:
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return
	var path := _path(key)
	var temporary := path + ".%d.%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	if image.save_png(temporary) != OK:
		return
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return
	_prune()


static func _path(key: String) -> String:
	return directory.path_join(key.sha256_text() + ".png")


static func _prune() -> void:
	# All disk work runs in a bake worker, never a scroll/zoom input callback.
	var folder := DirAccess.open(directory)
	if folder == null:
		return
	var files: Array[Dictionary] = []
	for name in folder.get_files():
		if name.ends_with(".png"):
			var path := directory.path_join(name)
			files.append({"path": path, "time": FileAccess.get_modified_time(path)})
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for index in range(maxi(files.size() - MAX_FILES, 0)):
		DirAccess.remove_absolute(files[index].path)
