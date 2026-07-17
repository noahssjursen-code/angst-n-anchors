class_name PortStructureLod
extends Node3D

## Port visual host wired to LodService (DETAILED / IMPOSTOR / CULLED).
## Prefer LodHost for new one-offs; this keeps the port visualizer API stable.

const LodSubjectScript := preload("res://scripts/core/lod_subject.gd")

const PROFILE_DEFAULT := &"default"
const PROFILE_TALL := &"tall"

var impostor_key := ""
var full_factory: Callable = Callable()
var teardown: Callable = Callable()
var profile_id: StringName = PROFILE_DEFAULT
var range_scale: float = 1.0

var _handle: int = -1


func setup(
		key: String,
		factory: Callable,
		profile: StringName = PROFILE_DEFAULT,
		teardown_cb: Callable = Callable(),
		scale: float = 1.0,
) -> void:
	impostor_key = key
	full_factory = factory
	profile_id = profile
	teardown = teardown_cb
	range_scale = scale
	if is_inside_tree():
		_register()
	else:
		call_deferred("_register")


func _exit_tree() -> void:
	_unregister()


func _register() -> void:
	_unregister()
	if not full_factory.is_valid():
		return
	if Engine.is_editor_hint():
		_editor_build()
		return
	var service := get_node_or_null("/root/LodService")
	if service == null:
		_editor_build()
		return
	var subject = LodSubjectScript.new()
	subject.host = self
	subject.anchor = self
	subject.profile_id = profile_id
	subject.impostor_key = impostor_key
	subject.build_detailed = full_factory
	subject.teardown = teardown
	subject.range_scale = range_scale
	_handle = service.register(subject)


func _unregister() -> void:
	var service := get_node_or_null("/root/LodService")
	if service != null and _handle >= 0:
		service.unregister(_handle)
	_handle = -1
	for child in get_children():
		child.free()


func _editor_build() -> void:
	for child in get_children():
		child.free()
	var built: Variant = full_factory.call()
	var node := built as Node3D
	if node != null:
		node.name = "Detailed"
		add_child(node)
