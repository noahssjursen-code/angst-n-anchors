class_name LodHost
extends Node3D

## Drop-in LOD host for one-off assets outside port systems.
## Set build_detailed (+ optional impostor_key), add to tree — registers with LodService.

const LodSubjectScript := preload("res://scripts/core/lod_subject.gd")

@export var profile_id: StringName = &"default"
@export var impostor_key: String = ""
@export var range_scale: float = 1.0

var build_detailed: Callable = Callable()
var teardown: Callable = Callable()

var _handle: int = -1


func _ready() -> void:
	_register()


func _exit_tree() -> void:
	_unregister()


func configure(
		detailed_builder: Callable,
		key: String = "",
		profile: StringName = &"default",
		teardown_cb: Callable = Callable(),
		scale: float = 1.0,
) -> void:
	build_detailed = detailed_builder
	impostor_key = key
	profile_id = profile
	teardown = teardown_cb
	range_scale = scale
	if is_inside_tree():
		_unregister()
		_register()


func _register() -> void:
	_unregister()
	if Engine.is_editor_hint():
		_editor_build()
		return
	var service := _lod_service()
	if service == null:
		_editor_build()
		return
	if not build_detailed.is_valid():
		push_warning("LodHost: build_detailed missing on %s" % name)
		return
	var subject = LodSubjectScript.new()
	subject.host = self
	subject.anchor = self
	subject.profile_id = profile_id
	subject.impostor_key = impostor_key
	subject.build_detailed = build_detailed
	subject.teardown = teardown
	subject.range_scale = range_scale
	_handle = service.register(subject)


func _unregister() -> void:
	var service := _lod_service()
	if service != null and _handle >= 0:
		service.unregister(_handle)
	_handle = -1


func _editor_build() -> void:
	for child in get_children():
		child.free()
	if not build_detailed.is_valid():
		return
	var built: Variant = build_detailed.call()
	var node := built as Node3D
	if node != null:
		node.name = "Detailed"
		add_child(node)


func _lod_service() -> Node:
	return get_node_or_null("/root/LodService")
