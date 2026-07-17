extends Node

## Game-wide LOD hub: DETAILED / IMPOSTOR / CULLED from player distance.
## Register subjects; one poll loop applies swaps. Do not invent per-asset distance logic.

const LodProfilesScript := preload("res://scripts/core/lod_profiles.gd")
const LodSubjectScript := preload("res://scripts/core/lod_subject.gd")
const ImpostorServiceScript := preload("res://scripts/core/impostor_service.gd")
const WorldReference := preload("res://scripts/world/world_reference.gd")

enum ObserverMode { GAMEPLAY, CAMERA }
enum Tier { DETAILED, IMPOSTOR, CULLED }

const POLL_INTERVAL_S := 0.25

var observer_mode: ObserverMode = ObserverMode.GAMEPLAY

var _entries: Dictionary = {} ## handle (int) -> Dictionary
var _next_handle: int = 1
var _poll_accum: float = 0.0


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < POLL_INTERVAL_S:
		return
	_poll_accum = 0.0
	_tick()


func set_observer_mode(mode: ObserverMode) -> void:
	observer_mode = mode
	_tick(true)


func register(subject: RefCounted) -> int:
	if subject == null:
		push_warning("LodService.register: subject required")
		return -1
	var host := subject.get("host") as Node3D
	if host == null or not is_instance_valid(host):
		push_warning("LodService.register: host required")
		return -1
	var build: Callable = subject.get("build_detailed") as Callable
	if not build.is_valid():
		push_warning("LodService.register: build_detailed required")
		return -1
	var handle := _next_handle
	_next_handle += 1
	_entries[handle] = {
		"handle": handle,
		"subject": subject,
		"tier": Tier.CULLED,
		"visual": null,
	}
	_apply_entry(_entries[handle] as Dictionary, true, observer_position())
	return handle


func unregister(handle: int) -> void:
	if not _entries.has(handle):
		return
	var entry: Dictionary = _entries[handle]
	_clear_visual(entry)
	_entries.erase(handle)


func current_tier(handle: int) -> Tier:
	if not _entries.has(handle):
		return Tier.CULLED
	return _entries[handle]["tier"] as Tier


func tier_at(
		distance_m: float,
		profile_id: StringName = &"default",
		range_scale: float = 1.0,
		impostor_key: String = "",
		current: Tier = Tier.CULLED,
) -> Tier:
	var profile: Dictionary = LodProfilesScript.get_profile(profile_id)
	var scale := maxf(range_scale, 0.01)
	var detailed_m := float(profile["detailed_m"]) * scale
	var impostor_m := float(profile["impostor_m"]) * scale
	var hyst := float(profile["hysteresis_m"])
	var has_impostor := not impostor_key.is_empty() and ImpostorServiceScript.has_key(impostor_key)

	var raw := Tier.CULLED
	if distance_m <= detailed_m:
		raw = Tier.DETAILED
	elif distance_m <= impostor_m:
		raw = Tier.IMPOSTOR if has_impostor else Tier.DETAILED
	else:
		raw = Tier.CULLED

	## Hysteresis only when downgrading.
	if current == Tier.DETAILED:
		if raw == Tier.IMPOSTOR and distance_m <= detailed_m + hyst:
			return Tier.DETAILED
		if raw == Tier.CULLED:
			if has_impostor:
				if distance_m <= impostor_m + hyst:
					return Tier.IMPOSTOR
			elif distance_m <= impostor_m + hyst:
				## No bake: keep detailed through the impostor band + grace.
				return Tier.DETAILED
	elif current == Tier.IMPOSTOR:
		if raw == Tier.CULLED and distance_m <= impostor_m + hyst:
			return Tier.IMPOSTOR
	return raw


func observer_position() -> Vector3:
	## CAMERA mode or F3 freecam → stream from the view so flying loads detail normally.
	if observer_mode == ObserverMode.CAMERA or WorldReference.is_freecam_active(get_tree()):
		return WorldReference.stream_position(get_viewport())
	return WorldReference.gameplay_position(get_tree())


func _tick(force: bool = false) -> void:
	var stale: Array[int] = []
	# Observer discovery can traverse scene-tree groups. Resolve it once for the
	# whole batch instead of once per building, house, and crane.
	var observer := observer_position()
	for handle in _entries.keys():
		var entry: Dictionary = _entries[handle]
		var subject: RefCounted = entry["subject"] as RefCounted
		var host := subject.get("host") as Node3D if subject != null else null
		if subject == null or host == null or not is_instance_valid(host):
			stale.append(int(handle))
			continue
		_apply_entry(entry, force, observer)
	for handle in stale:
		unregister(handle)


func _apply_entry(entry: Dictionary, force: bool, observer: Vector3) -> void:
	var subject: RefCounted = entry["subject"] as RefCounted
	var host := subject.get("host") as Node3D
	var anchor: Node3D = null
	if subject.has_method("resolve_anchor"):
		anchor = subject.call("resolve_anchor") as Node3D
	else:
		anchor = subject.get("anchor") as Node3D
		if anchor == null:
			anchor = host
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var dist := observer.distance_to(anchor.global_position)
	var current: Tier = entry["tier"]
	var want := tier_at(
		dist,
		subject.get("profile_id") as StringName,
		float(subject.get("range_scale")),
		str(subject.get("impostor_key")),
		current,
	)
	if not force and want == current:
		return
	_swap(entry, want)


func _swap(entry: Dictionary, want: Tier) -> void:
	_clear_visual(entry)
	var subject: RefCounted = entry["subject"] as RefCounted
	var host := subject.get("host") as Node3D
	var build: Callable = subject.get("build_detailed") as Callable
	var key := str(subject.get("impostor_key"))
	match want:
		Tier.DETAILED:
			var built: Variant = build.call()
			var node := built as Node3D
			if node != null:
				node.name = "Detailed"
				host.add_child(node)
				entry["visual"] = node
			entry["tier"] = Tier.DETAILED
		Tier.IMPOSTOR:
			if ImpostorServiceScript.has_key(key):
				var stamp := ImpostorServiceScript.stamp(key, false)
				stamp.name = "Impostor"
				host.add_child(stamp)
				entry["visual"] = stamp
				entry["tier"] = Tier.IMPOSTOR
			else:
				var built_fb: Variant = build.call()
				var node_fb := built_fb as Node3D
				if node_fb != null:
					node_fb.name = "Detailed"
					host.add_child(node_fb)
					entry["visual"] = node_fb
				entry["tier"] = Tier.DETAILED
		_:
			entry["tier"] = Tier.CULLED


func _clear_visual(entry: Dictionary) -> void:
	var subject: RefCounted = entry["subject"] as RefCounted
	if subject != null:
		var teardown: Callable = subject.get("teardown") as Callable
		if teardown.is_valid():
			teardown.call()
	var visual: Node = entry.get("visual") as Node
	if visual != null and is_instance_valid(visual):
		visual.free()
	entry["visual"] = null
	if subject != null:
		var host := subject.get("host") as Node3D
		if host != null and is_instance_valid(host):
			for child in host.get_children():
				child.free()
