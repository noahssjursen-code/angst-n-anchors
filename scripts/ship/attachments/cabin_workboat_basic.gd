@tool
class_name CabinWorkboatBasic
extends VesselAttachment

## Workboat cabin visual + helm boarding. Authored relative to socket (deck at y=0).

const HOUSE_W := 4.0
const HOUSE_H := 2.4
const HOUSE_L := 5.0


func attachment_id() -> String:
	return "cabin_workboat_basic"


func kind() -> String:
	return "cabin"


func _on_mounted() -> void:
	_build_visual()
	_add_helm()


func _build_visual() -> void:
	var house := MeshBuilder.box(
		Vector3(HOUSE_W, HOUSE_H, HOUSE_L),
		Color(0.85, 0.86, 0.88),
		0.7,
		0.0,
	)
	house.name = "CabinShell"
	house.position = Vector3(0.0, HOUSE_H * 0.5, 0.0)
	add_child(house)

	var window := ShipLight.new()
	window.name = "CabinWindow"
	window.light_type = ShipLight.LightType.WINDOW
	window.position = Vector3(0.0, HOUSE_H * 0.55, -HOUSE_L * 0.45)
	add_child(window)


func _add_helm() -> void:
	var helm := BridgeInteractable.new()
	helm.name = "BridgeInteractable"
	helm.position = Vector3(0.0, 0.1, 0.0)
	helm.exit_deck_offset = Vector2(0.0, 3.0)
	add_child(helm)
