class_name CraneRigging
extends Node3D

## Manages up to 4 chain visuals connecting the crane hook to attached pallet sockets.
## Each chain is a thin scaled box that stretches from hook to socket each frame.

const MAX_CHAINS := 4
const CHAIN_THICK := 0.06
const CHAIN_COLOR := Color(0.14, 0.14, 0.16)

var hook: Node3D = null
## Active attachments: [{socket: PalletAttachPoint, mesh: MeshInstance3D}]
var _links: Array = []


func _process(_dt: float) -> void:
	if hook == null:
		return
	for link in _links:
		_update_chain(link)


func attach(socket: Node3D) -> bool:
	if hook == null or socket == null:
		return false
	if _links.size() >= MAX_CHAINS:
		return false
	for link in _links:
		if link.socket == socket:
			return false

	var mesh := MeshInstance3D.new()
	mesh.name = "Chain%d" % _links.size()
	var box := BoxMesh.new()
	box.size = Vector3(CHAIN_THICK, 1.0, CHAIN_THICK)
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CHAIN_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	add_child(mesh)

	_links.append({ "socket": socket, "mesh": mesh })
	if socket.has_method("set_attached"):
		socket.set_attached(true)
	return true


func detach_all() -> void:
	for link in _links:
		if is_instance_valid(link.socket) and link.socket.has_method("set_attached"):
			link.socket.set_attached(false)
		if is_instance_valid(link.mesh):
			link.mesh.queue_free()
	_links.clear()


func attached_count() -> int:
	return _links.size()


func attached_sockets() -> Array:
	var out := []
	for link in _links:
		out.append(link.socket)
	return out


func _update_chain(link: Dictionary) -> void:
	var socket: Node3D = link.socket
	var mesh: MeshInstance3D = link.mesh
	if socket == null or not is_instance_valid(socket) or mesh == null or not is_instance_valid(mesh):
		return
	var a := hook.global_position
	var b := socket.global_position
	var mid := (a + b) * 0.5
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		mesh.visible = false
		return
	mesh.visible = true
	mesh.global_position = mid
	# Orient local +Y along the segment direction.
	mesh.look_at(b, Vector3(0, 0, 1) if absf(dir.normalized().dot(Vector3.UP)) > 0.95 else Vector3.UP, true)
	mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mesh.scale = Vector3(1.0, length, 1.0)
