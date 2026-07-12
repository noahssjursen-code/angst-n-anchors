@tool
class_name ShipCraneSmallAttachment
extends VesselAttachment

## Placeholder ship-mounted deck crane. Not the port gantry — visual stub only.


func attachment_id() -> String:
	return "ship_crane_small"


func kind() -> String:
	return "crane"


func _on_mounted() -> void:
	var pedestal := MeshBuilder.box(
		Vector3(0.8, 1.2, 0.8),
		Color(0.55, 0.45, 0.2),
		0.85,
		0.15,
	)
	pedestal.name = "CranePedestal"
	pedestal.position = Vector3(0.0, 0.6, 0.0)
	add_child(pedestal)

	var boom := MeshBuilder.box(
		Vector3(0.25, 0.25, 6.0),
		Color(0.6, 0.5, 0.22),
		0.8,
		0.2,
	)
	boom.name = "CraneBoom"
	boom.position = Vector3(0.0, 1.4, -2.5)
	boom.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	add_child(boom)
