class_name LodSubject
extends RefCounted

## Registration payload for LodService — plain data, not a Node.

var host: Node3D = null
var anchor: Node3D = null
var profile_id: StringName = &"default"
var impostor_key: String = ""
var build_detailed: Callable = Callable()
var teardown: Callable = Callable()
var range_scale: float = 1.0


func resolve_anchor() -> Node3D:
	if anchor != null and is_instance_valid(anchor):
		return anchor
	return host
