@tool
class_name MooringCleatAttachment
extends VesselAttachment

## Single MooringPoint at a mooring socket. Side/station inferred from socket_id.


func attachment_id() -> String:
	return "mooring_cleat"


func kind() -> String:
	return "mooring"


func _on_mounted() -> void:
	var cleat := MooringPoint.new()
	cleat.name = "MooringPoint"
	var sid := ""
	if _socket != null:
		sid = _socket.socket_id
	cleat.side = "port" if "port" in sid else "starboard"
	cleat.station = "bow" if "fwd" in sid else "stern"
	cleat.bollard_scale = 0.85
	add_child(cleat)
