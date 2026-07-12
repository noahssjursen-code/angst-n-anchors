@tool
class_name TrawlSystemAttachment
extends VesselAttachment

## Mounts FishingSystem at the fishing socket.


func attachment_id() -> String:
	return "trawl_system"


func kind() -> String:
	return "fishing"


func _on_mounted() -> void:
	var fishing := FishingSystem.new()
	fishing.name = "FishingSystem"
	add_child(fishing)
