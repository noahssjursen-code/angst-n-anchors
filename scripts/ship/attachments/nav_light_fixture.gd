@tool
class_name NavLightFixtureAttachment
extends VesselAttachment

## ShipLight fixture mounted at a light socket.

var _light_type: int = 0


func configure_from_catalog(entry: Dictionary) -> void:
	_light_type = int(entry.get("light_type", 0))


func attachment_id() -> String:
	match _light_type:
		1:
			return "nav_light_starboard"
		2:
			return "nav_light_bow"
		3:
			return "nav_light_stern"
		_:
			return "nav_light_port"


func kind() -> String:
	return "light"


func _on_mounted() -> void:
	var light := ShipLight.new()
	light.name = "ShipLight"
	light.light_type = _light_type as ShipLight.LightType
	add_child(light)
