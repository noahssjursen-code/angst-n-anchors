class_name AudioLibrary
extends RefCounted
## Manifest is the source of truth for clip type, bus and review information.
const ROOT := "res://resources/audio/"
static var _entries: Dictionary = {}
static var _loaded := false
static var _streams: Dictionary = {}

static func entries() -> Dictionary:
	if not _loaded:
		_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
		if data is Dictionary:
			for entry: Dictionary in data.get("entries", []):
				_entries[ROOT + str(entry.path)] = entry
	return _entries

static func stream(path: String, looping := false) -> AudioStream:
	var key := path + (":loop" if looping else ":shot")
	if _streams.has(key):
		return _streams[key]
	if not ResourceLoader.exists(path):
		return null
	var source := load(path) as AudioStream
	if source == null:
		return null
	var result := source.duplicate() as AudioStream
	if result is AudioStreamWAV:
		var wav := result as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		wav.loop_begin = 0
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	elif result is AudioStreamOggVorbis:
		(result as AudioStreamOggVorbis).loop = looping
	_streams[key] = result
	return result

static func bus(path: String) -> StringName:
	var entry: Dictionary = entries().get(path, {})
	var name := StringName(str(entry.get("bus", "SFX")))
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, &"Master")
	return name

static func distance_profile(path: String) -> Vector2:
	if "/wildlife/gulls/" in path: return Vector2(8, 140)
	if "/horns/" in path: return Vector2(60, 2000)
	if "/engines/" in path: return Vector2(14, 220)
	if "/thruster/" in path: return Vector2(5, 90)
	if "/controls/" in path: return Vector2(1.5, 12)
	if "/crane/" in path or "/cargo/" in path: return Vector2(7, 90)
	if "/water/" in path: return Vector2(5, 60)
	if "/helm/" in path or "/footsteps/" in path or "/body/" in path: return Vector2(2, 20)
	return Vector2(4, 40)
