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
	if hook == null or not is_instance_valid(hook) or not hook.is_inside_tree():
		detach_all()
		return
	var alive_links: Array = []
	for link in _links:
		var socket = link.socket
		var mesh = link.mesh
		if _update_chain(link):
			alive_links.append(link)
		elif is_instance_valid(mesh):
			mesh.queue_free()
	_links = alive_links


func attach(socket: Node3D) -> bool:
	if hook == null or not is_instance_valid(hook):
		return false
	if socket == null or not is_instance_valid(socket) or not socket.is_inside_tree():
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
		if is_instance_valid(link.socket):
			out.append(link.socket)
	return out


func _node_global_position(node: Node3D) -> Variant:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return null
	return node.global_position


func _update_chain(link: Dictionary) -> bool:
	var socket = link.socket
	var mesh = link.mesh
	if not is_instance_valid(socket) or not is_instance_valid(mesh):
		return false
	if not socket.is_inside_tree():
		return false
	var a_var = _node_global_position(hook)
	var b_var = _node_global_position(socket)
	if a_var == null or b_var == null:
		return false
	var a: Vector3 = a_var
	var b: Vector3 = b_var
	var mid := (a + b) * 0.5
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		mesh.visible = false
		return true
	mesh.visible = true
	mesh.global_position = mid
	# Orient local +Y along the segment direction.
	mesh.look_at(b, Vector3(0, 0, 1) if absf(dir.normalized().dot(Vector3.UP)) > 0.95 else Vector3.UP, true)
	mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mesh.scale = Vector3(1.0, length, 1.0)
	return true
