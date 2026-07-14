class_name WorldGenerationContext
extends RefCounted

## Pure comparison used before restoring coordinate-bearing player state.
## Empty legacy contexts are accepted once and adopt the current world on save.


static func matches(saved: Dictionary, current: Dictionary) -> bool:
	if saved.is_empty() or current.is_empty():
		return true
	if int(saved.get("seed", 0)) != int(current.get("seed", 0)):
		return false
	if int(saved.get("generation_version", 0)) != int(current.get("generation_version", 0)):
		return false
	if saved.has("weather_generation_version") and current.has("weather_generation_version"):
		if int(saved["weather_generation_version"]) != int(current["weather_generation_version"]):
			return false
	var saved_checksum := str(saved.get("layout_checksum", ""))
	var current_checksum := str(current.get("layout_checksum", ""))
	return saved_checksum.is_empty() or current_checksum.is_empty() or saved_checksum == current_checksum
