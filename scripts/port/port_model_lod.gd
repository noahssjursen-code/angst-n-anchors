@tool
class_name PortModelLod
extends RefCounted

## Authored mesh variants. Visibility dependencies switch visual meshes only;
## sockets, collision, lights and gameplay remain attached to the original root.
const MANIFEST_PATH := "res://resources/models/scenery/port_distance/facility_lods.json"
static var _manifest: Dictionary = {}
static var _scenes: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	return _manifest

static func attach(root: Node3D, source_path: String) -> void:
	var record: Dictionary = manifest().get(source_path, {})
	if record.is_empty(): return
	var path := str(record.mesh)
	if not _scenes.has(path): _scenes[path] = load(path)
	var scene := _scenes[path] as PackedScene
	if scene == null:
		push_error("Missing authored port LOD: " + path)
		return
	var detailed := root.find_children("*", "MeshInstance3D", true, false)
	var low := scene.instantiate() as Node3D
	low.name = "DistanceModel"
	root.add_child(low)
	var meshes := low.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 1, "Port LOD must export one combined mesh")
	var far := meshes[0] as MeshInstance3D
	far.name = "Lod1"
	far.visibility_range_begin = float(record.switch_m)
	far.visibility_range_begin_margin = float(record.margin_m)
	far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Shared visibility parent guarantees exactly one representation, and one
	# common distance origin, even if detail consists of several smaller meshes.
	for raw in detailed:
		var mesh := raw as MeshInstance3D
		mesh.visibility_parent = mesh.get_path_to(far)
	root.set_meta("port_model_lod", source_path)
